import test from 'node:test';
import assert from 'node:assert/strict';
import {promises as fs} from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import {randomUUID} from 'node:crypto';
import {c as createTar} from 'tar';
import {ExecutionJobs} from '../execution-jobs.mjs';
import {executeLifecycleInJobs} from '../lifecycle-executor.mjs';
import {installPackage,commitInstall} from '../package-installer.mjs';

test('actual MCP installation executes lifecycle before initialize/tools-list and preserves the prior server after failure',async t=>{
  const root=await fs.mkdtemp(path.join(os.tmpdir(),'hanlin-mcp-hooks-'));
  t.after(()=>fs.rm(root,{recursive:true,force:true}));
  const directory=path.join(root,'source','package');
  await fs.mkdir(directory,{recursive:true});
  const manifest={name:'hanlin-mcp-hooks-fixture',version:'1.0.0',type:'module',bin:{fixture:'server.mjs'},scripts:{
    preinstall:'echo pre > order.txt',install:'echo install >> order.txt',
    postinstall:'echo READY > marker.txt && echo post >> order.txt',prepare:'false',
  }};
  await fs.writeFile(path.join(directory,'package.json'),JSON.stringify(manifest));
  await fs.writeFile(path.join(directory,'server.mjs'),`
    import {readFileSync} from 'node:fs';import {createInterface} from 'node:readline';
    if(readFileSync(new URL('./marker.txt',import.meta.url),'utf8')!=='READY\\n')throw Error('Lifecycle output is missing');
    createInterface({input:process.stdin}).on('line',line=>{
      const request=JSON.parse(line);let result;
      if(request.method==='initialize')result={protocolVersion:request.params.protocolVersion,capabilities:{tools:{}},serverInfo:{name:'hooks',version:'1.0.0'}};
      if(request.method==='tools/list')result={tools:[{name:'fixture',description:'Actual lifecycle fixture',inputSchema:{type:'object'}}]};
      if(result)process.stdout.write(JSON.stringify({jsonrpc:'2.0',id:request.id,result})+'\\n');
    });
  `);
  const archive=path.join(root,'fixture.tgz');
  const pack=()=>createTar({gzip:true,cwd:path.dirname(directory),file:archive},['package']);
  await pack();
  const jobs=new ExecutionJobs({root:path.join(root,'jobs'),workerURL:new URL('../execution-worker.mjs',import.meta.url)});
  await jobs.initialize();
  const serverID=randomUUID(),operationID=randomUUID();
  const options={root:path.join(root,'runtime'),serverID,source:{kind:'file',path:archive},signal:new AbortController().signal,emit:()=>{},
    executeLifecycle:options=>executeLifecycleInJobs({...options,jobs})};
  const descriptor=await installPackage({...options,operationID});
  assert.equal(descriptor.compatibility.runtimeProbePassed,true,JSON.stringify(descriptor.compatibility));
  const installed=path.dirname(descriptor.entryPoint);
  assert.equal(await fs.readFile(path.join(installed,'order.txt'),'utf8'),'pre\ninstall\npost\n');
  await commitInstall({root:options.root,serverID,operationID});
  manifest.version='2.0.0';
  await fs.writeFile(path.join(directory,'package.json'),JSON.stringify(manifest));await pack();
  const updatedID=randomUUID();
  const updated=await installPackage({...options,operationID:updatedID});
  assert.notEqual(updated.packageRoot,descriptor.packageRoot);
  assert.equal(updated.entryPoint,path.join(updated.packageRoot,'server.mjs'));
  await commitInstall({root:options.root,serverID,operationID:updatedID});
  assert.equal(JSON.parse(await fs.readFile(path.join(updated.packageRoot,'package.json'),'utf8')).version,'2.0.0');
  assert.equal(JSON.parse(await fs.readFile(path.join(installed,'package.json'),'utf8')).version,'1.0.0');
  manifest.version='3.0.0';manifest.scripts.postinstall='false';
  await fs.writeFile(path.join(directory,'package.json'),JSON.stringify(manifest));await pack();
  await assert.rejects(installPackage({...options,operationID:randomUUID()}),error=>error.code==='lifecycle_failed'&&error.exitCode===1);
  const retained=JSON.parse(await fs.readFile(path.join(installed,'package.json'),'utf8'));
  assert.equal(retained.version,'1.0.0');
  assert.equal(await fs.readFile(path.join(installed,'marker.txt'),'utf8'),'READY\n');
  assert.equal(JSON.parse(await fs.readFile(path.join(updated.packageRoot,'package.json'),'utf8')).version,'2.0.0');
});
