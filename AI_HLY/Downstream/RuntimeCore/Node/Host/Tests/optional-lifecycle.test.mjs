import test from 'node:test';
import assert from 'node:assert/strict';
import {promises as fs} from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import http from 'node:http';
import {createHash} from 'node:crypto';
import {c as tar} from 'tar';
import Arborist from '@npmcli/arborist';
import {ExecutionJobs} from '../execution-jobs.mjs';
import {planLifecycle,planLifecycleTree,lifecycleFingerprint,verifyLifecyclePlan} from '../lifecycle-planner.mjs';
import {executeLifecycleInJobs} from '../lifecycle-executor.mjs';
import {pruneOptionalLifecycleFailure,prepareOptionalBuildRetry} from '../optional-lifecycle.mjs';
import {prepareGlobalTransaction,saveGlobalTransaction,loadGlobalTransaction} from '../global-package-state.mjs';
import {stageGlobalPackage,commitGlobalPackage} from '../global-package-manager.mjs';

async function fixture(t) {
  const runtimeRoot=await fs.mkdtemp(path.join(os.tmpdir(),'hanlin-optional-build-'));
  t.after(()=>fs.rm(runtimeRoot,{recursive:true,force:true}));
  const transaction=await prepareGlobalTransaction(runtimeRoot);
  const root=transaction.directory;
  const jobs=new ExecutionJobs({root:path.join(runtimeRoot,'jobs'),workerURL:new URL('../execution-worker.mjs',import.meta.url)});
  await jobs.initialize();
  return {runtimeRoot,transaction,root,jobs};
}
async function writePackage(directory,manifest) {
  await fs.mkdir(directory,{recursive:true});await fs.writeFile(path.join(directory,'package.json'),JSON.stringify(manifest));
  await fs.writeFile(path.join(directory,'index.cjs'),'module.exports=42;');
}
async function graphFixture(t,{mandatoryFailure=false,invalidOptionalSyntax=false}={}) {
  const value=await fixture(t),{root,runtimeRoot,transaction}=value;
  await writePackage(root,{name:'root-fixture',version:'1.0.0',dependencies:{required:'1.0.0',shared:'1.0.0'},optionalDependencies:{addon:'1.0.0'}});
  const definitions=[
    {name:'addon',dependencies:{bad:'1.0.0',unique:'1.0.0',shared:'1.0.0'},scripts:{preinstall:'echo addon-pre > pre.txt',postinstall:'echo must-not-run > post.txt'}},
    {name:'bad',dependencies:{unique:'1.0.0'},scripts:{install:invalidOptionalSyntax?"echo 'unterminated":'echo actual-partial-error && false',postinstall:'echo must-not-run > post.txt'},bin:{'bad-command':'index.cjs'}},
    {name:'unique',dependencies:{bad:'1.0.0'},scripts:{postinstall:'echo must-not-run > post.txt'}},
    {name:'required',scripts:{install:mandatoryFailure?'false':'echo required-ok > built.txt'}},
    {name:'shared',scripts:{postinstall:'echo shared-ok > built.txt'},bin:{'shared-command':'index.cjs'}},
  ];
  const packages={'':JSON.parse(await fs.readFile(path.join(root,'package.json'),'utf8'))};
  for(const definition of definitions) {
    const manifest={version:'1.0.0',...definition};
    await writePackage(path.join(root,'node_modules',definition.name),manifest);
    packages['node_modules/'+definition.name]=manifest;
  }
  await fs.writeFile(path.join(root,'package-lock.json'),JSON.stringify({lockfileVersion:3,packages}));
  const arborist=new Arborist({path:root,ignoreScripts:true,binLinks:true});
  const tree=await arborist.loadActual();await arborist.rebuild();
  const plan=await planLifecycleTree(tree);
  await saveGlobalTransaction(runtimeRoot,{...transaction,plan});
  return {...value,plan};
}

test('actual optional failure prunes its required ancestor and cyclic private deps, preserving required/shared builds and journals',async t=>{
  const {root,runtimeRoot,transaction,jobs,plan}=await graphFixture(t);
  assert.equal(plan.actions.find(item=>item.packageName==='bad').optional,true);
  const progress=[];
  await executeLifecycleInJobs({jobs,plan,packageRoot:root,runtimeRoot,onProgress:item=>progress.push(item)});
  const omitted=progress.find(item=>item.optionalDependencyOmitted);
  assert.ok(omitted);
  assert.deepEqual(new Set(omitted.omittedDirectories),new Set(['node_modules/addon','node_modules/bad','node_modules/unique']));
  for(const name of ['addon','bad','unique'])await assert.rejects(fs.access(path.join(root,'node_modules',name)),error=>error.code==='ENOENT');
  for(const name of ['required','shared'])assert.match(await fs.readFile(path.join(root,'node_modules',name,'built.txt'),'utf8'),/ok/);
  await fs.access(path.join(root,'node_modules/.bin/shared-command'));
  for(const suffix of ['', '.cmd', '.ps1'])await assert.rejects(fs.lstat(path.join(root,'node_modules/.bin/bad-command'+suffix)),error=>error.code==='ENOENT');
  const journal=await jobs.wait(omitted.executionID);
  assert.equal(journal.state,'failed');assert.equal(journal.result.exitCode,1);assert.match(journal.result.stdout,/actual-partial-error/);
  const current=await loadGlobalTransaction(runtimeRoot,transaction.transactionID);
  assert.ok(current.plan.actions.every(item=>!omitted.omittedDirectories.includes(item.workingDirectory)));
  await verifyLifecyclePlan(root,current.plan);
  await commitGlobalPackage({root:runtimeRoot,transactionID:transaction.transactionID});
  const receipt=JSON.parse(await fs.readFile(path.join(root,'.hanlin-optional-build-failures.json'),'utf8'));
  assert.equal(receipt.failures[0].executionID,omitted.executionID);
  const retry=await prepareGlobalTransaction(runtimeRoot),previous=JSON.parse(await fs.readFile(path.join(retry.directory,'package-lock.json'),'utf8')).packages;
  await prepareOptionalBuildRetry(retry.directory,previous);
  assert.equal(previous['node_modules/bad'],undefined);
  assert.ok(previous['node_modules/shared']);
  // A retained published generation cannot be changed by a later omission.
  await assert.rejects(pruneOptionalLifecycleFailure({runtimeRoot,packageRoot:root,plan,action:plan.actions.find(item=>item.packageName==='bad'),error:new Error('late')}),/published/);
  assert.match(await fs.readFile(path.join(root,'node_modules/shared/built.txt'),'utf8'),/shared-ok/);
});

test('required failures and forged optional flags cannot erase required packages',async t=>{
  const {root,runtimeRoot,plan,jobs,transaction}=await graphFixture(t,{mandatoryFailure:true});
  const required=plan.actions.find(item=>item.packageName==='required');
  const forged=structuredClone(plan);
  forged.actions=forged.actions.map(item=>item.packageName==='required'?{...item,optional:true}:item);
  forged.scriptHash=lifecycleFingerprint(forged);
  await saveGlobalTransaction(runtimeRoot,{...transaction,plan:forged});
  await assert.rejects(pruneOptionalLifecycleFailure({runtimeRoot,packageRoot:root,plan:forged,action:forged.actions.find(item=>item.packageName==='required'),error:new Error('forged')}),/actual optional dependency/);
  assert.equal(required.optional,false);
  await saveGlobalTransaction(runtimeRoot,{...transaction,plan});
  await assert.rejects(executeLifecycleInJobs({jobs,plan,packageRoot:root,runtimeRoot}),/required:install failed/);
  await fs.access(path.join(root,'node_modules/required/package.json'));
});

test('aborted optional work never becomes an optional success or omission',async t=>{
  const {root,runtimeRoot,plan,jobs}=await graphFixture(t);
  const controller=new AbortController();controller.abort(new Error('actual owner cancellation'));
  await assert.rejects(executeLifecycleInJobs({jobs,plan,packageRoot:root,runtimeRoot,signal:controller.signal}),/actual owner cancellation/);
  await fs.access(path.join(root,'node_modules/bad/package.json'));
  await assert.rejects(fs.access(path.join(root,'.hanlin-optional-build-failures.json')),error=>error.code==='ENOENT');
});

test('malformed optional shell syntax is a real journaled build failure, while required syntax remains rejected',async t=>{
  assert.equal(planLifecycle({name:'required-syntax',version:'1.0.0',scripts:{install:"echo 'unterminated"}}).executable,false);
  const {root,runtimeRoot,plan,jobs}=await graphFixture(t,{invalidOptionalSyntax:true});
  assert.equal(plan.executable,true);assert.equal(plan.rejected.length,0);
  const progress=[];
  await executeLifecycleInJobs({jobs,plan,packageRoot:root,runtimeRoot,onProgress:item=>progress.push(item)});
  const omission=progress.find(item=>item.optionalDependencyOmitted);
  assert.ok(omission);
  const failed=await jobs.wait(omission.executionID);
  assert.equal(failed.state,'failed');assert.notEqual(failed.result.exitCode,0);
  assert.match(failed.result.stderr,/SyntaxError|syntax|Expected|Parse error/);
  assert.match(await fs.readFile(path.join(root,'node_modules/required/built.txt'),'utf8'),/required-ok/);
});

test('actual registry reify retries previously omitted hooks after an unrelated root version update',async t=>{
  const {runtimeRoot,jobs}=await fixture(t),archives=new Map(),manifests=new Map();
  const server=http.createServer((request,response)=>{
    if(archives.has(request.url)){response.end(archives.get(request.url));return;}
    const versions=manifests.get(decodeURIComponent(request.url.slice(1)));
    if(!versions){response.statusCode=404;response.end();return;}
    response.setHeader('content-type','application/json');response.end(JSON.stringify({'dist-tags':{latest:Object.keys(versions).at(-1)},versions}));
  });
  await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
  t.after(()=>new Promise(resolve=>{server.closeAllConnections();server.close(resolve);}));
  const registry=`http://127.0.0.1:${server.address().port}`;
  for(const [name,version,optionalDependencies,scripts] of [
    ['retry-root','1.0.0',{'retry-optional':'1.0.0'},{}],['retry-root','2.0.0',{'retry-optional':'1.0.0'},{}],
    ['retry-optional','1.0.0',{}, {install:'echo actual-registry-optional-failure && false'}],
  ]) {
    const directory=path.join(runtimeRoot,`${name}-${version}`,'package'),manifest={name,version,optionalDependencies,scripts,main:'index.cjs'};
    await writePackage(directory,manifest);
    const archive=path.join(runtimeRoot,`${name}-${version}.tgz`);
    await tar({gzip:true,cwd:path.dirname(directory),file:archive},['package']);
    const bytes=await fs.readFile(archive),url=`/${name}/-/${name}-${version}.tgz`;
    archives.set(url,bytes);const versions=manifests.get(name)??{};
    versions[version]={...manifest,dist:{tarball:registry+url,integrity:'sha512-'+createHash('sha512').update(bytes).digest('base64')}};manifests.set(name,versions);
  }
  const generations=[];
  for(const version of ['1.0.0','2.0.0']) {
    const staged=await stageGlobalPackage({root:runtimeRoot,name:'retry-root',version,registry});
    assert.equal(staged.package.lifecycle.actions.filter(item=>item.packageName==='retry-optional').length,1);
    const progress=[];
    await executeLifecycleInJobs({jobs,plan:staged.package.lifecycle,packageRoot:staged.packageRoot,runtimeRoot,onProgress:item=>progress.push(item)});
    assert.equal(progress.filter(item=>item.optionalDependencyOmitted).length,1);
    await commitGlobalPackage({root:runtimeRoot,transactionID:staged.transactionID});
    await assert.rejects(fs.access(path.join(staged.packageRoot,'node_modules/retry-optional')),error=>error.code==='ENOENT');
    generations.push(staged.packageRoot);
  }
  assert.notEqual(generations[0],generations[1]);
  assert.equal(JSON.parse(await fs.readFile(path.join(generations[0],'node_modules/retry-root/package.json'),'utf8')).version,'1.0.0');
});
