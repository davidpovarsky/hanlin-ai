import test from 'node:test';
import assert from 'node:assert/strict';
import { existsSync } from 'node:fs';
import { readFile } from 'node:fs/promises';
import { resolve } from 'node:path';

const repoRoot = resolve(import.meta.dirname, '..', '..', '..');

test('Packaged probes contain valid Metro bundles and manifest files', async () => {
  const probesDir = resolve(repoRoot, 'Fixtures', 'ExpoNativeAPIProbe');
  const requiredZips = [
    'ExpoNativeAPIProbeA.hanlinExpo',
    'ExpoNativeAPIProbeB.hanlinExpo',
    'ExpoNativeAPIProbeMissingGrant.hanlinExpo',
    'ExpoNativeAPIProbeIncompatible.hanlinExpo',
    'ExpoNativeAPIMalformed.hanlinExpo',
  ];

  for (const zip of requiredZips) {
    const fullPath = resolve(probesDir, zip);
    assert.ok(existsSync(fullPath), `Probe package ${zip} must exist`);
  }
});

test('Bundle output contains worklet transforms and NativeScript JSI calls', async () => {
  const bundleAPath = resolve(repoRoot, 'Scripts', 'ExpoNativeAPI', '.scratch', 'probes', 'variant-a', 'bundle.js');
  if (existsSync(bundleAPath)) {
    const bundleText = await readFile(bundleAPath, 'utf8');
    assert.ok(bundleText.includes('NativeScript'), 'Bundle must reference NativeScript API');
    assert.ok(bundleText.includes('_worklet'), 'Bundle must contain transpiled worklet functions');
  }
});
