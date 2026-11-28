import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { readFile } from 'node:fs/promises';
import { test } from 'node:test';
import * as original from '../generated/policy.mjs';

test('exact original policy artifact and dependency closure are pinned', async () => {
  const artifact = await readFile(new URL('../generated/policy.mjs', import.meta.url));
  const provenance = JSON.parse(await readFile(new URL('../generated/policy-provenance.json', import.meta.url)));
  assert.equal(createHash('sha256').update(artifact).digest('hex'), provenance.artifactSHA256);
  assert.deepEqual(Object.keys(original).sort(), provenance.exports);
  assert.deepEqual(provenance.runtimeImports, ['node:fs', 'node:module', 'node:path']);
  assert.deepEqual(Object.keys(provenance.bundledDependencies).sort(), ['json5', 'semver']);
});

test('28 unchanged upstream policy tests run against the production artifact', async () => {
  const selection = JSON.parse(await readFile(new URL('../generated/policy-original-test-selection.json', import.meta.url)));
  const bytes = await readFile(new URL('../generated/upstream-policy-tests.mjs', import.meta.url));
  assert.equal(createHash('sha256').update(bytes).digest('hex'), selection.transformedArtifactSHA256);
  const { results } = await import('../generated/upstream-policy-tests.mjs');
  assert.equal(results.cases.length, selection.expectedTestInvocations);
  assert.ok(results.assertions >= 60);
});

test('original selection, source allowlist and disabled policy retain separate authority', () => {
  const entry = { skill: { name: 'visible-name', source: 'openclaw-bundled' }, metadata: { skillKey: 'stable-key', always: true } };
  assert.equal(original.isSkillEntrySelected(entry, [], undefined), false);
  assert.equal(original.isSkillEntrySelected(entry, [], { 'stable-key': true }), true);
  assert.equal(original.isSkillEntrySelected(entry, ['visible-name'], { 'stable-key': false }), false);
  const include = config => original.shouldIncludeSkill({ entry, config, platform: 'darwin',
    bundledAllowlist: original.resolveBundledAllowlist(config), hasBin: () => { throw Error('Unexpected filesystem/binary probe'); } });
  assert.equal(include({ skills: { allowBundled: [] } }), false);
  assert.equal(include({ skills: { allowBundled: ['stable-key'] } }), true);
  assert.equal(include({ skills: { entries: { 'stable-key': { enabled: false } } } }), false);
  const workshop = { ...entry, skill: { ...entry.skill, source: 'openclaw-workshop' } };
  assert.equal(original.isSkillEntrySelected(workshop, [], { 'stable-key': false }), true);
});

test('original invocation policy and install preferences are data, not installation', () => {
  assert.deepEqual(original.resolveSkillInvocationPolicy({ 'user-invocable': 'false', 'disable-model-invocation': 'true' }),
    { userInvocable: false, disableModelInvocation: true });
  assert.deepEqual(original.resolveSkillsInstallPreferences(), { preferBrew: true, nodeManager: 'npm' });
  assert.deepEqual(original.resolveSkillsInstallPreferences({ skills: { install: { preferBrew: false, nodeManager: 'pnpm' } } }),
    { preferBrew: false, nodeManager: 'pnpm' });
});
