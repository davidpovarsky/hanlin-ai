import test from 'node:test';
import assert from 'node:assert/strict';
import { promises as fs } from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import { randomUUID } from 'node:crypto';
import { Worker } from 'node:worker_threads';

test('named fs and fs/promises imports use the execution workspace', async () => {
  const workspace = await fs.mkdtemp(path.join(os.tmpdir(), 'hanlin-workspace-io-'));
  let worker;
  try {
    const name = `scope-${randomUUID()}.txt`;
    await fs.writeFile(path.join(workspace, name), 'שלום');
    const entryPoint = path.join(workspace, 'main.mjs');
    await fs.writeFile(entryPoint, `
      import fs, { readFileSync } from 'node:fs';
      import { readFile } from 'node:fs/promises';
      export default [fs.readFileSync(${JSON.stringify(name)}, 'utf8'),
        readFileSync(${JSON.stringify(name)}, 'utf8'),
        await readFile(${JSON.stringify(name)}, 'utf8')];
    `);
    worker = new Worker(new URL('../execution-worker.mjs', import.meta.url), {
      workerData: { entryPoint, workspace, moduleKind: 'esm', maximumOutputBytes: 4096 },
    });
    const result = await new Promise((resolve, reject) => {
      worker.once('message', resolve);
      worker.once('error', reject);
    });
    assert.equal(result.type, 'completed', result.stderr);
    assert.deepEqual(result.value, ['שלום', 'שלום', 'שלום']);
  } finally {
    await worker?.terminate();
    await fs.rm(workspace, { recursive: true, force: true });
  }
});


test('relative copy and rename destinations plus native realpath stay in the execution workspace', async t => {
  const workspace = await fs.mkdtemp(path.join(os.tmpdir(), 'hanlin-workspace-pairs-'));
  t.after(() => fs.rm(workspace, { recursive: true, force: true }));
  const entryPoint = path.join(workspace, 'main.mjs');
  await fs.writeFile(path.join(workspace, 'source.txt'), 'pair-paths-שלום');
  await fs.writeFile(entryPoint, `
    import {copyFileSync, renameSync, realpathSync, readFileSync, exists} from 'node:fs';
    import {promisify} from 'node:util';
    import {copyFile, rename} from 'node:fs/promises';
    copyFileSync('source.txt', 'copy.txt'); renameSync('copy.txt', 'renamed.txt');
    await copyFile('source.txt', 'async-copy.txt'); await rename('async-copy.txt', 'async-renamed.txt');
    export default [readFileSync('renamed.txt','utf8'), readFileSync('async-renamed.txt','utf8'), realpathSync.native('source.txt'), await promisify(exists)('source.txt')];
  `);
  const worker = new Worker(new URL('../execution-worker.mjs', import.meta.url), {workerData:{entryPoint, workspace, moduleKind:'esm'}});
  t.after(() => worker.terminate());
  const message = await new Promise((resolve, reject) => {worker.once('message',resolve);worker.once('error',reject);});
  assert.equal(message.type, 'completed', JSON.stringify(message));
  assert.deepEqual(message.value, ['pair-paths-שלום','pair-paths-שלום',await fs.realpath(path.join(workspace,'source.txt')), true]);
});
