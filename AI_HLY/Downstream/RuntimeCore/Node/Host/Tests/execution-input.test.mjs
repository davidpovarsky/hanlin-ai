import test from 'node:test';
import assert from 'node:assert/strict';
import {promises as fs} from 'node:fs';
import {spawn} from 'node:child_process';
import {once} from 'node:events';
import path from 'node:path';
import os from 'node:os';
import {fileURLToPath} from 'node:url';
import {randomUUID,createHash} from 'node:crypto';
import {ExecutionJobs} from '../execution-jobs.mjs';

async function fixture(t) {
  const root=await fs.mkdtemp(path.join(os.tmpdir(),'hanlin-file-input-'));
  t.after(()=>fs.rm(root,{recursive:true,force:true}));
  const inbox=path.join(root,'runtime','node','requests');await fs.mkdir(inbox,{recursive:true});
  const jobs=new ExecutionJobs({root:path.join(root,'jobs','node'),inputInbox:inbox,workerURL:new URL('../execution-worker.mjs',import.meta.url)});
  await jobs.initialize();
  return {root,inbox,jobs};
}
async function writeInput({root,inbox},extra={}) {
  const id=randomUUID(),body={executionID:id,source:"console.log('owned-input'); export default 42;",moduleKind:'esm',workspace:root,detached:true,...extra};
  const bytes=Buffer.from(JSON.stringify(body)),file=path.join(inbox,id+'.json');
  await fs.writeFile(file,bytes,{flag:'wx'});
  return {id,body,bytes,file,envelope:{executionID:id,detached:true,inputArtifact:{bytes:bytes.length,sha256:createHash('sha256').update(bytes).digest('hex')}}};
}

test('actual authenticated HTTP control executes >32MiB Unicode input with exact durable hashes and no replay',async t=>{
  const fixtureValue=await fixture(t),{root,inbox}=fixtureValue;
  const ready=path.join(root,'ready.json'),token='owned-input-test-token';
  const child=spawn(process.execPath,['--jitless',fileURLToPath(new URL('../host.mjs',import.meta.url)),root,ready,token,path.join(root,'host.log'),'0'],{stdio:['ignore','ignore','pipe']});
  let diagnostics='';child.stderr.on('data',chunk=>diagnostics+=chunk);
  t.after(async()=>{if(child.exitCode===null&&child.signalCode===null){child.kill();await once(child,'exit');}});
  const until=performance.now()+15000;let port;
  while(!port){
    assert.ok(performance.now()<until,'The real Host did not become ready: '+diagnostics);
    assert.equal(child.exitCode,null,diagnostics);
    try{port=JSON.parse(await fs.readFile(ready,'utf8')).port;}catch(error){if(error.code!=='ENOENT')throw error;}
    if(!port)await new Promise(resolve=>setTimeout(resolve,10));
  }
  const nonce=randomUUID();
  const input=await writeInput({root,inbox},{source:'/*'+'שלום 👨‍👩‍👧‍👦 '.repeat(1_000_000)+`*/\nconsole.log(${JSON.stringify(nonce)});export default {nonce:${JSON.stringify(nonce)},argument:process.argv[2]};`,arguments:['actual argument שלום']});
  assert.ok(input.bytes.length>32*1024*1024);
  const control=JSON.stringify(input.envelope);assert.ok(Buffer.byteLength(control)<1024);
  const request=async(route,body)=>fetch(`http://127.0.0.1:${port}${route}`,{method:body?'POST':'GET',
    headers:{Authorization:`Bearer ${token}`,'Content-Type':'application/json'},body,signal:AbortSignal.timeout(30000)});
  const accepted=await request('/v1/executions',control);assert.equal(accepted.status,200,await accepted.clone().text());
  let job=await accepted.json();
  const finishedBy=performance.now()+15000;
  while(!['completed','failed','cancelled','interrupted'].includes(job.state)){
    assert.ok(performance.now()<finishedBy,'The actual large-source Worker did not settle');
    await new Promise(resolve=>setTimeout(resolve,20));job=await (await request('/v1/executions/'+input.id)).json();
  }
  assert.equal(job.state,'completed',JSON.stringify(job));
  assert.equal(job.result.value.nonce,nonce);assert.equal(job.result.value.argument,'actual argument שלום');
  assert.equal(job.inputArtifact.bytes,input.bytes.length);assert.equal(job.inputArtifact.sha256,input.envelope.inputArtifact.sha256);
  assert.equal(job.inputArtifact.verified,true);
  const saved=await fs.readFile(path.join(root,'jobs','node',input.id,'request.json'));
  assert.deepEqual(saved,input.bytes);
  await assert.rejects(fs.access(input.file),error=>error.code==='ENOENT');
  const replay=await request('/v1/executions',control);assert.equal(replay.status,409);
  const reopened=new ExecutionJobs({root:path.join(root,'jobs','node')});await reopened.initialize();
  assert.equal(reopened.snapshot(input.id).inputArtifact.sha256,input.envelope.inputArtifact.sha256);
  assert.equal(reopened.snapshot(input.id).result.stdout.trim(),nonce);
});

test('wrong digest, size, identity and invalid UTF8 preserve failed input without executing its source',async t=>{
  const value=await fixture(t),{root,jobs}=value;
  for(const fault of ['digest','size','identity','utf8']) {
    const input=await writeInput(value,{source:"import {writeFileSync} from 'node:fs';writeFileSync('must-not-run','bad');"});
    if(fault==='digest')input.envelope.inputArtifact.sha256='0'.repeat(64);
    if(fault==='size')++input.envelope.inputArtifact.bytes;
    if(fault==='identity'){
      input.body.executionID=randomUUID();input.bytes=Buffer.from(JSON.stringify(input.body));
      await fs.writeFile(input.file,input.bytes);input.envelope.inputArtifact={bytes:input.bytes.length,sha256:createHash('sha256').update(input.bytes).digest('hex')};
    }
    if(fault==='utf8'){
      input.bytes=Buffer.from([0xff,0xfe,0xff]);await fs.writeFile(input.file,input.bytes);
      input.envelope.inputArtifact={bytes:input.bytes.length,sha256:createHash('sha256').update(input.bytes).digest('hex')};
    }
    await assert.rejects(jobs.start(input.envelope));
    assert.equal(jobs.snapshot(input.id).state,'failed');
    assert.deepEqual(await fs.readFile(path.join(root,'jobs','node',input.id,'request.json')),input.bytes);
    await assert.rejects(fs.access(path.join(root,'must-not-run')),error=>error.code==='ENOENT');
    await assert.rejects(fs.access(path.join(root,'jobs','node',input.id,'main.mjs')),error=>error.code==='ENOENT');
  }
});

test('interruption during claimed input preparation settles the original ID without a Worker or later replay',async t=>{
  const value=await fixture(t),{root,jobs}=value;
  const input=await writeInput(value,{source:'/*'+'x'.repeat(12*1024*1024)+"*/\nconsole.log('must-not-run');"});
  const started=jobs.start(input.envelope);
  const reason='Actual owner interruption during file input preparation';
  await jobs.interrupt(input.id,reason);
  await assert.rejects(started,/cancelled/);
  assert.equal(jobs.snapshot(input.id).state,'interrupted');assert.equal(jobs.snapshot(input.id).interruptionReason,reason);
  await assert.rejects(fs.access(path.join(root,'jobs','node',input.id,'main.mjs')),error=>error.code==='ENOENT');
  await assert.rejects(jobs.start(input.envelope),error=>error.status===409);
});

test('never-started receipts and nonregular inbox paths cannot be claimed as fresh execution',async t=>{
  const value=await fixture(t),{jobs,inbox,root}=value;
  const input=await writeInput(value);
  await jobs.interrupt(input.id,'Interrupted before submission');
  await assert.rejects(jobs.start(input.envelope),error=>error.status===409);
  assert.deepEqual(await fs.readFile(input.file),input.bytes);
  const id=randomUUID(),outside=path.join(root,'outside');await fs.mkdir(outside);
  const linked=path.join(inbox,id+'.json');await fs.symlink(outside,linked,process.platform==='win32'?'junction':'dir');
  await assert.rejects(jobs.start({executionID:id,inputArtifact:{bytes:10,sha256:'0'.repeat(64)}}),/regular owned file/);
  await fs.access(outside);assert.equal((await fs.lstat(linked)).isSymbolicLink(),true);
});

test('actual process termination during preflight recovers the claimed input as interrupted without source replay',{timeout:20000},async t=>{
  const value=await fixture(t),{root,inbox}=value;
  const input=await writeInput(value,{source:"import {writeFileSync} from 'node:fs';writeFileSync('must-not-run','bad');"});
  const ready=path.join(root,'actual-validation-entered');
  const code=`
    import {ExecutionJobs} from ${JSON.stringify(new URL('../execution-jobs.mjs',import.meta.url).href)};
    import {promises as fs} from 'node:fs';
    const jobs=new ExecutionJobs({root:${JSON.stringify(path.join(root,'jobs','node'))},inputInbox:${JSON.stringify(inbox)},
      workerURL:new URL(${JSON.stringify(new URL('../execution-worker.mjs',import.meta.url).href)}),
      validateInput:async body=>{await fs.writeFile(${JSON.stringify(ready)},'entered');await new Promise(()=>setInterval(()=>{},1000));return body;}});
    await jobs.initialize();await jobs.start(${JSON.stringify(input.envelope)});
  `;
  const child=spawn(process.execPath,['--jitless','--input-type=module','-e',code],{stdio:['ignore','ignore','pipe']});
  let diagnostics='';child.stderr.on('data',chunk=>diagnostics+=chunk);
  t.after(async()=>{if(child.exitCode===null&&child.signalCode===null){child.kill();await once(child,'exit');}});
  const deadline=performance.now()+15000;
  while(true){
    assert.ok(performance.now()<deadline,'The actual preflight did not enter: '+diagnostics);
    assert.equal(child.exitCode,null,diagnostics);
    try{await fs.access(ready);break;}catch(error){if(error.code!=='ENOENT')throw error;}
    await new Promise(resolve=>setTimeout(resolve,10));
  }
  child.kill();await once(child,'exit');
  const reopened=new ExecutionJobs({root:path.join(root,'jobs','node')});await reopened.initialize();
  const saved=reopened.snapshot(input.id);
  assert.equal(saved.state,'interrupted');assert.equal(saved.inputArtifact.verified,true);
  assert.deepEqual(await fs.readFile(path.join(root,'jobs','node',input.id,'request.json')),input.bytes);
  await assert.rejects(fs.access(path.join(root,'must-not-run')),error=>error.code==='ENOENT');
  await assert.rejects(reopened.start(input.envelope),error=>error.status===409);
});

test('ordinary cancellation before POST persists the first cause and prevents delayed file or Host operation side effects',async t=>{
  const value=await fixture(t),{root,jobs}=value;
  const input=await writeInput(value,{source:"import {writeFileSync} from 'node:fs';writeFileSync('must-not-run','bad');"});
  const pending=jobs.cancel(input.id);
  assert.equal(jobs.snapshot(input.id).state,'queued');
  assert.equal(jobs.snapshot(input.id).neverStarted,false,'No never-started classification before exclusive directory ownership');
  const [first,second]=await Promise.all([pending,jobs.cancel(input.id)]);
  assert.equal(first.state,'cancelled');assert.equal(second.state,'cancelled');assert.equal(first.neverStarted,true);
  await jobs.interrupt(input.id,'Later system interruption');
  assert.equal(jobs.snapshot(input.id).state,'cancelled');assert.equal(jobs.snapshot(input.id).interruptionReason,undefined);
  const reopened=new ExecutionJobs({root:path.join(root,'jobs','node')});await reopened.initialize();
  assert.equal(reopened.snapshot(input.id).state,'cancelled');
  await assert.rejects(reopened.start(input.envelope),error=>error.status===409);
  await assert.rejects(reopened.startOperation({executionID:input.id},async()=>{throw Error('must not execute');}),error=>error.status===409);
  assert.deepEqual(await fs.readFile(input.file),input.bytes);
  await assert.rejects(fs.access(path.join(root,'must-not-run')),error=>error.code==='ENOENT');
});

test('cancelling an unregistered pre-existing journal never overwrites or classifies its history as never-started',async t=>{
  const {root,jobs}=await fixture(t),id=randomUUID(),directory=path.join(root,'jobs','node',id);
  await fs.mkdir(directory);await fs.writeFile(path.join(directory,'job.json'),'original unknown journal');
  await fs.writeFile(path.join(directory,'stdout.log'),'prior output');
  await assert.rejects(jobs.cancel(id),error=>error.code==='EEXIST');
  assert.equal(jobs.snapshot(id).neverStarted,false);
  assert.equal(await fs.readFile(path.join(directory,'job.json'),'utf8'),'original unknown journal');
  assert.equal(await fs.readFile(path.join(directory,'stdout.log'),'utf8'),'prior output');
  await assert.rejects(jobs.start({executionID:id,source:'throw Error("must not execute")'}),error=>error.status===409);
});
