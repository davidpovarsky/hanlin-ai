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
    const appSymbols = spawnSync('/usr/bin/nm', ['-gU', executable], { encoding: 'utf8' });
    if (appSymbols.status !== 0
        || !appSymbols.stdout.includes('_OBJC_CLASS_$_HanlinNativeScriptSwiftUIFixtureProvider')) {
      throw new Error('The built app does not export the embedded NativeScript SwiftUI provider');
    }
    const loadCommands = spawnSync('/usr/bin/otool', ['-l', executable], { encoding: 'utf8' });
    if (loadCommands.status !== 0 || !loadCommands.stdout.includes('__TNSMetadata')) {
      throw new Error('The built app does not contain the NativeScript metadata section');
    }
    const strings = spawnSync('/usr/bin/strings', [executable], { encoding: 'utf8' });
    if (strings.status !== 0
        || !strings.stdout.includes('HanlinNativeScriptSwiftUIFixtureProvider')) {
      throw new Error('NativeScript SwiftUI provider metadata name is absent from the app closure');
    }
  }
}

console.log('NativeScript 9.1 + @nativescript/swift-ui 4.0.2 iOS dependency preflight passed');
