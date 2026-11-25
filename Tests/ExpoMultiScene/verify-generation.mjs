import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { patchNativeModuleForSessions, patchUIKitHostHeaderForSessions, patchUIKitViewForSessions } from '../../Scripts/ExpoNativeAPI/multiscene-patch.mjs';
const root = resolve(fileURLToPath(new URL('../..', import.meta.url)));
const upstream = process.argv[2];
if (!upstream) throw new Error('Pass the integrity-verified NativeScript React Native 9.1.2 ios directory');
const packageRoot = resolve(root, 'Packages/HanlinExpoNativeAPI');
for (const [file, patch] of [
  ['NativeScriptNativeApiModule.mm', patchNativeModuleForSessions],
  ['NativeScriptUIKitHost.h', patchUIKitHostHeaderForSessions],
  ['NativeScriptUIView.mm', patchUIKitViewForSessions]
]) {
  assert.equal(await readFile(resolve(packageRoot, 'Sources/HanlinExpoNativeAPICore/nativescript/ios', file), 'utf8'), patch(await readFile(resolve(upstream, file), 'utf8')));
  console.log('PASS upstream regeneration ' + file);
}
for (const name of ['HanlinExpoNativeAPIGate.h', 'HanlinExpoNativeAPIGate.mm', 'HanlinExpoSessionRuntimeRegistry.h']) {
  assert.equal(await readFile(resolve(packageRoot, 'Sources/HanlinExpoNativeAPICore/bridge', name), 'utf8'), await readFile(resolve(packageRoot, 'bridge-source', name), 'utf8'));
  console.log('PASS canonical bridge mirror ' + name);
}
for (const [canonical, publicHeader] of [
  ['bridge-source/HanlinExpoNativeAPIGate.h', 'HanlinExpoNativeAPIGate.h'],
  ['Sources/HanlinExpoNativeAPICore/nativescript/ios/NativeScriptUIKitHost.h', 'NativeScriptUIKitHost.h']
]) {
  assert.equal(await readFile(resolve(packageRoot, canonical), 'utf8'), await readFile(resolve(packageRoot, 'Sources/HanlinExpoNativeAPICore/include', publicHeader), 'utf8'));
  console.log('PASS public header mirror ' + publicHeader);
}
