import { parentPort, workerData } from 'node:worker_threads';
import { createRequire } from 'node:module';
import { pathToFileURL } from 'node:url';
import path from 'node:path';
import { promises as fs } from 'node:fs';

const entryPoint = path.resolve(workerData.entryPoint);
const packageRoot = path.resolve(workerData.packageRoot);
const relative = path.relative(packageRoot, entryPoint);
if (relative === '..' || relative.startsWith(`..${path.sep}`) || path.isAbsolute(relative)) {
  throw new Error('Entry point escapes package root.');
}

const manifest = JSON.parse(await fs.readFile(path.join(packageRoot, 'package.json'), 'utf8'));
const extension = path.extname(entryPoint).toLowerCase();
const useESM = extension === '.mjs' || (extension !== '.cjs' && manifest.type === 'module');

if (useESM) {
  await import(pathToFileURL(entryPoint).href);
} else {
  const require = createRequire(path.join(packageRoot, 'package.json'));
  require(entryPoint);
}

parentPort?.postMessage({ type: 'loaded' });
