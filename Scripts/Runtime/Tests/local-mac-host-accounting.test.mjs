import test from 'node:test';
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { accountLocalMacHostExecution, localMacHostLog } from '../local-mac-host-accounting.mjs';
import { verifiedReceiptAccounting } from '../upstream-host-accounting.mjs';

const digest = value => createHash('sha256').update(value).digest('hex');
const json = value => JSON.stringify(value, null, 2) + '\n';
const archiveSHA256 = 'a'.repeat(64), sourceInputsHash = 'b'.repeat(64), head = '1'.repeat(40);
const originalSkip = 'actual Node job crosses 300 seconds with no hidden deadline';
const names = ['ReactNativeHeaders', 'React', 'ReactNativeDependencies', 'hermesvm', 'ExpoModulesJSI',
  'ExpoModulesCore', 'ExpoModulesWorklets', 'ExpoUI', 'ExpoAsset', 'ExpoBrownfield', 'Libffi',
  'TNSWidgets', 'NSCWinterTC', 'NodeMobile', 'Python'];
const supports = ['HanlinExpoHeaderSupport', 'HanlinExpoWidgetRuntimeSupport', 'HanlinNativeScriptHostSupport',
  'HanlinNodeHostSupport', 'HanlinPythonHostSupport'];
function logFixture() {
  return '> node --test Tests/*.test.mjs\n'
    + Array.from({ length: 169 }, (_, index) => `✔ real fixture case ${index + 1} (1.25ms)`).join('\n')
    + `\n﹣ ${originalSkip} (0.01ms) # SKIP\n`
    + 'ℹ tests 170\nℹ suites 0\nℹ pass 169\nℹ fail 0\nℹ cancelled 0\nℹ skipped 1\nℹ todo 0\nℹ duration_ms 1000\n'
    + JSON.stringify({ passed: true, fetchImplementation: 'fixture-only', webAssemblyAvailable: false,
      contracts: ['GET', 'Request POST Unicode', 'redirect', 'HTTP error', 'ReadableStream', 'clone', 'gzip', 'multipart File', 'abort', 'HEAD', '204'] })
    + `\nPrepared RuntimeHostResources.zip (${archiveSHA256}).\n`;
}
function fixture() {
  const repository = 'owner/repo';
  const records = [...names, ...supports].map(target => ({ target, checksum: digest(target), archive: target + '.zip' }));
  const identity = digest(JSON.stringify(Object.fromEntries(records.map(item => [item.target, item.checksum]).sort(([a], [b]) => a < b ? -1 : 1))));
  const releaseTag = `sdk-native-v1-${identity}`;
  for (const item of records) item.url = `https://github.com/${repository}/releases/download/${releaseTag}/${item.archive}`;
  const nativeInputSHA256 = Object.fromEntries(Array.from({ length: 16 }, (_, index) => [`input-${index}`, digest(String(index))]));
  const catalog = { schemaVersion: 1, repository, state: 'prepared', scope: 'full', sourceCommit: '2'.repeat(40),
    missingTargets: [], requiredTargets: names, contentSHA256: identity, releaseTag,
    artifacts: records.slice(0, 15), supportArtifacts: records.slice(15), inputSHA256: nativeInputSHA256 };
  const hostMetadata = { archiveSha256: archiveSHA256, sourceInputsHash, nodeVersion: 'v24.5.0', tests: 'passed', jitlessArchiveSmoke: 'passed' };
  const proof = { controller: '# original fixture controller\n', log: logFixture(), nativeCatalog: json(catalog),
    nativeInventory: json({ 'framework/binary': { sha256: digest('binary'), mode: 493 } }) };
  const preparation = { source: head, status: 'PREPARED', hostResult: 'EXECUTED_PASS',
    startedAt: '2026-11-25T02:54:04Z', finishedAt: '2026-11-25T02:59:11Z',
    controllerSHA256: digest(proof.controller), toolchain: { node: 'v24.5.0', python: 'Python 3.12.16', xcode: 'Xcode 27.0' },
    producerExecutedSource: catalog.sourceCommit, runtimeHostZipSHA256: archiveSHA256, hostMetadata,
    steps: [{ name: 'original-host', argv: ['/bin/bash', 'Scripts/Runtime/prepare-runtime-host.sh'],
      status: 'EXECUTED_PASS', exitCode: 0, startedAt: '2026-11-25T02:55:35Z', finishedAt: '2026-11-25T02:58:36Z',
      elapsedSeconds: 181, logSHA256: digest(proof.log) }],
    catalogQualification: { sha256: digest(proof.nativeCatalog), targetCount: 15, nativeInputFiles: 16,
      producerOriginalExportAndVerify: 'EXECUTED_PASS', frameworkFileCount: 1 },
    nativeFrameworksReused: { status: 'REUSED_VERIFIED_PASS', unchangedFiles: 1, inventorySHA256: digest(proof.nativeInventory) },
    archiveQualification: records.map(item => ({ target: item.target, sha256: item.checksum, entries: 2, regularFiles: 1,
      status: 'EXACT_ARCHIVE_AND_INSTALLED_BYTES' })) };
  proof.preparation = json(preparation);
  return { repository, head, archiveSHA256, sourceInputsHash, hostMetadata, nativeInputSHA256,
    nodeFingerprint: { versions: { node: '24.5.0' }, platform: 'darwin', arch: 'arm64' }, proof,
    authentication: { preparationSHA256: digest(proof.preparation) } };
}
// Synthetic fixtures simulate independently authenticated producer receipts, never execution evidence.
function changePreparation(input, edit) {
  const preparation = JSON.parse(input.proof.preparation); edit(preparation);
  input.proof.preparation = json(preparation);
  input.authentication.preparationSHA256 = digest(input.proof.preparation);
}
function changeLog(input, edit) {
  input.proof.log = edit(input.proof.log);
  changePreparation(input, preparation => { preparation.steps[0].logSHA256 = digest(input.proof.log); });
}

test('local origin retains genuine170 accounting, original source and unexecuted credential claim', () => {
  const input = fixture(), result = accountLocalMacHostExecution(input);
  assert.equal(result.accepted, true);
  assert.equal(result.origin.provider, 'local-mac');
  assert.equal(result.origin.head, head);
  assert.equal(Object.hasOwn(result.origin, 'runId'), false);
  assert.deepEqual(result.origin.counts, { tests: 170, pass: 169, fail: 0, skipped: 1 });
  assert.equal(result.origin.cases.filter(item => item.status === 'EXECUTED_PASS').length, 169);
  assert.deepEqual(result.origin.cases.filter(item => item.status === 'SKIPPED'), [{ name: originalSkip, status: 'SKIPPED' }]);
  assert.equal(result.repositoryCredentialFreeHostTests.status, 'NOT_RUN');
  assert.equal(result.origin.nativeFrameworks.status, 'REUSED_VERIFIED_PASS');
});
test('local consumer requires the independently trusted producer pin and recomputes raw proof', () => {
  const input = fixture();
  const receipt = { schemaVersion: 3, provider: 'local-mac', status: 'EXECUTED_PASS', repository: input.repository,
    head, hostMetadata: input.hostMetadata, hostAccounting: accountLocalMacHostExecution(input),
    verification: { nodeFingerprint: input.nodeFingerprint, nativeInputSHA256: input.nativeInputSHA256 } };
  assert.equal(verifiedReceiptAccounting(receipt, input.proof, input.authentication), true);
  assert.equal(verifiedReceiptAccounting(receipt, input.proof), false);
  assert.equal(verifiedReceiptAccounting(receipt, input.proof, { preparationSHA256: 'f'.repeat(64) }), false);
  const changed = structuredClone(receipt); changed.hostAccounting.origin.counts.pass++;
  assert.equal(verifiedReceiptAccounting(changed, input.proof, input.authentication), false);
  const proof = structuredClone(input.proof); proof.log += 'later unverified output\n';
  assert.equal(verifiedReceiptAccounting(receipt, proof, input.authentication), false);
});
for (const [label, edit, reason] of [
  ['missing independent pin', input => { input.authentication = {}; }, 'UNAUTHENTICATED_LOCAL_PRODUCER_RECEIPT'],
  ['tampered original receipt', input => { input.proof.preparation += ' '; }, 'UNAUTHENTICATED_LOCAL_PRODUCER_RECEIPT'],
  ['different source commit', input => { input.head = '3'.repeat(40); }, 'LOCAL_PRODUCER_SOURCE_IDENTITY_MISMATCH'],
  ['module derivative archive', input => { input.archiveSHA256 = 'c'.repeat(64); }, 'LOCAL_HOST_ARCHIVE_SOURCE_OR_TOOLCHAIN_MISMATCH'],
  ['changed source closure', input => { input.sourceInputsHash = 'd'.repeat(64); }, 'LOCAL_HOST_ARCHIVE_SOURCE_OR_TOOLCHAIN_MISMATCH'],
  ['unrecorded toolchain', input => { input.nodeFingerprint.versions.node = '24.22.0'; }, 'LOCAL_HOST_ARCHIVE_SOURCE_OR_TOOLCHAIN_MISMATCH'],
  ['non-Mac origin', input => { input.nodeFingerprint.platform = 'linux'; }, 'LOCAL_HOST_ARCHIVE_SOURCE_OR_TOOLCHAIN_MISMATCH'],
  ['changed controller', input => { input.proof.controller += '# change\n'; }, 'LOCAL_PRODUCER_CONTROLLER_MISMATCH'],
  ['changed native input', input => { input.nativeInputSHA256['input-0'] = 'e'.repeat(64); }, 'LOCAL_NATIVE_OR_LOCK_PROVENANCE_MISMATCH'],
  ['changed native inventory', input => { input.proof.nativeInventory += ' '; }, 'LOCAL_NATIVE_OR_LOCK_PROVENANCE_MISMATCH'],
  ['changed native catalog', input => { input.proof.nativeCatalog += ' '; }, 'LOCAL_NATIVE_OR_LOCK_PROVENANCE_MISMATCH'],
  ['failed producer', input => changePreparation(input, prep => { prep.status = 'FAILED'; }), 'LOCAL_PRODUCER_NOT_COMPLETED'],
  ['reuse-only producer', input => changePreparation(input, prep => { prep.hostResult = 'REUSED_VERIFIED_PASS'; }), 'LOCAL_PRODUCER_NOT_COMPLETED'],
  ['failed Host step', input => changePreparation(input, prep => { prep.steps[0].exitCode = 1; }), 'LOCAL_HOST_STEP_OR_RAW_LOG_MISMATCH'],
  ['different command', input => changePreparation(input, prep => { prep.steps[0].argv.push('--skip-tests'); }), 'LOCAL_HOST_STEP_OR_RAW_LOG_MISMATCH'],
  ['ambiguous Host steps', input => changePreparation(input, prep => { prep.steps.push(prep.steps[0]); }), 'LOCAL_HOST_STEP_OR_RAW_LOG_MISMATCH'],
  ['unfinished Host step', input => changePreparation(input, prep => { delete prep.steps[0].finishedAt; }), 'LOCAL_HOST_STEP_OR_RAW_LOG_MISMATCH'],
  ['incomplete native closure', input => changePreparation(input, prep => { prep.archiveQualification.pop(); }), 'LOCAL_NATIVE_OR_LOCK_PROVENANCE_MISMATCH'],
]) test(`${label} cannot qualify a local producer`, () => {
  const input = fixture(); edit(input);
  const result = accountLocalMacHostExecution(input);
  assert.equal(result.accepted, false);
  assert.ok(result.reasons.includes(reason), JSON.stringify(result.reasons));
});
for (const [label, edit] of [
  ['historical153 summary', log => log.replace('tests 170', 'tests 153').replace('pass 169', 'pass 152')],
  ['summary with missing actual case', log => log.replace('✔ real fixture case 1 (1.25ms)\n', '')],
  ['indented nested case transcript', log => log.replace(/^([✔﹣])/gm, '  $1')],
  ['duplicate case identity', log => log.replace('real fixture case 2 (', 'real fixture case 1 (')],
  ['ambiguous suite summaries', log => log.replace('ℹ tests 170', 'ℹ tests 170\nℹ tests 170')],
  ['different skipped obligation', log => log.replace(originalSkip, 'another test')],
  ['hidden cancellation', log => log.replace('cancelled 0', 'cancelled 1')],
  ['hidden todo', log => log.replace('todo 0', 'todo 1')],
  ['absent packed smoke', log => log.replace('"passed":true', '"passed":false')],
  ['missing fetch contract', log => log.replace(',"204"', '')],
  ['second original test invocation', log => '> node --test Tests/*.test.mjs\n' + log],
  ['nonterminal archive completion', log => log + 'unverified trailing output\n'],
]) test(`${label} cannot substitute for original170 acceptance`, () => {
  const input = fixture(); changeLog(input, edit);
  assert.equal(localMacHostLog(input.proof.log, archiveSHA256), null);
  const result = accountLocalMacHostExecution(input);
  assert.equal(result.accepted, false);
  assert.ok(result.reasons.includes('LOCAL_HOST_170_CASE_OR_PACKED_PROBE_MISMATCH'));
});
