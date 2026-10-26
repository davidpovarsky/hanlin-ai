import test from 'node:test';
import assert from 'node:assert/strict';
import { existsSync } from 'node:fs';
import { readdir, readFile } from 'node:fs/promises';
import { resolve } from 'node:path';

const repoRoot = resolve(import.meta.dirname, '..', '..', '..');

test('Packages/HanlinExpoNativeAPI does not vendor duplicate React or Hermes binaries', async () => {
  const artifactsDir = resolve(repoRoot, 'Packages', 'HanlinExpoNativeAPI', 'Artifacts');
  assert.ok(existsSync(artifactsDir), 'Artifacts dir must exist');

  const entries = await readdir(artifactsDir);
  for (const entry of entries) {
    assert.ok(
      !entry.toLowerCase().includes('react') && !entry.toLowerCase().includes('hermes'),
      `Forbidden duplicate runtime binary found: ${entry}`
    );
  }
});

test('Packages/HanlinExpoNativeAPI has native authorization gate injected', async () => {
  const moduleMm = resolve(
    repoRoot,
    'Packages',
    'HanlinExpoNativeAPI',
    'Sources',
    'HanlinExpoNativeAPI',
    'nativescript',
    'ios',
    'NativeScriptNativeApiModule.mm'
  );
  assert.ok(existsSync(moduleMm), 'NativeScriptNativeApiModule.mm must exist');

  const content = await readFile(moduleMm, 'utf8');
  assert.ok(content.includes('HanlinExpoNativeAPIGate'), 'Must include HanlinExpoNativeAPIGate');
  assert.ok(
    content.includes('[HanlinExpoNativeAPIGate isNativeAPIAuthorizedForCurrentSession]'),
    'Must check authorization in native entrypoints'
  );
});

test('NativeScript metadata .nsmd files exist and have valid magic headers', async () => {
  const metaDir = resolve(repoRoot, 'Packages', 'HanlinExpoNativeAPI', 'Artifacts', 'metadata');
  const files = ['metadata.ios.arm64.nsmd', 'metadata.ios-sim.arm64.nsmd', 'metadata.ios-sim.x86_64.nsmd'];

  for (const f of files) {
    const fullPath = resolve(metaDir, f);
    assert.ok(existsSync(fullPath), `Metadata file ${f} must exist`);
    const data = await readFile(fullPath);
    assert.ok(data.length > 1000000, `Metadata file ${f} must be > 1MB`);
    assert.equal(data.subarray(0, 4).toString('ascii'), 'NSMD', `Metadata ${f} must have NSMD magic header`);
  }
});
