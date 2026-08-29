import { createHash } from 'node:crypto';
import { cp, mkdir, readFile, readdir, rename, rm, writeFile } from 'node:fs/promises';
import { basename, resolve } from 'node:path';

const pinnedVersion = '9.1.0';
const scriptRoot = resolve(import.meta.dirname);
const repositoryRoot = resolve(scriptRoot, '..', '..');
const coreRoot = resolve(scriptRoot, 'node_modules', '@nativescript', 'core');
const iosRuntimeRoot = resolve(scriptRoot, 'node_modules', '@nativescript', 'ios');
const platformRoot = resolve(coreRoot, 'platforms', 'ios');
const artifactsRoot = resolve(repositoryRoot, 'Packages', 'HanlinNativeScriptRuntime', 'Artifacts');
const stagingRoot = `${artifactsRoot}.staging-${process.pid}`;

const readJSON = async (path) => JSON.parse(await readFile(path, 'utf8'));
const sha256 = (bytes) => createHash('sha256').update(bytes).digest('hex');
const corePackage = await readJSON(resolve(coreRoot, 'package.json'));
const iosPackage = await readJSON(resolve(iosRuntimeRoot, 'package.json'));
if (corePackage.version !== pinnedVersion || iosPackage.version !== pinnedVersion) {
  throw new Error(
    `NativeScript version mismatch: core=${corePackage.version} ios=${iosPackage.version}; expected ${pinnedVersion}`
  );
}

const frameworks = (await readdir(platformRoot, { withFileTypes: true }))
  .filter((entry) => entry.isDirectory() && entry.name.endsWith('.xcframework'))
  .map((entry) => entry.name)
  .sort();
const expectedFrameworks = ['NSCWinterTC.xcframework', 'TNSWidgets.xcframework'];
if (JSON.stringify(frameworks) !== JSON.stringify(expectedFrameworks)) {
  throw new Error(`@nativescript/core ${pinnedVersion} iOS XCFramework closure changed: ${frameworks.join(', ')}`);
}

const nativeAPIUsageBytes = await readFile(resolve(platformRoot, 'native-api-usage.json'));
const nativeAPIUsage = JSON.parse(nativeAPIUsageBytes.toString('utf8'));
for (const requiredUsage of ['TNSWidgets*:*', 'UIViewNativeScript:NativeScript']) {
  if (!nativeAPIUsage.uses?.includes(requiredUsage)) {
    throw new Error(`native-api-usage.json is missing ${requiredUsage}`);
  }
}

await rm(stagingRoot, { recursive: true, force: true });
await mkdir(stagingRoot, { recursive: true });
const manifestArtifacts = [];
for (const framework of frameworks) {
  const source = resolve(platformRoot, framework);
  const infoBytes = await readFile(resolve(source, 'Info.plist'));
  const info = infoBytes.toString('utf8');
  if (!info.includes('<string>ios-arm64</string>') || !info.includes('ios-arm64_x86_64-simulator')) {
    throw new Error(`${framework} does not contain the required iOS device and Simulator slices`);
  }
  await cp(source, resolve(stagingRoot, framework), { recursive: true, verbatimSymlinks: true });
  manifestArtifacts.push({
    name: basename(framework, '.xcframework'),
    source: `@nativescript/core/platforms/ios/${framework}`,
    packagePath: `Artifacts/${framework}`,
    linkage: 'dynamic',
    disposition: 'link-and-embed',
    infoPlistSHA256: sha256(infoBytes),
  });
}

await writeFile(resolve(stagingRoot, 'native-api-usage.json'), nativeAPIUsageBytes);
await writeFile(resolve(stagingRoot, 'dependency-closure.json'), `${JSON.stringify({
  schemaVersion: 1,
  coreVersion: corePackage.version,
  iosRuntimeVersion: iosPackage.version,
  runtimeProvider: 'NativeScript/ios-spm',
  runtimeDisposition: 'SwiftPM link-and-embed',
  artifacts: manifestArtifacts,
  nativeAPIUsage: {
    source: '@nativescript/core/platforms/ios/native-api-usage.json',
    packagePath: 'Artifacts/native-api-usage.json',
    sha256: sha256(nativeAPIUsageBytes),
    uses: nativeAPIUsage.uses,
    disposition: 'metadata-generator-input',
  },
}, null, 2)}\n`);

await rm(artifactsRoot, { recursive: true, force: true });
await rename(stagingRoot, artifactsRoot);
console.log(`Prepared NativeScript ${pinnedVersion} iOS dependency closure: ${frameworks.join(', ')}`);
