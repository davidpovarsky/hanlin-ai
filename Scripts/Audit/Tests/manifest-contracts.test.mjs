import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import {execFileSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import {auditManifestContracts, manifestReferenceMarkdown, manifestSources} from '../miniapp-manifest-contracts.mjs';

const root = path.resolve(import.meta.dirname, '../../..');
const sha = text => createHash('sha256').update(text).digest('hex');
async function actualSources() {
  return new Map(await Promise.all(Object.values(manifestSources).map(async file => {
    let text;
    try { text = await fs.readFile(path.join(root, file), 'utf8'); }
    catch (error) {
      if (error.code !== 'ENOENT') throw error;
      text = execFileSync('git', ['show', 'HEAD:' + file], {cwd: root, encoding: 'utf8'});
    }
    return [file, text];
  })));
}
function reader(original, changes = new Map()) {
  return async file => {
    const text = changes.has(file) ? changes.get(file) : original.get(file);
    assert.equal(typeof text, 'string', 'Only actual declared source authorities may be read: ' + file);
    return {path: file, text, sha256: sha(text)};
  };
}

test('all current manifest fields have source authorities and future reader/schema drift is visible', async () => {
  const original = await actualSources();
  const coverage = await auditManifestContracts({source: reader(original)});
  assert.equal(coverage.nativeAcceptance, 'NOT_INFERRED');
  assert.equal(coverage.families.length, 8);
  const family = name => coverage.families.find(item => item.family === name);
  const script = family('script.json');
  assert.deepEqual(script.fields.find(item => item.field === 'entrypoints[].kind').type.split(' | '),
    ['assistantTool', 'appIntent', 'embeddedResult', 'share', 'translationUI', 'liveActivity',
     'keyboard', 'notificationUI', 'spotlight', 'capture']);
  assert.equal(script.decoderKnownKeys.length, 16);
  for (const key of ['entrypoints[].exportedSymbol', 'nativePresentations.*.input.submitTitle',
    'hanlinWidget.actions[].stateKey', 'hanlinWidget.actions[].hostAction.entrypointID',
    'hanlinWidget.actions[].hostAction.actionName', 'hanlinWidget.actions[].hostAction.parameters',
    'skills[].instructions.resource', 'actions[].entrypoint',
    'remoteResource.autoUpdateInterval', 'contributors[].homepage'])
    assert(script.fields.some(item => item.field === key), 'Recognized nested field must be mapped: ' + key);
  assert.equal(script.fields.find(item => item.field === 'runInApp').status, 'partial');
  assert(script.fields.find(item => item.field === '* (unrecognized keys)').semantics.includes('do not register'));
  const authoring = family('hanlin.authoring.json');
  for (const key of ['sourceHashes', 'sourceHashes.*', 'compiledHashes', 'compiledHashes.*', 'sdk.compilerVersion'])
    assert(authoring.fields.some(item => item.field === key));
  const expo = family('expo prepared package.json');
  assert.equal(expo.fields.find(item => item.field === 'hanlinExpo.nativeApi.abiIdentity').status, 'partial');
  assert(expo.fields.find(item => item.field === 'hanlinExpo.runtimeVersion').semantics.includes('separate stage authorities'));
  const expoAsset = expo.fields.find(item => item.field === 'hanlinExpo.plugins.expo-asset');
  assert.equal(expoAsset.status, 'supported');
  assert(expoAsset.semantics.includes('Exact installed original ExpoAsset version'));
  assert(expoAsset.semantics.includes('HanlinMiniAppHostVersions.expoAssetVersion'));
  assert(expoAsset.sources.some(item => item.path === manifestSources.analyzer && item.line));
  const dependency = family('NativeScript installed dependency package.json');
  for (const key of ['version', 'nativescript.platforms.ios', 'peerDependenciesMeta.*.optional', 'optionalDependencies.*'])
    assert(dependency.fields.some(item => item.field === key));
  assert(dependency.fields.find(item => item.field === 'nativescript.platforms.ios').type.includes('truthiness'));
  assert(script.fields.find(item => item.field === 'contributors[].homepage').semantics.includes('not contributors'));
  const widgets = family('original ScriptWidget widget.json');
  assert(widgets.fields.some(item => item.field === '#/$defs/WidgetPackageControl/properties/actionID'));
  const expectedOriginalPaths = [manifestSources.widgetMetadata, manifestSources.widgetPackage, manifestSources.widgetNetworkPolicy];
  assert.deepEqual(widgets.upstream.sources.map(item => item.path).sort(), expectedOriginalPaths.toSorted());
  for (const authority of widgets.upstream.sources)
    assert.equal(authority.sha256, sha(original.get(authority.path)));
  assert(widgets.additionalAuthorities.some(item => item.path === manifestSources.widgetNetworkPolicy && item.line));
  const canonical = family('canonical compiled Hanlin app');
  assert(canonical.fields.some(item => item.field === '#/$defs/tool/properties/presentation/properties/embeddedPresentation/properties/expansion/properties/expandedHandler'));
  assert(!canonical.fields.some(item => item.field === '#/$defs/schema/properties/properties/type'),
    'Do not mistake a schema property map for another schema and invent type/constraint fields');
  const markdown = manifestReferenceMarkdown(coverage);
  for (const group of coverage.families) {
    const section = markdown.split('## ' + group.family + '\n')[1]?.split('\n## ')[0];
    assert(section, 'Every family must reach public generated reference');
    for (const item of group.fields) {
      assert(item.sources.length && item.sources.every(source => source.sha256 && (source.line || source.jsonPointer)));
      assert(section.includes(item.field.replaceAll('|', '\\|')), 'Every inventoried field must reach public reference');
    }
  }

  const changedConsumer = original.get(manifestSources.analyzer).replace('var findings: [HanlinCompatibilityFinding] = []',
    'var findings: [HanlinCompatibilityFinding] = []\n        _ = package.manifest.unknownFields["futureContract"]');
  await assert.rejects(auditManifestContracts({source: reader(original, new Map([[manifestSources.analyzer, changedConsumer]]))}),
    /Unmapped manifest field drift: script.json retained extension consumers/);
  const changedNested = original.get(manifestSources.presentation).replaceAll('submitTitle', 'futureSubmitTitle');
  await assert.rejects(auditManifestContracts({source: reader(original, new Map([[manifestSources.presentation, changedNested]]))}),
    /Unmapped manifest field drift: HanlinNativePresentationInput/);
  const hostParameters = script.fields.find(item => item.field === 'hanlinWidget.actions[].hostAction.parameters');
  assert.equal(hostParameters.required, false);
  assert.match(hostParameters.semantics, /ordinary JSON.*explicit null/);
  assert.match(script.fields.find(item => item.field === 'nativePresentations.*.actions[].hostAction').semantics,
    /Unsupported.*reject/);
  const changedHostTarget = original.get(manifestSources.widgetProgram).replace('public let actionName: String', 'public let futureActionName: String');
  await assert.rejects(auditManifestContracts({source: reader(original, new Map([[manifestSources.widgetProgram, changedHostTarget]]))}),
    /Unmapped manifest field drift: HanlinWidgetHostAction/);
  const changedPackage = original.get(manifestSources.analyzer).replace('if let contractValue = packageJSON["hanlinNativeScript"]',
    '_ = packageJSON["futurePreparedContract"]\n        if let contractValue = packageJSON["hanlinNativeScript"]');
  await assert.rejects(auditManifestContracts({source: reader(original, new Map([[manifestSources.analyzer, changedPackage]]))}),
    /Unmapped manifest field drift: nativescript package.json reader/);
  const changedPlugin = original.get(manifestSources.analyzer).replace(
    'case "expo-asset": version == HanlinMiniAppHostVersions.expoAssetVersion',
    'case "future-asset-plugin": version == HanlinMiniAppHostVersions.expoAssetVersion');
  assert.notEqual(changedPlugin, original.get(manifestSources.analyzer));
  await assert.rejects(auditManifestContracts({source: reader(original, new Map([[manifestSources.analyzer, changedPlugin]]))}),
    /Unmapped manifest field drift: expo embedded plugins/);
  const changedDependency = original.get(manifestSources.authoring).replace(
    "const pkg = await json(path.join(source, 'package.json'));",
    "const pkg = await json(path.join(source, 'package.json')); void pkg.futureDependencyContract;");
  await assert.rejects(auditManifestContracts({source: reader(original, new Map([[manifestSources.authoring, changedDependency]]))}),
    /Unmapped manifest field drift: NativeScript installed dependency package.json reads/);
  const originalSchema = JSON.parse(original.get(manifestSources.widgetSchema));
  const provenanceCases = [
    ['missing helper', sources => sources.filter(item => item.path !== manifestSources.widgetNetworkPolicy), /Original widget provenance is missing/],
    ['extra authority', sources => [...sources, {path: manifestSources.widgetValidator, sha256: sha(original.get(manifestSources.widgetValidator))}], /Original widget provenance is missing/],
    ['duplicate replacing helper', sources => sources.map(item => item.path === manifestSources.widgetNetworkPolicy ? sources[0] : item), /Unmapped manifest field drift: original widget provenance sources/],
    ['different registered authority', sources => sources.map(item => item.path === manifestSources.widgetNetworkPolicy ? {path: manifestSources.widgetValidator, sha256: sha(original.get(manifestSources.widgetValidator))} : item), /Unmapped manifest field drift: original widget provenance sources/],
    ['incorrect helper hash', sources => sources.map(item => item.path === manifestSources.widgetNetworkPolicy ? {...item, sha256: '0'.repeat(64)} : item), /Original widget manifest source\/schema drift/],
  ];
  for (const [label, mutate, diagnostic] of provenanceCases) {
    const changed = structuredClone(originalSchema);
    changed['x-original-contract'].sources = mutate(changed['x-original-contract'].sources);
    await assert.rejects(auditManifestContracts({source: reader(original,
      new Map([[manifestSources.widgetSchema, JSON.stringify(changed)]]))}), diagnostic, label);
  }
  const changedOriginalSchema = JSON.parse(original.get(manifestSources.widgetSchema));
  changedOriginalSchema.$defs.WidgetPackageControl.properties.futureAction = {type: 'string'};
  await assert.rejects(auditManifestContracts({source: reader(original, new Map([[manifestSources.widgetSchema, JSON.stringify(changedOriginalSchema)]]))}),
    /Unmapped manifest field drift: original WidgetPackageControl/);
  const changedCanonical = JSON.parse(original.get(manifestSources.canonicalSchema));
  changedCanonical.$defs.tool.properties.presentation.properties.futurePolicy = {type: 'string'};
  const automaticallyMapped = await auditManifestContracts({source: reader(original,
    new Map([[manifestSources.canonicalSchema, JSON.stringify(changedCanonical)]]))});
  assert(automaticallyMapped.families.find(item => item.family === canonical.family).fields
    .some(item => item.field === '#/$defs/tool/properties/presentation/properties/futurePolicy'));
  assert.notEqual(manifestReferenceMarkdown(automaticallyMapped), markdown,
    'A newly declared canonical schema field must change checked JSON and public Markdown');
  console.log(JSON.stringify({sourceOnly: true, nativeAcceptance: 'NOT_INFERRED',
    fields: coverage.fieldCount, families: coverage.families.map(item => ({family: item.family, fields: item.fields.length})),
    sourceSHA256: Object.fromEntries([...original].map(([file, text]) => [file, sha(text)])),
    originalProvenanceSources: expectedOriginalPaths, provenanceMutationsRejected: provenanceCases.map(([label]) => label),
    driftCases: ['new retained-field consumer rejected', 'renamed native input field rejected',
      'new prepared package reader field rejected', 'changed embedded-plugin identity rejected',
      'new installed-dependency field rejected', 'original schema/Codable mismatch rejected',
      'new canonical schema property automatically reaches checked outputs']}));
});
