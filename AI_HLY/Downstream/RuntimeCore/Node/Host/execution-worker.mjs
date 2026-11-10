import './fetch-compatibility.mjs';
import { parentPort, workerData } from 'node:worker_threads';
import dns from 'node:dns';
if (typeof dns.setDefaultResultOrder === 'function') {
  dns.setDefaultResultOrder('ipv4first');
}
import { pathToFileURL } from 'node:url';
import { createRequire, syncBuiltinESMExports } from 'node:module';
import * as nodePath from 'node:path';
import { inspect } from 'node:util';

const { entryPoint, workspace, moduleKind, arguments: argv, environment, maximumOutputBytes } = workerData;

const entryDir = workspace || nodePath.dirname(entryPoint);
try {
  globalThis.require = createRequire(entryPoint);
  globalThis.__filename = entryPoint;
  globalThis.__dirname = entryDir;
} catch {}

if (workspace) {
  process.cwd = () => workspace;
  try {
    const fs = await import('node:fs');
    const path = await import('node:path');
    const resolvePath = p => (typeof p === 'string' && !path.isAbsolute(p)) ? path.resolve(workspace, p) : p;
    for (const mod of [fs.default || fs, fs.promises]) {
      if (!mod) continue;
      for (const fn of [
        'readFile', 'readFileSync', 'writeFile', 'writeFileSync',
        'appendFile', 'appendFileSync', 'stat', 'statSync',
        'access', 'accessSync', 'open', 'openSync', 'readdir', 'readdirSync',
        'unlink', 'unlinkSync', 'rm', 'rmSync', 'mkdir', 'mkdirSync',
        'existsSync', 'copyFile', 'copyFileSync', 'createReadStream', 'createWriteStream'
      ]) {
        const orig = mod[fn];
        if (typeof orig === 'function') {
          mod[fn] = function(first, ...args) {
            return orig.call(this, resolvePath(first), ...args);
          };
        }
      }
    }
    // Updating CommonJS builtin properties does not update named ESM exports.
    // Keep all import forms on the same per-execution workspace adapters.
    syncBuiltinESMExports();
  } catch {}
}

for (const [name, value] of Object.entries(environment ?? {})) process.env[name] = String(value);
process.argv = ['node', entryPoint, ...(argv ?? []).map(String)];

try {
  let value;
  // The export may itself be an asynchronous operation. Posting the Promise
  // serializes it to {} and causes the host to terminate its network work early.
  if (moduleKind === 'commonjs') value = await createRequire(import.meta.url)(entryPoint);
  else value = await (await import(`${pathToFileURL(entryPoint).href}?execution=${Date.now()}`)).default;
  parentPort.postMessage({ type: 'completed', value: jsonSafe(value) });
} catch (error) {
  console.error(inspect(error, { depth: null, maxArrayLength: null, maxStringLength: null, colors: false }));
  parentPort.postMessage({ type: 'failed' });
}

function jsonSafe(value) {
  if (value === undefined) return null;
  try { return JSON.parse(JSON.stringify(value)); } catch { return String(value); }
}
