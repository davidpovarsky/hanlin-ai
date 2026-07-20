import test from 'node:test';
import assert from 'node:assert/strict';
import { promises as fs } from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { Worker } from 'node:worker_threads';
import { inspectManifest } from '../package-compatibility.mjs';
import { checkCancelled, verifyIntegrity } from '../package-installer.mjs';

const workerURL = new URL('../server-worker.mjs', import.meta.url);

test('worker stdin and stdout remain isolated for multiple servers', async () => {
  const root = await fs.mkdtemp(path.join(os.tmpdir(), 'hanlin-mcp-test-'));
  await fs.writeFile(path.join(root, 'package.json'), JSON.stringify({ name: 'fixture', version: '1.0.0', type: 'module' }));
  await fs.writeFile(path.join(root, 'server.mjs'), `
    import { createInterface } from 'node:readline';
    createInterface({ input: process.stdin }).on('line', line => process.stdout.write(line + '\\n'));
  `);
  const create = () => new Worker(workerURL, {
    workerData: { packageRoot: root, entryPoint: path.join(root, 'server.mjs') },
    stdin: true, stdout: true, stderr: true,
  });
  const first = create();
  const second = create();
  const read = worker => new Promise(resolve => worker.stdout.once('data', data => resolve(data.toString('utf8').trim())));
  const firstRead = read(first); const secondRead = read(second);
  first.stdin.write('{"id":1}\n'); second.stdin.write('{"id":2}\n');
  assert.equal(await firstRead, '{"id":1}');
  assert.equal(await secondRead, '{"id":2}');
  await Promise.all([first.terminate(), second.terminate()]);
  await fs.rm(root, { recursive: true, force: true });
});

test('lifecycle scripts and incompatible engines are rejected by preflight', () => {
  const findings = inspectManifest({ engines: { node: '>=20' }, scripts: { postinstall: 'node setup.js' } });
  assert.equal(findings.filter(item => item.severity === 'unsupported').length, 2);
});

test('integrity mismatch fails closed', () => {
  assert.throws(() => verifyIntegrity(Buffer.from('wrong'), 'sha512-deadbeef'));
});

test('install cancellation aborts work', () => {
  const controller = new AbortController();
  controller.abort(new Error('cancelled'));
  assert.throws(() => checkCancelled(controller.signal), /cancelled/);
});
