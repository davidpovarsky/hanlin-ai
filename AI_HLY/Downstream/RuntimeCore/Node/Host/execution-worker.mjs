import { parentPort, workerData } from 'node:worker_threads';
import { pathToFileURL } from 'node:url';
import { createRequire } from 'node:module';
import * as nodePath from 'node:path';

const { entryPoint, workspace, moduleKind, arguments: argv, environment, maximumOutputBytes } = workerData;
let stdout = '';
let stderr = '';
let outputWasTruncated = false;

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
  } catch {}
}

for (const [name, value] of Object.entries(environment ?? {})) process.env[name] = String(value);
process.argv = ['node', entryPoint, ...(argv ?? []).map(String)];

function append(channel, values) {
  const rendered = `${values.map(format).join(' ')}\n`;
  const current = channel === 'stdout' ? stdout : stderr;
  const remaining = Math.max(0, maximumOutputBytes - Buffer.byteLength(stdout) - Buffer.byteLength(stderr));
  const accepted = Buffer.from(rendered).subarray(0, remaining).toString('utf8');
  if (channel === 'stdout') stdout = current + accepted;
  else stderr = current + accepted;
  if (Buffer.byteLength(rendered) > Buffer.byteLength(accepted)) outputWasTruncated = true;
}

function format(value) {
  if (typeof value === 'string') return value;
  try { return JSON.stringify(value); } catch { return String(value); }
}

console.log = (...values) => append('stdout', values);
console.info = (...values) => append('stdout', values);
console.warn = (...values) => append('stderr', values);
console.error = (...values) => append('stderr', values);

try {
  let value;
  if (moduleKind === 'commonjs') value = createRequire(import.meta.url)(entryPoint);
  else value = (await import(`${pathToFileURL(entryPoint).href}?execution=${Date.now()}`)).default;
  parentPort.postMessage({ type: 'completed', stdout, stderr, value: jsonSafe(value), outputWasTruncated });
} catch (error) {
  append('stderr', [error?.stack ?? error?.message ?? String(error)]);
  parentPort.postMessage({ type: 'failed', stdout, stderr, outputWasTruncated });
}

function jsonSafe(value) {
  if (value === undefined) return null;
  try { return JSON.parse(JSON.stringify(value)); } catch { return String(value); }
}
