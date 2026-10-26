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

const scriptRoot = resolve(import.meta.dirname);
const repoRoot = resolve(scriptRoot, '..', '..');
const lockPath = resolve(scriptRoot, 'dependency-lock.json');
const targetPackageRoot = resolve(repoRoot, 'Packages', 'HanlinExpoNativeAPI');

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

  // 4. Stage metadata and Libffi into Artifacts
  const artifactsDir = resolve(targetPackageRoot, 'Artifacts');
  const metadataTargetDir = resolve(artifactsDir, 'metadata');
  await mkdir(metadataTargetDir, { recursive: true });

  const nsPkgDir = resolve(nsExtractDir, 'package');
  const metadataSrcDir = resolve(nsPkgDir, 'metadata');
  for (const f of ['metadata.ios.arm64.nsmd', 'metadata.ios-sim.arm64.nsmd', 'metadata.ios-sim.x86_64.nsmd']) {
    await cp(resolve(metadataSrcDir, f), resolve(metadataTargetDir, f));
  }

  const libffiSrc = resolve(nsPkgDir, 'ios', 'vendor', 'Libffi.xcframework');
  const libffiDst = resolve(artifactsDir, 'Libffi.xcframework');
  if (existsSync(libffiSrc)) {
    await rm(libffiDst, { recursive: true, force: true });
    await cp(libffiSrc, libffiDst, { recursive: true, verbatimSymlinks: true });
  }

  // 5. Stage NativeScript sources into Sources/HanlinExpoNativeAPI/nativescript
  const nsTargetDir = resolve(targetPackageRoot, 'Sources', 'HanlinExpoNativeAPI', 'nativescript');
  await rm(nsTargetDir, { recursive: true, force: true });
  await mkdir(nsTargetDir, { recursive: true });

  // Copy ios/ directory
  await cp(resolve(nsPkgDir, 'ios'), resolve(nsTargetDir, 'ios'), { recursive: true });
  // Copy native-api/ directory
  await cp(resolve(nsPkgDir, 'native-api'), resolve(nsTargetDir, 'native-api'), { recursive: true });

  // 6. Apply native authorization gate hook into NativeScriptNativeApiModule.mm
  const moduleMmPath = resolve(nsTargetDir, 'ios', 'NativeScriptNativeApiModule.mm');
  if (existsSync(moduleMmPath)) {
    let mmContent = await readFile(moduleMmPath, 'utf8');

    // Add include if missing
    if (!mmContent.includes('#include "HanlinExpoNativeAPIGate.h"')) {
      mmContent = '#include "HanlinExpoNativeAPIGate.h"\n' + mmContent;
    }

    // In bundledMetadataPath(): consult HanlinExpoNativeAPIGate first
    if (!mmContent.includes('HanlinExpoNativeAPIGate.bundledMetadataPath')) {
      mmContent = mmContent.replace(
        'std::string bundledMetadataPath() {',
        `std::string bundledMetadataPath() {
  NSString* gatePath = [HanlinExpoNativeAPIGate bundledMetadataPath];
  if (gatePath != nil && gatePath.length > 0) {
    return gatePath.UTF8String;
  }`
      );
    }

    // In NativeScriptCreateUIKitHost: enforce native gate
    if (!mmContent.includes('[HanlinExpoNativeAPIGate isNativeAPIAuthorizedForCurrentSession]')) {
      mmContent = mmContent.replace(
        'NSDictionary<NSString*, NSString*>* NativeScriptCreateUIKitHost(NSString* hostId) {',
        `NSDictionary<NSString*, NSString*>* NativeScriptCreateUIKitHost(NSString* hostId) {
  if (![HanlinExpoNativeAPIGate isNativeAPIAuthorizedForCurrentSession]) {
    NSLog(@"[HANLIN_EXPO_NATIVEAPI_DENIAL] NativeScriptCreateUIKitHost rejected: 'ios-native-api' capability is NOT granted.");
    return nil;
  }`
      );

      // In install: enforce native gate
      mmContent = mmContent.replace(
        'bool NativeScriptNativeApiModule::install(jsi::Runtime& runtime, std::string metadataPath) {',
        `bool NativeScriptNativeApiModule::install(jsi::Runtime& runtime, std::string metadataPath) {
  if (![HanlinExpoNativeAPIGate isNativeAPIAuthorizedForCurrentSession]) {
    NSLog(@"[HANLIN_EXPO_NATIVEAPI_DENIAL] NativeScriptNativeApiModule::install rejected: 'ios-native-api' capability is NOT granted.");
    return false;
  }`
      );

      // In installWorkletRuntime: enforce native gate
      mmContent = mmContent.replace(
        'bool NativeScriptNativeApiModule::installWorkletRuntime(jsi::Runtime& runtime,',
        `bool NativeScriptNativeApiModule::installWorkletRuntime(jsi::Runtime& runtime,
                                                        jsi::Object runtimeHolder,
                                                        std::string metadataPath) {
  if (![HanlinExpoNativeAPIGate isNativeAPIAuthorizedForCurrentSession]) {
    NSLog(@"[HANLIN_EXPO_NATIVEAPI_DENIAL] NativeScriptNativeApiModule::installWorkletRuntime rejected: 'ios-native-api' capability is NOT granted.");
    return false;
  }`
      );
    }

    await writeFile(moduleMmPath, mmContent, 'utf8');
    console.log('[HanlinExpoNativeAPI] Injected session-scoped HanlinExpoNativeAPIGate into NativeScriptNativeApiModule.mm');
  }

  // 7. Stage Worklets sources into Sources/HanlinExpoNativeAPI/worklets
  const wlPkgDir = resolve(wlExtractDir, 'package');
  const wlTargetDir = resolve(targetPackageRoot, 'Sources', 'HanlinExpoNativeAPI', 'worklets');
  await rm(wlTargetDir, { recursive: true, force: true });
  await mkdir(wlTargetDir, { recursive: true });

  await cp(resolve(wlPkgDir, 'Common'), resolve(wlTargetDir, 'Common'), { recursive: true });
  await cp(resolve(wlPkgDir, 'apple'), resolve(wlTargetDir, 'apple'), { recursive: true });

  // 8. Generate Codegen artifacts
  await generateCodegen({
    outputDir: resolve(targetPackageRoot, 'Sources', 'HanlinExpoNativeAPI', 'generated')
  });

  // 9. Verify metadata
  await verifyNSMD(metadataTargetDir);

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
