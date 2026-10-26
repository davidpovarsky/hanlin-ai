import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { resolve } from 'node:path';

const repoRoot = resolve(import.meta.dirname, '..', '..', '..');

test('dependency-lock.json matches exact tested versions and checksums', async () => {
  const expoLockPath = resolve(repoRoot, 'Scripts', 'Expo', 'dependency-lock.json');
  const nativeLockPath = resolve(repoRoot, 'Scripts', 'ExpoNativeAPI', 'dependency-lock.json');

  const expoLock = JSON.parse(await readFile(expoLockPath, 'utf8'));
  const nativeLock = JSON.parse(await readFile(nativeLockPath, 'utf8'));

  // Expo & React Native ABI
  assert.equal(expoLock.expo.reactNativeVersion, '0.88.0');
  assert.equal(expoLock.expo.reactVersion, '19.3.0');
  assert.equal(expoLock.expo.sdkVersion, '58.0.0');
  assert.equal(expoLock.expo.hermesVersion, '260318099.0.4');

  // React artifact
  const reactArt = expoLock.artifacts.find((a) => a.name === 'React');
  assert.ok(reactArt, 'React artifact must be in lockfile');
  assert.equal(reactArt.sha256, '4f3d22afd5d74809178b737d3ed987cc747ea63336a758cdf20064c47ef67203');

  // hermesvm artifact
  const hermesArt = expoLock.artifacts.find((a) => a.name === 'hermesvm');
  assert.ok(hermesArt, 'hermesvm artifact must be in lockfile');
  assert.equal(hermesArt.sha256, 'b0db43628abc20b5eccb7ed1161801f418830f47b1ac1b5946cf532a886841f6');

  // NativeScript RN
  assert.equal(nativeLock.nativeApi.package, '@nativescript/react-native');
  assert.equal(nativeLock.nativeApi.version, '9.1.2');
  assert.equal(nativeLock.nativeApi.sha256, '906f2106215426e6211c27f37fe2e874b9d91d174efbabb1d8b512fcdb2d4798');
  assert.equal(nativeLock.nativeApi.codegen.schemaDigest, '3da4813f9bc64360b35b12fdb1720b1e47b3cdb9563a43ebd56ba3cfd22e16d1');

  // Worklets
  assert.equal(nativeLock.worklets.package, 'react-native-worklets');
  assert.equal(nativeLock.worklets.version, '0.13.1');
  assert.equal(nativeLock.worklets.sha256, '9d7a0e35344d454a8c661e01b6846252f4b016ef813a178a84768aa1197c5f9c');
});
