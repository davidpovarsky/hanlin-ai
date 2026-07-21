import { createHash, randomBytes } from 'node:crypto';
import { promises as fs } from 'node:fs';
import path from 'node:path';
import tls from 'node:tls';
import { Worker } from 'node:worker_threads';

const documents = path.join(process.env.HOME, 'Documents');
const runtimeRoot = path.join(process.env.HOME, 'Library', 'Application Support', 'HanlinRuntime', 'v1');
const resultPath = path.join(documents, 'hanlin-node-smoke.json');
const readyPath = path.join(runtimeRoot, 'runtime', 'node-smoke-ready.json');
const logPath = path.join(runtimeRoot, 'logs', 'node-smoke.log');
const token = randomBytes(32).toString('base64url');

const result = {
  nodeVersion: process.versions.node,
  fs: false,
  crypto: false,
  url: false,
  fetch: false,
  workerThreads: false,
  tls: false,
  hostStartup: false,
  hebrew: 'שלום',
};

try {
  await fs.mkdir(path.dirname(readyPath), { recursive: true });
  await fs.mkdir(path.dirname(logPath), { recursive: true });
  await fs.writeFile(path.join(runtimeRoot, 'runtime', 'fs-smoke.txt'), result.hebrew);
  result.fs = await fs.readFile(path.join(runtimeRoot, 'runtime', 'fs-smoke.txt'), 'utf8') === result.hebrew;
  result.crypto = createHash('sha256').update('hanlin').digest('hex').length === 64;
  result.url = new URL('https://example.com/runtime').pathname === '/runtime';
  result.tls = typeof tls.createSecureContext === 'function' && Boolean(tls.DEFAULT_MIN_VERSION);
  const fetchResponse = await fetch('data:text/plain;charset=utf-8,hanlin');
  result.fetch = fetchResponse.ok && await fetchResponse.text() === 'hanlin';

  result.workerThreads = await new Promise((resolve, reject) => {
    const worker = new Worker(
      `const { parentPort } = require('node:worker_threads'); parentPort.postMessage(6 * 7);`,
      { eval: true },
    );
    worker.once('message', value => resolve(value === 42));
    worker.once('error', reject);
  });

  const hostURL = new URL('./host.mjs', import.meta.url);
  process.argv = [process.execPath, hostURL.pathname, runtimeRoot, readyPath, token, logPath, '0'];
  await import(hostURL.href);

  const deadline = Date.now() + 15_000;
  while (Date.now() < deadline) {
    try {
      const ready = JSON.parse(await fs.readFile(readyPath, 'utf8'));
      result.hostStartup = Number.isInteger(ready.port)
        && ready.port > 0
        && ready.nodeVersion === process.versions.node
        && ready.protocolVersion === 1;
      result.hostProtocolVersion = ready.protocolVersion;
      result.hostNodeVersion = ready.nodeVersion;
      if (result.hostStartup) break;
    } catch {
      await new Promise(resolve => setTimeout(resolve, 100));
    }
  }

  if (!Object.entries(result).filter(([key]) => !['nodeVersion', 'hostNodeVersion', 'hostProtocolVersion', 'hebrew'].includes(key)).every(([, value]) => value === true)) {
    throw new Error(`Incomplete smoke result: ${JSON.stringify(result)}`);
  }
  await fs.writeFile(resultPath, JSON.stringify({ ok: true, ...result }, null, 2));
} catch (error) {
  await fs.writeFile(resultPath, JSON.stringify({ ok: false, ...result, error: error.stack ?? error.message }, null, 2));
  process.exitCode = 1;
}
