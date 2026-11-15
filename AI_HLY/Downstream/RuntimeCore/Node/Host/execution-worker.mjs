import './fetch-compatibility.mjs';
import { parentPort, workerData } from 'node:worker_threads';
import dns from 'node:dns';
if (typeof dns.setDefaultResultOrder === 'function') {
  dns.setDefaultResultOrder('ipv4first');
}
import { pathToFileURL } from 'node:url';
import { createRequire } from 'node:module';
import { inspect } from 'node:util';
import { configureExecutionContext } from './execution-context.mjs';

const { entryPoint, moduleKind } = workerData;
configureExecutionContext(workerData);

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
