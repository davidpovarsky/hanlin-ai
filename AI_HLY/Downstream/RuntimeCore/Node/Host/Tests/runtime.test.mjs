import test from 'node:test';
import assert from 'node:assert/strict';
import { promises as fs } from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { Worker } from 'node:worker_threads';
import ts from 'typescript';
import { planLifecycle } from '../lifecycle-planner.mjs';

const executionWorkerURL = new URL('../execution-worker.mjs', import.meta.url);

test('generic ESM execution captures Hebrew output and a structured value', async () => {
  const workspace = await fs.mkdtemp(path.join(os.tmpdir(), 'hanlin-js-'));
  const entryPoint = path.join(workspace, 'main.mjs');
  await fs.writeFile(entryPoint, 'console.log("שלום"); export default { answer: 42 };');
  const result = await runWorker({ entryPoint, moduleKind: 'esm', arguments: [], environment: {}, maximumOutputBytes: 4096 });
  assert.equal(result.type, 'completed');
  assert.equal(result.stdout, 'שלום\n');
  assert.deepEqual(result.value, { answer: 42 });
  await fs.rm(workspace, { recursive: true, force: true });
});

test('generic CommonJS execution returns module.exports', async () => {
  const workspace = await fs.mkdtemp(path.join(os.tmpdir(), 'hanlin-cjs-'));
  const entryPoint = path.join(workspace, 'main.cjs');
  await fs.writeFile(entryPoint, 'module.exports = { format: "commonjs" };');
  const result = await runWorker({ entryPoint, moduleKind: 'commonjs', arguments: [], environment: {}, maximumOutputBytes: 4096 });
  assert.deepEqual(result.value, { format: 'commonjs' });
  await fs.rm(workspace, { recursive: true, force: true });
});

test('TypeScript 6 compiler emits JavaScript and source maps', () => {
  const result = ts.transpileModule('const answer: number = 42; console.log(answer);', {
    fileName: 'main.ts',
    compilerOptions: { target: ts.ScriptTarget.ES2022, module: ts.ModuleKind.ESNext, sourceMap: true },
    reportDiagnostics: true,
  });
  assert.match(result.outputText, /const answer = 42/);
  assert.ok(result.sourceMapText);
  assert.equal(result.diagnostics?.length ?? 0, 0);
});

test('execution output is capped without splitting the worker protocol', async () => {
  const workspace = await fs.mkdtemp(path.join(os.tmpdir(), 'hanlin-output-'));
  const entryPoint = path.join(workspace, 'main.mjs');
  await fs.writeFile(entryPoint, 'console.log("x".repeat(4096)); export default 1;');
  const result = await runWorker({ entryPoint, moduleKind: 'esm', arguments: [], environment: {}, maximumOutputBytes: 128 });
  assert.equal(Buffer.byteLength(result.stdout) + Buffer.byteLength(result.stderr), 128);
  assert.equal(result.outputWasTruncated, true);
  await fs.rm(workspace, { recursive: true, force: true });
});

test('lifecycle planner accepts brokered actions and rejects shell syntax', () => {
  const accepted = planLifecycle({ name: 'fixture', version: '1.0.0', scripts: { install: 'node setup.mjs', prepare: 'npm run compile', compile: 'tsc --project tsconfig.json' } }, 'sha512-fixture');
  assert.equal(accepted.requiresApproval, true);
  assert.equal(accepted.executable, true);
  assert.deepEqual(accepted.actions.map(action => action.kind), ['node', 'typescript']);
  const rejected = planLifecycle({ name: 'fixture', version: '1.0.0', scripts: { postinstall: 'curl https://example.com | sh' } });
  assert.equal(rejected.executable, false);
  assert.match(rejected.rejected[0].reason, /unsupported/i);
});

test('failed executions preserve aggregate HTTPS cause codes', async () => {
  const workspace = await fs.mkdtemp(path.join(os.tmpdir(), 'hanlin-error-cause-'));
  try {
    const entryPoint = path.join(workspace, 'main.mjs');
    await fs.writeFile(entryPoint, `
      const refused = Object.assign(new Error('connection refused'), { code: 'ECONNREFUSED', syscall: 'connect', address: '127.0.0.1', port: 443 });
      const timedOut = Object.assign(new Error('connection timed out'), { code: 'ETIMEDOUT' });
      throw new TypeError('fetch failed', { cause: new AggregateError([refused, timedOut], 'all connections failed') });
    `);
    const result = await runWorker({ entryPoint, moduleKind: 'esm', maximumOutputBytes: 8192 });
    assert.equal(result.type, 'failed');
    assert.match(result.stderr, /fetch failed/);
    assert.match(result.stderr, /ECONNREFUSED/);
    assert.match(result.stderr, /ETIMEDOUT/);
    assert.match(result.stderr, /127\.0\.0\.1/);
  } finally {
    await fs.rm(workspace, { recursive: true, force: true });
  }
});

test('console errors preserve cyclic causes within the output budget', async () => {
  const workspace = await fs.mkdtemp(path.join(os.tmpdir(), 'hanlin-console-error-'));
  try {
    const entryPoint = path.join(workspace, 'main.mjs');
    await fs.writeFile(entryPoint, `
      const error = Object.assign(new Error('TLS diagnostic'), { code: 'CERT_HAS_EXPIRED' });
      error.cause = error;
      console.error(error);
      console.error('x'.repeat(4096));
      export default 42;
    `);
    const result = await runWorker({ entryPoint, moduleKind: 'esm', maximumOutputBytes: 1024 });
    assert.equal(result.type, 'completed');
    assert.equal(result.value, 42);
    assert.match(result.stderr, /TLS diagnostic/);
    assert.match(result.stderr, /CERT_HAS_EXPIRED/);
    assert.match(result.stderr, /Circular/);
    assert.equal(Buffer.byteLength(result.stdout) + Buffer.byteLength(result.stderr), 1024);
    assert.equal(result.outputWasTruncated, true);
  } finally {
    await fs.rm(workspace, { recursive: true, force: true });
  }
});

function runWorker(workerData) {
  return new Promise((resolve, reject) => {
    const worker = new Worker(executionWorkerURL, { workerData });
    worker.once('message', message => {
      worker.terminate().then(() => resolve(message), reject);
    });
    worker.once('error', reject);
  });
}
