import test from 'node:test';
import assert from 'node:assert/strict';
import { promises as fs } from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { Worker } from 'node:worker_threads';
import ts from 'typescript';

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

function runWorker(workerData) {
  return new Promise((resolve, reject) => {
    const worker = new Worker(executionWorkerURL, { workerData });
    worker.once('message', resolve);
    worker.once('error', reject);
  });
}
