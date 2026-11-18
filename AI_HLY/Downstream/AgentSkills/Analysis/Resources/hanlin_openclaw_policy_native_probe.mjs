import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { readFile, writeFile } from 'node:fs/promises';

const challenge = process.argv[2];
const output = process.env.HANLIN_OPENCLAW_POLICY_RESULT;
assert.match(challenge ?? '', /^[a-f0-9]{32}$/);
assert.ok(output, 'Explicit owned result path required');
const started = performance.now(), memoryBefore = process.memoryUsage(), cases = [];
let failure, artifactIdentity, upstreamCases, upstreamAssertions;
try {
  assert.equal(process.versions.node, '24.5.0');
  assert.ok(process.execArgv.includes('--jitless'));
  const provenance = JSON.parse(await readFile(new URL('./generated/policy-provenance.json', import.meta.url)));
  assert.equal(provenance.revision, '847611dcaa3bf0e2783335f961dd1fd0580e4d9f');
  for (const [file, hash] of Object.entries(provenance.nativeResources)) {
    const bytes = await readFile(new URL(file, import.meta.url));
    assert.equal(createHash('sha256').update(bytes).digest('hex'), hash, file);
  }
  artifactIdentity = { revision: provenance.revision, artifactSHA256: provenance.artifactSHA256,
    declarationClosureSHA256: provenance.declarationClosureSHA256, nativeContractSHA256: provenance.nativeResources['./generated/native-policy-contract.mjs'] };
  globalThis.__hanlinPolicyCases = [];
  await import('./generated/native-policy-contract.mjs');
  assert.equal(globalThis.__hanlinPolicyCases.length, 11);
  for (const entry of globalThis.__hanlinPolicyCases) {
    const begin = performance.now();
    try { await entry.body(); cases.push({ name: entry.name, status: 'EXECUTED_PASS', milliseconds: performance.now() - begin }); }
    catch (error) { cases.push({ name: entry.name, status: 'FAILED', error: String(error?.stack ?? error) }); }
  }
  const { results } = await import('./Tests/policy-upstream-shim.mjs');
  upstreamCases = results.cases.length; upstreamAssertions = results.assertions;
  assert.equal(upstreamCases, 28); assert.ok(upstreamAssertions >= 60);
  assert.ok(cases.every(value => value.status === 'EXECUTED_PASS'));
} catch (error) { failure = String(error?.stack ?? error); }
const report = {
  ok: !failure, failure, challenge, artifactIdentity, cases, upstreamCases, upstreamAssertions,
  node: process.versions.node, platform: process.platform, arch: process.arch, execArgv: process.execArgv,
  measuredMilliseconds: performance.now() - started, memoryBefore, memoryAfter: process.memoryUsage(),
  scope: 'Original policy and thin adapter in the existing Node engine, using owned synthetic fixtures',
  importedSkillExecution: 'NOT_RUN_BY_THIS_PROBE', physicalDeviceAcceptance: 'NOT_RUN'
};
await writeFile(output, JSON.stringify(report, null, 2));
console.log(JSON.stringify({ hanlinOriginalPolicy: report.ok, cases: cases.length, upstreamCases }));
if (!report.ok) process.exitCode = 1;
