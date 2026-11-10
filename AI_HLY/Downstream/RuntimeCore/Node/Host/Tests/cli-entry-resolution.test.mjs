import test from 'node:test';
import assert from 'node:assert/strict';
import {promises as fs} from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import {randomUUID} from 'node:crypto';
import {ExecutionJobs,resolveNodeCLIEntryPoint} from '../execution-jobs.mjs';

test('actual CLI Worker resolves extensionless scripts and directory mains using Node resolution',async t=>{
  const root=await fs.mkdtemp(path.join(os.tmpdir(),'hanlin-cli-resolve-'));
  t.after(()=>fs.rm(root,{recursive:true,force:true}));
  const jobs=new ExecutionJobs({root:path.join(root,'jobs'),workerURL:new URL('../execution-worker.mjs',import.meta.url)});await jobs.initialize();
  const nonce=randomUUID();
  await fs.mkdir(path.join(root,'scripts'));
  const actual=path.join(root,'scripts','postinstall.js');
  await fs.writeFile(actual,`if(require.main!==module)throw Error('Not actual main');console.log(${JSON.stringify(nonce)}+':'+process.argv[2]);`);
  const directory=path.join(root,'package-main');await fs.mkdir(directory);
  await fs.writeFile(path.join(directory,'package.json'),JSON.stringify({main:'../scripts/postinstall'}));
  for(const entryPoint of [actual.slice(0,-3),directory]) {
    assert.equal(await resolveNodeCLIEntryPoint(entryPoint),await fs.realpath(actual));
    const header=await jobs.start({executionMode:'cli',entryPoint,workspace:root,moduleKind:'commonjs',arguments:['שלום']});
    const completed=await jobs.wait(header.executionID);
    assert.equal(completed.state,'completed',JSON.stringify(completed));assert.equal(completed.result.stdout,nonce+':שלום\n');
  }
  await assert.rejects(resolveNodeCLIEntryPoint(path.join(root,'absent')),error=>error.code==='MODULE_NOT_FOUND');
});
