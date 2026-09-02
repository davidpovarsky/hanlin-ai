import { cp, mkdir, readFile, readdir, rm, writeFile } from 'node:fs/promises';
import { resolve } from 'node:path';
import { spawnSync } from 'node:child_process';

const scriptRoot = resolve(import.meta.dirname);
const outputRoot = resolve(scriptRoot, 'Prepared');
const buildParent = resolve(scriptRoot, '.ns-vite-build');
const packageJSONPath = resolve(scriptRoot, 'package.json');
const originalPackageJSON = await readFile(packageJSONPath, 'utf8');
const dependencyLock = JSON.parse(await readFile(resolve(scriptRoot, 'dependency-lock.json'), 'utf8'));

await rm(outputRoot, { recursive: true, force: true });
await rm(buildParent, { recursive: true, force: true });

async function buildFixture(entry, outputName) {
  const packageJSON = JSON.parse(originalPackageJSON);
  packageJSON.main = `Fixtures/Source/${entry}`;
  await writeFile(packageJSONPath, `${JSON.stringify(packageJSON, null, 2)}\n`);
  const result = spawnSync(
    process.execPath,
    [resolve(scriptRoot, 'node_modules', 'vite', 'bin', 'vite.js'), 'build', '--mode', 'production', '--', '--env.ios'],
    {
      cwd: scriptRoot,
      env: { ...process.env, NS_VITE_DIST_DIR: `.ns-vite-build/${outputName}` },
      stdio: 'inherit',
      shell: false
    }
  );
  if (result.error) throw result.error;
  if (result.status !== 0) throw new Error(`NativeScript fixture build failed with status ${result.status ?? 1}`);
}

const typeCheck = spawnSync(
  process.execPath,
  [resolve(scriptRoot, 'node_modules', 'typescript', 'bin', 'tsc'), '--noEmit'],
  { cwd: scriptRoot, stdio: 'inherit', shell: false }
);
if (typeCheck.error) throw typeCheck.error;
if (typeCheck.status !== 0) throw new Error(`NativeScript fixture type check failed with status ${typeCheck.status ?? 1}`);

try {
  await buildFixture('app.ts', 'core');
  await buildFixture('swiftui-app.ts', 'swiftui');
} finally {
  await writeFile(packageJSONPath, originalPackageJSON);
}

for (const outputName of ['core', 'swiftui']) {
  await cp(
    resolve(scriptRoot, 'Fixtures', 'Source', 'fixture-resource.txt'),
    resolve(buildParent, outputName, 'fixture-resource.txt')
  );
}

const fixtureDefinitions = [
  { name: 'fixture-a', outputName: 'core', plugins: undefined },
  { name: 'fixture-b', outputName: 'core', plugins: undefined },
  { name: 'core-fixture', outputName: 'core', plugins: undefined },
  {
    name: 'swiftui-fixture',
    outputName: 'swiftui',
    plugins: { '@nativescript/swift-ui': '4.0.2' }
  }
];

for (const fixture of fixtureDefinitions) {
  const { name, outputName, plugins } = fixture;
  const destination = resolve(outputRoot, name, 'nativescript', 'app');
  await mkdir(destination, { recursive: true });
  await cp(resolve(buildParent, outputName), destination, { recursive: true });
  const packageJSON = {
    name,
    version: '1.0.0',
    main: 'bundle.mjs',
    hanlinRuntime: 'hanlin-nativescript',
    ...(plugins ? {
      hanlinNativeScript: { runtimeVersion: '9.1.0', plugins }
    } : {})
  };
  await writeFile(resolve(destination, 'package.json'), `${JSON.stringify(packageJSON, null, 2)}\n`);
  if (plugins) {
    await writeFile(resolve(destination, 'hanlin-native-plugin-runtime.json'), `${JSON.stringify({
      schemaVersion: 1,
      package: dependencyLock.swiftUI.package,
      version: dependencyLock.swiftUI.version,
      integrity: dependencyLock.swiftUI.integrity,
      runtimeFiles: dependencyLock.swiftUI.runtimeFiles,
      disposition: 'Bundled JavaScript with provider support precompiled into Hanlin'
    }, null, 2)}\n`);
  }
}

const corePackage = JSON.parse(
  await readFile(resolve(scriptRoot, 'node_modules/@nativescript/core/package.json'), 'utf8')
);
if (corePackage.version !== '9.1.0') {
  throw new Error(`Unexpected @nativescript/core version: ${corePackage.version}`);
}
const swiftUIPackage = JSON.parse(
  await readFile(resolve(scriptRoot, 'node_modules/@nativescript/swift-ui/package.json'), 'utf8')
);
if (swiftUIPackage.version !== dependencyLock.swiftUI.version) {
  throw new Error(`Unexpected @nativescript/swift-ui version: ${swiftUIPackage.version}`);
}

const swiftUIAppRoot = resolve(outputRoot, 'swiftui-fixture', 'nativescript', 'app');
const swiftUIJavaScript = (await Promise.all(
  (await readdir(swiftUIAppRoot))
    .filter((name) => name.endsWith('.mjs'))
    .map((name) => readFile(resolve(swiftUIAppRoot, name), 'utf8'))
)).join('\n');
for (const proof of [
  'HanlinNativeScriptSwiftUIFixtureProvider',
  'swiftUIEvent',
  'swiftId',
  'HANLIN_NS_SWIFTUI_MODULE_OK'
]) {
  if (!swiftUIJavaScript.includes(proof)) {
    throw new Error(`SwiftUI production bundle is missing ${proof}`);
  }
}
