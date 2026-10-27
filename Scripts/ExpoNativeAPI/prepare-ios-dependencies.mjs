import { createHash } from 'node:crypto';
import { access, chmod, cp, lstat, mkdir, readFile, readdir, readlink, rm, stat, writeFile } from 'node:fs/promises';
import { createWriteStream, existsSync } from 'node:fs';
import { basename, dirname, resolve } from 'node:path';
import { execSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import https from 'node:https';
import http from 'node:http';

import { generateCodegen } from './generate-codegen.mjs';
import { verifyNSMD } from './verify-nsmd.mjs';
import { verifyArtifacts } from './verify-artifacts.mjs';

const scriptRoot = resolve(import.meta.dirname);
const repoRoot = resolve(scriptRoot, '..', '..');
const lockPath = resolve(scriptRoot, 'dependency-lock.json');
const targetPackageRoot = resolve(repoRoot, 'Packages', 'HanlinExpoNativeAPI');
const sourcesRoot = resolve(targetPackageRoot, 'Sources');

const sha256 = (bytes) => createHash('sha256').update(bytes).digest('hex');

function downloadFile(url, destPath) {
  return new Promise((res, rej) => {
    function get(currentURL) {
      const client = currentURL.startsWith('https') ? https : http;
      const headers = { 'User-Agent': 'Mozilla/5.0' };
      client.get(currentURL, { headers }, (response) => {
        if (response.statusCode >= 300 && response.statusCode < 400 && response.headers.location) {
          const redirectURL = new URL(response.headers.location, currentURL).toString();
          return get(redirectURL);
        }
        if (response.statusCode !== 200) {
          return rej(new Error(`Download failed with status ${response.statusCode} for ${currentURL}`));
        }
        const file = createWriteStream(destPath);
        response.pipe(file);
        file.on('finish', () => {
          file.close(() => res());
        });
      }).on('error', rej);
    }
    get(url);
  });
}

function applyStrictPatch(content, findExact, replaceWith, label) {
  const parts = content.split(findExact);
  if (parts.length !== 2) {
    throw new Error(`[HanlinExpoNativeAPI] Patch '${label}' failed: expected exactly 1 occurrence of anchor, found ${parts.length - 1}`);
  }
  return parts.join(replaceWith);
}

export async function prepareExpoNativeAPI() {
  console.log('[HanlinExpoNativeAPI] Preparing NativeScript RN and Worklets iOS dependencies...');
  const lock = JSON.parse(await readFile(lockPath, 'utf8'));
  const tempDir = resolve(scriptRoot, '.scratch', 'prep-downloads');
  await mkdir(tempDir, { recursive: true });

  // 1. Fetch & verify NativeScript RN 9.1.2 tarball
  const nsTarPath = resolve(tempDir, 'nativescript-rn.tgz');
  if (!existsSync(nsTarPath)) {
    console.log(`[HanlinExpoNativeAPI] Downloading ${lock.nativeApi.package}@${lock.nativeApi.version}...`);
    await downloadFile(lock.nativeApi.tarballUrl, nsTarPath);
  }
  const nsBytes = await readFile(nsTarPath);
  const nsDigest = sha256(nsBytes);
  if (nsDigest !== lock.nativeApi.sha256) {
    throw new Error(`[HanlinExpoNativeAPI] Checksum mismatch for NativeScript RN: expected ${lock.nativeApi.sha256}, got ${nsDigest}`);
  }
  console.log(`[HanlinExpoNativeAPI] Verified NativeScript RN tarball SHA256: ${nsDigest}`);

  // 2. Fetch & verify Worklets 0.13.1 tarball
  const wlTarPath = resolve(tempDir, 'worklets.tgz');
  if (!existsSync(wlTarPath)) {
    console.log(`[HanlinExpoNativeAPI] Downloading ${lock.worklets.package}@${lock.worklets.version}...`);
    await downloadFile(lock.worklets.tarballUrl, wlTarPath);
  }
  const wlBytes = await readFile(wlTarPath);
  const wlDigest = sha256(wlBytes);
  if (wlDigest !== lock.worklets.sha256) {
    throw new Error(`[HanlinExpoNativeAPI] Checksum mismatch for Worklets: expected ${lock.worklets.sha256}, got ${wlDigest}`);
  }
  console.log(`[HanlinExpoNativeAPI] Verified Worklets tarball SHA256: ${wlDigest}`);

  // 3. Unpack into scratch
  const nsExtractDir = resolve(tempDir, 'ns-extracted');
  await rm(nsExtractDir, { recursive: true, force: true });
  await mkdir(nsExtractDir, { recursive: true });
  execSync(`tar -zxf "${nsTarPath}" -C "${nsExtractDir}"`);

  const wlExtractDir = resolve(tempDir, 'wl-extracted');
  await rm(wlExtractDir, { recursive: true, force: true });
  await mkdir(wlExtractDir, { recursive: true });
  execSync(`tar -zxf "${wlTarPath}" -C "${wlExtractDir}"`);

  const nsPkgDir = resolve(nsExtractDir, 'package');
  const wlPkgDir = resolve(wlExtractDir, 'package');

  // 4. Stage metadata and Libffi into Artifacts
  const artifactsDir = resolve(targetPackageRoot, 'Artifacts');
  const metadataTargetDir = resolve(artifactsDir, 'metadata');
  await mkdir(metadataTargetDir, { recursive: true });

  const metadataSrcDir = resolve(nsPkgDir, 'metadata');
  const metadataFiles = ['metadata.ios.arm64.nsmd', 'metadata.ios-sim.arm64.nsmd', 'metadata.ios-sim.x86_64.nsmd'];
  for (const f of metadataFiles) {
    await cp(resolve(metadataSrcDir, f), resolve(metadataTargetDir, f));
  }

  // Also stage metadata into target-owned SwiftPM resource directory
  const swiftResourcesDir = resolve(sourcesRoot, 'HanlinExpoNativeAPI', 'Resources', 'metadata');
  await mkdir(swiftResourcesDir, { recursive: true });
  for (const f of metadataFiles) {
    await cp(resolve(metadataSrcDir, f), resolve(swiftResourcesDir, f));
  }
  console.log('[HanlinExpoNativeAPI] Staged metadata .nsmd files into Artifacts/metadata and Sources/HanlinExpoNativeAPI/Resources/metadata');

  // Libffi framework and static libraries
  const libffiSrc = resolve(nsPkgDir, 'ios', 'vendor', 'Libffi.xcframework');
  const libffiDst = resolve(artifactsDir, 'Libffi.xcframework');
  if (existsSync(libffiSrc)) {
    await rm(libffiDst, { recursive: true, force: true });
    await cp(libffiSrc, libffiDst, { recursive: true, verbatimSymlinks: true });
  }

  // Ensure Libffi static library slices are present and non-empty
  const libffiArm64 = resolve(libffiDst, 'ios-arm64', 'libffi.a');
  const libffiSim = resolve(libffiDst, 'ios-arm64_x86_64-simulator', 'libffi.a');
  if (!existsSync(libffiArm64) || (await stat(libffiArm64)).size === 0) {
    throw new Error(`[HanlinExpoNativeAPI] Missing or empty libffi.a slice for arm64: ${libffiArm64}`);
  }
  if (!existsSync(libffiSim) || (await stat(libffiSim)).size === 0) {
    throw new Error(`[HanlinExpoNativeAPI] Missing or empty libffi.a slice for simulator: ${libffiSim}`);
  }
  console.log('[HanlinExpoNativeAPI] Verified Libffi.xcframework static libraries (arm64 + sim).');

  // 5. Stage Worklets into Sources/HanlinExpoWorklets (Clang ARC target)
  const workletsTargetDir = resolve(sourcesRoot, 'HanlinExpoWorklets');
  await rm(workletsTargetDir, { recursive: true, force: true });
  await mkdir(workletsTargetDir, { recursive: true });

  await cp(resolve(wlPkgDir, 'Common'), resolve(workletsTargetDir, 'Common'), { recursive: true });
  await cp(resolve(wlPkgDir, 'apple'), resolve(workletsTargetDir, 'apple'), { recursive: true });

  // Public include directory for HanlinExpoWorklets
  const workletsIncludeDir = resolve(workletsTargetDir, 'include');
  await mkdir(resolve(workletsIncludeDir, 'worklets', 'apple'), { recursive: true });
  await cp(resolve(wlPkgDir, 'apple', 'worklets', 'apple', 'WorkletsModule.h'), resolve(workletsIncludeDir, 'worklets', 'apple', 'WorkletsModule.h'));
  await cp(resolve(wlPkgDir, 'apple', 'worklets', 'apple', 'WorkletsModule.h'), resolve(workletsIncludeDir, 'WorkletsModule.h'));

  const workletsUmbrellaHeader = resolve(workletsIncludeDir, 'HanlinExpoWorklets.h');
  await writeFile(workletsUmbrellaHeader, `#pragma once
#import <Foundation/Foundation.h>
#import "WorkletsModule.h"
`, 'utf8');

  const workletsModuleMap = resolve(workletsIncludeDir, 'module.modulemap');
  await writeFile(workletsModuleMap, `module HanlinExpoWorklets {
    umbrella header "HanlinExpoWorklets.h"
    export *
}
`, 'utf8');

  // 6. Stage NativeScript and Bridge into Sources/HanlinExpoNativeAPICore (Clang MRC target)
  const coreTargetDir = resolve(sourcesRoot, 'HanlinExpoNativeAPICore');
  await rm(coreTargetDir, { recursive: true, force: true });
  await mkdir(coreTargetDir, { recursive: true });

  // Copy ios/ directory
  await cp(resolve(nsPkgDir, 'ios'), resolve(coreTargetDir, 'nativescript', 'ios'), { recursive: true });

  // Copy native-api/ directory (strictly omitting non-iOS ffi/jni)
  const nativeApiDst = resolve(coreTargetDir, 'nativescript', 'native-api');
  await mkdir(nativeApiDst, { recursive: true });
  await cp(resolve(nsPkgDir, 'native-api', 'ffi', 'objc'), resolve(nativeApiDst, 'ffi', 'objc'), { recursive: true });
  await cp(resolve(nsPkgDir, 'native-api', 'metadata'), resolve(nativeApiDst, 'metadata'), { recursive: true });
  await cp(resolve(nsPkgDir, 'native-api', 'jsi', 'hermes'), resolve(nativeApiDst, 'jsi', 'hermes'), { recursive: true });
  await cp(resolve(nsPkgDir, 'native-api', 'jsi', 'shared'), resolve(nativeApiDst, 'jsi', 'shared'), { recursive: true });
  await rm(resolve(nativeApiDst, 'jsi', 'shared', 'Tasks.cpp'), { force: true });

  // Stage bridge sources
  const bridgeSrcDir = resolve(scriptRoot, '..', '..', 'Packages', 'HanlinExpoNativeAPI', 'bridge-source');
  const bridgeDstDir = resolve(coreTargetDir, 'bridge');
  await mkdir(bridgeDstDir, { recursive: true });

  // If bridge-source backup directory doesn't exist yet, save current bridge files there
  const legacyBridgeDir = resolve(sourcesRoot, 'HanlinExpoNativeAPI', 'bridge');
  if (existsSync(legacyBridgeDir) && !existsSync(bridgeSrcDir)) {
    await cp(legacyBridgeDir, bridgeSrcDir, { recursive: true });
  }
  const sourceBridgeDir = existsSync(bridgeSrcDir) ? bridgeSrcDir : legacyBridgeDir;
  await cp(sourceBridgeDir, bridgeDstDir, { recursive: true });

  // Public include directory for HanlinExpoNativeAPICore
  const coreIncludeDir = resolve(coreTargetDir, 'include');
  await mkdir(coreIncludeDir, { recursive: true });
  await cp(resolve(bridgeDstDir, 'HanlinExpoNativeAPIGate.h'), resolve(coreIncludeDir, 'HanlinExpoNativeAPIGate.h'));
  await cp(resolve(bridgeDstDir, 'HanlinExpoDependencyProvider.h'), resolve(coreIncludeDir, 'HanlinExpoDependencyProvider.h'));
  await cp(resolve(coreTargetDir, 'nativescript', 'ios', 'NativeScriptUIKitHost.h'), resolve(coreIncludeDir, 'NativeScriptUIKitHost.h'));
  await cp(resolve(coreTargetDir, 'nativescript', 'ios', 'NativeScriptUIView.h'), resolve(coreIncludeDir, 'NativeScriptUIView.h'));

  const coreUmbrellaHeader = resolve(coreIncludeDir, 'HanlinExpoNativeAPICore.h');
  await writeFile(coreUmbrellaHeader, `#pragma once
#import <Foundation/Foundation.h>
#import "HanlinExpoNativeAPIGate.h"
#import "HanlinExpoDependencyProvider.h"
#import "NativeScriptUIKitHost.h"
#import "NativeScriptUIView.h"
`, 'utf8');

  const coreModuleMap = resolve(coreIncludeDir, 'module.modulemap');
  await writeFile(coreModuleMap, `module HanlinExpoNativeAPICore {
    umbrella header "HanlinExpoNativeAPICore.h"
    export *
}
`, 'utf8');

  // 7. Apply native authorization gate patch into NativeScriptNativeApiModule.mm and .h
  const moduleMmPath = resolve(coreTargetDir, 'nativescript', 'ios', 'NativeScriptNativeApiModule.mm');
  const moduleHPath = resolve(coreTargetDir, 'nativescript', 'ios', 'NativeScriptNativeApiModule.h');

  if (existsSync(moduleMmPath)) {
    let mmContent = await readFile(moduleMmPath, 'utf8');

    // Prepend include
    mmContent = '#include "HanlinExpoNativeAPIGate.h"\n' + mmContent;

    // Append worklet clearing helper
    mmContent = mmContent + `
void HanlinExpoNativeAPIClearWorkletRuntime(void) {
  setNativeScriptWorkletRuntime(nullptr);
}
`;

    // Patch bundledMetadataPath()
    const bundleAnchor = 'std::string bundledMetadataPath() {';
    const bundleReplacement = `std::string bundledMetadataPath() {
  NSString* gatePath = [HanlinExpoNativeAPIGate bundledMetadataPath];
  if (gatePath != nil && gatePath.length > 0) {
    return gatePath.UTF8String;
  }`;
    mmContent = applyStrictPatch(mmContent, bundleAnchor, bundleReplacement, 'bundledMetadataPath');

    // Patch NativeScriptCreateUIKitHost()
    const createAnchor = 'NSDictionary<NSString*, NSString*>* NativeScriptCreateUIKitHost(NSString* hostId) {';
    const createReplacement = `NSDictionary<NSString*, NSString*>* NativeScriptCreateUIKitHost(NSString* hostId) {
  if (![HanlinExpoNativeAPIGate isNativeAPIAuthorizedForCurrentSession]) {
    NSLog(@"[HANLIN_EXPO_NATIVEAPI_DENIAL] NativeScriptCreateUIKitHost rejected: 'ios-native-api' capability is NOT granted.");
    return nil;
  }`;
    mmContent = applyStrictPatch(mmContent, createAnchor, createReplacement, 'NativeScriptCreateUIKitHost');

    // Patch NativeScriptRunUIKitHostLifecycle()
    const lifecycleAnchor = `NSDictionary<NSString*, NSString*>* NativeScriptRunUIKitHostLifecycle(NSString* hostId,
                                                                      NSString* phase) {`;
    const lifecycleReplacement = `NSDictionary<NSString*, NSString*>* NativeScriptRunUIKitHostLifecycle(NSString* hostId,
                                                                      NSString* phase) {
  if (![HanlinExpoNativeAPIGate isNativeAPIAuthorizedForCurrentSession]) {
    NSLog(@"[HANLIN_EXPO_NATIVEAPI_DENIAL] NativeScriptRunUIKitHostLifecycle rejected: 'ios-native-api' capability is NOT granted.");
    return nil;
  }`;
    mmContent = applyStrictPatch(mmContent, lifecycleAnchor, lifecycleReplacement, 'NativeScriptRunUIKitHostLifecycle');

    // Patch install()
    const installAnchor = 'bool NativeScriptNativeApiModule::install(jsi::Runtime& runtime, std::string metadataPath) {';
    const installReplacement = `bool NativeScriptNativeApiModule::install(jsi::Runtime& runtime, std::string metadataPath) {
  if (![HanlinExpoNativeAPIGate isNativeAPIAuthorizedForRuntime:&runtime]) {
    NSLog(@"[HANLIN_EXPO_NATIVEAPI_DENIAL] NativeScriptNativeApiModule::install rejected: 'ios-native-api' capability is NOT granted.");
    return false;
  }`;
    mmContent = applyStrictPatch(mmContent, installAnchor, installReplacement, 'install');

    // Patch installWorkletRuntime() - exactly one complete signature and opening brace
    const workletAnchor = `bool NativeScriptNativeApiModule::installWorkletRuntime(jsi::Runtime& runtime,
                                                        jsi::Object runtimeHolder,
                                                        std::string metadataPath) {`;
    const workletReplacement = `bool NativeScriptNativeApiModule::installWorkletRuntime(jsi::Runtime& runtime,
                                                        jsi::Object runtimeHolder,
                                                        std::string metadataPath) {
  if (![HanlinExpoNativeAPIGate isNativeAPIAuthorizedForRuntime:&runtime]) {
    NSLog(@"[HANLIN_EXPO_NATIVEAPI_DENIAL] NativeScriptNativeApiModule::installWorkletRuntime rejected: 'ios-native-api' capability is NOT granted.");
    return false;
  }`;
    mmContent = applyStrictPatch(mmContent, workletAnchor, workletReplacement, 'installWorkletRuntime');

    // Strict validation of the patched file:
    const installWorkletCount = mmContent.split('installWorkletRuntime(').length - 1;
    if (installWorkletCount !== 1) {
      throw new Error(`[HanlinExpoNativeAPI] Validation failed: installWorkletRuntime count = ${installWorkletCount}, expected 1`);
    }
    const denialCount = mmContent.split('[HANLIN_EXPO_NATIVEAPI_DENIAL]').length - 1;
    if (denialCount !== 4) {
      throw new Error(`[HanlinExpoNativeAPI] Validation failed: gate denial count = ${denialCount}, expected 4`);
    }
    if (mmContent.includes('jsi::Object runtimeHolder,\n                                                        std::string metadataPath) {\n  writeSmokeMarker')) {
      throw new Error('[HanlinExpoNativeAPI] Validation failed: duplicate parameters detected in installWorkletRuntime');
    }

    await writeFile(moduleMmPath, mmContent, 'utf8');

    console.log('[HanlinExpoNativeAPI] Injected session/runtime-scoped HanlinExpoNativeAPIGate into NativeScriptNativeApiModule.mm');
  }

  // 8. Generate Codegen artifacts into target directories
  await generateCodegen({
    nsOutputDir: resolve(coreTargetDir, 'generated'),
    wlOutputDir: resolve(workletsTargetDir, 'generated')
  });

  // 9. Clean up legacy subdirectories under Sources/HanlinExpoNativeAPI (pure Swift target)
  const swiftTargetDir = resolve(sourcesRoot, 'HanlinExpoNativeAPI');
  await rm(resolve(swiftTargetDir, 'nativescript'), { recursive: true, force: true });
  await rm(resolve(swiftTargetDir, 'worklets'), { recursive: true, force: true });
  await rm(resolve(swiftTargetDir, 'generated'), { recursive: true, force: true });
  await rm(resolve(swiftTargetDir, 'bridge'), { recursive: true, force: true });

  // 10. Verify metadata and artifacts
  await verifyNSMD(metadataTargetDir);
  await verifyArtifacts();

  console.log('[HanlinExpoNativeAPI] All Native API dependencies prepared and verified successfully.');
}

export default prepareExpoNativeAPI;

const isMain = process.argv[1] && resolve(fileURLToPath(import.meta.url)) === resolve(process.argv[1]);
if (isMain) {
  prepareExpoNativeAPI().catch((err) => {
    console.error(err);
    process.exit(1);
  });
}
