import { cp, mkdir, readFile, rm, writeFile } from 'node:fs/promises';
import { resolve } from 'node:path';

const scriptRoot = resolve(import.meta.dirname);
const repositoryRoot = resolve(scriptRoot, '..', '..');
const preparedApp = resolve(scriptRoot, 'Prepared', 'fixture-a', 'nativescript', 'app');
const packageRoot = resolve(repositoryRoot, 'build', 'NativeScriptE2E', 'package');
const destinationApp = resolve(packageRoot, 'nativescript', 'app');
const malformedRoot = resolve(repositoryRoot, 'build', 'NativeScriptE2E', 'malformed');

const preparedPackage = JSON.parse(await readFile(resolve(preparedApp, 'package.json'), 'utf8'));
if (preparedPackage.hanlinRuntime !== 'hanlin-nativescript') {
  throw new Error('Prepared NativeScript application is missing the Hanlin runtime declaration');
}

await rm(packageRoot, { recursive: true, force: true });
await mkdir(destinationApp, { recursive: true });
await cp(preparedApp, destinationApp, { recursive: true });
await writeFile(resolve(packageRoot, 'script.json'), `${JSON.stringify({
  name: 'Hanlin NativeScript Production E2E',
  version: '1.0.0',
  description: 'Production import/install/run fixture for NativeScript 9.1.',
  entry: 'nativescript/app/bundle.mjs',
  runInApp: true,
  hanlinRuntime: 'hanlin-nativescript',
}, null, 2)}\n`);

await rm(malformedRoot, { recursive: true, force: true });
await mkdir(malformedRoot, { recursive: true });
await writeFile(resolve(malformedRoot, 'script.json'), '{"name":"Malformed NativeScript E2E",');

console.log(`Prepared production NativeScript package at ${packageRoot}`);
console.log(`Prepared malformed package at ${malformedRoot}`);
