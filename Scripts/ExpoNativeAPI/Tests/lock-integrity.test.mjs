import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { resolve } from 'node:path';
import { checkVersionContract } from '../preflight.mjs';

const repoRoot = resolve(import.meta.dirname, '..', '..', '..');

test('dependency-lock.json matches the resolved original versions and checksums', async () => {
  const expoLockPath = resolve(repoRoot, 'Scripts', 'Expo', 'dependency-lock.json');
  const nativeLockPath = resolve(repoRoot, 'Scripts', 'ExpoNativeAPI', 'dependency-lock.json');

  const expoLock = JSON.parse(await readFile(expoLockPath, 'utf8'));
  const nativeLock = JSON.parse(await readFile(nativeLockPath, 'utf8'));

  // The resolver publication/artifact receipt is the authority for changing
  // upstream versions and checksums; historical literals must not pin a build.
  const resolution = JSON.parse(await readFile(resolve(repoRoot, 'Scripts/MiniApps/upstream-resolution.json'), 'utf8'));
  const versions = await checkVersionContract();
  assert.equal(versions.reactNativeVersion, resolution.versions.expo['react-native']);
  assert.equal(versions.reactVersion, resolution.versions.expo.react);
  assert.equal(versions.expoSDKVersion, resolution.versions.expo.expo);
  assert.equal(versions.hermesVersion, resolution.hermesVersion);
  for (const name of ['React', 'hermesvm']) {
    const actual = expoLock.artifacts.find(artifact => artifact.name === name);
    const resolved = resolution.nativeArtifacts.find(artifact => artifact.name === name);
    assert.ok(actual && resolved, name + ' must be in the resolved native graph');
    assert.match(actual.sha256, /^[a-f0-9]{64}$/);
    assert.equal(actual.sha256, resolved.sha256);
    assert.equal(actual.url, resolved.url);
  }

  // NativeScript RN
  assert.equal(nativeLock.nativeApi.package, '@nativescript/react-native');
  assert.equal(nativeLock.nativeApi.version, versions.nativeApiVersion);
  assert.equal(nativeLock.nativeApi.codegen.schemaDigest, '3da4813f9bc64360b35b12fdb1720b1e47b3cdb9563a43ebd56ba3cfd22e16d1');

  // Worklets
  assert.equal(nativeLock.worklets.package, 'react-native-worklets');
  assert.equal(nativeLock.worklets.version, versions.workletsVersion);
  const packageLock = JSON.parse(await readFile(resolve(repoRoot, 'Scripts/Expo/package-lock.json'), 'utf8'));
  for (const input of [nativeLock.nativeApi, nativeLock.worklets]) {
    const original = resolution.originals[input.package];
    assert.ok(original, input.package + ' must retain its original publication identity');
    assert.equal(input.version, original.version);
    assert.match(input.sha256, /^[a-f0-9]{64}$/);
    assert.equal(input.sha256, original.sha256);
    assert.equal(input.distIntegrity, original.integrity);
    assert.equal(input.distIntegrity, packageLock.packages['node_modules/' + input.package].integrity);
    assert.equal(input.tarballUrl, original.tarball);
  }
});
