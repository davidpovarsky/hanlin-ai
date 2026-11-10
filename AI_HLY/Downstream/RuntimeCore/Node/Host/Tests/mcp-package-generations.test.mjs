import test from 'node:test';
import assert from 'node:assert/strict';
import {promises as fs} from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import {randomUUID} from 'node:crypto';
import {Worker} from 'node:worker_threads';
import {once} from 'node:events';
import {publishMCPGeneration, finishMCPGeneration, resolveMCPPackageRoot} from '../mcp-package-generations.mjs';

test('MCP generations retain actual late Worker imports across commit, rollback and process-style reopen', async t => {
  const root = await fs.mkdtemp(path.join(os.tmpdir(), 'hanlin-mcp-generations-'));
  t.after(() => fs.rm(root, {recursive:true,force:true}));
  const serverID = randomUUID();
  const legacy = path.join(root,'packages','mcp',serverID);
  await fs.mkdir(legacy,{recursive:true});
  await fs.writeFile(path.join(legacy,'late.mjs'),'export default "legacy";');
  const worker = new Worker(`const {parentPort,workerData}=require('node:worker_threads');
    const {pathToFileURL}=require('node:url');
    parentPort.on('message', async file => {
      try {parentPort.postMessage({value:(await import(pathToFileURL(file).href)).default});}
      catch(error){parentPort.postMessage({error:error.message});}
    });parentPort.postMessage({ready:true});`,{eval:true});
  t.after(() => worker.terminate());
  assert.deepEqual((await once(worker,'message'))[0],{ready:true});
  const publish = async version => {
    const packageRoot = path.join(root,'stage-'+randomUUID());
    await fs.mkdir(packageRoot);
    await fs.writeFile(path.join(packageRoot,'late.mjs'),`export default ${JSON.stringify(version)};`);
    const operationID = randomUUID();
    const directory = await publishMCPGeneration({root,serverID,operationID,packageRoot});
    return {root,serverID,operationID,directory};
  };
  const first = await publish('first');
  await finishMCPGeneration({...first,state:'committed'});
  const second = await publish('second');
  await finishMCPGeneration({...second,state:'rolledBack'});
  await finishMCPGeneration({...second,state:'rolledBack'}); // idempotent retry
  await assert.rejects(finishMCPGeneration({...first,state:'rolledBack'}),/terminal state/);
  await assert.rejects(finishMCPGeneration({...first,serverID:randomUUID(),state:'rolledBack'}),{code:'ENOENT'});
  await assert.rejects(resolveMCPPackageRoot(root,serverID,second.directory),/rolled back/);
  assert.equal(await resolveMCPPackageRoot(root,serverID,first.directory),await fs.realpath(first.directory));
  assert.equal(await resolveMCPPackageRoot(root,serverID,legacy),await fs.realpath(legacy));
  for (const [directory,value] of [[legacy,'legacy'],[first.directory,'first'],[second.directory,'second']]) {
    const result = once(worker,'message');
    worker.postMessage(path.join(directory,'late.mjs'));
    assert.deepEqual((await result)[0],{value});
  }
  const alias = root+'-alias';
  await fs.symlink(root,alias,process.platform==='win32'?'junction':'dir');
  t.after(() => fs.unlink(alias));
  assert.equal(await resolveMCPPackageRoot(alias,serverID,first.directory),await fs.realpath(first.directory));
  await assert.rejects(resolveMCPPackageRoot(root,randomUUID(),first.directory));
  const reopened = await import(new URL('../mcp-package-generations.mjs?reopen='+randomUUID(),import.meta.url));
  assert.equal(await reopened.resolveMCPPackageRoot(root,serverID,first.directory),await fs.realpath(first.directory));
  await reopened.finishMCPGeneration({...first,state:'committed'});
});
