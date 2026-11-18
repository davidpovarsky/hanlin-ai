import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { readFile, writeFile } from 'node:fs/promises';
import { createRequire, registerHooks } from 'node:module';

// Test-job observation only: no production permission, engine or global OS network
// change. Install hints remain data. The exact policy loads after these observers.
function observeOfflinePolicyBoundary() {
  const controlAttempts = [], policyAttempts = [], restoreProperties = [];
  let phase = 'controls', hooks, restored = false;
  const networkModules = new Set(['http', 'https', 'http2', 'net', 'tls', 'dns', 'dgram', 'undici', 'node-fetch', 'ws']);
  const installerModules = new Set(['npm', 'npm-cli', 'npx', 'pnpm', 'yarn', 'corepack', 'bun']);
  const launchModules = new Set(['child_process', 'cluster', 'worker_threads']);
  const moduleKind = specifier => {
    if (specifier === 'hanlin:runtime') return 'processLaunch';
    const name = String(specifier).replace(/^node:/, ''), root = name.split('/')[0];
    if (/^https?:/.test(name) || networkModules.has(root)) return 'network';
    if (installerModules.has(root)) return 'installer';
    if (launchModules.has(root)) return 'processLaunch';
  };
  const deny = (kind, entryPoint) => {
    (phase === 'controls' ? controlAttempts : policyAttempts).push({ kind, entryPoint });
    const error = new Error('Offline policy probe forbids ' + entryPoint);
    error.code = 'HANLIN_OPENCLAW_OFFLINE_PROBE';
    throw error;
  };
  const replace = (target, key, value) => {
    const descriptor = Object.getOwnPropertyDescriptor(target, key);
    if (descriptor && !descriptor.configurable) {
      assert.ok('value' in descriptor && descriptor.writable, 'Observation target is not replaceable: ' + key);
      Object.defineProperty(target, key, { ...descriptor, value });
    } else {
      Object.defineProperty(target, key, { configurable: true, writable: true,
        enumerable: descriptor?.enumerable ?? true, value });
    }
    restoreProperties.push(() => {
      if (descriptor) Object.defineProperty(target, key, descriptor);
      else delete target[key];
    });
  };
  const restore = () => {
    if (restored) return;
    const errors = [];
    try { hooks?.deregister(); } catch (error) { errors.push(error); }
    for (const action of restoreProperties.reverse()) {
      try { action(); } catch (error) { errors.push(error); }
    }
    if (errors.length) throw new AggregateError(errors, 'Offline policy observer restoration failed');
    restored = true;
  };
  try {
    assert.equal(typeof registerHooks, 'function', 'Node 24.5 synchronous hooks must be available');
    for (const name of ['fetch', 'WebSocket', 'EventSource', 'XMLHttpRequest']) {
      replace(globalThis, name, function () { return deny('network', 'globalThis.' + name); });
    }
    const getBuiltinModule = process.getBuiltinModule;
    assert.equal(typeof getBuiltinModule, 'function');
    replace(process, 'getBuiltinModule', function (specifier) {
      const kind = moduleKind(specifier);
      if (kind) return deny(kind, 'process.getBuiltinModule:' + specifier);
      return getBuiltinModule.call(process, specifier);
    });
    hooks = registerHooks({ resolve(specifier, context, nextResolve) {
      const kind = moduleKind(specifier);
      if (kind) return deny(kind, 'module:' + specifier);
      return nextResolve(specifier, context);
    } });
    assert.equal(typeof hooks?.deregister, 'function', 'Probe must be able to restore its hook');
    const require = createRequire(import.meta.url);
    const blocked = { code: 'HANLIN_OPENCLAW_OFFLINE_PROBE' };
    assert.throws(() => globalThis.fetch('https://offline-control.invalid'), blocked);
    assert.throws(() => require('node:https'), blocked);
    assert.throws(() => process.getBuiltinModule('net'), blocked);
    assert.throws(() => require('node:child_process'), blocked);
    assert.throws(() => require('npm'), blocked);
    assert.throws(() => require('hanlin:runtime'), blocked);
    assert.equal(controlAttempts.length, 6);
    phase = 'policy';
    return {
      assertUnused() { assert.deepEqual(policyAttempts, [], 'Policy must not request network, installation or subprocess work'); },
      restore,
      receipt() {
        return { status: restored && policyAttempts.length === 0 ? 'EXECUTED_PASS' : 'FAILED',
          scope: 'Offline original-policy boundary only; not whole-app or physical-device offline acceptance',
          installedBeforePolicyImport: true, selfChecksPassed: controlAttempts.length,
          networkAttempts: policyAttempts.filter(x => x.kind === 'network').length,
          installerAttempts: policyAttempts.filter(x => x.kind === 'installer').length,
          processLaunchAttempts: policyAttempts.filter(x => x.kind === 'processLaunch').length,
          policyAttempts, restored };
      }
    };
  } catch (error) {
    restore();
    throw error;
  }
}

const challenge = process.argv[2];
const output = process.env.HANLIN_OPENCLAW_POLICY_RESULT;
assert.match(challenge ?? '', /^[a-f0-9]{32}$/);
assert.ok(output, 'Explicit owned result path required');
const started = performance.now(), memoryBefore = process.memoryUsage(), cases = [];
let failure, artifactIdentity, upstreamCases, upstreamAssertions, offlineObserver, offlinePolicyBoundary;
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
  offlineObserver = observeOfflinePolicyBoundary();
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
  offlineObserver.assertUnused();
} catch (error) { failure = String(error?.stack ?? error); }
finally {
  if (offlineObserver) {
    try { offlineObserver.restore(); }
    catch (error) { failure = [failure, String(error?.stack ?? error)].filter(Boolean).join('\n'); }
    offlinePolicyBoundary = offlineObserver.receipt();
  }
}
const report = {
  ok: !failure, failure, challenge, artifactIdentity, cases, upstreamCases, upstreamAssertions, offlinePolicyBoundary,
  node: process.versions.node, platform: process.platform, arch: process.arch, execArgv: process.execArgv,
  measuredMilliseconds: performance.now() - started, memoryBefore, memoryAfter: process.memoryUsage(),
  scope: 'Original policy and thin adapter in the existing Node engine, using owned synthetic fixtures',
  importedSkillExecution: 'NOT_RUN_BY_THIS_PROBE', physicalDeviceAcceptance: 'NOT_RUN'
};
await writeFile(output, JSON.stringify(report, null, 2));
console.log(JSON.stringify({ hanlinOriginalPolicy: report.ok, cases: cases.length, upstreamCases }));
if (!report.ok) process.exitCode = 1;
