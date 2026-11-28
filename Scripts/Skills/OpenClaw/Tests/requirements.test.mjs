import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { readFile } from 'node:fs/promises';
import { test } from 'node:test';
import vm from 'node:vm';
import { probeOriginalRequirements } from '../memory-probe.mjs';

const root = new URL('../', import.meta.url);
const artifact = await readFile(new URL('generated/requirements.js', root));
const provenance = JSON.parse(await readFile(new URL('generated/provenance.json', root)));
assert.equal(createHash('sha256').update(artifact).digest('hex'), provenance.artifactSHA256);
const context = vm.createContext({});
new vm.Script(artifact.toString('utf8')).runInContext(context, { timeout: 1000 });
const original = context.HanlinOpenClawOriginalRequirements;

test('pinned original upstream five tests/assertions execute against the built artifact', async () => {
  const cases = [], suites = []; let assertions = 0;
  context.__hanlinOriginalTestHost = {
    suite: name => suites.push(name), passed: name => cases.push(name),
    equal(a, b) { assertions++; assert.deepStrictEqual(a, b); },
    identical(a, b) { assertions++; assert.equal(a, b); }
  };
  const bytes = await readFile(new URL('generated/upstream-requirements-tests.js', root));
  assert.equal(createHash('sha256').update(bytes).digest('hex'), provenance.originalTestArtifactSHA256);
  new vm.Script(bytes.toString('utf8')).runInContext(context, { timeout: 1000 });
  assert.equal(cases.length, 5); assert.equal(suites.length, 1); assert.equal(assertions, 16);
});

test('artifact exposes exactly the original pure API with no runtime imports', () => {
  assert.deepEqual(Object.keys(original).sort(), ['evaluateRequirementsFromMetadataWithRemote', 'isOsRequirementSatisfied']);
  assert.deepEqual(provenance.runtimeDependencies, []);
  assert.ok(!artifact.toString().includes('require('));
});

test('native and iSH fact snapshots cannot supply each other binary availability', () => {
  const metadata = { requires: { bins: ['node', 'python3'] } };
  const native = probeOriginalRequirements(original, { metadataStatus: 'supported', metadata, snapshot: { scope: 'native', platform: 'darwin', bins: { node: true, python3: false } } });
  const ish = probeOriginalRequirements(original, { metadataStatus: 'supported', metadata, snapshot: { scope: 'ish', platform: 'linux', bins: { node: false, python3: true } } });
  assert.equal(native.rawUpstreamResult.eligible, false); assert.equal(ish.rawUpstreamResult.eligible, false);
  assert.deepEqual(Array.from(native.rawUpstreamResult.missing.bins), ['python3']);
  assert.deepEqual(Array.from(ish.rawUpstreamResult.missing.bins), ['node']);
});

test('missing observations stay unknown instead of becoming verified negative facts', () => {
  const result = probeOriginalRequirements(original, { metadataStatus: 'supported', metadata: { requires: { env: ['KEY'], config: ['feature.enabled'] } }, snapshot: { scope: 'native', platform: 'darwin', env: { KEY: true } } });
  assert.equal(result.executionVerified, false); assert.deepEqual(result.unobserved, [{ kind: 'config', key: 'feature.enabled' }]);
});

test('absent and unsupported metadata never establish readiness', () => {
  const absent = probeOriginalRequirements(original, { metadataStatus: 'absent', snapshot: { scope: 'native', platform: 'darwin' } });
  assert.equal(absent.rawUpstreamResult.eligible, true); assert.equal(absent.declaredMetadata, false); assert.equal(absent.executionVerified, false);
  const unsupported = probeOriginalRequirements(original, { metadataStatus: 'unsupported' });
  assert.equal(unsupported.rawUpstreamResult, null); assert.equal(unsupported.executionVerified, false);
});

test('dynamic memory snapshots observe newly installed and removed binaries', () => {
  const input = { metadataStatus: 'supported', metadata: { requires: { bins: ['jq'] } }, snapshot: { scope: 'native', platform: 'darwin', bins: { jq: false } } };
  assert.equal(probeOriginalRequirements(original, input).rawUpstreamResult.eligible, false);
  input.snapshot.bins.jq = true;
  assert.equal(probeOriginalRequirements(original, input).rawUpstreamResult.eligible, true);
  input.snapshot.bins.jq = false;
  assert.equal(probeOriginalRequirements(original, input).rawUpstreamResult.eligible, false);
});
