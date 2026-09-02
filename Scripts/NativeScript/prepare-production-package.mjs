import { cp, mkdir, readFile, rm, writeFile } from 'node:fs/promises';
import { resolve } from 'node:path';

const scriptRoot = resolve(import.meta.dirname);
const repositoryRoot = resolve(scriptRoot, '..', '..');
const e2eRoot = resolve(repositoryRoot, 'build', 'NativeScriptE2E');

async function preparePackage({ preparedName, directoryName, displayName, description, pluginVersion }) {
  const preparedApp = resolve(scriptRoot, 'Prepared', preparedName, 'nativescript', 'app');
  const packageRoot = resolve(e2eRoot, directoryName);
  const destinationApp = resolve(packageRoot, 'nativescript', 'app');
  const preparedPackage = JSON.parse(await readFile(resolve(preparedApp, 'package.json'), 'utf8'));
  if (preparedPackage.hanlinRuntime !== 'hanlin-nativescript') {
    throw new Error(`${preparedName} is missing the Hanlin runtime declaration`);
  }
  if (pluginVersion) {
    preparedPackage.hanlinNativeScript = {
      runtimeVersion: '9.1.0',
      plugins: { '@nativescript/swift-ui': pluginVersion }
    };
  }

  await mkdir(destinationApp, { recursive: true });
  await cp(preparedApp, destinationApp, { recursive: true });
  await writeFile(resolve(destinationApp, 'package.json'), `${JSON.stringify(preparedPackage, null, 2)}\n`);
  await writeFile(resolve(packageRoot, 'script.json'), `${JSON.stringify({
    name: displayName,
    version: '1.0.0',
    description,
    entry: 'nativescript/app/bundle.mjs',
    runInApp: true,
    hanlinRuntime: 'hanlin-nativescript'
  }, null, 2)}\n`);
}

await rm(e2eRoot, { recursive: true, force: true });
await preparePackage({
  preparedName: 'swiftui-fixture',
  directoryName: 'swiftui-package',
  displayName: 'Hanlin NativeScript SwiftUI E2E',
  description: 'Production @nativescript/swift-ui 4.0.2 import/install/run fixture.',
  pluginVersion: '4.0.2'
});
await preparePackage({
  preparedName: 'core-fixture',
  directoryName: 'core-package',
  displayName: 'Hanlin NativeScript Core E2E',
  description: 'Plugin-free NativeScript 9.1 production regression fixture.'
});
await preparePackage({
  preparedName: 'swiftui-fixture',
  directoryName: 'unsupported-package',
  displayName: 'Hanlin NativeScript Unsupported Plugin E2E',
  description: 'A deterministic unsupported native-plugin compatibility fixture.',
  pluginVersion: '99.0.0'
});

const malformedRoot = resolve(e2eRoot, 'malformed');
await mkdir(malformedRoot, { recursive: true });
await writeFile(resolve(malformedRoot, 'script.json'), '{"name":"Malformed NativeScript E2E",');

console.log(`Prepared NativeScript production packages at ${e2eRoot}`);
