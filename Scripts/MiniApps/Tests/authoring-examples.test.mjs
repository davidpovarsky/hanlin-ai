import test from 'node:test';
import assert from 'node:assert/strict';
import {promises as fs} from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import {execFileSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import {fileURLToPath, pathToFileURL} from 'node:url';
import {readGuideExamples, prepareGuideProjects, validateGuideProject, checkExpoRegistration,
  checkAuthoringExamples, extractOriginalSDKArchive} from '../check-authoring-examples.mjs';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../../..');
const sdkRoot = process.env.HANLIN_AUTHORING_EXAMPLE_SDK;
assert.ok(sdkRoot, 'Set HANLIN_AUTHORING_EXAMPLE_SDK to the actual exported original SDK; no mock SDK or skipped check is used.');
const evidence = process.env.HANLIN_AUTHORING_EXAMPLE_EVIDENCE;
const guides = await readGuideExamples(root);
const sdk = JSON.parse(await fs.readFile(path.join(sdkRoot, 'miniapp-sdk.json'), 'utf8'));
const ts = (await import(pathToFileURL(path.join(sdkRoot, sdk.engines.expo.typescriptPath)).href)).default;
const nativeSource = await fs.readFile(path.join(root,
  'Packages/HanlinExpoRuntime/Sources/HanlinExpoRuntime/HanlinExpoSession.swift'), 'utf8');
const digest = source => createHash('sha256').update(source).digest('hex');

async function record(name, value) {
  if (!evidence) return;
  await fs.mkdir(evidence, {recursive: true});
  await fs.writeFile(path.join(evidence, name + '.json'), JSON.stringify(value, null, 2) + '\n');
}
async function withProject(name, blocks, callback) {
  const directory = await fs.mkdtemp(path.join(os.tmpdir(), 'hanlin-guide-regression-'));
  try {
    const project = (await prepareGuideProjects({blocks, directory})).find(item => item.name === name);
    assert.ok(project);
    return await callback(project);
  } finally { await fs.rm(directory, {recursive: true, force: true}); }
}
function modified(id, source) {
  const blocks = new Map(guides.blocks);
  blocks.set(id, {...blocks.get(id), source, sha256: digest(source)});
  return blocks;
}

test('the corrected actual NativeScript guide checks with original source policy and all eight extracted modules', async () => {
  await withProject('nativescript-guide', guides.blocks, async project => {
    const report = await validateGuideProject(project, sdkRoot);
    await record('nativescript-guide-green', {project, report});
    assert.equal(report.succeeded, true, JSON.stringify(report.diagnostics));
    assert.deepEqual(report.diagnostics, []);
    assert.deepEqual(report.typecheck, {strict: true, checkJs: true, skipLibCheck: true, dependencyDeclarationsChecked: false});
    assert.equal(project.snippets.filter(item => item.mode === 'original-source-typecheck').length, 8);
  });
});

test('the historical Expo probe registration fails the actual native default-name contract', async () => {
  const correct = guides.blocks.get('expo.registration').source;
  const wrong = correct.replace("'main'", "'ExpoSwiftUIProbe'");
  assert.notEqual(wrong, correct);
  const accepted = checkExpoRegistration(ts, correct, nativeSource);
  assert.throws(() => checkExpoRegistration(ts, wrong, nativeSource), /native foreground host requests main/);
  await record('registration-drift', {accepted, rejectedSource: wrong, rejectedSHA256: digest(wrong), expectedRejection: 'native foreground host requests main'});
});

test('new or removed guide blocks and stale staged documentation fail closed', async () => {
  const name = 'docs/miniapp-sdk/README.md';
  const original = await fs.readFile(path.join(root, name), 'utf8');
  const fence = String.fromCharCode(96).repeat(3);
  await assert.rejects(readGuideExamples(root, new Map([[name, original + '\n' + fence + 'ts\nconst added = 1;\n' + fence + '\n']])),
    /unclassified fenced block/);
  const unsupportedPrefixes = ['> ', '> > ', '- ', '1. ', '> 1. ', '    ', '\t'];
  for (const prefix of unsupportedPrefixes) {
    const hidden = prefix + fence + 'ts\n' + prefix + 'const example: string = 1;\n' + prefix + fence + '\n';
    await assert.rejects(readGuideExamples(root, new Map([[name, original + '\n' + hidden]])),
      /unsupported Markdown fence form/, 'A container/indented fence must not disappear from coverage: ' + JSON.stringify(prefix));
  }
  await assert.rejects(readGuideExamples(root, new Map([[name, original + '\n' + fence + 'ts title=example\nconst example = 1;\n' + fence + '\n']])),
    /unsupported Markdown fence form/);
  await assert.rejects(readGuideExamples(root, new Map([[name, original.replace('miniapp-snippet: readme.descriptor', 'miniapp-snippet: unreviewed.descriptor')]])),
    /unclassified snippet/);
  const removed = original.replace(/<!-- miniapp-snippet: readme.descriptor -->[\s\S]*?\x60{3}json[\s\S]*?\x60{3}/, '');
  await assert.rejects(readGuideExamples(root, new Map([[name, removed]])), /inventory changed/);
  // A changed checked document must not silently validate the older bytes in a staged SDK.
  let observedDocumentationMismatch;
  await assert.rejects(checkAuthoringExamples({sdkRoot, root, requireSDKDocs: true,
    documentOverrides: new Map([[name, original + '\n<!-- deliberate documentation drift -->\n']])}), error => {
      observedDocumentationMismatch = error.message;
      return /staged SDK guide differs/.test(error.message);
    });
  await record('coverage-and-shipping-guards', {unclassifiedBlock: 'REJECTED', unreviewedLabel: 'REJECTED',
    removedBlock: 'REJECTED', unsupportedPrefixes, unsupportedFenceInfo: 'REJECTED',
    stagedDocumentationDrift: {status: 'REJECTED', observedError: observedDocumentationMismatch,
      isolatedChangedDocument: observedDocumentationMismatch.startsWith(name + ':'),
      wholeSDKDocumentationPositive: 'NOT_RUN'},
    sdkInputSHA256: sdk.inputSHA256});
});

test('an invalid property in the actual Markdown source produces an original NativeScript diagnostic', async () => {
  const source = guides.blocks.get('ns.properties').source + '\nview.notAnOriginalUIKitProperty = 1;\n';
  await withProject('nativescript-guide', modified('ns.properties', source), async project => {
    const report = await validateGuideProject(project, sdkRoot);
    await record('nativescript-guide-negative', {source, sourceSHA256: digest(source), report});
    assert.equal(report.succeeded, false);
    assert.ok(report.diagnostics.some(item => item.code === 'TS2339' && item.file === 'src/properties.js'
      && item.message.includes('notAnOriginalUIKitProperty')), JSON.stringify(report.diagnostics));
  });
});

test('the actual control-manifest excerpt reaches the original semantic validator', async () => {
  const manifest = JSON.parse(guides.blocks.get('controls.manifest').source);
  manifest.controls[0].actionID = 'undeclared-action';
  const source = JSON.stringify(manifest, null, 2) + '\n';
  await withProject('scriptwidget-controls', modified('controls.manifest', source), async project => {
    const report = await validateGuideProject(project, sdkRoot);
    await record('control-manifest-negative', {source, sourceSHA256: digest(source), report});
    assert.equal(report.succeeded, false);
    assert.ok(report.diagnostics.some(item => item.code === 'SCRIPTWIDGET_MISSING_CONTROL_ACTION'
      && item.originalCode === 'missing_control_action' && item.file === 'widget.json'), JSON.stringify(report.diagnostics));
  });
});


test('the verified Host archive adapter preserves original SDK bytes and ignores other Host payloads', async () => {
  const directory = await fs.mkdtemp(path.join(os.tmpdir(), 'hanlin-guide-archive-'));
  try {
    const archive = path.join(directory, 'Host.zip');
    const output = path.join(directory, 'extracted');
    const source = path.join(sdkRoot, 'miniapp-sdk.json');
    execFileSync('python3', ['-c', [
      'import pathlib, sys, zipfile',
      'with zipfile.ZipFile(sys.argv[2], "w") as archive:',
      '    archive.writestr("MiniAppSDK/miniapp-sdk.json", pathlib.Path(sys.argv[1]).read_bytes())',
      '    archive.writestr("host-only.js", "throw new Error(\\"must not execute or copy\\");")'
    ].join('\n'), source, archive]);
    extractOriginalSDKArchive(archive, output);
    assert.deepEqual(await fs.readFile(path.join(output, 'MiniAppSDK/miniapp-sdk.json')), await fs.readFile(source));
    await assert.rejects(fs.access(path.join(output, 'host-only.js')), {code: 'ENOENT'});
    await record('archive-adapter', {status: 'EXECUTED_PASS', copiedManifestSHA256: digest(await fs.readFile(source)),
      unselectedHostFile: 'NOT_EXTRACTED', sdkCompilerExecution: 'NOT_RUN', nativeExecution: 'NOT_RUN'});
  } finally { await fs.rm(directory, {recursive: true, force: true}); }
});
