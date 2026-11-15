import test from 'node:test';
import assert from 'node:assert/strict';
import {promises as fs} from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import {randomUUID} from 'node:crypto';
import {ExecutionJobs} from '../execution-jobs.mjs';

for(const kind of ['worker','operation'])test(`${kind} terminal status is observable only after its actual atomic journal rename`,async t=>{
  const root=await fs.mkdtemp(path.join(os.tmpdir(),'hanlin-terminal-publish-')),id=randomUUID();
  t.after(()=>fs.rm(root,{recursive:true,force:true}));
  const jobs=new ExecutionJobs({root:path.join(root,'jobs'),workerURL:new URL('../execution-worker.mjs',import.meta.url)});
  await jobs.initialize();
  const file=path.join(root,'jobs',id,'job.json'),rename=fs.rename;
  let release,entered;
  const gate=new Promise(resolve=>release=resolve),blocked=new Promise(resolve=>entered=resolve);
  // Hold only the real final atomic rename, after its full bytes are written.
  // All filesystem writes/renames still execute; this controls scheduling only.
  fs.rename=async(source,destination)=>{
    if(destination===file&&JSON.parse(await fs.readFile(source,'utf8')).state==='completed'){
      entered();await gate;
    }
    return rename(source,destination);
  };
  t.after(()=>{release();fs.rename=rename;});
  if(kind==='worker')await jobs.start({executionID:id,source:"console.log('retained final bytes'); export default 42;",workspace:root,moduleKind:'esm'});
  else await jobs.startOperation({executionID:id},async({emit})=>{await emit({phase:'retained final bytes'});return 42;});
  await blocked;
  try {
    assert.equal(JSON.parse(await fs.readFile(file,'utf8')).state,'running');
    const observed=jobs.snapshot(id);
    assert.equal(observed.state,'running','A memory-only terminal state must not escape before durable publication');
    assert.equal(observed.result,null);assert.equal(observed.completedAt,undefined);
    assert.equal(jobs.activeCount,1);
  } finally {release();}
  const completed=await jobs.wait(id);
  assert.equal(completed.state,'completed');assert.equal(completed.result.value,42);
  const reopened=new ExecutionJobs({root:path.join(root,'jobs')});await reopened.initialize();
  assert.equal(reopened.snapshot(id).state,'completed');assert.equal(reopened.snapshot(id).result.value,42);
  assert.match(reopened.snapshot(id).result.stdout,/retained final bytes/);
});
