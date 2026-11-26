import assert from 'node:assert/strict';
import {readFile, writeFile, mkdir} from 'node:fs/promises';
import path from 'node:path';
import {pathToFileURL} from 'node:url';
import {createHash} from 'node:crypto';

const [root, sdkRoot, output] = process.argv.slice(2);
if (!root || !sdkRoot || !output) throw new Error('Usage: node run-public-authoring-build.mjs REPOSITORY ORIGINAL_SDK OUTPUT');
const hash = bytes => createHash('sha256').update(bytes).digest('hex');
const project = path.join(root, 'Fixtures/ExpoSwiftUIProbe');
const {runMiniAppOperation} = await import(pathToFileURL(path.join(root,
  'AI_HLY/Downstream/RuntimeCore/Node/Host/miniapp-authoring.mjs')).href);
await mkdir(output, {recursive: true});
const report = await runMiniAppOperation({operation: 'build', engine: 'expo',
  projectRoot: project, outputDirectory: path.join(output, 'package')}, {sdkRoot});
await writeFile(path.join(output, 'public-build-result.json'), JSON.stringify(report, null, 2) + '\n');
if (!report.succeeded) {
  console.log(JSON.stringify(report, null, 2));
  process.exitCode = 1;
} else {
  assert.equal(report.diagnostics.length, 0);
  assert.equal(report.typecheck.strict, true);
  assert.equal(report.typecheck.skipLibCheck, false);
  assert.equal(report.typecheck.dependencyDeclarationsChecked, true);
  const map = JSON.parse(await readFile(path.join(report.preparedPackagePath, 'bundle.js.map'), 'utf8'));
  const mapped = [
    ['GeneratedViewsProbe.tsx', path.join(project, 'GeneratedViewsProbe.tsx')],
    ['GeneratedModifiersProbe.tsx', path.join(project, 'GeneratedModifiersProbe.tsx')],
    ['HostServicesProbe.tsx', path.join(project, 'HostServicesProbe.tsx')],
    ['@hanlin/expo-ui/src/generated/bridge-manifest.ts', path.join(root, 'Packages/HanlinExpoUI/src/generated/bridge-manifest.ts')],
    ['@hanlin/expo-ui/src/host-services.ts', path.join(root, 'Packages/HanlinExpoUI/src/host-services.ts')],
  ];
  const sources = [];
  for (const [suffix, original] of mapped) {
    const indices = map.sources.flatMap((name, index) => name.endsWith('/' + suffix) || name === suffix ? [index] : []);
    assert.equal(indices.length, 1, 'Expected one current source-map module: ' + suffix);
    const source = await readFile(original, 'utf8');
    assert.equal(map.sourcesContent[indices[0]], source, 'Metro must use exact current authored bytes: ' + suffix);
    sources.push({source: path.relative(root, original), mappedSource: map.sources[indices[0]], sha256: hash(source)});
  }
  const author = JSON.parse(await readFile(path.join(report.preparedPackagePath, 'hanlin.authoring.json'), 'utf8'));
  for (const name of ['App.tsx', 'GeneratedViewsProbe.tsx', 'GeneratedModifiersProbe.tsx', 'HostServicesProbe.tsx', 'widget.tsx', 'script.json']) {
    const source = await readFile(path.join(project, name));
    assert.equal(author.sourceHashes[name], hash(source), 'Retained source identity: ' + name);
    assert.equal(hash(await readFile(path.join(report.preparedPackagePath, 'source', name))), hash(source));
  }
  const receipt = {schemaVersion: 1, status: 'EXECUTED_PASS', operation: 'real public authoring build',
    compilerVersion: report.sdk.compilerVersion, diagnostics: 0, strict: true, skipLibCheck: false,
    sdkManifestSHA256: report.sdk.manifestSHA256, currentSourceMapModules: sources,
    bundleSHA256: hash(await readFile(path.join(report.preparedPackagePath, 'bundle.js'))),
    sourceMapSHA256: hash(await readFile(path.join(report.preparedPackagePath, 'bundle.js.map'))),
    retainedSourceIdentity: 'All six selected current fixture sources match sourceHashes and original bytes.',
    boundary: 'Original exported compiler/dependency graph with exact current repository local facade overlay; no new full SDK assembly, application execution, simulator/device or all-modifier semantic pass.'};
  await writeFile(path.join(output, 'current-source-proof.json'), JSON.stringify(receipt, null, 2) + '\n');
  console.log(JSON.stringify(receipt, null, 2));
}
