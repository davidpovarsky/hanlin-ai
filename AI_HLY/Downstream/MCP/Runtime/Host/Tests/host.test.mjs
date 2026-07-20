import test from 'node:test';
import assert from 'node:assert/strict';
import { promises as fs } from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { Worker } from 'node:worker_threads';
import { inspectManifest, listEntryPoints, resolveEntryPoint } from '../package-compatibility.mjs';
import { checkCancelled, commitInstall, rollbackInstall, verifyIntegrity } from '../package-installer.mjs';

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

test('multiple package bins are listed and an explicit path preserves its bin name', () => {
  const manifest = { bin: { alpha: './alpha.mjs', beta: './beta.mjs' }, main: './fallback.mjs' };
  assert.deepEqual(listEntryPoints(manifest), ['./alpha.mjs', './beta.mjs', './fallback.mjs']);
  assert.deepEqual(resolveEntryPoint(manifest, './beta.mjs'), { entryPoint: './beta.mjs', binName: 'beta' });
  assert.deepEqual(resolveEntryPoint(manifest, 'alpha'), { entryPoint: './alpha.mjs', binName: 'alpha' });
});

test('replacement rollback restores the prior server and commit removes its backup', async () => {
  const root = await fs.mkdtemp(path.join(os.tmpdir(), 'hanlin-mcp-transaction-'));
  const operationID = '11111111-1111-4111-8111-111111111111';
  const serverID = '22222222-2222-4222-8222-222222222222';
  const servers = path.join(root, 'servers');
  const staging = path.join(root, 'staging');
  const finalRoot = path.join(servers, serverID);
  const backupRoot = path.join(staging, `backup-${operationID}`);
  await fs.mkdir(finalRoot, { recursive: true });
  await fs.mkdir(backupRoot, { recursive: true });
  await fs.writeFile(path.join(finalRoot, 'version'), 'new');
  await fs.writeFile(path.join(backupRoot, 'version'), 'old');

  await rollbackInstall({ root, operationID, serverID });
  assert.equal(await fs.readFile(path.join(finalRoot, 'version'), 'utf8'), 'old');

  await fs.mkdir(backupRoot, { recursive: true });
  await commitInstall({ root, operationID, serverID });
  await assert.rejects(fs.access(backupRoot), error => error.code === 'ENOENT');
  await fs.rm(root, { recursive: true, force: true });
});
