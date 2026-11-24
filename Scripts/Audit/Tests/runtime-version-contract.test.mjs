import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import path from 'node:path';
import {auditPreparedRuntimeContract} from '../miniapp-runtime-contract.mjs';
import {generatedHostVersions, generatedNativeScriptHostVersions} from '../../MiniApps/resolve-upstreams.mjs';

const root = path.resolve(import.meta.dirname, '../../..');
const paths = {
  platform: 'Packages/HanlinPlatform/Sources/HanlinScriptCompiler/HanlinMiniAppHostVersions.swift',
  native: 'Packages/HanlinNativeScriptRuntime/Sources/HanlinNativeScriptRuntime/HanlinNativeScriptHostVersions.swift',
  session: 'Packages/HanlinNativeScriptRuntime/Sources/HanlinNativeScriptRuntime/HanlinNativeScriptSession.swift',
  analyzer: 'Packages/HanlinPlatform/Sources/HanlinScriptCompiler/HanlinScriptAnalyzer.swift',
};
async function fixture(overrides = new Map()) {
  const source = async file => ({path: file, text: overrides.get(file) ?? await readFile(path.join(root, file), 'utf8')});
  const json = async file => JSON.parse((await source(file)).text);
  return {source, json, nsLock: await json('Scripts/NativeScript/dependency-lock.json'),
    nsPackage: await json('Scripts/NativeScript/package.json'), tooling: await json('Scripts/Expo/package.json'),
    lock: await json('Scripts/Expo/package-lock.json'), bridge: await json('Tools/SwiftUIBridge/configuration.json')};
}
function versions(input) {
  return {expo: input.tooling.dependencies, nativescript: {
    '@nativescript/ios': input.nsLock.nativeScript.iosRuntimeVersion,
    '@nativescript/core': input.nsLock.nativeScript.coreVersion,
    '@nativescript/swift-ui': input.nsLock.swiftUI.version,
  }};
}

test('actual importer and sessions reconcile independent original versions and the bridge baseline', async () => {
  const input = await fixture(), result = await auditPreparedRuntimeContract(input);
  assert.deepEqual(result.nativeSession, {runtimeVersion: input.nsLock.nativeScript.iosRuntimeVersion,
    coreVersion: input.nsLock.nativeScript.coreVersion, swiftUIVersion: input.nsLock.swiftUI.version});
  assert.equal((await input.source(paths.native)).text, generatedNativeScriptHostVersions(versions(input)));
  assert.equal(result.expoSession.runtimeVersion, input.tooling.dependencies['@expo/ui']);
  assert.equal(result.expoSession.sdkVersion, input.tooling.dependencies.expo);
  assert.equal(result.bridgeGenerationBaseline.generatedRuntimeVersion, input.bridge.runtimeVersion);
  assert.equal(result.expoSession.bridgeVersion, input.bridge.bridgeVersion);
});

test('future independent Core iOS and SwiftUI updates reach both generated consumers', async () => {
  const overrides = new Map(), input = await fixture(overrides);
  // Controlled future inputs exercise the real generator; these are not claimed
  // to be published upstream packages or a native compatibility execution.
  input.nsLock.nativeScript.iosRuntimeVersion = '9.2.1';
  input.nsLock.nativeScript.coreVersion = '9.2.7';
  input.nsLock.swiftUI.version = '4.1.0';
  input.nsPackage.devDependencies['@nativescript/ios'] = '9.2.1';
  input.nsPackage.dependencies['@nativescript/core'] = '9.2.7';
  input.nsPackage.dependencies['@nativescript/swift-ui'] = '4.1.0';
  overrides.set(paths.platform, generatedHostVersions(versions(input)));
  await assert.rejects(auditPreparedRuntimeContract(input), /versions disagree for NativeScript iOS runtime/);
  overrides.set(paths.native, generatedNativeScriptHostVersions(versions(input)));
  const result = await auditPreparedRuntimeContract(input);
  assert.deepEqual(result.nativeSession, {runtimeVersion: '9.2.1', coreVersion: '9.2.7', swiftUIVersion: '4.1.0'});
  assert.equal(result.versions.nativeScriptCoreVersion, '9.2.7');
  assert.equal(result.versions.nativeScriptRuntimeVersion, '9.2.1');
  assert.throws(() => generatedNativeScriptHostVersions({nativescript: {'@nativescript/core': '9.2.7'}}), /Missing exact NativeScript host version/);
});

test('stale direct-session runtime and using iOS as the Core ceiling both fail the audit', async () => {
  const input = await fixture();
  const session = (await input.source(paths.session)).text;
  const stale = await fixture(new Map([[paths.session, session.replace('supportedRuntimeVersion = HanlinNativeScriptHostVersions.runtimeVersion', 'supportedRuntimeVersion = "9.1.0"')]]));
  await assert.rejects(auditPreparedRuntimeContract(stale), /versions disagree for NativeScript iOS runtime/);
  const analyzer = (await input.source(paths.analyzer)).text;
  const conflated = await fixture(new Map([[paths.analyzer, analyzer.replace('supportsMinimum(versionString, installed: nativeScriptCoreVersion)', 'supportsMinimum(versionString, installed: nativeScriptRuntimeVersion)')]]));
  await assert.rejects(auditPreparedRuntimeContract(conflated), /policy changed: importer Core minimum/);
});

test('original dependency drift and bridge baseline drift remain rejected separately', async () => {
  const input = await fixture();
  input.nsLock.nativeScript.coreVersion = '99.0.0';
  await assert.rejects(auditPreparedRuntimeContract(input), /versions disagree for NativeScript Core/);
  const bridge = await fixture();
  bridge.bridge.runtimeVersion = '99.0.0';
  await assert.rejects(auditPreparedRuntimeContract(bridge), /versions disagree for Expo bridge generation baseline/);
  const expo = await fixture();
  expo.tooling.dependencies['@expo/ui'] = '99.0.0';
  await assert.rejects(auditPreparedRuntimeContract(expo), /versions disagree for Expo UI/);
});
