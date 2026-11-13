import test from 'node:test';
import assert from 'node:assert/strict';
import {promises as fs} from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import {randomUUID,createHash} from 'node:crypto';
import {MessageChannel} from 'node:worker_threads';
import {ExecutionJobs} from '../execution-jobs.mjs';
import {RuntimeCommandBroker} from '../runtime-command-broker.mjs';

async function fixture(t) {
  const root=await fs.mkdtemp(path.join(os.tmpdir(),'hanlin-command-broker-'));
  t.after(()=>fs.rm(root,{recursive:true,force:true}));
  const jobs=new ExecutionJobs({root:path.join(root,'jobs'),workerURL:new URL('../execution-worker.mjs',import.meta.url)});
  await jobs.initialize();
  return {root,jobs};
}

// Drives the same receipt boundary that Swift consumes, using real Node CLI
// jobs. It is an actual Node-to-Node integration proof, not an ios_system/Python proof.
async function runShell(jobs,root,script) {
  const source=`import {executePortableShell} from ${JSON.stringify(new URL('../portable-shell.mjs',import.meta.url).href)};
    const status=await executePortableShell(${JSON.stringify(script)},[],{cwd:process.cwd(),environment:process.env});
    process.exitCode=status; export default status;`;
  const started=await jobs.start({source,moduleKind:'esm',workspace:root});
  const tasks=new Map();
  const deadline=performance.now()+15000;
  while(!['completed','failed','cancelled','interrupted'].includes(jobs.snapshot(started.executionID).state)) {
    assert.ok(performance.now()<deadline,'Actual command broker fixture did not finish');
    for(const request of await jobs.commandRequests(started.executionID)) {
      if(tasks.has(request.id))continue;
      tasks.set(request.id,(async()=>{
        assert.ok(request.command==='node'||request.engine==='node',JSON.stringify(request));
        const entryPoint=request.entryPoint??path.resolve(request.cwd,request.arguments[0]);
        const child=await jobs.start({executionMode:'cli',entryPoint,workspace:request.cwd,moduleKind:'commonjs',
          arguments:request.entryPoint?request.arguments:request.arguments.slice(1),environment:request.environment,standardInputPath:request.standardInputPath});
        const completed=await jobs.wait(child.executionID);
        const result={exitCode:completed.result.exitCode,stdoutPath:completed.result.outputFiles.stdout.path,stderrPath:completed.result.outputFiles.stderr.path};
        const response=path.join(path.dirname(request.standardInputPath),'response.json');
        await fs.writeFile(response+'.tmp',JSON.stringify(result)); await fs.rename(response+'.tmp',response);
      })());
    }
    await new Promise(resolve=>setTimeout(resolve,10));
  }
  await Promise.all(tasks.values());
  return {job:await jobs.wait(started.executionID),commands:tasks.size};
}

test('real parent Worker spools a >10MiB Unicode pipeline through actual CLI jobs without output loss',async t=>{
  const {root,jobs}=await fixture(t);
  const text='שלום 👨‍👩‍👧‍👦\n'.repeat(400000);
  await fs.writeFile(path.join(root,'produce.cjs'),`if(require.main!==module)throw Error('Not CLI main');process.stdout.write('שלום 👨‍👩‍👧‍👦\\n'.repeat(400000));`);
  await fs.writeFile(path.join(root,'copy.cjs'),`if(process.argv[2]!=='arg with spaces'||process.argv[3]!=='עברית')throw Error('argv');process.stdin.pipe(process.stdout);`);
  const {job,commands}=await runShell(jobs,root,`node produce.cjs | node copy.cjs 'arg with spaces' עברית > 'complete output.txt'`);
  assert.equal(job.state,'completed',JSON.stringify(job)); assert.equal(commands,2);
  const output=await fs.readFile(path.join(root,'complete output.txt'));
  assert.ok(output.length>10*1024*1024); assert.equal(output.toString(),text);
  assert.equal(createHash('sha256').update(output).digest('hex'),createHash('sha256').update(text).digest('hex'));
});

test('npm run uses actual pre/main/post CLI jobs, lifecycle environment and stops at real exit23',async t=>{
  const {root,jobs}=await fixture(t);
  const scripts={prebuild:'node phase.cjs pre',build:'node phase.cjs build',postbuild:'node phase.cjs post'};
  await fs.writeFile(path.join(root,'package.json'),JSON.stringify({name:'actual-npm-run',version:'1.2.3',scripts}));
  await fs.writeFile(path.join(root,'phase.cjs'),`const fs=require('node:fs');fs.appendFileSync('order.jsonl',JSON.stringify({args:process.argv.slice(2),event:process.env.npm_lifecycle_event,name:process.env.npm_package_name,cwd:process.cwd()})+'\\n');if(process.argv[2]==='fail')process.exitCode=23;`);
  let actual=await runShell(jobs,root,'npm run build');
  assert.equal(actual.job.state,'completed',JSON.stringify(actual.job)); assert.equal(actual.commands,3);
  let events=(await fs.readFile(path.join(root,'order.jsonl'),'utf8')).trim().split('\n').map(JSON.parse);
  assert.deepEqual(events.map(item=>[item.args,item.event,item.name,item.cwd]),[
    [['pre'],'prebuild','actual-npm-run',root],[['build'],'build','actual-npm-run',root],[['post'],'postbuild','actual-npm-run',root]]);
  scripts.build='node phase.cjs fail';
  await fs.writeFile(path.join(root,'package.json'),JSON.stringify({name:'actual-npm-run',version:'1.2.3',scripts}));
  await fs.writeFile(path.join(root,'order.jsonl'),'');
  actual=await runShell(jobs,root,'npm run build');
  assert.equal(actual.job.state,'failed'); assert.equal(actual.job.result.exitCode,23); assert.equal(actual.commands,2);
  events=(await fs.readFile(path.join(root,'order.jsonl'),'utf8')).trim().split('\n').map(JSON.parse);
  assert.deepEqual(events.map(item=>item.args),[['pre'],['fail']]);
});

test('durable completion receipt is idempotent across lost/reordered acknowledgements and rejects conflicts',async t=>{
  const {root}=await fixture(t);const id=randomUUID();const {port1,port2}=new MessageChannel();
  const broker=new RuntimeCommandBroker({directory:root,port:port1,parentExecutionID:randomUUID()});
  t.after(()=>port2.close());
  await fs.mkdir(path.join(root,id));await fs.writeFile(path.join(root,id,'stdin'),'');
  const request={id,command:'node',arguments:['script.cjs'],cwd:root,environment:{},standardInputPath:path.join(root,id,'stdin')};
  const message=new Promise(resolve=>port2.once('message',resolve));
  port2.postMessage(request);
  while((await broker.requests()).length===0)await new Promise(resolve=>setTimeout(resolve,5));
  const result={exitCode:23,stdoutPath:'/actual/stdout',stderrPath:'/actual/stderr'};
  await broker.complete(id,result);assert.deepEqual((await message).result,result);
  await broker.complete(id,{stderrPath:'/actual/stderr',stdoutPath:'/actual/stdout',exitCode:23});
  await assert.rejects(broker.complete(id,{...result,exitCode:0}),/Conflicting/);
  assert.equal((await broker.requests()).length,0);await broker.drain();
});


test('parent cancellation remains pending until the actual linked-command receipt arrives',async t=>{
  const {root,jobs}=await fixture(t);
  const source=`import {executePortableShell} from ${JSON.stringify(new URL('../portable-shell.mjs',import.meta.url).href)};await executePortableShell('node pending.cjs',[],{cwd:process.cwd(),environment:process.env});`;
  const parent=await jobs.start({source,moduleKind:'esm',workspace:root});
  let requests=[]; const deadline=performance.now()+5000;
  while(!(requests=await jobs.commandRequests(parent.executionID)).length){assert.ok(performance.now()<deadline);await new Promise(resolve=>setTimeout(resolve,10));}
  await jobs.cancel(parent.executionID);
  assert.equal(jobs.snapshot(parent.executionID).cancellationRequested,true);
  assert.equal(jobs.snapshot(parent.executionID).state,'running');
  const request=(await jobs.commandRequests(parent.executionID))[0];
  assert.equal(request.cancellationRequested,true);
  const directory=path.dirname(request.standardInputPath);
  const stdoutPath=path.join(directory,'out'),stderrPath=path.join(directory,'err');
  await fs.writeFile(stdoutPath,'partial output');await fs.writeFile(stderrPath,'cancelled');
  await fs.writeFile(path.join(directory,'response.json'),JSON.stringify({exitCode:130,stdoutPath,stderrPath}));
  const done=await jobs.wait(parent.executionID);
  assert.equal(done.state,'cancelled');assert.equal(done.result.wasCancelled,true);
});

test('actual journal write failure returns a failed in-memory status and retains partial output',async t=>{
  const {root,jobs}=await fixture(t);
  const parent=await jobs.start({workspace:root,moduleKind:'esm',source:`import {existsSync} from 'node:fs';console.log('BEFORE_REAL_IO_FAILURE');while(!existsSync('release'))await new Promise(resolve=>setTimeout(resolve,10));console.log('AFTER_RELEASE');`});
  const directory=path.join(root,'jobs',parent.executionID);
  const deadline=performance.now()+5000;
  while(jobs.snapshot(parent.executionID).stdoutBytes===0){
    const current=jobs.snapshot(parent.executionID);
    assert.ok(!['failed','completed','cancelled','interrupted'].includes(current.state), JSON.stringify(current));
    assert.ok(performance.now()<deadline,JSON.stringify(current));await new Promise(resolve=>setTimeout(resolve,10));
  }
  assert.equal(JSON.parse(await fs.readFile(path.join(directory,'job.json'),'utf8')).state,'running');
  // A real incompatible filesystem object, not a mocked fs implementation.
  await fs.mkdir(path.join(directory,'job.json.tmp'));
  await fs.writeFile(path.join(root,'release'),'');
  const failed=await jobs.wait(parent.executionID);
  assert.equal(failed.state,'failed');assert.equal(failed.memoryOnlyFailure,true);
  assert.match(failed.error,/EISDIR|EPERM|illegal operation|directory/i);
  const page=await jobs.readOutput(parent.executionID,'stdout',0,4096);
  assert.match(Buffer.from(page.base64,'base64').toString(),/BEFORE_REAL_IO_FAILURE/);
});
