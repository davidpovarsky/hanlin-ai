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

test('Packages/HanlinExpoNativeAPI has multi-target architecture with Swift and Clang separation', async () => {
  const packageSwiftPath = resolve(repoRoot, 'Packages', 'HanlinExpoNativeAPI', 'Package.swift');
  assert.ok(existsSync(packageSwiftPath), 'Package.swift must exist');
  const pkgContent = await readFile(packageSwiftPath, 'utf8');

  // Multi-target declaration
  assert.ok(pkgContent.includes('name: "HanlinExpoNativeAPI"'), 'Must define HanlinExpoNativeAPI target');
  assert.ok(pkgContent.includes('name: "HanlinExpoNativeAPICore"'), 'Must define HanlinExpoNativeAPICore target');
  assert.ok(pkgContent.includes('name: "HanlinExpoWorklets"'), 'Must define HanlinExpoWorklets target');

  // ARC separation
  assert.ok(pkgContent.includes('"-fno-objc-arc"'), 'HanlinExpoNativeAPICore must use -fno-objc-arc for NativeScript');
  assert.ok(pkgContent.includes('"-fobjc-arc"'), 'HanlinExpoWorklets must use -fobjc-arc for Worklets');

  // Resource ownership in Swift target
  assert.ok(pkgContent.includes('.process("Resources/metadata")'), 'Swift target must own Resources/metadata');

  // Ensure Android/JNI files are not in HanlinExpoNativeAPICore
  const coreDir = resolve(repoRoot, 'Packages', 'HanlinExpoNativeAPI', 'Sources', 'HanlinExpoNativeAPICore');
  const androidJniDir = resolve(coreDir, 'nativescript', 'native-api', 'ffi', 'jni');
  assert.ok(!existsSync(androidJniDir), 'Android JNI directory must be excluded from HanlinExpoNativeAPICore');
});

test('Packages/HanlinExpoNativeAPI has native authorization gate injected in all 4 entrypoints', async () => {
  const moduleMm = resolve(
    repoRoot,
    'Packages',
    'HanlinExpoNativeAPI',
    'Sources',
    'HanlinExpoNativeAPICore',
    'nativescript',
    'ios',
    'NativeScriptNativeApiModule.mm'
  );
  assert.ok(existsSync(moduleMm), 'NativeScriptNativeApiModule.mm must exist in HanlinExpoNativeAPICore');

  const content = await readFile(moduleMm, 'utf8');
  assert.ok(content.includes('HanlinExpoNativeAPIGate.h'), 'Must include HanlinExpoNativeAPIGate.h');
  assert.ok(
    content.includes('HanlinExpoNativeAPIGate isNativeAPIAuthorizedForRuntime'),
    'Must check runtime authorization in JSI entrypoints'
  );
  assert.ok(
    content.includes('HanlinExpoNativeAPIGate isNativeAPIAuthorizedForCurrentSession'),
    'Must check session authorization in UIKit entrypoints'
  );

  // Check 4 entrypoint gates
  assert.ok(content.includes('[HANLIN_EXPO_NATIVEAPI_DENIAL] NativeScriptNativeApiModule::install rejected'), 'install denial gate must exist');
  assert.ok(content.includes('[HANLIN_EXPO_NATIVEAPI_DENIAL] NativeScriptNativeApiModule::installWorkletRuntime rejected'), 'installWorkletRuntime denial gate must exist');
  assert.ok(content.includes('[HANLIN_EXPO_NATIVEAPI_DENIAL] NativeScriptCreateUIKitHost rejected'), 'NativeScriptCreateUIKitHost denial gate must exist');
  assert.ok(content.includes('[HANLIN_EXPO_NATIVEAPI_DENIAL] NativeScriptRunUIKitHostLifecycle rejected'), 'NativeScriptRunUIKitHostLifecycle denial gate must exist');
});

test('NativeScript metadata .nsmd files exist in target Resources and Artifacts with valid magic headers', async () => {
  const targetMetaDir = resolve(repoRoot, 'Packages', 'HanlinExpoNativeAPI', 'Sources', 'HanlinExpoNativeAPI', 'Resources', 'metadata');
  const artifactMetaDir = resolve(repoRoot, 'Packages', 'HanlinExpoNativeAPI', 'Artifacts', 'metadata');
  const files = ['metadata.ios.arm64.nsmd', 'metadata.ios-sim.arm64.nsmd', 'metadata.ios-sim.x86_64.nsmd'];

  for (const dir of [targetMetaDir, artifactMetaDir]) {
    for (const f of files) {
      const fullPath = resolve(dir, f);
      assert.ok(existsSync(fullPath), `Metadata file ${f} must exist in ${dir}`);
      const data = await readFile(fullPath);
      assert.ok(data.length > 1000000, `Metadata file ${f} must be > 1MB`);
      assert.equal(data.subarray(0, 4).toString('ascii'), 'NSMD', `Metadata ${f} must have NSMD magic header`);
    }
  }
});

test('Libffi.xcframework contains valid static library slices for device and simulator', async () => {
  const libffiBase = resolve(repoRoot, 'Packages', 'HanlinExpoNativeAPI', 'Artifacts', 'Libffi.xcframework');
  assert.ok(existsSync(libffiBase), 'Libffi.xcframework must exist');

  const arm64Slice = resolve(libffiBase, 'ios-arm64', 'libffi.a');
  const simSlice = resolve(libffiBase, 'ios-arm64_x86_64-simulator', 'libffi.a');

  assert.ok(existsSync(arm64Slice), 'ios-arm64/libffi.a must exist');
  assert.ok(existsSync(simSlice), 'ios-arm64_x86_64-simulator/libffi.a must exist');

  const arm64Data = await readFile(arm64Slice);
  const simData = await readFile(simSlice);

  assert.ok(arm64Data.length > 50000, 'ios-arm64/libffi.a must be > 50KB');
  assert.ok(simData.length > 80000, 'ios-arm64_x86_64-simulator/libffi.a must be > 80KB');
  assert.equal(arm64Data.subarray(0, 8).toString('ascii'), '!<arch>\n', 'device libffi.a must be a valid ar archive');

  // Simulator slice is a universal Mach-O FAT binary (cafebabe) containing arm64 and x86_64
  const simMagic = simData.readUInt32BE(0);
  assert.ok(simMagic === 0xcafebabe || simData.subarray(0, 8).toString('ascii') === '!<arch>\n', 'simulator libffi.a must be a universal Mach-O fat binary or ar archive');
});

test('HanlinExpoDependencyProvider registers NativeScript, Worklets, and Fabric component', async () => {
  const providerPath = resolve(
    repoRoot,
    'Packages',
    'HanlinExpoNativeAPI',
    'Sources',
    'HanlinExpoNativeAPICore',
    'bridge',
    'HanlinExpoDependencyProvider.mm'
  );
  assert.ok(existsSync(providerPath), 'HanlinExpoDependencyProvider.mm must exist');

  const content = await readFile(providerPath, 'utf8');
  assert.ok(content.includes('NativeScriptNativeApiModuleProvider'), 'Must register NativeScriptNativeApi');
  assert.ok(content.includes('WorkletsModule'), 'Must register WorkletsModule');
  assert.ok(content.includes('NativeScriptUIViewComponentView'), 'Must register NativeScriptUIView Fabric component');
});
