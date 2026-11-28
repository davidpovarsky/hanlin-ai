import test from 'node:test';
import assert from 'node:assert/strict';
import {promises as fs} from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import {runMCPRuntimeProbe} from '../runtime-probe.mjs';
import {installPackage} from '../package-installer.mjs';
import {c as createTar} from 'tar';
import {randomUUID} from 'node:crypto';

async function fixture(t,descriptionBytes) {
  const root=await fs.mkdtemp(path.join(os.tmpdir(),'hanlin-mcp-probe-output-'));
  t.after(()=>fs.rm(root,{recursive:true,force:true}));
  await fs.writeFile(path.join(root,'package.json'),JSON.stringify({name:'large-protocol-fixture',version:'1.0.0',type:'module'}));
  await fs.writeFile(path.join(root,'server.mjs'),`
    import {createInterface} from 'node:readline';
    createInterface({input:process.stdin}).on('line',line=>{
      const request=JSON.parse(line);let result;
      if(request.method==='initialize')result={protocolVersion:request.params.protocolVersion,capabilities:{tools:{}},serverInfo:{name:'large-tools',version:'1'}};
      if(request.method==='tools/list')result={tools:[{name:'actual_large_schema',description:'d'.repeat(${descriptionBytes}),inputSchema:{type:'object'}}]};
      if(result)process.stdout.write(JSON.stringify({jsonrpc:'2.0',id:request.id,result})+'\\n');
    });
  `);
  return {packageRoot:root,entryPoint:path.join(root,'server.mjs'),workspace:path.join(root,'work'),moduleKind:'esm'};
}

test('actual MCP tools/list above the former one-MiB probe cap passes by default',async t=>{
  const options=await fixture(t,2*1024*1024);
  const result=await runMCPRuntimeProbe({...options,timeoutMilliseconds:5000});
  assert.equal(result.passed,true,result.message);
  assert.equal(result.toolCount,1);
});

test('ordinary installation probes a real >one-MiB schema after the former thirty-second deadline and journals exact output',async t=>{
  const options=await fixture(t,2*1024*1024);
  const file=options.entryPoint;
  await fs.writeFile(file,"await new Promise(resolve=>setTimeout(resolve,31_000));\n"+await fs.readFile(file,'utf8'));
  const manifest={name:'large-protocol-fixture',version:'1.0.0',type:'module',bin:{fixture:'server.mjs'}};
  await fs.writeFile(path.join(options.packageRoot,'package.json'),JSON.stringify(manifest));
  const archive=path.join(options.packageRoot,'fixture.tgz');
  const packageDirectory=path.join(options.packageRoot,'package');await fs.mkdir(packageDirectory);
  for(const name of ['package.json','server.mjs'])await fs.copyFile(path.join(options.packageRoot,name),path.join(packageDirectory,name));
  await createTar({gzip:true,cwd:options.packageRoot,file:archive},['package']);
  const output=[];
  const descriptor=await installPackage({root:path.join(options.packageRoot,'runtime'),operationID:randomUUID(),serverID:randomUUID(),
    source:{kind:'file',path:archive},signal:new AbortController().signal,
    emit:async(channel,value)=>{if(value.probeOutput)output.push(Buffer.from(value.probeOutput.base64,'base64'));}});
  assert.equal(descriptor.compatibility.runtimeProbePassed,true);
  assert.ok(Buffer.concat(output).includes(Buffer.from('d'.repeat(2*1024*1024))));
});

test('a stopped probe cancels its actual Worker without waiting for a protocol timeout',async t=>{
  const options=await fixture(t,1),controller=new AbortController();
  await fs.writeFile(options.entryPoint,"setInterval(()=>{},1000);\nawait new Promise(()=>{});");
  const started=performance.now(),timer=setTimeout(()=>controller.abort(new Error('actual owner stopped')),150);
  t.after(()=>clearTimeout(timer));
  await assert.rejects(runMCPRuntimeProbe({...options,signal:controller.signal}),/actual owner stopped/);
  assert.ok(performance.now()-started<5000);
});

test('exit zero without a protocol response fails promptly instead of waiting forever',async t=>{
  const options=await fixture(t,1);
  await fs.writeFile(options.entryPoint,"process.exit(0);");
  const result=await runMCPRuntimeProbe(options);
  assert.equal(result.passed,false);assert.match(result.message,/exited.*code 0/);
});

test('complete protocol reply immediately followed by exit zero remains a valid probe',async t=>{
  const options=await fixture(t,1);
  await fs.writeFile(options.entryPoint,(await fs.readFile(options.entryPoint,'utf8'))
    .replace("+'\\n');","+'\\n',()=>{if(request.method==='tools/list')process.exit(0);});"));
  const result=await runMCPRuntimeProbe(options);
  assert.equal(result.passed,true,result.message);
});

test('a caller-selected probe byte budget is honored without a hidden minimum',async t=>{
  const options=await fixture(t,2048);
  const result=await runMCPRuntimeProbe({...options,maximumOutputBytes:1024,timeoutMilliseconds:5000});
  assert.equal(result.passed,false,'The explicit1KiB budget must not be clamped to4KiB');
  assert.match(result.message,/output.*(budget|limit)/i);
});
