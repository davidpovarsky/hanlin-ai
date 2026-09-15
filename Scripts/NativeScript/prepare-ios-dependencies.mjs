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
    'source-map-js/index.mjs': 'export * from "./source-map.js";\n',
    'source-map-js/index.js': 'export * from "./source-map.js";\n',
  };
  for (const [subpath, content] of Object.entries(reexports)) {
    const targetFile = resolve(sharedStaging, subpath);
    await writeFile(targetFile, content);
  }

  await mkdir(resolve(destinationRoot, '..'), { recursive: true });
  await safeMoveDirectory(sharedStaging, destinationRoot);
  console.log(`Staged NativeScriptSharedRuntime JavaScript modules at ${destinationRoot}`);
}

await stageSharedCoreRuntime(sharedRuntimeRoot);

console.log(
  `Prepared NativeScript ${pinnedVersion} iOS dependency closure: ${frameworks.join(', ')}; `
  + `installed Swift metadata wrapper for ${metadataGeneratorDirectories.join(', ')}`
);
