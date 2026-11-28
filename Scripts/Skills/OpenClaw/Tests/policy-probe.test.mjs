import assert from 'node:assert/strict';
import { test } from 'node:test';
import * as original from '../generated/policy.mjs';
import { probeOriginalPolicy } from '../policy-probe.mjs';

const input = (metadata, extra = {}) => ({
  scope: 'native', name: 'fixture', enabled: true, platform: 'darwin',
  metadataPresence: metadata === undefined ? 'absent' : 'present',
  frontmatter: metadata === undefined ? {} : { metadata: JSON.stringify({ openclaw: metadata }) },
  bins: {}, configFacts: {}, ...extra
});

test('missing observations remain unknown but original any-bin and always short circuits stay decisive', () => {
  const missing = probeOriginalPolicy(original, input({ requires: { bins: ['not-observed'] } }));
  assert.equal(missing.known, false); assert.equal(missing.executionVerified, false);
  assert.deepEqual(missing.unobserved, ['bins:not-observed']);
  const any = probeOriginalPolicy(original, input({ requires: { anyBins: ['not-observed', 'node'] } }, { bins: { node: true } }));
  assert.equal(any.known, true); assert.equal(any.rawUpstreamResult.eligible, true);
  const always = probeOriginalPolicy(original, input({ always: true, requires: { config: ['browser.enabled'] } }));
  assert.equal(always.known, true); assert.equal(always.rawUpstreamResult.eligible, true);
  const wrongOS = probeOriginalPolicy(original, input({ always: true, os: ['linux'] }));
  assert.equal(wrongOS.known, true); assert.equal(wrongOS.rawUpstreamResult.eligible, false);
});

test('unknown OpenClaw config cannot inherit a browser default as a verified Hanlin capability', () => {
  const value = probeOriginalPolicy(original, input({ requires: { config: ['browser.enabled'] } }));
  assert.equal(value.known, false);
  const observed = probeOriginalPolicy(original, input({ requires: { config: ['browser.enabled'] } }, { configFacts: { 'browser.enabled': true } }));
  assert.equal(observed.known, true); assert.equal(observed.rawUpstreamResult.eligible, true);
});

test('original disabled and degraded owner controls are isolated between inspections', () => {
  const metadata = { always: true, skillKey: 'stable-key' };
  const disabled = probeOriginalPolicy(original, input(metadata, { enabled: false }));
  assert.equal(disabled.known, true); assert.equal(disabled.rawUpstreamResult.eligible, false);
  const degraded = probeOriginalPolicy(original, input(metadata, {
    degradedOwners: [{ ownerKind: 'capability', ownerId: 'skill:stable-key', state: 'unavailable', paths: [], refKeys: [], reason: 'secret provider failed' }]
  }));
  assert.equal(degraded.rawUpstreamResult.eligible, false);
  assert.equal(probeOriginalPolicy(original, input(metadata)).rawUpstreamResult.eligible, true);
});

test('native snapshots cannot borrow iSH platform or observations', () => {
  assert.throws(() => probeOriginalPolicy(original, input({ always: true }, { scope: 'ish' })), /input boundary/);
  const native = probeOriginalPolicy(original, input({ requires: { bins: ['python3'] } }, { bins: { node: true } }));
  assert.equal(native.known, false); assert.equal(native.factScope, 'native');
});

test('absent, invalid and future requirement shapes never become execution proof', () => {
  const absent = probeOriginalPolicy(original, input(undefined));
  assert.equal(absent.metadataStatus, 'absent'); assert.equal(absent.declaredMetadata, false); assert.equal(absent.executionVerified, false);
  for (const metadata of [[], { always: 'yes' }, { requires: { futureGPU: [] } }, { requires: { bins: 7 } }]) {
    const value = probeOriginalPolicy(original, input(metadata));
    assert.equal(value.known, false); assert.equal(value.metadataStatus, 'unsupported');
  }
  const invalid = probeOriginalPolicy(original, input({}, { frontmatter: { metadata: 'not-json5' } }));
  assert.equal(invalid.metadataStatus, 'unsupported');
});

test('original JSON5, CSV normalization and install-hint rejection survive the typed boundary', () => {
  const value = probeOriginalPolicy(original, input({}, {
    frontmatter: { metadata: "{openclaw:{requires:{bins:'node'},install:[{kind:'node',package:'file:../escape'},{kind:'node',package:'@scope/ok@1.2.3'}]}}" },
    bins: { node: true }
  }));
  assert.equal(value.metadataStatus, 'supported'); assert.equal(value.rawUpstreamResult.eligible, true);
  assert.deepEqual(value.installHints, [{ kind: 'node', package: '@scope/ok@1.2.3' }]);
});

test('rechecking actual snapshots observes both installation and removal without a stale eligibility cache', () => {
  const params = input({ requires: { bins: ['tool'] } }, { bins: { tool: false } });
  assert.equal(probeOriginalPolicy(original, params).rawUpstreamResult.eligible, false);
  params.bins.tool = true;
  assert.equal(probeOriginalPolicy(original, params).rawUpstreamResult.eligible, true);
  params.bins.tool = false;
  assert.equal(probeOriginalPolicy(original, params).rawUpstreamResult.eligible, false);
});
