import test from 'node:test';
import assert from 'node:assert/strict';
import { promises as fs } from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { randomUUID } from 'node:crypto';
import { Worker } from 'node:worker_threads';
import { traceRuntimeWarnings } from '../warning-diagnostics.mjs';

test('warning tracing is scoped, reference counted and idempotent', () => {
  const baseline = process.listenerCount('warning');
  const first = traceRuntimeWarnings();
  const second = traceRuntimeWarnings();
  assert.equal(process.listenerCount('warning'), baseline + 1);
  first(); first();
  assert.equal(process.listenerCount('warning'), baseline + 1);
  second();
  assert.equal(process.listenerCount('warning'), baseline);
});

test('diagnostic execution retains the actual warning stack and worker identity', async () => {
  const workspace = await fs.mkdtemp(path.join(os.tmpdir(), 'hanlin-warning-trace-'));
  const entryPoint = path.join(workspace, 'main.mjs');
  const nonce = randomUUID();
  let worker;
  try {
    await fs.writeFile(entryPoint, `process.emitWarning(${JSON.stringify(nonce)});
      await new Promise(resolve => setImmediate(resolve));
      export default ${JSON.stringify(nonce)};`);
    worker = new Worker(new URL('../diagnostic-worker.mjs', import.meta.url), {
      stderr: true,
      workerData: { entryPoint, workspace, moduleKind: 'esm', maximumOutputBytes: 4096 },
    });
    let output = '';
    worker.stderr.setEncoding('utf8');
    worker.stderr.on('data', chunk => { output += chunk; });
    const result = await new Promise((resolve, reject) => {
      worker.once('message', resolve);
      worker.once('error', reject);
    });
    await new Promise(resolve => worker.once('exit', resolve));
    assert.equal(result.type, 'completed');
    assert.equal(result.value, nonce);
    assert.match(output, /HANLIN_NODE_WARNING thread=[1-9][0-9]*/);
    assert.ok(output.includes(`Warning: ${nonce}`));
    assert.match(output, /main\.mjs\?execution=[0-9]+:1:9/);
  } finally {
    await worker?.terminate();
    await fs.rm(workspace, { recursive: true, force: true });
  }
});
