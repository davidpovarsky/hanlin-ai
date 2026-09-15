import { createHash } from 'node:crypto';
import { access, chmod, cp, mkdir, readFile, readdir, rename, rm, writeFile } from 'node:fs/promises';
import { basename, resolve } from 'node:path';

const scriptRoot = resolve(import.meta.dirname);
const repositoryRoot = resolve(scriptRoot, '..', '..');
const coreRoot = resolve(scriptRoot, 'node_modules', '@nativescript', 'core');
const iosRuntimeRoot = resolve(scriptRoot, 'node_modules', '@nativescript', 'ios');
const swiftUIRoot = resolve(scriptRoot, 'node_modules', '@nativescript', 'swift-ui');
const platformRoot = resolve(coreRoot, 'platforms', 'ios');
const artifactsRoot = resolve(repositoryRoot, 'Packages', 'HanlinNativeScriptRuntime', 'Artifacts');
const stagingRoot = `${artifactsRoot}.staging-${process.pid}`;
const sharedRuntimeRoot = resolve(
  repositoryRoot,
  'Packages',
  'HanlinNativeScriptRuntime',
  'Sources',
  'HanlinNativeScriptRuntime',
  'Resources',
  'NativeScriptSharedRuntime'
);

const readJSON = async (path) => JSON.parse(await readFile(path, 'utf8'));
const sha256 = (bytes) => createHash('sha256').update(bytes).digest('hex');
const dependencyLock = await readJSON(resolve(scriptRoot, 'dependency-lock.json'));
const pinnedVersion = dependencyLock.nativeScript.coreVersion;
const corePackage = await readJSON(resolve(coreRoot, 'package.json'));
const iosPackage = await readJSON(resolve(iosRuntimeRoot, 'package.json'));
const swiftUIPackage = await readJSON(resolve(swiftUIRoot, 'package.json'));
if (corePackage.version !== pinnedVersion || iosPackage.version !== dependencyLock.nativeScript.iosRuntimeVersion) {
  throw new Error(
    `NativeScript version mismatch: core=${corePackage.version} ios=${iosPackage.version}; expected ${pinnedVersion}`
  );
}
if (swiftUIPackage.version !== dependencyLock.swiftUI.version) {
  throw new Error(
    `NativeScript SwiftUI version mismatch: installed=${swiftUIPackage.version}; expected ${dependencyLock.swiftUI.version}`
  );
}
for (const [path, expectedSHA256] of Object.entries(dependencyLock.swiftUI.runtimeFiles)) {
  const bytes = await readFile(resolve(swiftUIRoot, path));
  if (sha256(bytes) !== expectedSHA256) {
    throw new Error(`@nativescript/swift-ui ${path} does not match dependency-lock.json`);
  }
}
const upstreamNativeContractBytes = await readFile(
  resolve(swiftUIRoot, dependencyLock.swiftUI.upstreamNativeContract.path)
);
if (sha256(upstreamNativeContractBytes) !== dependencyLock.swiftUI.upstreamNativeContract.sha256) {
  throw new Error('@nativescript/swift-ui SwiftUIProvider.swift does not match dependency-lock.json');
}

// The app's existing Xcode metadata phase runs after SwiftPM has emitted the
// generated Objective-C interface for HanlinNativeScriptRuntime. Install a
// downstream wrapper at the pinned NativeScript generator entry point so that
// phase can expose the Swift interface to the upstream metadata generator while
// retaining the full Xcode build-phase environment it requires.
const metadataInternalRoot = resolve(iosRuntimeRoot, 'framework', 'internal');
const metadataWrapper = await readFile(resolve(scriptRoot, 'build-step-metadata-generator-wrapper.py'), 'utf8');
const metadataGeneratorDirectories = (await readdir(metadataInternalRoot, { withFileTypes: true }))
  .filter((entry) => entry.isDirectory() && entry.name.startsWith('metadata-generator-'))
  .map((entry) => entry.name)
  .sort();
if (metadataGeneratorDirectories.length === 0) {
  throw new Error('No NativeScript metadata generator directory was found');
}
for (const directory of metadataGeneratorDirectories) {
  const generatorRoot = resolve(metadataInternalRoot, directory, 'bin');
  const generatorPath = resolve(generatorRoot, 'build-step-metadata-generator.py');
  const upstreamPath = resolve(generatorRoot, 'build-step-metadata-generator-upstream.py');
  const currentGenerator = await readFile(generatorPath, 'utf8');
  if (currentGenerator.includes('HANLIN_METADATA_WRAPPER_V1')) {
    try {
      await readFile(upstreamPath, 'utf8');
    } catch {
      throw new Error(`Hanlin NativeScript metadata wrapper is installed without its upstream backup: ${upstreamPath}`);
    }
  } else {
    await writeFile(upstreamPath, currentGenerator, 'utf8');
    await chmod(upstreamPath, 0o755);
  }
  await writeFile(generatorPath, metadataWrapper, 'utf8');
  await chmod(generatorPath, 0o755);
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
  schemaVersion: 2,
  coreVersion: corePackage.version,
  iosRuntimeVersion: iosPackage.version,
  runtimeProvider: 'NativeScript/ios-spm',
  runtimeDisposition: 'SwiftPM link-and-embed',
  swiftUIPlugin: {
    package: dependencyLock.swiftUI.package,
    version: swiftUIPackage.version,
    registryTarball: dependencyLock.swiftUI.registryTarball,
    integrity: dependencyLock.swiftUI.integrity,
    tarballSHA256: dependencyLock.swiftUI.tarballSHA256,
    license: dependencyLock.swiftUI.license,
    runtimeFiles: dependencyLock.swiftUI.runtimeFiles,
    upstreamNativeContract: dependencyLock.swiftUI.upstreamNativeContract,
    embeddedProviderClass: dependencyLock.swiftUI.embeddedProviderClass,
    disposition: 'JavaScript bundled per package; native provider compiled into host',
  },
  artifacts: manifestArtifacts,
  nativeAPIUsage: {
    source: '@nativescript/core/platforms/ios/native-api-usage.json',
    packagePath: 'Artifacts/native-api-usage.json',
    sha256: sha256(nativeAPIUsageBytes),
    uses: nativeAPIUsage.uses,
    disposition: 'metadata-generator-input',
  },
  sharedRuntime: {
    coreVersion: corePackage.version,
    disposition: 'Embedded JavaScript modules in HanlinNativeScriptRuntime Resources',
    packages: [
      '@nativescript/core',
      '@csstools/color-helpers',
      '@csstools/css-calc',
      '@csstools/css-color-parser',
      '@csstools/css-parser-algorithms',
      '@csstools/css-tokenizer',
      'acorn',
      'css-tree',
      'css-what',
      'emoji-regex',
      'source-map-js',
      'tslib',
    ],
  },
}, null, 2)}\n`);

async function safeMoveDirectory(source, destination) {
  try {
    await rm(destination, { recursive: true, force: true });
  } catch {}
  for (let i = 0; i < 5; i++) {
    try {
      await rename(source, destination);
      return;
    } catch (e) {
      if (e.code === 'EPERM' || e.code === 'EBUSY') {
        await new Promise((r) => setTimeout(r, 200));
      } else {
        throw e;
      }
    }
  }
  await cp(source, destination, { recursive: true });
  await rm(source, { recursive: true, force: true });
}

await safeMoveDirectory(stagingRoot, artifactsRoot);

async function stageSharedCoreRuntime(destinationRoot) {
  const sharedStaging = `${destinationRoot}.staging-${process.pid}`;
  await rm(sharedStaging, { recursive: true, force: true });
  await mkdir(sharedStaging, { recursive: true });

  const coreDest = resolve(sharedStaging, '@nativescript', 'core');
  await mkdir(coreDest, { recursive: true });

  async function copyCoreTree(srcDir, destDir) {
    const entries = await readdir(srcDir, { withFileTypes: true });
    for (const entry of entries) {
      if (entry.name === 'platforms' || entry.name === 'cli-hooks') continue;
      const srcPath = resolve(srcDir, entry.name);
      const destPath = resolve(destDir, entry.name);
      if (entry.isDirectory()) {
        await mkdir(destPath, { recursive: true });
        await copyCoreTree(srcPath, destPath);
      } else if (entry.isFile()) {
        if ((entry.name.endsWith('.js') || entry.name.endsWith('.mjs') || entry.name === 'package.json') && !entry.name.endsWith('.android.js')) {
          await cp(srcPath, destPath);
          if (entry.name.endsWith('.ios.js')) {
            const alias = resolve(destDir, entry.name.replace(/\.ios\.js$/, '.js'));
            try { await access(alias); } catch { await cp(srcPath, alias); }
          } else if (entry.name.endsWith('.ios.mjs')) {
            const alias = resolve(destDir, entry.name.replace(/\.ios\.mjs$/, '.mjs'));
            try { await access(alias); } catch { await cp(srcPath, alias); }
          }
        }
      }
    }
  }
  await copyCoreTree(coreRoot, coreDest);

  // Hanlin NativeScript Config-as-JSON ESM Provider
  // Resolves the current MiniApp's package.json configuration at runtime per session
  // without bundling @nativescript/core into the MiniApp or compiling raw JSON as JS.
  const appConfigProviderContent = `// Hanlin NativeScript Config-as-JSON ESM Provider
// Implements runtime resolution of the active MiniApp's package.json configuration
// without bundling @nativescript/core into the MiniApp or compiling raw JSON as JS.
let config = {};
try {
  if (typeof global !== 'undefined' && global.require) {
    config = global.require('~/package.json');
  }
} catch (e) {
  try {
    if (typeof global !== 'undefined' && global.__hanlinAppConfig) {
      config = global.__hanlinAppConfig;
    }
  } catch (_) {}
}
export default config;
`;
  await writeFile(resolve(coreDest, 'app-config.js'), appConfigProviderContent);
  await writeFile(resolve(coreDest, 'app-config.mjs'), appConfigProviderContent);

  // Rewire ~/package.json imports in Core to the Hanlin config-as-JSON provider
  for (const profilingSubpath of ['profiling/index.js', 'profiling/index.ios.js']) {
    const p = resolve(coreDest, profilingSubpath);
    try {
      const src = await readFile(p, 'utf8');
      await writeFile(p, src.replace("import appConfig from '~/package.json';", "import appConfig from '../app-config.js';"));
    } catch {}
  }
  for (const styleScopeSubpath of ['ui/styling/style-scope.js', 'ui/styling/style-scope.ios.js']) {
    const p = resolve(coreDest, styleScopeSubpath);
    try {
      const src = await readFile(p, 'utf8');
      await writeFile(p, src.replace("import appConfig from '~/package.json';", "import appConfig from '../../app-config.js';"));
    } catch {}
  }

  const dependencies = [
    '@csstools/color-helpers',
    '@csstools/css-calc',
    '@csstools/css-color-parser',
    '@csstools/css-parser-algorithms',
    '@csstools/css-tokenizer',
    'acorn',
    'css-tree',
    'css-what',
    'emoji-regex',
    'source-map-js',
    'tslib',
  ];

  for (const dep of dependencies) {
    const depSrc = resolve(scriptRoot, 'node_modules', dep);
    const depDest = resolve(sharedStaging, dep);
    await mkdir(depDest, { recursive: true });

    async function copyDepTree(srcDir, destDir) {
      const entries = await readdir(srcDir, { withFileTypes: true });
      for (const entry of entries) {
        if (entry.name === 'node_modules' || entry.name.startsWith('.')) continue;
        const srcPath = resolve(srcDir, entry.name);
        const destPath = resolve(destDir, entry.name);
        if (entry.isDirectory()) {
          await mkdir(destPath, { recursive: true });
          await copyDepTree(srcPath, destPath);
        } else if (entry.isFile()) {
          if (entry.name.endsWith('.js') || entry.name.endsWith('.mjs') || entry.name === 'package.json') {
            await cp(srcPath, destPath);
          }
        }
      }
    }
    await copyDepTree(depSrc, depDest);
  }

  const reexports = {
    'tslib/index.mjs': 'import * as tslib from "./tslib.es6.mjs"; export * from "./tslib.es6.mjs"; export default tslib;\n',
    'tslib/index.js': 'import * as tslib from "./tslib.es6.mjs"; export * from "./tslib.es6.mjs"; export default tslib;\n',
    '@csstools/color-helpers/index.mjs': 'export * from "./dist/index.mjs";\n',
    '@csstools/color-helpers/index.js': 'export * from "./dist/index.mjs";\n',
    '@csstools/css-calc/index.mjs': 'export * from "./dist/index.mjs";\n',
    '@csstools/css-calc/index.js': 'export * from "./dist/index.mjs";\n',
    '@csstools/css-color-parser/index.mjs': 'export * from "./dist/index.mjs";\n',
    '@csstools/css-color-parser/index.js': 'export * from "./dist/index.mjs";\n',
    '@csstools/css-parser-algorithms/index.mjs': 'export * from "./dist/index.mjs";\n',
    '@csstools/css-parser-algorithms/index.js': 'export * from "./dist/index.mjs";\n',
    '@csstools/css-tokenizer/index.mjs': 'export * from "./dist/index.mjs";\n',
    '@csstools/css-tokenizer/index.js': 'export * from "./dist/index.mjs";\n',
    'acorn/index.mjs': 'export * from "./dist/acorn.mjs";\n',
    'acorn/index.js': 'export * from "./dist/acorn.mjs";\n',
    'css-tree/index.mjs': 'export * from "./dist/csstree.esm.js";\n',
    'css-tree/index.js': 'export * from "./dist/csstree.esm.js";\n',
    'css-what/index.mjs': 'export * from "./dist/esm/index.js";\n',
    'css-what/index.js': 'export * from "./dist/esm/index.js";\n',
    'emoji-regex/index.mjs': `const emojiRegex = () => {
  return /[#*0-9]\\uFE0F?\\u20E3|[\\xA9\\xAE\\u203C\\u2049\\u2122\\u2139\\u2194-\\u2199\\u21A9\\u21AA\\u231A\\u231B\\u2328\\u23CF\\u23ED-\\u23EF\\u23F1\\u23F2\\u23F8-\\u23FA\\u24C2\\u25AA\\u25AB\\u25B6\\u25C0\\u25FB\\u25FC\\u25FE\\u2600-\\u2604\\u260E\\u2611\\u2614\\u2615\\u2618\\u2620\\u2622\\u2623\\u2626\\u262A\\u262E\\u262F\\u2638-\\u263A\\u2640\\u2642\\u2648-\\u2653\\u265F\\u2660\\u2663\\u2665\\u2666\\u2668\\u267B\\u267E\\u267F\\u2692\\u2694-\\u2697\\u2699\\u269B\\u269C\\u26A0\\u26A7\\u26AA\\u26B0\\u26B1\\u26BD\\u26BE\\u26C4\\u26C8\\u26CF\\u26D1\\u26E9\\u26F0-\\u26F5\\u26F7\\u26F8\\u26FA\\u2702\\u2708\\u2709\\u270F\\u2712\\u2714\\u2716\\u271D\\u2721\\u2733\\u2734\\u2744\\u2747\\u2757\\u2763\\u27A1\\u2934\\u2935\\u2B05-\\u2B07\\u2B1B\\u2B1C\\u2B55\\u3030\\u303D\\u3297\\u3299]\\uFE0F?|[\\u261D\\u270C\\u270D](?:\\uD83C[\\uDFFB-\\uDFFF]|\\uFE0F)?|[\\u270A\\u270B](?:\\uD83C[\\uDFFB-\\uDFFF])?|[\\u23E9-\\u23EC\\u23F0\\u23F3\\u25FD\\u2693\\u26A1\\u26AB\\u26C5\\u26CE\\u26D4\\u26EA\\u26FD\\u2705\\u2728\\u274C\\u274E\\u2753-\\u2755\\u2795-\\u2797\\u27B0\\u27BF\\u2B50]|\\u26D3\\uFE0F?(?:\\u200D\\uD83D\\uDCA5)?|\\u26F9(?:\\uD83C[\\uDFFB-\\uDFFF]|\\uFE0F)?(?:\\u200D[\\u2640\\u2642]\\uFE0F?)?|\\u2764\\uFE0F?(?:\\u200D(?:\\uD83D\\uDD25|\\uD83E\\uDE79))?|\\uD83C(?:[\\uDC04\\uDD70\\uDD71\\uDD7E\\uDD7F\\uDE02\\uDE37\\uDF21\\uDF24-\\uDF2C\\uDF36\\uDF7D\\uDF96\\uDF97\\uDF99-\\uDF9B\\uDF9E\\uDF9F\\uDFCD\\uDFCE\\uDFD4-\\uDFDF\\uDFF5\\uDFF7]\\uFE0F?|[\\uDF85\\uDFC2\\uDFC7](?:\\uD83C[\\uDFFB-\\uDFFF])?|[\\uDFC4\\uDFCA](?:\\uD83C[\\uDFFB-\\uDFFF])?(?:\\u200D[\\u2640\\u2642]\\uFE0F?)?|[\\uDFCB\\uDFCC](?:\\uD83C[\\uDFFB-\\uDFFF]|\\uFE0F)?(?:\\u200D[\\u2640\\u2642]\\uFE0F?)?|[\\uDCCF\\uDD8E\\uDD91-\\uDD9A\\uDE01\\uDE1A\\uDE2F\\uDE32-\\uDE36\\uDE38-\\uDE3A\\uDE50\\uDE51\\uDF00-\\uDF20\\uDF2D-\\uDF35\\uDF37-\\uDF43\\uDF45-\\uDF4A\\uDF4C-\\uDF7C\\uDF7E-\\uDF84\\uDF86-\\uDF93\\uDFA0-\\uDFC1\\uDFC5\\uDFC6\\uDFC8\\uDFC9\\uDFCF-\\uDFD3\\uDFE0-\\uDFF0\\uDFF8-\\uDFFF]|\\uDDE6\\uD83C[\\uDDE8-\\uDDEC\\uDDEE\\uDDF1\\uDDF2\\uDDF4\\uDDF6-\\uDDFA\\uDDFC\\uDDFD\\uDDFF]|\\uDDE7\\uD83C[\\uDDE6\\uDDE7\\uDDE9-\\uDDEF\\uDDF1-\\uDDF4\\uDDF6-\\uDDF9\\uDDFB\\uDDFC\\uDDFE\\uDDFF]|\\uDDE8\\uD83C[\\uDDE6\\uDDE8\\uDDE9\\uDDEB-\\uDDEE\\uDDF0-\\uDDF7\\uDDFA-\\uDDFF]|\\uDDE9\\uD83C[\\uDDEA\\uDDEC\\uDDEF\\uDDF0\\uDDF2\\uDDF4\\uDDFF]|\\uDDEA\\uD83C[\\uDDE6\\uDDE8\\uDDEA\\uDDEC\\uDDED\\uDDF7-\\uDDFA]|\\uDDEB\\uD83C[\\uDDEE-\\uDDF0\\uDDF2\\uDDF4\\uDDF7]|\\uDDEC\\uD83C[\\uDDE6\\uDDE7\\uDDE9-\\uDDEE\\uDDF1-\\uDDF3\\uDDF5-\\uDDFA\\uDDFC\\uDDFE]|\\uDDED\\uD83C[\\uDDF0\\uDDF2\\uDDF3\\uDDF7\\uDDF9\\uDDFA]|\\uDDEE\\uD83C[\\uDDE8-\\uDDEA\\uDDF1-\\uDDF4\\uDDF6-\\uDDF9]|\\uDDEF\\uD83C[\\uDDEA\\uDDF2\\uDDF4\\uDDF5]|\\uDDF0\\uD83C[\\uDDEA\\uDDEC-\\uDDEE\\uDDF2\\uDDF3\\uDDF5\\uDDF7\\uDDFC\\uDDFE\\uDDFF]|\\uDDF1\\uD83C[\\uDDE6-\\uDDE8\\uDDEE\\uDDF0\\uDDF7-\\uDDFB\\uDDFE]|\\uDDF2\\uD83C[\\uDDE6\\uDDE8-\\uDDED\\uDDF0-\\uDDFF]|\\uDDF3\\uD83C[\\uDDE6\\uDDE8\\uDDEA-\\uDDEC\\uDDEE\\uDDF1\\uDDF4\\uDDF5\\uDDF7\\uDDFA\\uDDFF]|\\uDDF4\\uD83C\\uDDF2|\\uDDF5\\uD83C[\\uDDE6\\uDDEA-\\uDDED\\uDDF0-\\uDDF3\\uDDF7-\\uDDF9\\uDDFC\\uDDFE]|\\uDDF6\\uD83C\\uDDE6|\\uDDF7\\uD83C[\\uDDEA\\uDDF4\\uDDF8\\uDDFA\\uDDFC]|\\uDDF8\\uD83C[\\uDDE6-\\uDDEA\\uDDEC-\\uDDF4\\uDDF7-\\uDDF9\\uDDFB\\uDDFD-\\uDDFF]|\\uDDF9\\uD83C[\\uDDE6\\uDDE8\\uDDE9\\uDDEB-\\uDDED\\uDDEF-\\uDDF4\\uDDF7\\uDDF9\\uDDFB\\uDDFC\\uDDFF]|\\uDDFA\\uD83C[\\uDDE6\\uDDEC\\uDDF2\\uDDF3\\uDDF8\\uDDFE\\uDDFF]|\\uDDFB\\uD83C[\\uDDE6\\uDDE8\\uDDEA\\uDDEC\\uDDEE\\uDDF3\\uDDFA]|\\uDDFC\\uD83C[\\uDDEB\\uDDF8]|\\uDDFD\\uD83C\\uDDF0|\\uDDFE\\uD83C[\\uDDEA\\uDDF9]|\\uDDFF\\uD83C[\\uDDE6\\uDDF2\\uDDFC]|\\uDF44(?:\\u200D\\uD83D\\uDFEB)?|\\uDF4B(?:\\u200D\\uD83D\\uDFE9)?|\\uDFC3(?:\\uD83C[\\uDFFB-\\uDFFF])?(?:\\u200D(?:[\\u2640\\u2642]\\uFE0F?(?:\\u200D\\u27A1\\uFE0F?)?|\\u27A1\\uFE0F?))?|\\uDFF3\\uFE0F?(?:\\u200D(?:\\u26A7\\uFE0F?|\\uD83C\\uDF08))?|\\uDFF4(?:\\u200D\\u2620\\uFE0F?|\\uDB40\\uDC67\\uDB40\\uDC62\\uDB40(?:\\uDC65\\uDB40\\uDC6E\\uDB40\\uDC67|\\uDC73\\uDB40\\uDC63\\uDB40\\uDC74|\\uDC77\\uDB40\\uDC6C\\uDB40\\uDC73)\\uDB40\\uDC7F)?)|\\uD83D(?:[\\uDC3F\\uDCFD\\uDD49\\uDD4A\\uDD6F\\uDD70\\uDD73\\uDD76-\\uDD79\\uDD87\\uDD8A-\\uDD8D\\uDDA5\\uDDA8\\uDDB1\\uDDB2\\uDDBC\\uDDC2-\\uDDC4\\uDDD1-\\uDDD3\\uDDDC-\\uDDDE\\uDDE1\\uDDE3\\uDDE8\\uDDEF\\uDDF3\\uDDFA\\uDECB\\uDECD-\\uDECF\\uDEE0-\\uDEE5\\uDEE9\\uDEF0\\uDEF3]\\uFE0F?|[\\uDC42\\uDC43\\uDC46-\\uDC50\\uDC66\\uDC67\\uDC6B-\\uDC6D\\uDC72\\uDC74-\\uDC76\\uDC78\\uDC7C\\uDC83\\uDC85\\uDC8F\\uDC91\\uDCAA\\uDD7A\\uDD95\\uDD96\\uDE4C\\uDE4F\\uDEC0\\uDECC](?:\\uD83C[\\uDFFB-\\uDFFF])?|[\\uDC6E-\\uDC71\\uDC73\\uDC77\\uDC81\\uDC82\\uDC86\\uDC87\\uDE45-\\uDE47\\uDE4B\\uDE4D\\uDE4E\\uDEA3\\uDEB4\\uDEB5](?:\\uD83C[\\uDFFB-\\uDFFF])?(?:\\u200D[\\u2640\\u2642]\\uFE0F?)?|[\\uDD74\\uDD90](?:\\uD83C[\\uDFFB-\\uDFFF]|\\uFE0F)?|[\\uDC00-\\uDC07\\uDC09-\\uDC14\\uDC16-\\uDC25\\uDC27-\\uDC3A\\uDC3C-\\uDC3E\\uDC40\\uDC44\\uDC45\\uDC51-\\uDC65\\uDC6A\\uDC79-\\uDC7B\\uDC7D-\\uDC80\\uDC84\\uDC88-\\uDC8E\\uDC90\\uDC92-\\uDCA9\\uDCAB-\\uDCFC\\uDCFF-\\uDD3D\\uDD4B-\\uDD4E\\uDD50-\\uDD67\\uDDA4\\uDDFB-\\uDE2D\\uDE2F-\\uDE34\\uDE37-\\uDE41\\uDE43\\uDE44\\uDE48-\\uDE4A\\uDE80-\\uDEA2\\uDEA4-\\uDEB3\\uDEB7-\\uDEBF\\uDEC1-\\uDEC5\\uDED0-\\uDED2\\uDED5-\\uDED8\\uDEDC-\\uDEDF\\uDEEB\\uDEEC\\uDEF4-\\uDEFC\\uDFE0-\\uDFEB\\uDFF0]|\\uDC08(?:\\u200D\\u2B1B)?|\\uDC15(?:\\u200D\\uD83E\\uDDBA)?|\\uDC26(?:\\u200D(?:\\u2B1B|\\uD83D\\uDD25))?|\\uDC3B(?:\\u200D\\u2744\\uFE0F?)?|\\uDC41\\uFE0F?(?:\\u200D\\uD83D\\uDDE8\\uFE0F?)?|\\uDC68(?:\\u200D(?:[\\u2695\\u2696\\u2708]\\uFE0F?|\\u2764\\uFE0F?\\u200D\\uD83D(?:\\uDC8B\\u200D\\uD83D)?\\uDC68|\\uD83C[\\uDF3E\\uDF73\\uDF7C\\uDF93\\uDFA4\\uDFA8\\uDFEB\\uDFED]|\\uD83D(?:[\\uDC68\\uDC69]\\u200D\\uD83D(?:\\uDC66(?:\\u200D\\uD83D\\uDC66)?|\\uDC67(?:\\u200D\\uD83D[\\uDC66\\uDC67])?)|[\\uDCBB\\uDCBC\\uDD27\\uDD2C\\uDE80\\uDE92]|\\uDC66(?:\\u200D\\uD83D\\uDC66)?|\\uDC67(?:\\u200D\\uD83D[\\uDC66\\uDC67])?)|\\uD83E(?:[\\uDDAF\\uDDBC\\uDDBD](?:\\u200D\\u27A1\\uFE0F?)?|[\\uDDB0-\\uDDB3]))|\\uD83C(?:\\uDFFB(?:\\u200D(?:[\\u2695\\u2696\\u2708]\\uFE0F?|\\u2764\\uFE0F?\\u200D\\uD83D(?:\\uDC8B\\u200D\\uD83D)?\\uDC68\\uD83C[\\uDFFB-\\uDFFF]|\\uD83C[\\uDF3E\\uDF73\\uDF7C\\uDF93\\uDFA4\\uDFA8\\uDFEB\\uDFED]|\\uD83D(?:[\\uDCBB\\uDCBC\\uDD27\\uDD2C\\uDE80\\uDE92]|\\uDC30\\u200D\\uD83D\\uDC68\\uD83C[\\uDFFC-\\uDFFF])|\\uD83E(?:[\\uDD1D\\uDEEF]\\u200D\\uD83D\\uDC68\\uD83C[\\uDFFC-\\uDFFF]|[\\uDDAF\\uDDBC\\uDDBD](?:\\u200D\\u27A1\\uFE0F?)?|[\\uDDB0-\\uDDB3])))?|\\uDFFC(?:\\u200D(?:[\\u2695\\u2696\\u2708]\\uFE0F?|\\u2764\\uFE0F?\\u200D\\uD83D(?:\\uDC8B\\u200D\\uD83D)?\\uDC68\\uD83C[\\uDFFB-\\uDFFF]|\\uD83C[\\uDF3E\\uDF73\\uDF7C\\uDF93\\uDFA4\\uDFA8\\uDFEB\\uDFED]|\\uD83D(?:[\\uDCBB\\uDCBC\\uDD27\\uDD2C\\uDE80\\uDE92]|\\uDC30\\u200D\\uD83D\\uDC68\\uD83C[\\uDFFB\\uDFFD-\\uDFFF])|\\uD83E(?:[\\uDD1D\\uDEEF]\\u200D\\uD83D\\uDC68\\uD83C[\\uDFFB\\uDFFD-\\uDFFF]|[\\uDDAF\\uDDBC\\uDDBD](?:\\u200D\\u27A1\\uFE0F?)?|[\\uDDB0-\\uDDB3])))?|\\uDFFD(?:\\u200D(?:[\\u2695\\u2696\\u2708]\\uFE0F?|\\u2764\\uFE0F?\\u200D\\uD83D(?:\\uDC8B\\u200D\\uD83D)?\\uDC68\\uD83C[\\uDFFB-\\uDFFF]|\\uD83C[\\uDF3E\\uDF73\\uDF7C\\uDF93\\uDFA4\\uDFA8\\uDFEB\\uDFED]|\\uD83D(?:[\\uDCBB\\uDCBC\\uDD27\\uDD2C\\uDE80\\uDE92]|\\uDC30\\u200D\\uD83D\\uDC68\\uD83C[\\uDFFB\\uDFFC\\uDFFE\\uDFFF])|\\uD83E(?:[\\uDD1D\\uDEEF]\\u200D\\uD83D\\uDC68\\uD83C[\\uDFFB\\uDFFC\\uDFFE\\uDFFF]|[\\uDDAF\\uDDBC\\uDDBD](?:\\u200D\\u27A1\\uFE0F?)?|[\\uDDB0-\\uDDB3])))?|\\uDFFE(?:\\u200D(?:[\\u2695\\u2696\\u2708]\\uFE0F?|\\u2764\\uFE0F?\\u200D\\uD83D(?:\\uDC8B\\u200D\\uD83D)?\\uDC68\\uD83C[\\uDFFB-\\uDFFF]|\\uD83C[\\uDF3E\\uDF73\\uDF7C\\uDF93\\uDFA4\\uDFA8\\uDFEB\\uDFED]|\\uD83D(?:[\\uDCBB\\uDCBC\\uDD27\\uDD2C\\uDE80\\uDE92]|\\uDC30\\u200D\\uD83D\\uDC68\\uD83C[\\uDFFB-\\uDFFD\\uDFFF])|\\uD83E(?:[\\uDD1D\\uDEEF]\\u200D\\uD83D\\uDC68\\uD83C[\\uDFFB-\\uDFFD\\uDFFF]|[\\uDDAF\\uDDBC\\uDDBD](?:\\u200D\\u27A1\\uFE0F?)?|[\\uDDB0-\\uDDB3])))?|\\uDFFF(?:\\u200D(?:[\\u2695\\u2696\\u2708]\\uFE0F?|\\u2764\\uFE0F?\\u200D\\uD83D(?:\\uDC8B\\u200D\\uD83D)?\\uDC68\\uD83C[\\uDFFB-\\uDFFF]|\\uD83C[\\uDF3E\\uDF73\\uDF7C\\uDF93\\uDFA4\\uDFA8\\uDFEB\\uDFED]|\\uD83D(?:[\\uDCBB\\uDCBC\\uDD27\\uDD2C\\uDE80\\uDE92]|\\uDC30\\u200D\\uD83D\\uDC68\\uD83C[\\uDFFB-\\uDFFE])|\\uD83E(?:[\\uDD1D\\uDEEF]\\u200D\\uD83D\\uDC68\\uD83C[\\uDFFB-\\uDFFE]|[\\uDDAF\\uDDBC\\uDDBD](?:\\u200D\\u27A1\\uFE0F?)?|[\\uDDB0-\\uDDB3])))?))?|\\uDC69(?:\\u200D(?:[\\u2695\\u2696\\u2708]\\uFE0F?|\\u2764\\uFE0F?\\u200D\\uD83D(?:\\uDC8B\\u200D\\uD83D)?[\\uDC68\\uDC69]|\\uD83C[\\uDF3E\\uDF73\\uDF7C\\uDF93\\uDFA4\\uDFA8\\uDFEB\\uDFED]|\\uD83D(?:[\\uDCBB\\uDCBC\\uDD27\\uDD2C\\uDE80\\uDE92]|\\uDC66(?:\\u200D\\uD83D\\uDC66)?|\\uDC67(?:\\u200D\\uD83D[\\uDC66\\uDC67])?|\\uDC69\\u200D\\uD83D(?:\\uDC66(?:\\u200D\\uD83D\\uDC66)?|\\uDC67(?:\\u200D\\uD83D[\\uDC66\\uDC67])?))|\\uD83E(?:[\\uDDAF\\uDDBC\\uDDBD](?:\\u200D\\u27A1\\uFE0F?)?|[\\uDDB0-\\uDDB3]))|\\uD83C(?:\\uDFFB(?:\\u200D(?:[\\u2695\\u2696\\u2708]\\uFE0F?|\\u2764\\uFE0F?\\u200D\\uD83D(?:[\\uDC68\\uDC69]|\\uDC8B\\u200D\\uD83D[\\uDC68\\uDC69])\\uD83C[\\uDFFB-\\uDFFF]|\\uD83C[\\uDF3E\\uDF73\\uDF7C\\uDF93\\uDFA4\\uDFA8\\uDFEB\\uDFED]|\\uD83D(?:[\\uDCBB\\uDCBC\\uDD27\\uDD2C\\uDE80\\uDE92]|\\uDC30\\u200D\\uD83D\\uDC69\\uD83C[\\uDFFC-\\uDFFF])|\\uD83E(?:[\\uDDAF\\uDDBC\\uDDBD](?:\\u200D\\u27A1\\uFE0F?)?|[\\uDDB0-\\uDDB3]|\\uDD1D\\u200D\\uD83D[\\uDC68\\uDC69]\\uD83C[\\uDFFC-\\uDFFF]|\\uDEEF\\u200D\\uD83D\\uDC69\\uD83C[\\uDFFC-\\uDFFF])))?|\\uDFFC(?:\\u200D(?:[\\u2695\\u2696\\u2708]\\uFE0F?|\\u2764\\uFE0F?\\u200D\\uD83D(?:[\\uDC68\\uDC69]|\\uDC8B\\u200D\\uD83D[\\uDC68\\uDC69])\\uD83C[\\uDFFB-\\uDFFF]|\\uD83C[\\uDF3E\\uDF73\\uDF7C\\uDF93\\uDFA4\\uDFA8\\uDFEB\\uDFED]|\\uD83D(?:[\\uDCBB\\uDCBC\\uDD27\\uDD2C\\uDE80\\uDE92]|\\uDC30\\u200D\\uD83D\\uDC69\\uD83C[\\uDFFB\\uDFFD-\\uDFFF])|\\uD83E(?:[\\uDDAF\\uDDBC\\uDDBD](?:\\u200D\\u27A1\\uFE0F?)?|[\\uDDB0-\\uDDB3]|\\uDD1D\\u200D\\uD83D[\\uDC68\\uDC69]\\uD83C[\\uDFFB\\uDFFD-\\uDFFF]|\\uDEEF\\u200D\\uD83D\\uDC69\\uD83C[\\uDFFB\\uDFFD-\\uDFFF])))?|\\uDFFD(?:\\u200D(?:[\\u2695\\u2696\\u2708]\\uFE0F?|\\u2764\\uFE0F?\\u200D\\uD83D(?:[\\uDC68\\uDC69]|\\uDC8B\\u200D\\uD83D[\\uDC68\\uDC69])\\uD83C[\\uDFFB-\\uDFFF]|\\uD83C[\\uDF3E\\uDF73\\uDF7C\\uDF93\\uDFA4\\uDFA8\\uDFEB\\uDFED]|\\uD83D(?:[\\uDCBB\\uDCBC\\uDD27\\uDD2C\\uDE80\\uDE92]|\\uDC30\\u200D\\uD83D\\uDC69\\uD83C[\\uDFFB\\uDFFC\\uDFFE\\uDFFF])|\\uD83E(?:[\\uDDAF\\uDDBC\\uDDBD](?:\\u200D\\u27A1\\uFE0F?)?|[\\uDDB0-\\uDDB3]|\\uDD1D\\u200D\\uD83D[\\uDC68\\uDC69]\\uD83C[\\uDFFB\\uDFFC\\uDFFE\\uDFFF]|\\uDEEF\\u200D\\uD83D\\uDC69\\uD83C[\\uDFFB\\uDFFC\\uDFFE\\uDFFF])))?|\\uDFFE(?:\\u200D(?:[\\u2695\\u2696\\u2708]\\uFE0F?|\\u2764\\uFE0F?\\u200D\\uD83D(?:[\\uDC68\\uDC69]|\\uDC8B\\u200D\\uD83D[\\uDC68\\uDC69])\\uD83C[\\uDFFB-\\uDFFF]|\\uD83C[\\uDF3E\\uDF73\\uDF7C\\uDF93\\uDFA4\\uDFA8\\uDFEB\\uDFED]|\\uD83D(?:[\\uDCBB\\uDCBC\\uDD27\\uDD2C\\uDE80\\uDE92]|\\uDC30\\u200D\\uD83D\\uDC69\\uD83C[\\uDFFB-\\uDFFD\\uDFFF])|\\uD83E(?:[\\uDDAF\\uDDBC\\uDDBD](?:\\u200D\\u27A1\\uFE0F?)?|[\\uDDB0-\\uDDB3]|\\uDD1D\\u200D\\uD83D[\\uDC68\\uDC69]\\uD83C[\\uDFFB-\\uDFFD\\uDFFF]|\\uDEEF\\u200D\\uD83D\\uDC69\\uD83C[\\uDFFB-\\uDFFD\\uDFFF])))?|\\uDFFF(?:\\u200D(?:[\\u2695\\u2696\\u2708]\\uFE0F?|\\u2764\\uFE0F?\\u200D\\uD83D(?:[\\uDC68\\uDC69]|\\uDC8B\\u200D\\uD83D[\\uDC68\\uDC69])\\uD83C[\\uDFFB-\\uDFFF]|\\uD83C[\\uDF3E\\uDF73\\uDF7C\\uDF93\\uDFA4\\uDFA8\\uDFEB\\uDFED]|\\uD83D(?:[\\uDCBB\\uDCBC\\uDD27\\uDD2C\\uDE80\\uDE92]|\\uDC30\\u200D\\uD83D\\uDC69\\uD83C[\\uDFFB-\\uDFFE])|\\uD83E(?:[\\uDDAF\\uDDBC\\uDDBD](?:\\u200D\\u27A1\\uFE0F?)?|[\\uDDB0-\\uDDB3]|\\uDD1D\\u200D\\uD83D[\\uDC68\\uDC69]\\uD83C[\\uDFFB-\\uDFFE]|\\uDEEF\\u200D\\uD83D\\uDC69\\uD83C[\\uDFFB-\\uDFFE])))?))?|\\uDD75(?:\\uD83C[\\uDFFB-\\uDFFF]|\\uFE0F)?(?:\\u200D[\\u2640\\u2642]\\uFE0F?)?|\\uDE2E(?:\\u200D\\uD83D\\uDCA8)?|\\uDE35(?:\\u200D\\uD83D\\uDCAB)?|\\uDE36(?:\\u200D\\uD83C\\uDF2B\\uFE0F?)?|\\uDE42(?:\\u200D[\\u2194\\u2195]\\uFE0F?)?|\\uDEB6(?:\\uD83C[\\uDFFB-\\uDFFF])?(?:\\u200D(?:[\\u2640\\u2642]\\uFE0F?(?:\\u200D\\u27A1\\uFE0F?)?|\\u27A1\\uFE0F?))?)|\\uD83E(?:[\\uDD0C\\uDD0F\\uDD18-\\uDD1F\\uDD30-\\uDD34\\uDD36\\uDD77\\uDDB5\\uDDB6\\uDDBB\\uDDD2\\uDDD3\\uDDD5\\uDEC3-\\uDEC5\\uDEF0\\uDEF2-\\uDEF8](?:\\uD83C[\\uDFFB-\\uDFFF])?|[\\uDD26\\uDD35\\uDD37-\\uDD39\\uDD3C-\\uDD3E\\uDDB8\\uDDB9\\uDDCD\\uDDCF\\uDDD4\\uDDD6-\\uDDDD](?:\\uD83C[\\uDFFB-\\uDFFF])?(?:\\u200D[\\u2640\\u2642]\\uFE0F?)?|[\\uDDDE\\uDDDF](?:\\u200D[\\u2640\\u2642]\\uFE0F?)?|[\\uDD0D\\uDD0E\\uDD10-\\uDD17\\uDD20-\\uDD25\\uDD27-\\uDD2F\\uDD3A\\uDD3F-\\uDD45\\uDD47-\\uDD76\\uDD78-\\uDDB4\\uDDB7\\uDDBA\\uDDBC-\\uDDCC\\uDDD0\\uDDE0-\\uDDFF\\uDE70-\\uDE7C\\uDE80-\\uDE8A\\uDE8E-\\uDEC2\\uDEC6\\uDEC8\\uDECD-\\uDEDC\\uDEDF-\\uDEEA\\uDEEF]|\\uDDCE(?:\\uD83C[\\uDFFB-\\uDFFF])?(?:\\u200D(?:[\\u2640\\u2642]\\uFE0F?(?:\\u200D\\u27A1\\uFE0F?)?|\\u27A1\\uFE0F?))?|\\uDDD1(?:\\u200D(?:[\\u2695\\u2696\\u2708]\\uFE0F?|\\uD83C[\\uDF3E\\uDF73\\uDF7C\\uDF84\\uDF93\\uDFA4\\uDFA8\\uDFEB\\uDFED]|\\uD83D[\\uDCBB\\uDCBC\\uDD27\\uDD2C\\uDE80\\uDE92]|\\uD83E(?:[\\uDDAF\\uDDBC\\uDDBD](?:\\u200D\\u27A1\\uFE0F?)?|[\\uDDB0-\\uDDB3\\uDE70]|\\uDD1D\\u200D\\uD83E\\uDDD1|\\uDDD1\\u200D\\uD83E\\uDDD2(?:\\u200D\\uD83E\\uDDD2)?|\\uDDD2(?:\\u200D\\uD83E\\uDDD2)?))|\\uD83C(?:\\uDFFB(?:\\u200D(?:[\\u2695\\u2696\\u2708]\\uFE0F?|\\u2764\\uFE0F?\\u200D(?:\\uD83D\\uDC8B\\u200D)?\\uD83E\\uDDD1\\uD83C[\\uDFFC-\\uDFFF]|\\uD83C[\\uDF3E\\uDF73\\uDF7C\\uDF84\\uDF93\\uDFA4\\uDFA8\\uDFEB\\uDFED]|\\uD83D(?:[\\uDCBB\\uDCBC\\uDD27\\uDD2C\\uDE80\\uDE92]|\\uDC30\\u200D\\uD83E\\uDDD1\\uD83C[\\uDFFC-\\uDFFF])|\\uD83E(?:[\\uDDAF\\uDDBC\\uDDBD](?:\\u200D\\u27A1\\uFE0F?)?|[\\uDDB0-\\uDDB3\\uDE70]|\\uDD1D\\u200D\\uD83E\\uDDD1\\uD83C[\\uDFFB-\\uDFFF]|\\uDEEF\\u200D\\uD83E\\uDDD1\\uD83C[\\uDFFC-\\uDFFF])))?|\\uDFFC(?:\\u200D(?:[\\u2695\\u2696\\u2708]\\uFE0F?|\\u2764\\uFE0F?\\u200D(?:\\uD83D\\uDC8B\\u200D)?\\uD83E\\uDDD1\\uD83C[\\uDFFB\\uDFFD-\\uDFFF]|\\uD83C[\\uDF3E\\uDF73\\uDF7C\\uDF84\\uDF93\\uDFA4\\uDFA8\\uDFEB\\uDFED]|\\uD83D(?:[\\uDCBB\\uDCBC\\uDD27\\uDD2C\\uDE80\\uDE92]|\\uDC30\\u200D\\uD83E\\uDDD1\\uD83C[\\uDFFB\\uDFFD-\\uDFFF])|\\uD83E(?:[\\uDDAF\\uDDBC\\uDDBD](?:\\u200D\\u27A1\\uFE0F?)?|[\\uDDB0-\\uDDB3\\uDE70]|\\uDD1D\\u200D\\uD83E\\uDDD1\\uD83C[\\uDFFB-\\uDFFF]|\\uDEEF\\u200D\\uD83E\\uDDD1\\uD83C[\\uDFFB\\uDFFD-\\uDFFF])))?|\\uDFFD(?:\\u200D(?:[\\u2695\\u2696\\u2708]\\uFE0F?|\\u2764\\uFE0F?\\u200D(?:\\uD83D\\uDC8B\\u200D)?\\uD83E\\uDDD1\\uD83C[\\uDFFB\\uDFFC\\uDFFE\\uDFFF]|\\uD83C[\\uDF3E\\uDF73\\uDF7C\\uDF84\\uDF93\\uDFA4\\uDFA8\\uDFEB\\uDFED]|\\uD83D(?:[\\uDCBB\\uDCBC\\uDD27\\uDD2C\\uDE80\\uDE92]|\\uDC30\\u200D\\uD83E\\uDDD1\\uD83C[\\uDFFB\\uDFFC\\uDFFE\\uDFFF])|\\uD83E(?:[\\uDDAF\\uDDBC\\uDDBD](?:\\u200D\\u27A1\\uFE0F?)?|[\\uDDB0-\\uDDB3\\uDE70]|\\uDD1D\\u200D\\uD83E\\uDDD1\\uD83C[\\uDFFB-\\uDFFF]|\\uDEEF\\u200D\\uD83E\\uDDD1\\uD83C[\\uDFFB\\uDFFC\\uDFFE\\uDFFF])))?|\\uDFFE(?:\\u200D(?:[\\u2695\\u2696\\u2708]\\uFE0F?|\\u2764\\uFE0F?\\u200D(?:\\uD83D\\uDC8B\\u200D)?\\uD83E\\uDDD1\\uD83C[\\uDFFB-\\uDFFD\\uDFFF]|\\uD83C[\\uDF3E\\uDF73\\uDF7C\\uDF84\\uDF93\\uDFA4\\uDFA8\\uDFEB\\uDFED]|\\uD83D(?:[\\uDCBB\\uDCBC\\uDD27\\uDD2C\\uDE80\\uDE92]|\\uDC30\\u200D\\uD83E\\uDDD1\\uD83C[\\uDFFB-\\uDFFD\\uDFFF])|\\uD83E(?:[\\uDDAF\\uDDBC\\uDDBD](?:\\u200D\\u27A1\\uFE0F?)?|[\\uDDB0-\\uDDB3\\uDE70]|\\uDD1D\\u200D\\uD83E\\uDDD1\\uD83C[\\uDFFB-\\uDFFF]|\\uDEEF\\u200D\\uD83E\\uDDD1\\uD83C[\\uDFFB-\\uDFFD\\uDFFF])))?|\\uDFFF(?:\\u200D(?:[\\u2695\\u2696\\u2708]\\uFE0F?|\\u2764\\uFE0F?\\u200D(?:\\uD83D\\uDC8B\\u200D)?\\uD83E\\uDDD1\\uD83C[\\uDFFB-\\uDFFE]|\\uD83C[\\uDF3E\\uDF73\\uDF7C\\uDF84\\uDF93\\uDFA4\\uDFA8\\uDFEB\\uDFED]|\\uD83D(?:[\\uDCBB\\uDCBC\\uDD27\\uDD2C\\uDE80\\uDE92]|\\uDC30\\u200D\\uD83E\\uDDD1\\uD83C[\\uDFFB-\\uDFFE])|\\uD83E(?:[\\uDDAF\\uDDBC\\uDDBD](?:\\u200D\\u27A1\\uFE0F?)?|[\\uDDB0-\\uDDB3\\uDE70]|\\uDD1D\\u200D\\uD83E\\uDDD1\\uD83C[\\uDFFB-\\uDFFF]|\\uDEEF\\u200D\\uD83E\\uDDD1\\uD83C[\\uDFFB-\\uDFFE])))?))?|\\uDEF1(?:\\uD83C(?:\\uDFFB(?:\\u200D\\uD83E\\uDEF2\\uD83C[\\uDFFC-\\uDFFF])?|\\uDFFC(?:\\u200D\\uD83E\\uDEF2\\uD83C[\\uDFFB\\uDFFD-\\uDFFF])?|\\uDFFD(?:\\u200D\\uD83E\\uDEF2\\uD83C[\\uDFFB\\uDFFC\\uDFFE\\uDFFF])?|\\uDFFE(?:\\u200D\\uD83E\\uDEF2\\uD83C[\\uDFFB-\\uDFFD\\uDFFF])?|\\uDFFF(?:\\u200D\\uD83E\\uDEF2\\uD83C[\\uDFFB-\\uDFFE])?))?)/g;
};
export default emojiRegex;
`,
    'emoji-regex/index.js': `const emojiRegex = () => {
  return /[#*0-9]\\uFE0F?\\u20E3|[\\xA9\\xAE\\u203C\\u2049\\u2122\\u2139\\u2194-\\u2199\\u21A9\\u21AA\\u231A\\u231B\\u2328\\u23CF\\u23ED-\\u23EF\\u23F1\\u23F2\\u23F8-\\u23FA\\u24C2\\u25AA\\u25AB\\u25B6\\u25C0\\u25FB\\u25FC\\u25FE\\u2600-\\u2604\\u260E\\u2611\\u2614\\u2615\\u2618\\u2620\\u2622\\u2623\\u2626\\u262A\\u262E\\u262F\\u2638-\\u263A\\u2640\\u2642\\u2648-\\u2653\\u265F\\u2660\\u2663\\u2665\\u2666\\u2668\\u267B\\u267E\\u267F\\u2692\\u2694-\\u2697\\u2699\\u269B\\u269C\\u26A0\\u26A7\\u26AA\\u26B0\\u26B1\\u26BD\\u26BE\\u26C4\\u26C8\\u26CF\\u26D1\\u26E9\\u26F0-\\u26F5\\u26F7\\u26F8\\u26FA\\u2702\\u2708\\u2709\\u270F\\u2712\\u2714\\u2716\\u271D\\u2721\\u2733\\u2734\\u2744\\u2747\\u2757\\u2763\\u27A1\\u2934\\u2935\\u2B05-\\u2B07\\u2B1B\\u2B1C\\u2B55\\u3030\\u303D\\u3297\\u3299]\\uFE0F?|[\\u261D\\u270C\\u270D](?:\\uD83C[\\uDFFB-\\uDFFF]|\\uFE0F)?|[\\u270A\\u270B](?:\\uD83C[\\uDFFB-\\uDFFF])?|[\\u23E9-\\u23EC\\u23F0\\u23F3\\u25FD\\u2693\\u26A1\\u26AB\\u26C5\\u26CE\\u26D4\\u26EA\\u26FD\\u2705\\u2728\\u274C\\u274E\\u2753-\\u2755\\u2795-\\u2797\\u27B0\\u27BF\\u2B50]|\\u26D3\\uFE0F?(?:\\u200D\\uD83D\\uDCA5)?|\\u26F9(?:\\uD83C[\\uDFFB-\\uDFFF]|\\uFE0F)?(?:\\u200D[\\u2640\\u2642]\\uFE0F?)?|\\u2764\\uFE0F?(?:\\u200D(?:\\uD83D\\uDD25|\\uD83E\\uDE79))?|\\uD83C(?:[\\uDC04\\uDD70\\uDD71\\uDD7E\\uDD7F\\uDE02\\uDE37\\uDF21\\uDF24-\\uDF2C\\uDF36\\uDF7D\\uDF96\\uDF97\\uDF99-\\uDF9B\\uDF9E\\uDF9F\\uDFCD\\uDFCE\\uDFD4-\\uDFDF\\uDFF5\\uDFF7]\\uFE0F?|[\\uDF85\\uDFC2\\uDFC7](?:\\uD83C[\\uDFFB-\\uDFFF])?|[\\uDFC4\\uDFCA](?:\\uD83C[\\uDFFB-\\uDFFF])?(?:\\u200D[\\u2640\\u2642]\\uFE0F?)?|[\\uDFCB\\uDFCC](?:\\uD83C[\\uDFFB-\\uDFFF]|\\uFE0F)?(?:\\u200D[\\u2640\\u2642]\\uFE0F?)?|[\\uDCCF\\uDD8E\\uDD91-\\uDD9A\\uDE01\\uDE1A\\uDE2F\\uDE32-\\uDE36\\uDE38-\\uDE3A\\uDE50\\uDE51\\uDF00-\\uDF20\\uDF2D-\\uDF35\\uDF37-\\uDF43\\uDF45-\\uDF4A\\uDF4C-\\uDF7C\\uDF7E-\\uDF84\\uDF86-\\uDF93\\uDFA0-\\uDFC1\\uDFC5\\uDFC6\\uDFC8\\uDFC9\\uDFCF-\\uDFD3\\uDFE0-\\uDFF0\\uDFF8-\\uDFFF]|\\uDDE6\\uD83C[\\uDDE8-\\uDDEC\\uDDEE\\uDDF1\\uDDF2\\uDDF4\\uDDF6-\\uDDFA\\uDDFC\\uDDFD\\uDDFF]|\\uDDE7\\uD83C[\\uDDE6\\uDDE7\\uDDE9-\\uDDEF\\uDDF1-\\uDDF4\\uDDF6-\\uDDF9\\uDDFB\\uDDFC\\uDDFE\\uDDFF]|\\uDDE8\\uD83C[\\uDDE6\\uDDE8\\uDDE9\\uDDEB-\\uDDEE\\uDDF0-\\uDDF7\\uDDFA-\\uDDFF]|\\uDDE9\\uD83C[\\uDDEA\\uDDEC\\uDDEF\\uDDF0\\uDDF2\\uDDF4\\uDDFF]|\\uDDEA\\uD83C[\\uDDE6\\uDDE8\\uDDEA\\uDDEC\\uDDED\\uDDF7-\\uDDFA]|\\uDDEB\\uD83C[\\uDDEE-\\uDDF0\\uDDF2\\uDDF4\\uDDF7]|\\uDDEC\\uD83C[\\uDDE6\\uDDE7\\uDDE9-\\uDDEE\\uDDF1-\\uDDF3\\uDDF5-\\uDDFA\\uDDFC\\uDDFE]|\\uDDED\\uD83C[\\uDDF0\\uDDF2\\uDDF3\\uDDF7\\uDDF9\\uDDFA]|\\uDDEE\\uD83C[\\uDDE8-\\uDDEA\\uDDF1-\\uDDF4\\uDDF6-\\uDDF9]|\\uDDEF\\uD83C[\\uDDEA\\uDDF2\\uDDF4\\uDDF5]|\\uDDF0\\uD83C[\\uDDEA\\uDDEC-\\uDDEE\\uDDF2\\uDDF3\\uDDF5\\uDDF7\\uDDFC\\uDDFE\\uDDFF]|\\uDDF1\\uD83C[\\uDDE6-\\uDDE8\\uDDEE\\uDDF0\\uDDF7-\\uDDFB\\uDDFE]|\\uDDF2\\uD83C[\\uDDE6\\uDDE8-\\uDDED\\uDDF0-\\uDDFF]|\\uDDF3\\uD83C[\\uDDE6\\uDDE8\\uDDEA-\\uDDEC\\uDDEE\\uDDF1\\uDDF4\\uDDF5\\uDDF7\\uDDFA\\uDDFF]|\\uDDF4\\uD83C\\uDDF2|\\uDDF5\\uD83C[\\uDDE6\\uDDEA-\\uDDED\\uDDF0-\\uDDF3\\uDDF7-\\uDDF9\\uDDFC\\uDDFE]|\\uDDF6\\uD83C\\uDDE6|\\uDDF7\\uD83C[\\uDDEA\\uDDF4\\uDDF8\\uDDFA\\uDDFC]|\\uDDF8\\uD83C[\\uDDE6-\\uDDEA\\uDDEC-\\uDDF4\\uDDF7-\\uDDF9\\uDDFB\\uDDFD-\\uDDFF]|\\uDDF9\\uD83C[\\uDDE6\\uDDE8\\uDDE9\\uDDEB-\\uDDED\\uDDEF-\\uDDF4\\uDDF7\\uDDF9\\uDDFB\\uDDFC\\uDDFF]|\\uDDFA\\uD83C[\\uDDE6\\uDDEC\\uDDF2\\uDDF3\\uDDF8\\uDDFE\\uDDFF]|\\uDDFB\\uD83C[\\uDDE6\\uDDE8\\uDDEA\\uDDEC\\uDDEE\\uDDF3\\uDDFA]|\\uDDFC\\uD83C[\\uDDEB\\uDDF8]|\\uDDFD\\uD83C\\uDDF0|\\uDDFE\\uD83C[\\uDDEA\\uDDF9]|\\uDDFF\\uD83C[\\uDDE6\\uDDF2\\uDDFC]|\\uDF44(?:\\u200D\\uD83D\\uDFEB)?|\\uDF4B(?:\\u200D\\uD83D\\uDFE9)?|\\uDFC3(?:\\uD83C[\\uDFFB-\\uDFFF])?(?:\\u200D(?:[\\u2640\\u2642]\\uFE0F?(?:\\u200D\\u27A1\\uFE0F?)?|\\u27A1\\uFE0F?))?|\\uDFF3\\uFE0F?(?:\\u200D(?:\\u26A7\\uFE0F?|\\uD83C\\uDF08))?|\\uDFF4(?:\\u200D\\u2620\\uFE0F?|\\uDB40\\uDC67\\uDB40\\uDC62\\uDB40(?:\\uDC65\\uDB40\\uDC6E\\uDB40\\uDC67|\\uDC73\\uDB40\\uDC63\\uDB40\\uDC74|\\uDC77\\uDB40\\uDC6C\\uDB40\\uDC73)\\uDB40\\uDC7F)?)|\\uD83D(?:[\\uDC3F\\uDCFD\\uDD49\\uDD4A\\uDD6F\\uDD70\\uDD73\\uDD76-\\uDD79\\uDD87\\uDD8A-\\uDD8D\\uDDA5\\uDDA8\\uDDB1\\uDDB2\\uDDBC\\uDDC2-\\uDDC4\\uDDD1-\\uDDD3\\uDDDC-\\uDDDE\\uDDE1\\uDDE3\\uDDE8\\uDDEF\\uDDF3\\uDDFA\\uDECB\\uDECD-\\uDECF\\uDEE0-\\uDEE5\\uDEE9\\uDEF0\\uDEF3]\\uFE0F?|[\\uDC42\\uDC43\\uDC46-\\uDC50\\uDC66\\uDC67\\uDC6B-\\uDC6D\\uDC72\\uDC74-\\uDC76\\uDC78\\uDC7C\\uDC83\\uDC85\\uDC8F\\uDC91\\uDCAA\\uDD7A\\uDD95\\uDD96\\uDE4C\\uDE4F\\uDEC0\\uDECC](?:\\uD83C[\\uDFFB-\\uDFFF])?|[\\uDC6E-\\uDC71\\uDC73\\uDC77\\uDC81\\uDC82\\uDC86\\uDC87\\uDE45-\\uDE47\\uDE4B\\uDE4D\\uDE4E\\uDEA3\\uDEB4\\uDEB5](?:\\uD83C[\\uDFFB-\\uDFFF])?(?:\\u200D[\\u2640\\u2642]\\uFE0F?)?|[\\uDD74\\uDD90](?:\\uD83C[\\uDFFB-\\uDFFF]|\\uFE0F)?|[\\uDC00-\\uDC07\\uDC09-\\uDC14\\uDC16-\\uDC25\\uDC27-\\uDC3A\\uDC3C-\\uDC3E\\uDC40\\uDC44\\uDC45\\uDC51-\\uDC65\\uDC6A\\uDC79-\\uDC7B\\uDC7D-\\uDC80\\uDC84\\uDC88-\\uDC8E\\uDC90\\uDC92-\\uDCA9\\uDCAB-\\uDCFC\\uDCFF-\\uDD3D\\uDD4B-\\uDD4E\\uDD50-\\uDD67\\uDDA4\\uDDFB-\\uDE2D\\uDE2F-\\uDE34\\uDE37-\\uDE41\\uDE43\\uDE44\\uDE48-\\uDE4A\\uDE80-\\uDEA2\\uDEA4-\\uDEB3\\uDEB7-\\uDEBF\\uDEC1-\\uDEC5\\uDED0-\\uDED2\\uDED5-\\uDED8\\uDEDC-\\uDEDF\\uDEEB\\uDEEC\\uDEF4-\\uDEFC\\uDFE0-\\uDFEB\\uDFF0]|\\uDC08(?:\\u200D\\u2B1B)?|\\uDC15(?:\\u200D\\uD83E\\uDDBA)?|\\uDC26(?:\\u200D(?:\\u2B1B|\\uD83D\\uDD25))?|\\uDC3B(?:\\u200D\\u2744\\uFE0F?)?|\\uDC41\\uFE0F?(?:\\u200D\\uD83D\\uDDE8\\uFE0F?)?|\\uDC68(?:\\u200D(?:[\\u2695\\u2696\\u2708]\\uFE0F?|\\u2764\\uFE0F?\\u200D\\uD83D(?:\\uDC8B\\u200D\\uD83D)?\\uDC68|\\uD83C[\\uDF3E\\uDF73\\uDF7C\\uDF93\\uDFA4\\uDFA8\\uDFEB\\uDFED]|\\uD83D(?:[\\uDC68\\uDC69]\\u200D\\uD83D(?:\\uDC66(?:\\u200D\\uD83D\\uDC66)?|\\uDC67(?:\\u200D\\uD83D[\\uDC66\\uDC67])?)|[\\uDCBB\\uDCBC\\uDD27\\uDD2C\\uDE80\\uDE92]|\\uDC66(?:\\u200D\\uD83D\\uDC66)?|\\uDC67(?:\\u200D\\uD83D[\\uDC66\\uDC67])?)|\\uD83E(?:[\\uDDAF\\uDDBC\\uDDBD](?:\\u200D\\u27A1\\uFE0F?)?|[\\uDDB0-\\uDDB3]))|\\uD83C(?:\\uDFFB(?:\\u200D(?:[\\u2695\\u2696\\u2708]\\uFE0F?|\\u2764\\uFE0F?\\u200D\\uD83D(?:\\uDC8B\\u200D\\uD83D)?\\uDC68\\uD83C[\\uDFFB-\\uDFFF]|\\uD83C[\\uDF3E\\uDF73\\uDF7C\\uDF93\\uDFA4\\uDFA8\\uDFEB\\uDFED]|\\uD83D(?:[\\uDCBB\\uDCBC\\uDD27\\uDD2C\\uDE80\\uDE92]|\\uDC30\\u200D\\uD83D\\uDC68\\uD83C[\\uDFFC-\\uDFFF])|\\uD83E(?:[\\uDD1D\\uDEEF]\\u200D\\uD83D\\uDC68\\uD83C[\\uDFFC-\\uDFFF]|[\\uDDAF\\uDDBC\\uDDBD](?:\\u200D\\u27A1\\uFE0F?)?|[\\uDDB0-\\uDDB3])))?|\\uDFFC(?:\\u200D(?:[\\u2695\\u2696\\u2708]\\uFE0F?|\\u2764\\uFE0F?\\u200D\\uD83D(?:\\uDC8B\\u200D\\uD83D)?\\uDC68\\uD83C[\\uDFFB-\\uDFFF]|\\uD83C[\\uDF3E\\uDF73\\uDF7C\\uDF93\\uDFA4\\uDFA8\\uDFEB\\uDFED]|\\uD83D(?:[\\uDCBB\\uDCBC\\uDD27\\uDD2C\\uDE80\\uDE92]|\\uDC30\\u200D\\uD83D\\uDC68\\uD83C[\\uDFFB\\uDFFD-\\uDFFF])|\\uD83E(?:[\\uDD1D\\uDEEF]\\u200D\\uD83D\\uDC68\\uD83C[\\uDFFB\\uDFFD-\\uDFFF]|[\\uDDAF\\uDDBC\\uDDBD](?:\\u200D\\u27A1\\uFE0F?)?|[\\uDDB0-\\uDDB3])))?|\\uDFFD(?:\\u200D(?:[\\u2695\\u2696\\u2708]\\uFE0F?|\\u2764\\uFE0F?\\u200D\\uD83D(?:\\uDC8B\\u200D\\uD83D)?\\uDC68\\uD83C[\\uDFFB-\\uDFFF]|\\uD83C[\\uDF3E\\uDF73\\uDF7C\\uDF93\\uDFA4\\uDFA8\\uDFEB\\uDFED]|\\uD83D(?:[\\uDCBB\\uDCBC\\uDD27\\uDD2C\\uDE80\\uDE92]|\\uDC30\\u200D\\uD83D\\uDC68\\uD83C[\\uDFFB\\uDFFC\\uDFFE\\uDFFF])|\\uD83E(?:[\\uDD1D\\uDEEF]\\u200D\\uD83D\\uDC68\\uD83C[\\uDFFB\\uDFFC\\uDFFE\\uDFFF]|[\\uDDAF\\uDDBC\\uDDBD](?:\\u200D\\u27A1\\uFE0F?)?|[\\uDDB0-\\uDDB3])))?|\\uDFFE(?:\\u200D(?:[\\u2695\\u2696\\u2708]\\uFE0F?|\\u2764\\uFE0F?\\u200D\\uD83D(?:\\uDC8B\\u200D\\uD83D)?\\uDC68\\uD83C[\\uDFFB-\\uDFFF]|\\uD83C[\\uDF3E\\uDF73\\uDF7C\\uDF93\\uDFA4\\uDFA8\\uDFEB\\uDFED]|\\uD83D(?:[\\uDCBB\\uDCBC\\uDD27\\uDD2C\\uDE80\\uDE92]|\\uDC30\\u200D\\uD83D\\uDC68\\uD83C[\\uDFFB-\\uDFFD\\uDFFF])|\\uD83E(?:[\\uDD1D\\uDEEF]\\u200D\\uD83D\\uDC68\\uD83C[\\uDFFB-\\uDFFD\\uDFFF]|[\\uDDAF\\uDDBC\\uDDBD](?:\\u200D\\u27A1\\uFE0F?)?|[\\uDDB0-\\uDDB3])))?|\\uDFFF(?:\\u200D(?:[\\u2695\\u2696\\u2708]\\uFE0F?|\\u2764\\uFE0F?\\u200D\\uD83D(?:\\uDC8B\\u200D\\uD83D)?\\uDC68\\uD83C[\\uDFFB-\\uDFFF]|\\uD83C[\\uDF3E\\uDF73\\uDF7C\\uDF93\\uDFA4\\uDFA8\\uDFEB\\uDFED]|\\uD83D(?:[\\uDCBB\\uDCBC\\uDD27\\uDD2C\\uDE80\\uDE92]|\\uDC30\\u200D\\uD83D\\uDC68\\uD83C[\\uDFFB-\\uDFFE])|\\uD83E(?:[\\uDD1D\\uDEEF]\\u200D\\uD83D\\uDC68\\uD83C[\\uDFFB-\\uDFFE]|[\\uDDAF\\uDDBC\\uDDBD](?:\\u200D\\u27A1\\uFE0F?)?|[\\uDDB0-\\uDDB3])))?))?|\\uDC69(?:\\u200D(?:[\\u2695\\u2696\\u2708]\\uFE0F?|\\u2764\\uFE0F?\\u200D\\uD83D(?:\\uDC8B\\u200D\\uD83D)?[\\uDC68\\uDC69]|\\uD83C[\\uDF3E\\uDF73\\uDF7C\\uDF93\\uDFA4\\uDFA8\\uDFEB\\uDFED]|\\uD83D(?:[\\uDCBB\\uDCBC\\uDD27\\uDD2C\\uDE80\\uDE92]|\\uDC66(?:\\u200D\\uD83D\\uDC66)?|\\uDC67(?:\\u200D\\uD83D[\\uDC66\\uDC67])?|\\uDC69\\u200D\\uD83D(?:\\uDC66(?:\\u200D\\uD83D\\uDC66)?|\\uDC67(?:\\u200D\\uD83D[\\uDC66\\uDC67])?))|\\uD83E(?:[\\uDDAF\\uDDBC\\uDDBD](?:\\u200D\\u27A1\\uFE0F?)?|[\\uDDB0-\\uDDB3]))|\\uD83C(?:\\uDFFB(?:\\u200D(?:[\\u2695\\u2696\\u2708]\\uFE0F?|\\u2764\\uFE0F?\\u200D\\uD83D(?:[\\uDC68\\uDC69]|\\uDC8B\\u200D\\uD83D[\\uDC68\\uDC69])\\uD83C[\\uDFFB-\\uDFFF]|\\uD83C[\\uDF3E\\uDF73\\uDF7C\\uDF93\\uDFA4\\uDFA8\\uDFEB\\uDFED]|\\uD83D(?:[\\uDCBB\\uDCBC\\uDD27\\uDD2C\\uDE80\\uDE92]|\\uDC30\\u200D\\uD83D\\uDC69\\uD83C[\\uDFFC-\\uDFFF])|\\uD83E(?:[\\uDDAF\\uDDBC\\uDDBD](?:\\u200D\\u27A1\\uFE0F?)?|[\\uDDB0-\\uDDB3]|\\uDD1D\\u200D\\uD83D[\\uDC68\\uDC69]\\uD83C[\\uDFFC-\\uDFFF]|\\uDEEF\\u200D\\uD83D\\uDC69\\uD83C[\\uDFFC-\\uDFFF])))?|\\uDFFC(?:\\u200D(?:[\\u2695\\u2696\\u2708]\\uFE0F?|\\u2764\\uFE0F?\\u200D\\uD83D(?:[\\uDC68\\uDC69]|\\uDC8B\\u200D\\uD83D[\\uDC68\\uDC69])\\uD83C[\\uDFFB-\\uDFFF]|\\uD83C[\\uDF3E\\uDF73\\uDF7C\\uDF93\\uDFA4\\uDFA8\\uDFEB\\uDFED]|\\uD83D(?:[\\uDCBB\\uDCBC\\uDD27\\uDD2C\\uDE80\\uDE92]|\\uDC30\\u200D\\uD83D\\uDC69\\uD83C[\\uDFFB\\uDFFD-\\uDFFF])|\\uD83E(?:[\\uDDAF\\uDDBC\\uDDBD](?:\\u200D\\u27A1\\uFE0F?)?|[\\uDDB0-\\uDDB3]|\\uDD1D\\u200D\\uD83D[\\uDC68\\uDC69]\\uD83C[\\uDFFB\\uDFFD-\\uDFFF]|\\uDEEF\\u200D\\uD83D\\uDC69\\uD83C[\\uDFFB\\uDFFD-\\uDFFF])))?|\\uDFFD(?:\\u200D(?:[\\u2695\\u2696\\u2708]\\uFE0F?|\\u2764\\uFE0F?\\u200D\\uD83D(?:[\\uDC68\\uDC69]|\\uDC8B\\u200D\\uD83D[\\uDC68\\uDC69])\\uD83C[\\uDFFB-\\uDFFF]|\\uD83C[\\uDF3E\\uDF73\\uDF7C\\uDF93\\uDFA4\\uDFA8\\uDFEB\\uDFED]|\\uD83D(?:[\\uDCBB\\uDCBC\\uDD27\\uDD2C\\uDE80\\uDE92]|\\uDC30\\u200D\\uD83D\\uDC69\\uD83C[\\uDFFB\\uDFFC\\uDFFE\\uDFFF])|\\uD83E(?:[\\uDDAF\\uDDBC\\uDDBD](?:\\u200D\\u27A1\\uFE0F?)?|[\\uDDB0-\\uDDB3]|\\uDD1D\\u200D\\uD83D[\\uDC68\\uDC69]\\uD83C[\\uDFFB\\uDFFC\\uDFFE\\uDFFF]|\\uDEEF\\u200D\\uD83D\\uDC69\\uD83C[\\uDFFB\\uDFFC\\uDFFE\\uDFFF])))?|\\uDFFE(?:\\u200D(?:[\\u2695\\u2696\\u2708]\\uFE0F?|\\u2764\\uFE0F?\\u200D\\uD83D(?:[\\uDC68\\uDC69]|\\uDC8B\\u200D\\uD83D[\\uDC68\\uDC69])\\uD83C[\\uDFFB-\\uDFFF]|\\uD83C[\\uDF3E\\uDF73\\uDF7C\\uDF93\\uDFA4\\uDFA8\\uDFEB\\uDFED]|\\uD83D(?:[\\uDCBB\\uDCBC\\uDD27\\uDD2C\\uDE80\\uDE92]|\\uDC30\\u200D\\uD83D\\uDC69\\uD83C[\\uDFFB-\\uDFFD\\uDFFF])|\\uD83E(?:[\\uDDAF\\uDDBC\\uDDBD](?:\\u200D\\u27A1\\uFE0F?)?|[\\uDDB0-\\uDDB3]|\\uDD1D\\u200D\\uD83D[\\uDC68\\uDC69]\\uD83C[\\uDFFB-\\uDFFD\\uDFFF]|\\uDEEF\\u200D\\uD83D\\uDC69\\uD83C[\\uDFFB-\\uDFFD\\uDFFF])))?|\\uDFFF(?:\\u200D(?:[\\u2695\\u2696\\u2708]\\uFE0F?|\\u2764\\uFE0F?\\u200D\\uD83D(?:[\\uDC68\\uDC69]|\\uDC8B\\u200D\\uD83D[\\uDC68\\uDC69])\\uD83C[\\uDFFB-\\uDFFF]|\\uD83C[\\uDF3E\\uDF73\\uDF7C\\uDF93\\uDFA4\\uDFA8\\uDFEB\\uDFED]|\\uD83D(?:[\\uDCBB\\uDCBC\\uDD27\\uDD2C\\uDE80\\uDE92]|\\uDC30\\u200D\\uD83D\\uDC69\\uD83C[\\uDFFB-\\uDFFE])|\\uD83E(?:[\\uDDAF\\uDDBC\\uDDBD](?:\\u200D\\u27A1\\uFE0F?)?|[\\uDDB0-\\uDDB3]|\\uDD1D\\u200D\\uD83D[\\uDC68\\uDC69]\\uD83C[\\uDFFB-\\uDFFE]|\\uDEEF\\u200D\\uD83D\\uDC69\\uD83C[\\uDFFB-\\uDFFE])))?))?|\\uDD75(?:\\uD83C[\\uDFFB-\\uDFFF]|\\uFE0F)?(?:\\u200D[\\u2640\\u2642]\\uFE0F?)?|\\uDE2E(?:\\u200D\\uD83D\\uDCA8)?|\\uDE35(?:\\u200D\\uD83D\\uDCAB)?|\\uDE36(?:\\u200D\\uD83C\\uDF2B\\uFE0F?)?|\\uDE42(?:\\u200D[\\u2194\\u2195]\\uFE0F?)?|\\uDEB6(?:\\uD83C[\\uDFFB-\\uDFFF])?(?:\\u200D(?:[\\u2640\\u2642]\\uFE0F?(?:\\u200D\\u27A1\\uFE0F?)?|\\u27A1\\uFE0F?))?)|\\uD83E(?:[\\uDD0C\\uDD0F\\uDD18-\\uDD1F\\uDD30-\\uDD34\\uDD36\\uDD77\\uDDB5\\uDDB6\\uDDBB\\uDDD2\\uDDD3\\uDDD5\\uDEC3-\\uDEC5\\uDEF0\\uDEF2-\\uDEF8](?:\\uD83C[\\uDFFB-\\uDFFF])?|[\\uDD26\\uDD35\\uDD37-\\uDD39\\uDD3C-\\uDD3E\\uDDB8\\uDDB9\\uDDCD\\uDDCF\\uDDD4\\uDDD6-\\uDDDD](?:\\uD83C[\\uDFFB-\\uDFFF])?(?:\\u200D[\\u2640\\u2642]\\uFE0F?)?|[\\uDDDE\\uDDDF](?:\\u200D[\\u2640\\u2642]\\uFE0F?)?|[\\uDD0D\\uDD0E\\uDD10-\\uDD17\\uDD20-\\uDD25\\uDD27-\\uDD2F\\uDD3A\\uDD3F-\\uDD45\\uDD47-\\uDD76\\uDD78-\\uDDB4\\uDDB7\\uDDBA\\uDDBC-\\uDDCC\\uDDD0\\uDDE0-\\uDDFF\\uDE70-\\uDE7C\\uDE80-\\uDE8A\\uDE8E-\\uDEC2\\uDEC6\\uDEC8\\uDECD-\\uDEDC\\uDEDF-\\uDEEA\\uDEEF]|\\uDDCE(?:\\uD83C[\\uDFFB-\\uDFFF])?(?:\\u200D(?:[\\u2640\\u2642]\\uFE0F?(?:\\u200D\\u27A1\\uFE0F?)?|\\u27A1\\uFE0F?))?|\\uDDD1(?:\\u200D(?:[\\u2695\\u2696\\u2708]\\uFE0F?|\\uD83C[\\uDF3E\\uDF73\\uDF7C\\uDF84\\uDF93\\uDFA4\\uDFA8\\uDFEB\\uDFED]|\\uD83D[\\uDCBB\\uDCBC\\uDD27\\uDD2C\\uDE80\\uDE92]|\\uD83E(?:[\\uDDAF\\uDDBC\\uDDBD](?:\\u200D\\u27A1\\uFE0F?)?|[\\uDDB0-\\uDDB3\\uDE70]|\\uDD1D\\u200D\\uD83E\\uDDD1|\\uDDD1\\u200D\\uD83E\\uDDD2(?:\\u200D\\uD83E\\uDDD2)?|\\uDDD2(?:\\u200D\\uD83E\\uDDD2)?))|\\uD83C(?:\\uDFFB(?:\\u200D(?:[\\u2695\\u2696\\u2708]\\uFE0F?|\\u2764\\uFE0F?\\u200D(?:\\uD83D\\uDC8B\\u200D)?\\uD83E\\uDDD1\\uD83C[\\uDFFC-\\uDFFF]|\\uD83C[\\uDF3E\\uDF73\\uDF7C\\uDF84\\uDF93\\uDFA4\\uDFA8\\uDFEB\\uDFED]|\\uD83D(?:[\\uDCBB\\uDCBC\\uDD27\\uDD2C\\uDE80\\uDE92]|\\uDC30\\u200D\\uD83E\\uDDD1\\uD83C[\\uDFFC-\\uDFFF])|\\uD83E(?:[\\uDDAF\\uDDBC\\uDDBD](?:\\u200D\\u27A1\\uFE0F?)?|[\\uDDB0-\\uDDB3\\uDE70]|\\uDD1D\\u200D\\uD83E\\uDDD1\\uD83C[\\uDFFB-\\uDFFF]|\\uDEEF\\u200D\\uD83E\\uDDD1\\uD83C[\\uDFFC-\\uDFFF])))?|\\uDFFC(?:\\u200D(?:[\\u2695\\u2696\\u2708]\\uFE0F?|\\u2764\\uFE0F?\\u200D(?:\\uD83D\\uDC8B\\u200D)?\\uD83E\\uDDD1\\uD83C[\\uDFFB\\uDFFD-\\uDFFF]|\\uD83C[\\uDF3E\\uDF73\\uDF7C\\uDF84\\uDF93\\uDFA4\\uDFA8\\uDFEB\\uDFED]|\\uD83D(?:[\\uDCBB\\uDCBC\\uDD27\\uDD2C\\uDE80\\uDE92]|\\uDC30\\u200D\\uD83E\\uDDD1\\uD83C[\\uDFFB\\uDFFD-\\uDFFF])|\\uD83E(?:[\\uDDAF\\uDDBC\\uDDBD](?:\\u200D\\u27A1\\uFE0F?)?|[\\uDDB0-\\uDDB3\\uDE70]|\\uDD1D\\u200D\\uD83E\\uDDD1\\uD83C[\\uDFFB-\\uDFFF]|\\uDEEF\\u200D\\uD83E\\uDDD1\\uD83C[\\uDFFB\\uDFFD-\\uDFFF])))?|\\uDFFD(?:\\u200D(?:[\\u2695\\u2696\\u2708]\\uFE0F?|\\u2764\\uFE0F?\\u200D(?:\\uD83D\\uDC8B\\u200D)?\\uD83E\\uDDD1\\uD83C[\\uDFFB\\uDFFC\\uDFFE\\uDFFF]|\\uD83C[\\uDF3E\\uDF73\\uDF7C\\uDF84\\uDF93\\uDFA4\\uDFA8\\uDFEB\\uDFED]|\\uD83D(?:[\\uDCBB\\uDCBC\\uDD27\\uDD2C\\uDE80\\uDE92]|\\uDC30\\u200D\\uD83E\\uDDD1\\uD83C[\\uDFFB\\uDFFC\\uDFFE\\uDFFF])|\\uD83E(?:[\\uDDAF\\uDDBC\\uDDBD](?:\\u200D\\u27A1\\uFE0F?)?|[\\uDDB0-\\uDDB3\\uDE70]|\\uDD1D\\u200D\\uD83E\\uDDD1\\uD83C[\\uDFFB-\\uDFFF]|\\uDEEF\\u200D\\uD83E\\uDDD1\\uD83C[\\uDFFB\\uDFFC\\uDFFE\\uDFFF])))?|\\uDFFE(?:\\u200D(?:[\\u2695\\u2696\\u2708]\\uFE0F?|\\u2764\\uFE0F?\\u200D(?:\\uD83D\\uDC8B\\u200D)?\\uD83E\\uDDD1\\uD83C[\\uDFFB-\\uDFFD\\uDFFF]|\\uD83C[\\uDF3E\\uDF73\\uDF7C\\uDF84\\uDF93\\uDFA4\\uDFA8\\uDFEB\\uDFED]|\\uD83D(?:[\\uDCBB\\uDCBC\\uDD27\\uDD2C\\uDE80\\uDE92]|\\uDC30\\u200D\\uD83E\\uDDD1\\uD83C[\\uDFFB-\\uDFFD\\uDFFF])|\\uD83E(?:[\\uDDAF\\uDDBC\\uDDBD](?:\\u200D\\u27A1\\uFE0F?)?|[\\uDDB0-\\uDDB3\\uDE70]|\\uDD1D\\u200D\\uD83E\\uDDD1\\uD83C[\\uDFFB-\\uDFFF]|\\uDEEF\\u200D\\uD83E\\uDDD1\\uD83C[\\uDFFB-\\uDFFD\\uDFFF])))?|\\uDFFF(?:\\u200D(?:[\\u2695\\u2696\\u2708]\\uFE0F?|\\u2764\\uFE0F?\\u200D(?:\\uD83D\\uDC8B\\u200D)?\\uD83E\\uDDD1\\uD83C[\\uDFFB-\\uDFFE]|\\uD83C[\\uDF3E\\uDF73\\uDF7C\\uDF84\\uDF93\\uDFA4\\uDFA8\\uDFEB\\uDFED]|\\uD83D(?:[\\uDCBB\\uDCBC\\uDD27\\uDD2C\\uDE80\\uDE92]|\\uDC30\\u200D\\uD83E\\uDDD1\\uD83C[\\uDFFB-\\uDFFE])|\\uD83E(?:[\\uDDAF\\uDDBC\\uDDBD](?:\\u200D\\u27A1\\uFE0F?)?|[\\uDDB0-\\uDDB3\\uDE70]|\\uDD1D\\u200D\\uD83E\\uDDD1\\uD83C[\\uDFFB-\\uDFFF]|\\uDEEF\\u200D\\uD83E\\uDDD1\\uD83C[\\uDFFB-\\uDFFE])))?))?|\\uDEF1(?:\\uD83C(?:\\uDFFB(?:\\u200D\\uD83E\\uDEF2\\uD83C[\\uDFFC-\\uDFFF])?|\\uDFFC(?:\\u200D\\uD83E\\uDEF2\\uD83C[\\uDFFB\\uDFFD-\\uDFFF])?|\\uDFFD(?:\\u200D\\uD83E\\uDEF2\\uD83C[\\uDFFB\\uDFFC\\uDFFE\\uDFFF])?|\\uDFFE(?:\\u200D\\uD83E\\uDEF2\\uD83C[\\uDFFB-\\uDFFD\\uDFFF])?|\\uDFFF(?:\\u200D\\uD83E\\uDEF2\\uD83C[\\uDFFB-\\uDFFE])?))?)/g;
};
export default emojiRegex;
`,
    'source-map-js/index.mjs': `export class SourceMapConsumer {}
export class SourceMapGenerator {}
export class SourceNode {}
export default { SourceMapConsumer, SourceMapGenerator, SourceNode };
`,
    'source-map-js/index.js': `export class SourceMapConsumer {}
export class SourceMapGenerator {}
export class SourceNode {}
export default { SourceMapConsumer, SourceMapGenerator, SourceNode };
`,
    'source-map-js/source-map.js': `export class SourceMapConsumer {}
export class SourceMapGenerator {}
export class SourceNode {}
export default { SourceMapConsumer, SourceMapGenerator, SourceNode };
`,
  };
  for (const [subpath, content] of Object.entries(reexports)) {
    const targetFile = resolve(sharedStaging, subpath);
    await writeFile(targetFile, content);
  }

  // Rewire bare external dependency imports in Core to relative paths inside the shared runtime.
  // NativeScript's V8 module loader (v8-module-loader.cpp) does not perform node_modules lookup
  // for bare imports when resolving dependencies of submodules; relative paths allow the V8 loader
  // to resolve the shared runtime packages directly without per-app bundling.
  const externalRewires = [
    {
      file: 'globals/index.js',
      from: "import tslib from 'tslib';",
      to: "import tslib from '../../../tslib/index.js';",
    },
    {
      file: 'color/color-utils.js',
      from: "from '@csstools/css-color-parser';",
      to: "from '../../../@csstools/css-color-parser/index.js';",
    },
    {
      file: 'color/color-utils.js',
      from: "from '@csstools/css-parser-algorithms';",
      to: "from '../../../@csstools/css-parser-algorithms/index.js';",
    },
    {
      file: 'color/color-utils.js',
      from: "from '@csstools/css-tokenizer';",
      to: "from '../../../@csstools/css-tokenizer/index.js';",
    },
    {
      file: 'css/css-tree-parser.js',
      from: "from 'css-tree';",
      to: "from '../../../css-tree/index.js';",
    },
    {
      file: 'inspector_modules.js',
      from: "from 'source-map-js';",
      to: "from '../../source-map-js/index.js';",
    },
    {
      file: 'ui/core/bindable/bindable-expressions.js',
      from: "from 'acorn';",
      to: "from '../../../../../acorn/index.js';",
    },
    {
      file: 'ui/core/properties/index.js',
      from: "from '@csstools/css-calc';",
      to: "from '../../../../../@csstools/css-calc/index.js';",
    },
    {
      file: 'ui/styling/css-selector.js',
      from: "from 'css-what';",
      to: "from '../../../../css-what/index.js';",
    },
    {
      file: 'utils/common.js',
      from: "from 'emoji-regex';",
      to: "from '../../../emoji-regex/index.js';",
    },
    {
      file: 'application/application-shims.js',
      from: "from '@nativescript/core';",
      to: "from '../index.js';",
    },
  ];

  for (const rewire of externalRewires) {
    const p = resolve(coreDest, rewire.file);
    try {
      const src = await readFile(p, 'utf8');
      await writeFile(p, src.replaceAll(rewire.from, rewire.to));
    } catch {}
  }

  // Rewire cross-package imports within @csstools to relative paths
  const csstoolsRewires = [
    {
      file: '@csstools/css-calc/dist/index.mjs',
      from: '"@csstools/css-parser-algorithms"',
      to: '"../../css-parser-algorithms/index.js"',
    },
    {
      file: '@csstools/css-calc/dist/index.mjs',
      from: '"@csstools/css-tokenizer"',
      to: '"../../css-tokenizer/index.js"',
    },
    {
      file: '@csstools/css-color-parser/dist/index.mjs',
      from: '"@csstools/css-tokenizer"',
      to: '"../../css-tokenizer/index.js"',
    },
    {
      file: '@csstools/css-color-parser/dist/index.mjs',
      from: '"@csstools/color-helpers"',
      to: '"../../color-helpers/index.js"',
    },
    {
      file: '@csstools/css-color-parser/dist/index.mjs',
      from: '"@csstools/css-parser-algorithms"',
      to: '"../../css-parser-algorithms/index.js"',
    },
    {
      file: '@csstools/css-color-parser/dist/index.mjs',
      from: '"@csstools/css-calc"',
      to: '"../../css-calc/index.js"',
    },
    {
      file: '@csstools/css-parser-algorithms/dist/index.mjs',
      from: '"@csstools/css-tokenizer"',
      to: '"../../css-tokenizer/index.js"',
    },
  ];

  for (const rewire of csstoolsRewires) {
    const p = resolve(sharedStaging, rewire.file);
    try {
      const src = await readFile(p, 'utf8');
      await writeFile(p, src.replaceAll(rewire.from, rewire.to));
    } catch {}
  }

  // Normalize all package.json files across the shared runtime to ensure
  // "type": "module" is declared as the first property. This prevents NativeScript's
  // V8 module loader (v8-module-loader.cpp) from misclassifying nested ESM subpackages
  // (such as @nativescript/core/globals, css, css-value, easysax, or dependencies with
  // funding/repository "type" properties) as CommonJS and wrapping them into functions.
  async function normalizePackageJsons(dir) {
    const entries = await readdir(dir, { withFileTypes: true });
    for (const entry of entries) {
      const full = resolve(dir, entry.name);
      if (entry.isDirectory()) {
        await normalizePackageJsons(full);
      } else if (entry.name === 'package.json') {
        try {
          const content = await readFile(full, 'utf8');
          const data = JSON.parse(content);
          const normalized = { type: 'module', ...data };
          await writeFile(full, JSON.stringify(normalized, null, 2) + '\n');
        } catch {}
      }
    }
  }
  await normalizePackageJsons(sharedStaging);

  await mkdir(resolve(destinationRoot, '..'), { recursive: true });
  await safeMoveDirectory(sharedStaging, destinationRoot);
  console.log(`Staged NativeScriptSharedRuntime JavaScript modules at ${destinationRoot}`);
}


await stageSharedCoreRuntime(sharedRuntimeRoot);

console.log(
  `Prepared NativeScript ${pinnedVersion} iOS dependency closure: ${frameworks.join(', ')}; `
  + `installed Swift metadata wrapper for ${metadataGeneratorDirectories.join(', ')}`
);
