import { cp, mkdir, readFile, rm, writeFile } from 'node:fs/promises';
import { resolve } from 'node:path';
import { spawnSync } from 'node:child_process';

const scriptRoot = resolve(import.meta.dirname);
const outputRoot = resolve(scriptRoot, 'Prepared');
const buildRoot = resolve(scriptRoot, '.ns-vite-build');

await rm(outputRoot, { recursive: true, force: true });
await rm(buildRoot, { recursive: true, force: true });

const result = spawnSync(
  process.platform === 'win32' ? 'npm.cmd' : 'npm',
  ['run', 'prepare:fixture'],
  {
    cwd: scriptRoot,
    env: { ...process.env, NS_VITE_DIST_DIR: '.ns-vite-build' },
    stdio: 'inherit',
    shell: process.platform === 'win32'
  }
);
if (result.error) throw result.error;
if (result.status !== 0) process.exit(result.status ?? 1);

await cp(
  resolve(scriptRoot, 'Fixtures', 'Source', 'fixture-resource.txt'),
  resolve(buildRoot, 'fixture-resource.txt')
);

for (const name of ['fixture-a', 'fixture-b']) {
  const destination = resolve(outputRoot, name, 'nativescript', 'app');
  await mkdir(destination, { recursive: true });
  await cp(buildRoot, destination, { recursive: true });
  const packageJSON = {
    name,
    version: '1.0.0',
    main: 'bundle.mjs',
    hanlinRuntime: 'hanlin-nativescript'
  };
  await writeFile(resolve(destination, 'package.json'), `${JSON.stringify(packageJSON, null, 2)}\n`);
}

const corePackage = JSON.parse(
  await readFile(resolve(scriptRoot, 'node_modules/@nativescript/core/package.json'), 'utf8')
);
if (corePackage.version !== '9.1.0') {
  throw new Error(`Unexpected @nativescript/core version: ${corePackage.version}`);
}
