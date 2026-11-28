import test from 'node:test';
import assert from 'node:assert/strict';
import {promises as fs} from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import {randomUUID, createHash} from 'node:crypto';
import {ExecutionJobs} from '../execution-jobs.mjs';

async function fixture(t) {
  const root = await fs.mkdtemp(path.join(os.tmpdir(), 'hanlin-ts-jobs-'));
  t.after(() => fs.rm(root, {recursive:true, force:true}));
  const inbox = path.join(root,'runtime','node','requests');
  await fs.mkdir(inbox,{recursive:true});
  const jobs = new ExecutionJobs({root:path.join(root,'jobs','node'), inputInbox:inbox,
    workerURL:new URL('../execution-worker.mjs',import.meta.url)});
  await jobs.initialize();
  return {root,inbox,jobs};
}

function compilerSource(root, id, body, project=false) {
  const name = project ? 'compileTypeScriptProject' : 'compileTypeScript';
  return `import {${name}} from ${JSON.stringify(new URL('../typescript-compiler.mjs',import.meta.url).href)};
    const compiled = await ${name}(${JSON.stringify(body)}, {root:${JSON.stringify(root)}});
    const receipt = {...compiled,executionID:${JSON.stringify(id)}};
    console.log(JSON.stringify(receipt));process.exitCode=receipt.succeeded?0:1;export default receipt;`;
}

test('actual compiler Worker accepts >10MiB durable source and retains full typed output/hash/reopen',async t=>{
  const {root,inbox,jobs}=await fixture(t),id=randomUUID();
  const original='/*'+'שלום🙂 '.repeat(1_100_000)+'*/\nexport const retainedCompilerValue: number = 17;';
  assert.ok(Buffer.byteLength(original)>10*1024*1024);
  const source=compilerSource(root,id,{source:original,fileName:'מקור.ts',
    tsconfig:{compilerOptions:{types:[],skipLibCheck:true}}});
  const bytes=Buffer.from(JSON.stringify({executionID:id,source,moduleKind:'esm',workspace:root}));
  const digest=createHash('sha256').update(bytes).digest('hex');
  await fs.writeFile(path.join(inbox,id+'.json'),bytes,{flag:'wx'});
  await jobs.start({executionID:id,inputArtifact:{bytes:bytes.length,sha256:digest}});
  const finished=await jobs.wait(id);
  assert.equal(finished.state,'completed',finished.result?.stderr);
  assert.equal(finished.result.value.succeeded,true);
  assert.equal(finished.result.value.executionID,id);
  assert.equal(finished.result.value.compilerVersion,'6.0.3');
  assert.match(finished.result.value.javaScript,/retainedCompilerValue/);
  assert.equal(finished.inputArtifact.sha256,digest);
  assert.equal(finished.inputArtifact.verified,true);
  const storedRequest=JSON.parse(await fs.readFile(path.join(root,'jobs','node',id,'request.json')));
  assert.equal(storedRequest.timeoutMilliseconds,undefined);
  const artifact=finished.result.outputFiles.stdout,output=await fs.readFile(artifact.path);
  assert.ok(output.length>10*1024*1024);
  assert.equal(output.length,artifact.bytes);
  assert.equal(createHash('sha256').update(output).digest('hex'),artifact.sha256);
  assert.deepEqual(JSON.parse(output),finished.result.value);
  assert.equal(JSON.parse(finished.result.value.sourceMap).sourcesContent[0],original);
  const reopened=new ExecutionJobs({root:path.join(root,'jobs','node')});await reopened.initialize();
  assert.deepEqual(reopened.snapshot(id).result.value,finished.result.value);
  await assert.rejects(jobs.start({executionID:id,source:'throw Error("must not replay")',workspace:root}),error=>error.status===409);
});

test('actual project compiler preserves >128 argv values, emits files and reports locked compiler identity',async t=>{
  const {root,jobs}=await fixture(t),id=randomUUID();
  await fs.writeFile(path.join(root,'tsconfig.json'),JSON.stringify({compilerOptions:{target:'ES2022',module:'ESNext',types:[],skipLibCheck:true,outDir:'dist'},include:['source.ts']}));
  await fs.writeFile(path.join(root,'source.ts'),'export const projectNonce: number = 317;');
  const args=Array.from({length:70},()=>['--pretty','false']).flat();
  await jobs.start({executionID:id,workspace:root,moduleKind:'esm',
    source:compilerSource(root,id,{workspace:root,arguments:args},true)});
  const finished=await jobs.wait(id);
  assert.equal(finished.result.value.succeeded,true,finished.result.stderr);
  assert.equal(finished.result.value.compilerVersion,'6.0.3');
  assert.match(finished.result.value.compilerIntegrity,/^sha512-/);
  assert.deepEqual(finished.result.value.emittedFiles,[path.join('dist','source.js')]);
  assert.match(await fs.readFile(path.join(root,'dist','source.js'),'utf8'),/projectNonce = 317/);
});

test('compiler diagnostics are preserved with actual failing exit and no emitted JavaScript',async t=>{
  const {root,jobs}=await fixture(t),id=randomUUID();
  await jobs.start({executionID:id,workspace:root,moduleKind:'esm',source:compilerSource(root,id,{
    source:'export const invalidValue: string = 17;',tsconfig:{compilerOptions:{types:[],skipLibCheck:true}}})});
  const finished=await jobs.wait(id);
  assert.equal(finished.result.exitCode,1);
  assert.equal(finished.result.value.succeeded,false);
  assert.equal(finished.result.value.javaScript,null);
  assert.ok(finished.result.value.diagnostics.some(item=>item.code===2322));
  assert.deepEqual(JSON.parse(await fs.readFile(finished.result.outputFiles.stdout.path)),finished.result.value);
});

test('virtual source does not replace an installed dependency with the same basename',async t=>{
  const {root,jobs}=await fixture(t),id=randomUUID();
  const dependency=path.join(root,'packages','node-global','node_modules','fixture');
  await fs.mkdir(dependency,{recursive:true});
  await fs.writeFile(path.join(dependency,'package.json'),JSON.stringify({name:'fixture',version:'1.0.0',types:'main.ts'}));
  await fs.writeFile(path.join(dependency,'main.ts'),'export const dependencyValue: number = 17;');
  await jobs.start({executionID:id,workspace:root,moduleKind:'esm',source:compilerSource(root,id,{
    source:"import {dependencyValue} from 'fixture'; export const result: number = dependencyValue;",fileName:'main.ts',
    tsconfig:{compilerOptions:{types:[],skipLibCheck:true}}})});
  const finished=await jobs.wait(id);
  assert.equal(finished.result.value.succeeded,true,JSON.stringify(finished.result.value.diagnostics));
  assert.match(finished.result.value.javaScript,/export const result/);
  assert.equal(await fs.readFile(path.join(dependency,'main.ts'),'utf8'),'export const dependencyValue: number = 17;');
});

test('actual compiler job cancellation retains entered Worker output and does not block another job',async t=>{
  const {root,jobs}=await fixture(t),id=randomUUID();
  const body={source:'/*'+'actual compiler cancellation '.repeat(600_000)+'*/\nexport const value: number = 17;',
    tsconfig:{compilerOptions:{types:[],skipLibCheck:true}}};
  await jobs.start({executionID:id,workspace:root,moduleKind:'esm',
    source:"console.log('compiler worker entered');\n"+compilerSource(root,id,body)});
  const deadline=performance.now()+15000;
  while(!jobs.snapshot(id).stdoutBytes){
    assert.ok(performance.now()<deadline,'The actual compiler job never entered its Worker');
    await new Promise(resolve=>setTimeout(resolve,10));
  }
  await jobs.cancel(id);
  const cancelled=await jobs.wait(id);
  assert.equal(cancelled.state,'cancelled');
  assert.equal(cancelled.result.wasCancelled,true);
  assert.match(await fs.readFile(cancelled.result.outputFiles.stdout.path,'utf8'),/compiler worker entered/);
  const next=await jobs.start({workspace:root,moduleKind:'esm',source:'export default 19;'});
  assert.equal((await jobs.wait(next.executionID)).result.value,19);
});
