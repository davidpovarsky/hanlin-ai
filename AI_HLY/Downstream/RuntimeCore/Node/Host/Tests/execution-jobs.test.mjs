import test from 'node:test';
import assert from 'node:assert/strict';
import { promises as fs } from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { createHash } from 'node:crypto';
import { ExecutionJobs } from '../execution-jobs.mjs';

async function fixture(t) {
  const root = await fs.mkdtemp(path.join(os.tmpdir(), 'hanlin-jobs-'));
  t.after(() => fs.rm(root, { recursive: true, force: true }));
  const jobs = new ExecutionJobs({ root: path.join(root, 'jobs'), workerURL: new URL('../execution-worker.mjs', import.meta.url) });
  await jobs.initialize();
  return { jobs, root, body: { workspace: root, moduleKind: 'esm', maximumOutputBytes: 4096 } };
}

test('full stdout and stderr survive preview limits and store reopen with verified hashes', async t => {
  const { jobs, root, body } = await fixture(t);
  const text = 'שלום 👨‍👩‍👧‍👦\n'.repeat(400_000);
  const header = await jobs.start({ ...body, source: `const text = 'שלום 👨‍👩‍👧‍👦\\n'.repeat(400000); process.stdout.write(text); process.stderr.write('tail stderr'); export default 42;` });
  const completed = await jobs.wait(header.executionID);
  assert.equal(completed.state, 'completed', JSON.stringify(completed));
  assert.equal(completed.result.value, 42);
  assert.equal(completed.result.outputWasTruncated, true);
  const actual = await fs.readFile(completed.result.outputFiles.stdout.path);
  assert.ok(actual.length > 10 * 1024 * 1024);
  assert.equal(actual.toString('utf8'), text);
  assert.equal(completed.result.outputFiles.stdout.sha256, createHash('sha256').update(text).digest('hex'));
  assert.equal(await fs.readFile(completed.result.outputFiles.stderr.path, 'utf8'), 'tail stderr');
  const reopened = new ExecutionJobs({ root: path.join(root, 'jobs'), workerURL: new URL('../execution-worker.mjs', import.meta.url) });
  await reopened.initialize();
  assert.equal(reopened.snapshot(header.executionID).state, 'completed');
  const parts = [];
  let offset = 0;
  while (true) {
    const page = await reopened.readOutput(header.executionID, 'stdout', offset, 4093);
    parts.push(Buffer.from(page.base64, 'base64'));
    if (!page.hasMore) break;
    offset = page.nextOffset;
  }
  assert.equal(Buffer.concat(parts).toString('utf8'), text);
  await assert.rejects(jobs.start({ ...body, executionID: header.executionID, source: 'throw new Error("replayed")' }), /already exists/);
});

test('ordinary event-loop work finishes after module evaluation without being terminated early', async t => {
  const { jobs, body } = await fixture(t);
  const started = Date.now();
  const header = await jobs.start({ ...body, source: `setTimeout(() => console.log('ASYNC_TIMER_COMPLETE'), 120); export default 'loaded';` });
  const completed = await jobs.wait(header.executionID);
  assert.equal(completed.state, 'completed');
  assert.ok(Date.now() - started >= 120);
  assert.match(completed.result.stdout, /ASYNC_TIMER_COMPLETE/);
});

test('explicit timeout retains partial output and is distinct from user cancellation', async t => {
  const { jobs, body } = await fixture(t);
  const header = await jobs.start({ ...body, timeoutMilliseconds: 1500, source: `console.log('BEFORE_TIMEOUT'); await new Promise(resolve => setTimeout(resolve, 60000));` });
  const completed = await jobs.wait(header.executionID);
  assert.equal(completed.state, 'failed');
  assert.equal(completed.result.didTimeOut, true);
  assert.equal(completed.result.wasCancelled, false);
  assert.match(await fs.readFile(completed.result.outputFiles.stdout.path, 'utf8'), /BEFORE_TIMEOUT/);
});

test('explicit cancellation terminates the actual worker and retains partial output', async t => {
  const { jobs, body } = await fixture(t);
  const header = await jobs.start({ ...body, source: `console.log('BEFORE_CANCEL'); await new Promise(resolve => setTimeout(resolve, 60000));` });
  while (jobs.snapshot(header.executionID).stdoutBytes === 0) await new Promise(resolve => setTimeout(resolve, 10));
  await jobs.cancel(header.executionID);
  const completed = await jobs.wait(header.executionID);
  assert.equal(completed.state, 'cancelled');
  assert.equal(completed.result.wasCancelled, true);
  assert.equal(completed.result.didTimeOut, false);
  assert.match(await fs.readFile(completed.result.outputFiles.stdout.path, 'utf8'), /BEFORE_CANCEL/);
});

test('actual Node job crosses 300 seconds with no hidden deadline', { skip: process.env.HANLIN_RUN_LONG_JOBS !== '1' }, async t => {
  const { jobs, body } = await fixture(t);
  const start = performance.now();
  const header = await jobs.start({ ...body, source: `console.log('LONG_JOB_STARTED'); await new Promise(resolve => setTimeout(resolve, 305000)); console.log('LONG_JOB_COMPLETED'); export default 305;` });
  const completed = await jobs.wait(header.executionID);
  const elapsed = performance.now() - start;
  assert.ok(elapsed > 300000, String(elapsed));
  assert.equal(completed.state, 'completed');
  assert.equal(completed.result.value, 305);
  assert.match(completed.result.stdout, /LONG_JOB_COMPLETED/);
  console.log(JSON.stringify({ proof: 'actual-node-job-over-300-seconds', elapsedMilliseconds: elapsed, executionID: header.executionID }));
});

test('a later nonzero exit cannot be hidden by an earlier successful module export', async t => {
  const { jobs, body } = await fixture(t);
  const header = await jobs.start({ ...body, source: `process.exitCode = 23; export default 'module loaded';` });
  const result = await jobs.wait(header.executionID);
  assert.equal(result.state, 'failed');
  assert.equal(result.result.exitCode, 23);
});


test('user worker messages cannot hide the final module result', async t => {
  const { jobs, body } = await fixture(t);
  const header = await jobs.start({ ...body, source: `import { parentPort } from 'node:worker_threads'; parentPort.postMessage({ user: 'progress' }); export default 73;` });
  const result = await jobs.wait(header.executionID);
  assert.equal(result.state, 'completed');
  assert.equal(result.result.value, 73);
});

test('a restored job with no opened streams has an empty lossless output page', async t => {
  const { jobs, root } = await fixture(t);
  const id = '10d4d9c5-5cb9-4afb-abc2-2f088de780ac';
  const directory = path.join(root, 'jobs', id);
  await fs.mkdir(directory);
  await fs.writeFile(path.join(directory, 'job.json'), JSON.stringify({ executionID: id, state: 'queued', startedAt: Date.now(), cancellationRequested: true }));
  await jobs.initialize();
  assert.equal(jobs.snapshot(id).state, 'interrupted');
  assert.deepEqual(await jobs.readOutput(id, 'stdout'), { executionID: id, channel: 'stdout', offset: 0, nextOffset: 0, totalBytes: 0, hasMore: false, base64: '' });
});
