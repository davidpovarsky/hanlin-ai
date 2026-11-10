import test from 'node:test';
import assert from 'node:assert/strict';
import {spawn} from 'node:child_process';
import {once} from 'node:events';
import {promises as fs} from 'node:fs';
import {randomUUID,createHash} from 'node:crypto';
import {fileURLToPath} from 'node:url';
import path from 'node:path';
import os from 'node:os';
import {MCPLineFrames} from '../mcp-framing.mjs';

async function hostFixture(t,source) {
  const root=await fs.mkdtemp(path.join(os.tmpdir(),'hanlin-mcp-transport-')),id=randomUUID(),token=randomUUID();
  t.after(()=>fs.rm(root,{recursive:true,force:true}));
  const packageRoot=path.join(root,'packages','mcp',id),entryPoint=path.join(packageRoot,'server.mjs');
  await fs.mkdir(packageRoot,{recursive:true});
  await fs.writeFile(path.join(packageRoot,'package.json'),JSON.stringify({name:'transport-fixture',version:'1.0.0',type:'module'}));
  await fs.writeFile(entryPoint,source);
  const ready=path.join(root,'ready.json');
  const child=spawn(process.execPath,['--jitless',fileURLToPath(new URL('../host.mjs',import.meta.url)),root,ready,token,path.join(root,'host.log'),'0'],{stdio:['ignore','ignore','pipe']});
  let diagnostics='';child.stderr.on('data',chunk=>diagnostics+=chunk);
  t.after(async()=>{if(child.exitCode===null&&child.signalCode===null){child.kill();await once(child,'exit');}});
  let port;const deadline=performance.now()+15000;
  while(!port){
    assert.ok(performance.now()<deadline,diagnostics);assert.equal(child.exitCode,null,diagnostics);
    try{port=JSON.parse(await fs.readFile(ready,'utf8')).port;}catch(error){if(error.code!=='ENOENT')throw error;}
    if(!port)await new Promise(resolve=>setTimeout(resolve,10));
  }
  const request=(route,body,signal=AbortSignal.timeout(20000))=>fetch(`http://127.0.0.1:${port}${route}`,{
    method:body?'POST':'GET',headers:{Authorization:`Bearer ${token}`,'Content-Type':'application/json'},
    body:body?JSON.stringify(body):undefined,signal});
  const post=async(route,body)=>{const response=await request(route,body);assert.equal(response.status,200,await response.clone().text());return response.json();};
  const wait=async executionID=>{
    let job;const until=performance.now()+20000;
    do{assert.ok(performance.now()<until,'Actual operation did not settle');job=await (await request('/v1/executions/'+executionID)).json();
      if(!['completed','failed','cancelled','interrupted'].includes(job.state))await new Promise(resolve=>setTimeout(resolve,10));else return job;
    }while(true);
  };
  const owned=async(body)=>{
    const executionID=randomUUID();body={...body,executionID,detached:true};
    const bytes=Buffer.from(JSON.stringify(body)),inbox=path.join(root,'runtime','node','requests');await fs.mkdir(inbox,{recursive:true});
    await fs.writeFile(path.join(inbox,executionID+'.json'),bytes,{flag:'wx'});
    return {executionID,detached:true,inputArtifact:{bytes:bytes.length,sha256:createHash('sha256').update(bytes).digest('hex')}};
  };
  return {root,id,request,post,wait,owned,configuration:{serverID:id,packageRoot,entryPoint,arguments:[],environment:{}}};
}

test('real MCP HTTP transport retains >eight-MiB disconnected frames, accepts owned >ten-MiB input, and binds generation',async t=>{
  const f=await hostFixture(t,`
    import {createInterface} from 'node:readline';
    // Multiple complete frames must survive before the event observer attaches.
    process.stdout.write(JSON.stringify({id:'first',text:'שלום'.repeat(900000)})+'\\n');
    process.stdout.write(JSON.stringify({id:'second',text:'😀'.repeat(2300000)})+'\\n');
    createInterface({input:process.stdin}).on('line',line=>{
      const request=JSON.parse(line);process.stdout.write(JSON.stringify({id:request.id,result:request.payload})+'\\n');
    });
  `);
  const control=await f.owned({...f.configuration,arguments:['x'.repeat(11*1024*1024)]});
  const operation=await f.post(`/v1/servers/${f.id}/start`,control),started=await f.wait(operation.executionID);
  assert.equal(started.state,'completed',JSON.stringify(started));
  const generation=started.result.value.generation;
  // Observe actual transport spool production, not a fixed sleep or fake queue.
  const spoolRoot=path.join(f.root,'staging','tmp'),until=performance.now()+15000;
  while(true){
    const files=await fs.readdir(spoolRoot),spool=files.find(name=>name.startsWith('mcp-output-'));
    if(spool&&(await fs.stat(path.join(spoolRoot,spool))).size>20*1024*1024)break;
    assert.ok(performance.now()<until,'Actual disconnected frames were not spooled');await new Promise(resolve=>setTimeout(resolve,20));
  }
  const abort=new AbortController();t.after(()=>abort.abort());
  const response=await f.request(`/v1/servers/${f.id}/events?generation=${generation}`,undefined,abort.signal);
  const pending=[],frames=new MCPLineFrames();let waiter;
  const reading=(async()=>{for await(const chunk of response.body)for(const bytes of frames.push(Buffer.from(chunk))){
    const event=JSON.parse(bytes);if(event.channel==='stdout'){pending.push(JSON.parse(Buffer.from(event.data,'base64')));waiter?.();}
  }})();reading.catch(()=>{});
  const next=async()=>{while(!pending.length)await new Promise(resolve=>{waiter=resolve;});return pending.shift();};
  assert.deepEqual(await next(),{id:'first',text:'שלום'.repeat(900000)});
  assert.deepEqual(await next(),{id:'second',text:'😀'.repeat(2300000)});
  const payload='שלום 😀'.repeat(1000000),message=Buffer.from(JSON.stringify({id:randomUUID(),payload})+'\n');
  const input=await f.owned({data:message.toString('base64'),generation});
  assert.ok(input.inputArtifact.bytes>10*1024*1024);
  const delivered=await f.post(`/v1/servers/${f.id}/stdin`,input),receipt=await f.wait(delivered.executionID);
  assert.equal(receipt.state,'completed',JSON.stringify(receipt));assert.equal(receipt.result.value.accepted,message.length);
  const returned=await next();assert.equal(returned.result,payload);
  await f.post(`/v1/servers/${f.id}/stop`,{generation});abort.abort();await reading.catch(()=>{});
  const restarted=await f.post(`/v1/servers/${f.id}/start`,f.configuration);
  assert.ok(restarted.generation>generation);
  for(const action of ['stdin','stop']){
    const stale=await f.request(`/v1/servers/${f.id}/${action}`,{generation,data:Buffer.from('{}\n').toString('base64')});
    assert.equal(stale.status,409);await stale.text();
  }
  await f.post(`/v1/servers/${f.id}/stop`,{generation:restarted.generation});
});

test('cancelling an actual pending MCP startup settles the managed job and permits a clean later generation',async t=>{
  const f=await hostFixture(t,"await new Promise(resolve=>setTimeout(resolve,60000)); export {};"),executionID=randomUUID();
  await f.post(`/v1/servers/${f.id}/start`,{...f.configuration,executionID,detached:true});
  const until=performance.now()+10000;
  while(true){const runtime=await (await f.request('/v1/runtime')).json();if(runtime.workers.some(worker=>worker.id===f.id))break;
    assert.ok(performance.now()<until);await new Promise(resolve=>setTimeout(resolve,10));}
  await f.post(`/v1/executions/${executionID}/cancel`,{});
  const cancelled=await f.wait(executionID);assert.equal(cancelled.state,'cancelled');
  assert.equal((await (await f.request('/v1/runtime')).json()).workers.length,0);
  await fs.writeFile(f.configuration.entryPoint,"process.stdin.resume();");
  const restarted=await f.post(`/v1/servers/${f.id}/start`,f.configuration);
  assert.equal(restarted.state,'running');await f.post(`/v1/servers/${f.id}/stop`,{generation:restarted.generation});
});
