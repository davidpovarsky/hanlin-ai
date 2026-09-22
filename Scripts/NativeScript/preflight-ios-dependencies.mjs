import { createHash } from 'node:crypto';
import { access, readFile, readdir } from 'node:fs/promises';
import { resolve } from 'node:path';
import { spawnSync } from 'node:child_process';

const scriptRoot = resolve(import.meta.dirname);
const repositoryRoot = resolve(scriptRoot, '..', '..');
const artifactsRoot = resolve(repositoryRoot, 'Packages', 'HanlinNativeScriptRuntime', 'Artifacts');
const manifest = JSON.parse(await readFile(resolve(artifactsRoot, 'dependency-closure.json'), 'utf8'));
const dependencyLock = JSON.parse(await readFile(resolve(scriptRoot, 'dependency-lock.json'), 'utf8'));
const sha256 = (bytes) => createHash('sha256').update(bytes).digest('hex');

if (manifest.schemaVersion !== 2 || manifest.coreVersion !== '9.1.0' || manifest.iosRuntimeVersion !== '9.1.0') {
  throw new Error('NativeScript dependency closure is not consistently pinned to 9.1.0');
}
if (manifest.swiftUIPlugin?.version !== dependencyLock.swiftUI.version
    || manifest.swiftUIPlugin?.integrity !== dependencyLock.swiftUI.integrity
    || manifest.swiftUIPlugin?.embeddedProviderClass !== dependencyLock.swiftUI.embeddedProviderClass) {
  throw new Error('NativeScript SwiftUI dependency closure is incomplete or inconsistent');
}
const swiftUIRoot = resolve(scriptRoot, 'node_modules', '@nativescript', 'swift-ui');
for (const [path, expectedSHA256] of Object.entries(dependencyLock.swiftUI.runtimeFiles)) {
  if (sha256(await readFile(resolve(swiftUIRoot, path))) !== expectedSHA256) {
    throw new Error(`Prepared @nativescript/swift-ui runtime file changed: ${path}`);
  }
}
const expected = ['NSCWinterTC', 'TNSWidgets'];
const actual = manifest.artifacts.map((artifact) => artifact.name).sort();
if (JSON.stringify(actual) !== JSON.stringify(expected)) {
  throw new Error(`Unexpected NativeScript Core framework closure: ${actual.join(', ')}`);
}
for (const artifact of manifest.artifacts) {
  await access(resolve(artifactsRoot, `${artifact.name}.xcframework`, 'Info.plist'));
}

const preparedRoot = resolve(scriptRoot, 'Prepared');
const preparedFixtures = (await readdir(preparedRoot, { withFileTypes: true })).filter((entry) => entry.isDirectory());
if (preparedFixtures.length === 0) throw new Error('No prepared NativeScript fixture exists');
for (const fixture of preparedFixtures) {
  const appRoot = resolve(preparedRoot, fixture.name, 'nativescript', 'app');
  await access(resolve(appRoot, 'package.json'));
  await access(resolve(appRoot, 'bundle.mjs'));
}
const swiftUIFixturePackage = JSON.parse(await readFile(
  resolve(preparedRoot, 'swiftui-fixture', 'nativescript', 'app', 'package.json'),
  'utf8'
));
if (swiftUIFixturePackage.hanlinNativeScript?.plugins?.['@nativescript/swift-ui'] !== '4.0.2') {
  throw new Error('Prepared SwiftUI fixture does not declare its embedded native plugin requirement');
}
const preparedPluginReport = JSON.parse(await readFile(
  resolve(preparedRoot, 'swiftui-fixture', 'nativescript', 'app', 'hanlin-native-plugin-runtime.json'),
  'utf8'
));
if (preparedPluginReport.version !== dependencyLock.swiftUI.version
    || preparedPluginReport.integrity !== dependencyLock.swiftUI.integrity
    || JSON.stringify(preparedPluginReport.runtimeFiles) !== JSON.stringify(dependencyLock.swiftUI.runtimeFiles)) {
  throw new Error('Prepared SwiftUI runtime provenance report is inconsistent');
}
const coreFixturePackage = JSON.parse(await readFile(
  resolve(preparedRoot, 'core-fixture', 'nativescript', 'app', 'package.json'),
  'utf8'
));
if (coreFixturePackage.hanlinNativeScript !== undefined) {
  throw new Error('Plugin-free Core fixture unexpectedly declares a native plugin');
}

const CANONICAL_BUILD_DEFINES = {
  __ANDROID__: 'false',
  __IOS__: 'true',
  __VISIONOS__: 'false',
  __APPLE__: 'true',
  __DEV__: 'false',
  __COMMONJS__: 'false',
  __NS_WEBPACK__: 'false',
  __NS_ENV_VERBOSE__: 'false',
  __CSS_PARSER__: "'css-tree'",
  __UI_USE_XML_PARSER__: 'true',
  __UI_USE_EXTERNAL_RENDERER__: 'false',
  __TEST__: 'false',
};

const sharedRuntimeDir = resolve(
  repositoryRoot,
  'Packages',
  'HanlinNativeScriptRuntime',
  'Sources',
  'HanlinNativeScriptRuntime',
  'Resources',
  'NativeScriptSharedRuntime'
);

async function collectMjsFiles(dir) {
  let list = [];
  try {
    const entries = await readdir(dir, { withFileTypes: true });
    for (const entry of entries) {
      const full = resolve(dir, entry.name);
      if (entry.isDirectory()) {
        list = list.concat(await collectMjsFiles(full));
      } else if (entry.name.endsWith('.mjs')) {
        list.push(full);
      }
    }
  } catch {}
  return list;
}

const stagedMjsFiles = await collectMjsFiles(sharedRuntimeDir);
if (stagedMjsFiles.length > 0) {
  for (const file of stagedMjsFiles) {
    const content = await readFile(file, 'utf8');
    for (const [key, _val] of Object.entries(CANONICAL_BUILD_DEFINES)) {
      const declMatches = content.match(new RegExp(`(?:^|[\\s;])(?:const|let|var)\\s+${key}\\s*=`, 'g'));
      if (declMatches && declMatches.length > 1) {
        throw new Error(`Build defines preflight failed: duplicate declaration of ${key} in ${file}`);
      }
      const hasFree = new RegExp(`(?<![.\\w$])${key}\\b`).test(content);
      const hasDecl = new RegExp(`(?:^|[\\s;])(?:const|let|var|function|class)\\s+${key}\\b`).test(content);
      if (hasFree && !hasDecl) {
        throw new Error(`Build defines preflight failed: free identifier ${key} in ${file} was not shimmed or declared`);
      }
    }
  }
}

const appIndex = process.argv.indexOf('--app');
if (appIndex >= 0) {
  const argument = process.argv[appIndex + 1];
  if (!argument) throw new Error('--app requires an application path');
  // npm --prefix changes the script working directory. Interpret relative app
  // paths from the repository root so CI and direct invocations agree.
  const appRoot = resolve(repositoryRoot, argument);
  for (const name of ['NativeScript', ...expected]) {
    const binary = resolve(appRoot, 'Frameworks', `${name}.framework`, name);
    await access(binary);
    if (process.platform !== 'win32') {
      const file = spawnSync('/usr/bin/file', [binary], { encoding: 'utf8' });
      if (file.status !== 0 || !file.stdout.includes('Mach-O')) {
        throw new Error(`${name}.framework is not a loadable Mach-O framework`);
      }
    }
  }
  if (process.platform !== 'win32') {
    const widgets = resolve(appRoot, 'Frameworks', 'TNSWidgets.framework', 'TNSWidgets');
    const symbols = spawnSync('/usr/bin/nm', ['-gU', widgets], { encoding: 'utf8' });
    if (symbols.status !== 0 || !symbols.stdout.includes('_OBJC_CLASS_$_TNSLabel')) {
      throw new Error('Embedded TNSWidgets does not export the TNSLabel Objective-C class');
    }
    const plistPath = resolve(appRoot, 'Info.plist');
    const plist = spawnSync('/usr/bin/plutil', [
      '-extract', 'CFBundleExecutable', 'raw', '-o', '-', plistPath
    ], { encoding: 'utf8' });
    if (plist.status !== 0 || !plist.stdout.trim()) {
      throw new Error('Unable to resolve the built application executable');
    }
    const executable = resolve(appRoot, plist.stdout.trim());
    // SwiftPM may place the provider in an embedded package-product framework
    // instead of the main executable. Scan every Mach-O in the app's dyld
    // closure and still require real Objective-C class metadata, matching the
    // NSClassFromString / objc_lookUpClass contract used at runtime.
    const frameworkRoot = resolve(appRoot, 'Frameworks');
    const closureExecutables = [executable];
    for (const entry of await readdir(frameworkRoot, { withFileTypes: true })) {
      if (entry.isDirectory() && entry.name.endsWith('.framework')) {
        const frameworkName = entry.name.slice(0, -'.framework'.length);
        closureExecutables.push(resolve(frameworkRoot, entry.name, frameworkName));
      }
    }
    let providerExecutable = null;
    let objcRuntimeError = null;
    for (const candidate of closureExecutables) {
      const objcRuntime = spawnSync('/usr/bin/otool', ['-ov', candidate], {
        encoding: 'utf8',
        maxBuffer: 64 * 1024 * 1024
      });
      if (objcRuntime.error) objcRuntimeError = objcRuntime.error;
      if (objcRuntime.status === 0
          && objcRuntime.stdout.includes('HanlinNativeScriptSwiftUIFixtureProvider')) {
        providerExecutable = candidate;
        break;
      }
    }
    if (!providerExecutable) {
      const detail = objcRuntimeError ? ` (${objcRuntimeError.message})` : '';
      throw new Error(`The built app closure does not register the embedded NativeScript SwiftUI provider class${detail}`);
    }
    const loadCommands = spawnSync('/usr/bin/otool', ['-l', executable], {
      encoding: 'utf8',
      maxBuffer: 64 * 1024 * 1024
    });
    if (loadCommands.status !== 0 || !loadCommands.stdout.includes('__TNSMetadata')) {
      throw new Error('The built app does not contain the NativeScript metadata section');
    }
    const strings = spawnSync('/usr/bin/strings', [providerExecutable], {
      encoding: 'utf8',
      maxBuffer: 64 * 1024 * 1024
    });
    if (strings.status !== 0
        || !strings.stdout.includes('HanlinNativeScriptSwiftUIFixtureProvider')) {
      throw new Error('NativeScript SwiftUI provider metadata name is absent from the app closure');
    }
  }
}

console.log('NativeScript 9.1 + @nativescript/swift-ui 4.0.2 iOS dependency preflight passed');
