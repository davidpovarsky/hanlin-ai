// Verify a completed local Mac producer. This module never builds, tests or changes artifacts.
import { createHash } from 'node:crypto';
import { isDeepStrictEqual as same } from 'node:util';

const digest = value => createHash('sha256').update(value).digest('hex');
const sha256 = value => /^[a-f0-9]{64}$/.test(value ?? '');
const commit = value => /^[a-f0-9]{40}$/.test(value ?? '');
const repositoryName = value => /^[\w.-]+\/[\w.-]+$/.test(value ?? '');
export const LOCAL_MAC_HOST_COUNTS = Object.freeze({ tests: 170, pass: 169, fail: 0, skipped: 1 });
const terminalCounts = { tests: 170, suites: 0, pass: 169, fail: 0, cancelled: 0, skipped: 1, todo: 0 };
const originalSkip = 'actual Node job crosses 300 seconds with no hidden deadline';
const supportTargets = ['HanlinExpoHeaderSupport', 'HanlinExpoWidgetRuntimeSupport',
  'HanlinNativeScriptHostSupport', 'HanlinNodeHostSupport', 'HanlinPythonHostSupport'];
const fetchContracts = ['GET', 'Request POST Unicode', 'redirect', 'HTTP error', 'ReadableStream',
  'clone', 'gzip', 'multipart File', 'abort', 'HEAD', '204'];

export function localMacHostLog(log, archiveSHA256) {
  if (typeof log !== 'string' || !sha256(archiveSHA256)) return null;
  const lines = log.split(/\r?\n/);
  const command = '> node --test Tests/*.test.mjs';
  const starts = lines.flatMap((line, index) => line === command ? [index] : []);
  const counts = {};
  let summaryIndex = -1;
  for (const [index, line] of lines.entries()) {
    const match = /^ℹ (tests|suites|pass|fail|cancelled|skipped|todo) (\d+)\s*$/.exec(line);
    if (!match) continue;
    if (Object.hasOwn(counts, match[1])) return null;
    counts[match[1]] = Number(match[2]);
    if (summaryIndex < 0) summaryIndex = index;
  }
  if (starts.length !== 1 || summaryIndex <= starts[0] || !same(counts, terminalCounts)) return null;
  const cases = [];
  for (const line of lines.slice(starts[0] + 1, summaryIndex)) {
    // Only root-level spec-reporter records qualify, never indented/nested transcripts.
    const match = /^([✔﹣✖]) (.+) \((\d+(?:\.\d+)?)ms\)(?: # (SKIP|TODO)(?: .*)?)?$/.exec(line);
    if (!match) continue;
    if (match[1] === '✔' && !match[4]) cases.push({ name: match[2], status: 'EXECUTED_PASS' });
    else if (match[1] === '﹣' && match[4] === 'SKIP') cases.push({ name: match[2], status: 'SKIPPED' });
    else return null;
  }
  if (cases.length !== 170 || new Set(cases.map(item => item.name)).size !== 170
      || cases.filter(item => item.status === 'EXECUTED_PASS').length !== 169
      || !same(cases.filter(item => item.status === 'SKIPPED'), [{ name: originalSkip, status: 'SKIPPED' }])) return null;
  const prepared = lines.filter(line => /^Prepared RuntimeHostResources\.zip \(/.test(line));
  const lastLine = lines.filter(line => line.trim()).at(-1);
  if (!same(prepared, [`Prepared RuntimeHostResources.zip (${archiveSHA256}).`]) || lastLine !== prepared[0]) return null;
  const probes = lines.slice(summaryIndex).flatMap(line => {
    try { const value = JSON.parse(line); return value?.passed === true ? [value] : []; }
    catch { return []; }
  });
  if (probes.length !== 1 || probes[0].webAssemblyAvailable !== false
      || typeof probes[0].fetchImplementation !== 'string' || !probes[0].fetchImplementation
      || !same(probes[0].contracts, fetchContracts)) return null;
  return { counts: LOCAL_MAC_HOST_COUNTS, cases, packedJitlessProbe: probes[0], logSHA256: digest(log) };
}

function decode(value) {
  if (typeof value !== 'string') return null;
  try { return JSON.parse(value); } catch { return null; }
}
function instant(value) { return typeof value === 'string' ? Date.parse(value) : NaN; }

export function accountLocalMacHostExecution({ repository, head, archiveSHA256, sourceInputsHash,
  nodeFingerprint, hostMetadata, nativeInputSHA256, proof = {}, authentication = {} }) {
  const reasons = [];
  const preparation = decode(proof.preparation);
  const catalog = decode(proof.nativeCatalog);
  const inventory = decode(proof.nativeInventory);
  const receiptHash = typeof proof.preparation === 'string' ? digest(proof.preparation) : null;
  if (!sha256(authentication.preparationSHA256) || receiptHash !== authentication.preparationSHA256)
    reasons.push('UNAUTHENTICATED_LOCAL_PRODUCER_RECEIPT');
  if (!repositoryName(repository) || !commit(head) || preparation?.source !== head)
    reasons.push('LOCAL_PRODUCER_SOURCE_IDENTITY_MISMATCH');
  if (preparation?.status !== 'PREPARED' || preparation?.hostResult !== 'EXECUTED_PASS'
      || preparation?.error || !Number.isFinite(instant(preparation?.startedAt))
      || !(instant(preparation?.finishedAt) > instant(preparation?.startedAt)))
    reasons.push('LOCAL_PRODUCER_NOT_COMPLETED');
  if (typeof proof.controller !== 'string' || !sha256(preparation?.controllerSHA256)
      || digest(proof.controller ?? '') !== preparation?.controllerSHA256)
    reasons.push('LOCAL_PRODUCER_CONTROLLER_MISMATCH');
  const steps = Array.isArray(preparation?.steps) ? preparation.steps.filter(step => step.name === 'original-host') : [];
  const step = steps.length === 1 ? steps[0] : null;
  if (!step || step.status !== 'EXECUTED_PASS' || step.exitCode !== 0
      || !same(step.argv, ['/bin/bash', 'Scripts/Runtime/prepare-runtime-host.sh'])
      || !(instant(step.startedAt) >= instant(preparation?.startedAt))
      || !(instant(step.finishedAt) > instant(step.startedAt))
      || !(instant(step.finishedAt) <= instant(preparation?.finishedAt))
      || !(step.elapsedSeconds > 0) || typeof proof.log !== 'string'
      || step.logSHA256 !== digest(proof.log ?? '')) reasons.push('LOCAL_HOST_STEP_OR_RAW_LOG_MISMATCH');
  if (!sha256(archiveSHA256) || !sha256(sourceInputsHash)
      || preparation?.runtimeHostZipSHA256 !== archiveSHA256
      || hostMetadata?.archiveSha256 !== archiveSHA256 || hostMetadata?.sourceInputsHash !== sourceInputsHash
      || !same(hostMetadata, preparation?.hostMetadata)
      || hostMetadata?.tests !== 'passed' || hostMetadata?.jitlessArchiveSmoke !== 'passed'
      || hostMetadata?.nodeVersion !== 'v24.5.0' || preparation?.toolchain?.node !== 'v24.5.0'
      || nodeFingerprint?.versions?.node !== '24.5.0' || nodeFingerprint?.platform !== 'darwin'
      || nodeFingerprint?.arch !== 'arm64') reasons.push('LOCAL_HOST_ARCHIVE_SOURCE_OR_TOOLCHAIN_MISMATCH');
  const qualification = preparation?.catalogQualification;
  const nativeReuse = preparation?.nativeFrameworksReused;
  const artifacts = Array.isArray(catalog?.artifacts) ? catalog.artifacts : [];
  const support = Array.isArray(catalog?.supportArtifacts) ? catalog.supportArtifacts : [];
  const records = [...artifacts, ...support];
  const names = artifacts.map(item => item.target);
  const nativeInputs = catalog?.inputSHA256;
  const archiveProof = Array.isArray(preparation?.archiveQualification) ? preparation.archiveQualification : [];
  const identity = digest(JSON.stringify(Object.fromEntries(records.map(item => [item.target, item.checksum]).sort(([a], [b]) => a < b ? -1 : a > b ? 1 : 0))));
  if (!catalog || typeof proof.nativeCatalog !== 'string' || digest(proof.nativeCatalog) !== qualification?.sha256
      || catalog.schemaVersion !== 1 || catalog.repository !== repository || catalog.scope !== 'full'
      || catalog.state !== 'prepared' || !same(catalog.missingTargets, [])
      || !commit(catalog.sourceCommit) || catalog.sourceCommit !== preparation?.producerExecutedSource
      || artifacts.length !== 15 || new Set(names).size !== 15
      || !same([...names].sort(), [...(catalog.requiredTargets ?? [])].sort())
      || !same(support.map(item => item.target).sort(), [...supportTargets].sort())
      || catalog.contentSHA256 !== identity || catalog.releaseTag !== `sdk-native-v1-${identity}`
      || records.some(item => !sha256(item.checksum)
        || item.url !== `https://github.com/${repository}/releases/download/${catalog.releaseTag}/${item.archive}`)
      || qualification?.targetCount !== 15 || qualification?.nativeInputFiles !== 16
      || qualification?.producerOriginalExportAndVerify !== 'EXECUTED_PASS'
      || !nativeInputs || Object.keys(nativeInputs).length !== 16
      || Object.values(nativeInputs).some(value => !sha256(value)) || !same(nativeInputSHA256, nativeInputs)
      || archiveProof.length !== records.length || new Set(archiveProof.map(item => item.target)).size !== records.length
      || records.some(item => !archiveProof.some(row => row.target === item.target && row.sha256 === item.checksum
        && row.status === 'EXACT_ARCHIVE_AND_INSTALLED_BYTES' && row.regularFiles > 0 && row.entries >= row.regularFiles))
      || !inventory || typeof proof.nativeInventory !== 'string'
      || digest(proof.nativeInventory) !== nativeReuse?.inventorySHA256
      || nativeReuse?.status !== 'REUSED_VERIFIED_PASS'
      || Object.keys(inventory).length !== nativeReuse?.unchangedFiles
      || nativeReuse?.unchangedFiles !== qualification?.frameworkFileCount)
    reasons.push('LOCAL_NATIVE_OR_LOCK_PROVENANCE_MISMATCH');
  const fresh = localMacHostLog(proof.log, archiveSHA256);
  if (!fresh) reasons.push('LOCAL_HOST_170_CASE_OR_PACKED_PROBE_MISMATCH');
  const accepted = reasons.length === 0;
  const origin = accepted ? { provider: 'local-mac', repository, head, stage: 'original-host', status: 'EXECUTED_PASS',
    preparationSHA256: receiptHash, controllerSHA256: preparation.controllerSHA256,
    startedAt: step.startedAt, finishedAt: step.finishedAt, elapsedSeconds: step.elapsedSeconds,
    command: step.argv, archiveSHA256, sourceInputsHash, toolchain: preparation.toolchain,
    nativeFrameworks: { ...nativeReuse, producerSource: catalog.sourceCommit, catalogSHA256: qualification.sha256 },
    ...fresh } : null;
  return { schemaVersion: 3, provider: 'local-mac', accepted, status: accepted ? 'EXECUTED_PASS' : 'UNKNOWN', reasons, origin,
    directHostStage: { status: accepted ? 'EXECUTED_PASS' : 'NOT_RUN', testsExecutedHere: accepted },
    repositoryCredentialFreeHostTests: { status: 'NOT_RUN', reason: 'The original local producer did not record caller credential presence.' },
    crossRunReuse: 'NOT_ACCEPTED_WITHOUT_A_SEPARATE_AUTHENTICATED_ORIGIN_AND_COMPLETE_UNCHANGED_INPUT_CLOSURE' };
}

export function verifiedLocalMacReceiptAccounting(receipt, proof, authentication) {
  if (receipt?.schemaVersion !== 3 || receipt.provider !== 'local-mac' || receipt.status !== 'EXECUTED_PASS'
      || receipt.hostAccounting?.accepted !== true || !authentication?.preparationSHA256) return false;
  const recomputed = accountLocalMacHostExecution({ repository: receipt.repository, head: receipt.head,
    archiveSHA256: receipt.hostMetadata?.archiveSha256, sourceInputsHash: receipt.hostMetadata?.sourceInputsHash,
    nodeFingerprint: receipt.verification?.nodeFingerprint, hostMetadata: receipt.hostMetadata,
    nativeInputSHA256: receipt.verification?.nativeInputSHA256, proof, authentication });
  return recomputed.accepted && same(recomputed, receipt.hostAccounting);
}
