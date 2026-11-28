import test from 'node:test';
import assert from 'node:assert/strict';
import {promises as fs} from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import {randomUUID,createHash} from 'node:crypto';
import {ExecutionJobs} from '../execution-jobs.mjs';
import {runCommand,capabilities} from '../native-commands.mjs';
import {runtimeCapabilities} from '../runtime-capabilities.mjs';
import {Worker} from 'node:worker_threads';
import {once} from 'node:events';

for(const moduleKind of ['esm','commonjs']) {
  test(`explicit ${moduleKind} native command module executes a real CLI and retains complete binary streams`,async t=>{
    const root=await fs.mkdtemp(path.join(os.tmpdir(),'hanlin-native-command-api-'));
    t.after(()=>fs.rm(root,{recursive:true,force:true}));
    const jobs=new ExecutionJobs({root:path.join(root,'jobs'),workerURL:new URL('../execution-worker.mjs',import.meta.url)});
    await jobs.initialize();
    const input=Buffer.concat([Buffer.from('שלום\0🙂\n'),Buffer.alloc(12*1024*1024,0xa5)]);
    const nonce=randomUUID();
    await fs.writeFile(path.join(root,'input.bin'),input);
    await fs.writeFile(path.join(root,'real-cli.cjs'),`
      if(require.main!==module||process.argv[2]!=='עברית with spaces'||process.env.API_NONCE!==${JSON.stringify(nonce)})throw Error('Wrong real CLI contract');
      process.stdin.pipe(process.stdout);
      process.stdin.on('end',()=>{console.error('actual stderr '+process.env.API_NONCE);process.exitCode=23;});
    `);
    const body=`
      let invalidEnvironment=false;
      try{await runCommand('node',[],{env:{BAD:42}});}catch(error){invalidEnvironment=/NUL-free strings/.test(error.message);}
      if(!invalidEnvironment)throw Error('An invalid environment was executed or left an unowned port operation');
      const receipt=await runCommand('node',['real-cli.cjs','עברית with spaces'],{stdinFile:'input.bin',env:{...process.env,API_NONCE:${JSON.stringify(nonce)}}});
      const hash=createHash('sha256');let bytes=0;
      for await(const chunk of openOutput(receipt)){hash.update(chunk);bytes+=chunk.length;}
      return {receipt,bytes,sha256:hash.digest('hex'),capabilities:capabilities(),stderr:await fs.readFile(receipt.stderrPath,'utf8')};
    `;
    const source=moduleKind==='esm'
      ? `import {runCommand,openOutput,capabilities} from 'hanlin:runtime';import {createHash} from 'node:crypto';import {promises as fs} from 'node:fs';export default await (async()=>{${body}})();`
      : `const {runCommand,openOutput,capabilities}=require('hanlin:runtime');const {createHash}=require('node:crypto');const {promises:fs}=require('node:fs');module.exports=(async()=>{${body}})();`;
    const parent=await jobs.start({source,moduleKind,workspace:root});
    const deadline=performance.now()+20000;
    const owners=new Map();
    while(!jobs.snapshot(parent.executionID).completedAt) {
      assert.ok(performance.now()<deadline,'The real native-command API fixture did not finish');
      for(const command of await jobs.commandRequests(parent.executionID)) {
        if(owners.has(command.id))continue;
        owners.set(command.id,(async()=>{
          assert.equal(command.command,'node');
          const child=await jobs.start({executionID:command.id,executionMode:'cli',entryPoint:path.resolve(command.cwd,command.arguments[0]),
            workspace:command.cwd,moduleKind:'commonjs',arguments:command.arguments.slice(1),environment:command.environment,standardInputPath:command.standardInputPath});
          const ended=await jobs.wait(child.executionID);
          const response={executionID:child.executionID,exitCode:ended.result.exitCode,stdoutPath:ended.result.outputFiles.stdout.path,stderrPath:ended.result.outputFiles.stderr.path};
          const file=path.join(path.dirname(command.standardInputPath),'response.json');
          await fs.writeFile(file+'.tmp',JSON.stringify(response));await fs.rename(file+'.tmp',file);
        })());
      }
      await new Promise(resolve=>setTimeout(resolve,10));
    }
    await Promise.all(owners.values());
    const ended=await jobs.wait(parent.executionID);
    assert.equal(ended.state,'completed',JSON.stringify(ended));
    const result=ended.result.value;
    assert.equal(owners.size,1);
    assert.equal(result.receipt.exitCode,23);
    assert.equal(result.receipt.executionID,result.receipt.commandID);
    assert.equal(result.receipt.parentExecutionID,parent.executionID);
    assert.equal(result.bytes,input.length);
    assert.equal(result.sha256,createHash('sha256').update(input).digest('hex'));
    assert.equal(result.stderr,'actual stderr '+nonce+'\n');
    assert.equal(result.capabilities.finiteCommandsConnected,true);
    assert.equal(result.capabilities.pid,false);
    assert.equal(result.capabilities.ipc,false);
    assert.equal(result.capabilities.tty,false);
  });
}

test('an unattached context never fabricates an execution, PID or successful empty output',async()=>{
  assert.equal(capabilities().finiteCommandsConnected,false);
  await assert.rejects(runCommand('node',['script.cjs']),error=>error.code==='HANLIN_NATIVE_COMMAND_ADAPTER_UNAVAILABLE');
  await assert.rejects(runCommand('node',[],{signal:new AbortController().signal}),/Unsupported native-command option/);
  await assert.rejects(runCommand('node',['bad\0argument']),/NUL-free/);
  const report=runtimeCapabilities();
  assert.equal(report.targetProfile,'hanlin-ios-app');
  assert.equal(report.observed.node,process.versions.node);
  assert.equal(report.observed.platform,process.platform);
  assert.equal(report.externalExecution.configured,false);
  assert.equal(report.externalExecution.automaticTransfer,false);
  assert.equal(report.finiteCommandAdapter.persistentMCPServerConnected,false);
});

test('actual persistent MCP Worker can inspect the module but cannot inherit a chat command owner',async t=>{
  const root=await fs.mkdtemp(path.join(os.tmpdir(),'hanlin-mcp-native-command-scope-'));
  t.after(()=>fs.rm(root,{recursive:true,force:true}));
  const entry=path.join(root,'server.mjs');
  await fs.writeFile(path.join(root,'package.json'),JSON.stringify({name:'native-command-context-proof',version:'1.0.0',type:'module'}));
  await fs.writeFile(entry,`
    import {capabilities,runCommand} from 'hanlin:runtime';
    let errorCode;
    try{await runCommand('node',['must-not-run.cjs']);}catch(error){errorCode=error.code;}
    console.log('COMMAND_SCOPE '+JSON.stringify({capabilities:capabilities(),errorCode}));
  `);
  const worker=new Worker(new URL('../server-worker.mjs',import.meta.url),{
    workerData:{packageRoot:root,entryPoint:entry,arguments:[],environment:{}},stdin:true,stdout:true,stderr:true,
  });
  t.after(()=>worker.terminate());
  let output='',stderr='';
  worker.stdout.on('data',chunk=>output+=chunk);worker.stderr.on('data',chunk=>stderr+=chunk);
  const [exit]=await once(worker,'exit');
  assert.equal(exit,0,stderr);
  const line=output.split('\n').find(value=>value.startsWith('COMMAND_SCOPE '));
  assert.ok(line,output+'\n'+stderr);
  const result=JSON.parse(line.slice('COMMAND_SCOPE '.length));
  assert.equal(result.capabilities.finiteCommandsConnected,false);
  assert.equal(result.errorCode,'HANLIN_NATIVE_COMMAND_ADAPTER_UNAVAILABLE');
});
