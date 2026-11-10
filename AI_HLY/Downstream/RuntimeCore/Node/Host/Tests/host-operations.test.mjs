import test from 'node:test';
import assert from 'node:assert/strict';
import {promises as fs} from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import {randomUUID,createHash} from 'node:crypto';
import {ExecutionJobs} from '../execution-jobs.mjs';

async function fixture(t){
  const root=await fs.mkdtemp(path.join(os.tmpdir(),'hanlin-host-operation-'));
  t.after(()=>fs.rm(root,{recursive:true,force:true}));
  const jobs=new ExecutionJobs({root});await jobs.initialize();return {root,jobs};
}

test('Host operation survives observer loss and retains complete progress, UTF8 previews, digests and reopen',async t=>{
  const {root,jobs}=await fixture(t),id=randomUUID();
  let release;const gate=new Promise(resolve=>release=resolve);
  const progress={phase:'installing',detail:'שלום 😀'.repeat(2000)};
  const started=await jobs.startOperation({executionID:id,maximumOutputBytes:71},async({emit})=>{
    emit(progress);await gate;return {version:'2.0.0',nonce:id};
  });
  assert.equal(started.executionID,id);
  assert.equal(jobs.activeCount,1);
  // There is deliberately no waiter while the actual installation continues.
  release();
  const completed=await jobs.wait(id);
  assert.equal(completed.state,'completed');assert.deepEqual(completed.result.value,{version:'2.0.0',nonce:id});
  const output=await fs.readFile(completed.result.outputFiles.stdout.path);
  assert.equal(output.toString(),JSON.stringify(progress)+'\n');
  assert.equal(createHash('sha256').update(output).digest('hex'),completed.result.outputFiles.stdout.sha256);
  assert.equal(completed.result.outputWasTruncated,true);assert.doesNotMatch(completed.result.stdout,/\uFFFD/);
  const reopened=new ExecutionJobs({root});await reopened.initialize();
  assert.deepEqual(reopened.snapshot(id).result.value,completed.result.value);
  assert.deepEqual(reopened.snapshot(id).progress,progress);
  await assert.rejects(jobs.startOperation({executionID:id},async()=>{throw Error('replayed');}),/never replayed/);
});

test('Host cancellation stays requested until the real asynchronous operation drains',async t=>{
  const {jobs}=await fixture(t),id=randomUUID();
  let release,started;const gate=new Promise(resolve=>release=resolve),began=new Promise(resolve=>started=resolve);
  await jobs.startOperation({executionID:id},async({signal,emit})=>{
    emit({phase:'running'});started();await gate;signal.throwIfAborted();throw Error('cancelled work resumed');
  });
  await began;await jobs.cancel(id);
  const requested=jobs.snapshot(id);
  assert.equal(requested.state,'running');assert.equal(requested.cancellationRequested,true);
  release();const cancelled=await jobs.wait(id);
  assert.equal(cancelled.state,'cancelled');assert.equal(cancelled.result.wasCancelled,true);
  assert.equal(cancelled.result.didTimeOut,false);assert.match(cancelled.result.stdout,/running/);
});

test('a real Host journal failure aborts extraction and exposes failed in-memory status with partial output',async t=>{
  const {root,jobs}=await fixture(t),id=randomUUID();
  let started,release;const began=new Promise(resolve=>started=resolve),gate=new Promise(resolve=>release=resolve);
  await jobs.startOperation({executionID:id},async({signal,emit})=>{
    started();await gate;
    emit({phase:'before-real-disk-failure'});
    await new Promise(resolve=>{if(signal.aborted)resolve();else signal.addEventListener('abort',resolve,{once:true});});
    signal.throwIfAborted();
  });
  await began;await fs.mkdir(path.join(root,id,'job.json.tmp'));release();
  const failed=await jobs.wait(id);
  assert.equal(failed.state,'failed');assert.equal(failed.memoryOnlyFailure,true);
  assert.match(failed.error,/EISDIR|EPERM|directory|illegal operation/i);
  const output=await jobs.readOutput(id,'stdout');
  assert.match(Buffer.from(output.base64,'base64').toString(),/before-real-disk-failure/);
});
