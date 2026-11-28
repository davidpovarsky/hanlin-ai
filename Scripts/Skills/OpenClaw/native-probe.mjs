import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { readFile, writeFile } from 'node:fs/promises';
import path from 'node:path';

// Owned diagnostic resources only. The original eligibility artifact itself imports nothing;
// its callbacks below use synthetic memory facts, not PATH/env/config or installed Skills.
const resultPath = process.env.HANLIN_OPENCLAW_PROBE_RESULT
  ?? path.join(process.env.HOME, 'Documents', 'hanlin-openclaw-probe.json');
const started = performance.now();
const before = process.memoryUsage();
const results = [];
let failure;
let artifactIdentity;
const challenge = process.argv[2];
try {
  assert.equal(process.versions.node, '24.5.0');
  assert.ok(process.execArgv.includes('--jitless'));
  assert.match(challenge ?? '', /^[a-f0-9]{32}$/);
  const provenance = JSON.parse(await readFile(new URL('./generated/provenance.json', import.meta.url)));
  artifactIdentity = { revision: provenance.revision, artifactSHA256: provenance.artifactSHA256, nativeContractArtifactSHA256: provenance.nativeContractArtifactSHA256 };
  const contract = await readFile(new URL('./generated/native-contract.mjs', import.meta.url));
  assert.equal(createHash('sha256').update(contract).digest('hex'), provenance.nativeContractArtifactSHA256);
  globalThis.__hanlinMemoryProbeCases = [];
  await import('./generated/native-contract.mjs');
  assert.equal(globalThis.__hanlinMemoryProbeCases.length, 6);
  for (const entry of globalThis.__hanlinMemoryProbeCases) {
    const start = performance.now();
    try { await entry.body(); results.push({ name: entry.name, status: 'EXECUTED_PASS', milliseconds: performance.now() - start }); }
    catch (error) { results.push({ name: entry.name, status: 'FAILED', error: String(error?.stack ?? error) }); }
  }
  assert.ok(results.every(value => value.status === 'EXECUTED_PASS'));
} catch (error) { failure = String(error?.stack ?? error); }
const report = {
  ok: !failure, failure, scope: 'in-process original Node requirements diagnostic; actual environment identified below',
  node: process.versions.node, v8: process.versions.v8, platform: process.platform, arch: process.arch,
  challenge, artifactIdentity,
  execArgv: process.execArgv, cases: results,
  measuredMilliseconds: performance.now() - started, memoryBefore: before, memoryAfter: process.memoryUsage(),
  facts: 'synthetic scoped in-memory fixtures; no actual binary/env/config availability is established',
  skillExecution: 'NOT_RUN', hanlinReadiness: 'NOT_ASSERTED',
  physicalIPadStartupAndRAM: 'NOT_RUN', fullHanlinAppIntegration: 'NOT_RUN',
  disabledInstallHintsAndToolVisibility: 'OUT_OF_SCOPE_FOR_THIS_PURE_REQUIREMENTS_SUBSET'
};
await writeFile(resultPath, JSON.stringify(report, null, 2));
console.log(JSON.stringify({ hanlinOpenClawProbe: report.ok, cases: results.length }));
if (!report.ok) process.exitCode = 1;
