import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import path from 'node:path';
import {auditPreparedRuntimeContract} from '../miniapp-runtime-contract.mjs';
import {generatedHostVersions, generatedNativeScriptHostVersions} from '../../MiniApps/resolve-upstreams.mjs';
import * as upstreamResolver from '../../MiniApps/resolve-upstreams.mjs';
import * as nativeAPIPreflight from '../../ExpoNativeAPI/preflight.mjs';

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
  assert.equal(result.expoBridgeRuntimeMetadata.runtimeVersion, input.bridge.runtimeVersion);
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

test('original dependency drift and public runtime metadata drift remain rejected separately', async () => {
  const input = await fixture();
  input.nsLock.nativeScript.coreVersion = '99.0.0';
  await assert.rejects(auditPreparedRuntimeContract(input), /versions disagree for NativeScript Core/);
  const bridge = await fixture();
  bridge.bridge.runtimeVersion = '99.0.0';
  await assert.rejects(auditPreparedRuntimeContract(bridge), /versions disagree for Expo public runtime metadata/);
  const expo = await fixture();
  expo.tooling.dependencies['@expo/ui'] = '99.0.0';
  await assert.rejects(auditPreparedRuntimeContract(expo), /versions disagree for Expo UI/);
});


test('Native API facade versions follow the resolved graph and reject an actual exported mismatch', async () => {
  const input = await fixture();
  const facadePath = 'Packages/HanlinExpoNativeAPIJS/src/index.ts';
  const facade = (await input.source(facadePath)).text;
  const nativeLock = await input.json('Scripts/ExpoNativeAPI/dependency-lock.json');
  const literal = (source, name) => source.match(new RegExp(`^export const ${name} = "([^"\\r\\n]+)";$`, 'm'))?.[1];
  assert.equal(literal(facade, 'WORKLETS_VERSION'), nativeLock.worklets.version,
    'public WORKLETS_VERSION must identify the actual native Worklets input');
  assert.equal(literal(facade, 'UPSTREAM_VERSION'), nativeLock.nativeApi.version);
  const result = await auditPreparedRuntimeContract(input);
  assert.equal(result.nativeAPI.workletsVersion, nativeLock.worklets.version);
  assert.equal(result.nativeAPI.nativeApiVersion, nativeLock.nativeApi.version);
  assert.deepEqual(await nativeAPIPreflight.checkVersionContract(), result.nativeAPI,
    'the active preflight must use the same version contract as the source audit');

  const stale = facade.replace(/^export const WORKLETS_VERSION = .*;$/m,
    'export const WORKLETS_VERSION = "999.0.0";');
  const mismatch = await fixture(new Map([[facadePath, stale]]));
  await assert.rejects(auditPreparedRuntimeContract(mismatch), /versions disagree for Expo Worklets/);

  // Controlled future inputs exercise the production resolver, not a claim that
  // these package versions have been published or compiled into a native host.
  const future = {expo: {'@nativescript/react-native': '9.2.3', 'react-native-worklets': '0.14.2'}};
  const updated = upstreamResolver.updatedNativeAPIFacadeVersions(facade, future);
  assert.equal(literal(updated, 'UPSTREAM_VERSION'), '9.2.3');
  assert.equal(literal(updated, 'WORKLETS_VERSION'), '0.14.2');
  const withoutVersions = source => source.replace(/^export const (UPSTREAM_VERSION|WORKLETS_VERSION) = .*;\n/gm, '');
  assert.equal(withoutVersions(updated), withoutVersions(facade), 'all original API forwarding bytes are preserved');
  assert.equal(upstreamResolver.updatedNativeAPIFacadeVersions(updated, future), updated);
  assert.throws(() => upstreamResolver.updatedNativeAPIFacadeVersions(facade, {expo: {}}), /Missing exact Native API facade version/);
  assert.throws(() => upstreamResolver.updatedNativeAPIFacadeVersions(facade + '\nexport const WORKLETS_VERSION = "0.13.0";\n', future), /Expected one exported Native API facade version/);
});


test('Expo UI public runtime metadata follows the installed original runtime across every mirror', async () => {
  const input = await fixture();
  const expected = input.tooling.dependencies['@expo/ui'];
  assert.equal(input.bridge.runtimeVersion, expected, 'public generator runtime identity must match installed original Expo UI');
  const contract = await auditPreparedRuntimeContract(input);
  assert.equal(contract.expoBridgeRuntimeMetadata.runtimeVersion, expected);
  const read = async file => (await input.source(file)).text;
  const original = new Map(await Promise.all(upstreamResolver.expoBridgeRuntimeMetadataPaths.map(async file => [file, await read(file)])));
  const same = await upstreamResolver.updatedExpoBridgeRuntimeMetadata(read, versions(input));
  assert.deepEqual(same, original, 'resolving the same original graph is byte-idempotent');
  const future = {expo: {...versions(input).expo, '@expo/ui': '58.0.99'}};
  const updated = await upstreamResolver.updatedExpoBridgeRuntimeMetadata(read, future);
  assert.equal(updated.size, 5);
  for (const [file, before] of original) {
    const after = updated.get(file);
    if (file.endsWith('.json')) {
      const previous = JSON.parse(before), next = JSON.parse(after);
      assert.equal(next.runtimeVersion, '58.0.99');
      assert.deepEqual({...next, runtimeVersion: previous.runtimeVersion}, previous,
        'reviewed coverage, bridge ABI and all other configuration stay unchanged');
    } else {
      assert.equal(after.replace('58.0.99', expected), before,
        'only the runtime identity changes in the original generated mirror: ' + file);
    }
    const stale = before.replace(expected, '999.0.0');
    assert.notEqual(stale, before);
    await assert.rejects(auditPreparedRuntimeContract(await fixture(new Map([[file, stale]]))),
      /Expo public runtime metadata|Expo bridge metadata mirrors differ/, file);
  }
  await assert.rejects(upstreamResolver.updatedExpoBridgeRuntimeMetadata(read, {expo: {}}), /Missing exact Expo UI runtime/);
});
