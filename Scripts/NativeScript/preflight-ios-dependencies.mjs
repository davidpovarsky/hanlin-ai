import { access, readFile, readdir } from 'node:fs/promises';
import { resolve } from 'node:path';
import { spawnSync } from 'node:child_process';

const scriptRoot = resolve(import.meta.dirname);
const repositoryRoot = resolve(scriptRoot, '..', '..');
const artifactsRoot = resolve(repositoryRoot, 'Packages', 'HanlinNativeScriptRuntime', 'Artifacts');
const manifest = JSON.parse(await readFile(resolve(artifactsRoot, 'dependency-closure.json'), 'utf8'));

if (manifest.coreVersion !== '9.1.0' || manifest.iosRuntimeVersion !== '9.1.0') {
  throw new Error('NativeScript dependency closure is not consistently pinned to 9.1.0');
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
  }
}

console.log('NativeScript 9.1 iOS dependency preflight passed');
