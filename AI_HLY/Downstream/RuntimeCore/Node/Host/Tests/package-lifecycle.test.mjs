import test from 'node:test';
import assert from 'node:assert/strict';
import {promises as fs} from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import http from 'node:http';
import {createHash} from 'node:crypto';
import {c as createTar} from 'tar';
import {ExecutionJobs} from '../execution-jobs.mjs';
import {stageGlobalPackage,commitGlobalPackage,rollbackGlobalPackage,listGlobalPackages,stageUninstallGlobalPackage} from '../global-package-manager.mjs';
import {executePortableShell} from '../portable-shell.mjs';
import Arborist from '@npmcli/arborist';
import {planLifecycle,planLifecycleTree,verifyLifecyclePlan,lifecycleFingerprint} from '../lifecycle-planner.mjs';
import {prepareGlobalTransaction,saveGlobalTransaction,publishGlobalTransaction,currentGlobalState,discardGlobalTransaction} from '../global-package-state.mjs';
import {packageLifecycleEnvironment} from '../portable-shell.mjs';

async function fixture(t) {
  const root=await fs.mkdtemp(path.join(os.tmpdir(),'hanlin-npm-lifecycle-'));
  t.after(()=>fs.rm(root,{recursive:true,force:true}));return root;
}
async function writePackage(directory,manifest) {
  await fs.mkdir(directory,{recursive:true});await fs.writeFile(path.join(directory,'package.json'),JSON.stringify(manifest));
}

test('actual Arborist tree plans dependency phases, root project phases and skips unchanged build products',async t=>{
  const root=await fixture(t);
  const rootScripts=Object.fromEntries(['preinstall','install','postinstall','prepublish','preprepare','prepare','postprepare'].map(name=>[name,`echo ${name}`]));
  await writePackage(root,{name:'project',version:'1.0.0',dependencies:{alpha:'1.0.0'},scripts:rootScripts});
  const alpha=path.join(root,'node_modules','alpha');
  await writePackage(alpha,{name:'alpha',version:'1.0.0',dependencies:{beta:'1.0.0'},scripts:{preinstall:'echo alpha-pre',install:'echo alpha-install',postinstall:'echo alpha-post',prepare:'echo not-registry-prepare'}});
  const beta=path.join(alpha,'node_modules','beta');
  await writePackage(beta,{name:'beta',version:'1.0.0',scripts:{preinstall:'echo beta-pre',postinstall:'echo beta-post'}});
  const packages={
    'node_modules/alpha':{version:'1.0.0',integrity:'sha512-alpha'},
    'node_modules/alpha/node_modules/beta':{version:'1.0.0',integrity:'sha512-beta'},
  };
  await fs.writeFile(path.join(root,'package-lock.json'),JSON.stringify({name:'project',version:'1.0.0',lockfileVersion:3,packages}));
  const tree=await new Arborist({path:root}).loadActual();
  const plan=await planLifecycleTree(tree,{includeRoot:true,rootContext:'project'});
  assert.deepEqual(plan.actions.map(item=>[item.packageName,item.script]),[
    ['alpha','preinstall'],['beta','preinstall'],['alpha','install'],['alpha','postinstall'],['beta','postinstall'],
    ...Object.keys(rootScripts).map(event=>['project',event]),
  ]);
  assert.deepEqual(await verifyLifecyclePlan(root,plan),{verified:true});
  const alias=path.join(root,'project-alias');
  await fs.symlink(root,alias,process.platform==='win32'?'junction':'dir');
  const linkedTree=await new Arborist({path:alias}).loadActual();
  assert.equal(linkedTree.isLink,true,'Exercise the real Arborist Link root used by macOS temporary-directory aliases');
  const linkedPlan=await planLifecycleTree(linkedTree);
  assert.deepEqual(linkedPlan.actions.map(item=>[item.packageName,item.script]),plan.actions.slice(0,5).map(item=>[item.packageName,item.script]));
  const unchanged=await planLifecycleTree(tree,{previousPackages:packages});
  assert.equal(unchanged.actions.length,0);
  const modified=structuredClone(plan);modified.actions[0].source='echo changed';
  await assert.rejects(verifyLifecyclePlan(root,modified),/identity changed/);
  modified.scriptHash=lifecycleFingerprint(modified);
  await assert.rejects(verifyLifecyclePlan(root,modified),/script changed/);
  await fs.writeFile(path.join(alpha,'package.json'),JSON.stringify({name:'alpha',version:'2.0.0'}));
  await assert.rejects(verifyLifecyclePlan(root,plan),/identity changed/);
});

test('immutable package generations preserve old files, reject conflicting commits and retain published generations',async t=>{
  const root=await fixture(t);
  const legacy=path.join(root,'packages','node-global');
  await writePackage(legacy,{name:'global',version:'1.0.0'});
  await fs.writeFile(path.join(legacy,'built.txt'),'old-built-product');
  const first=await prepareGlobalTransaction(root),second=await prepareGlobalTransaction(root);
  const plan=planLifecycle({name:'global',version:'1.0.0'});
  await saveGlobalTransaction(root,{...first,plan});await saveGlobalTransaction(root,{...second,plan});
  assert.equal(await fs.readFile(path.join(first.directory,'built.txt'),'utf8'),'old-built-product');
  await fs.writeFile(path.join(first.directory,'built.txt'),'new-built-product');
  await publishGlobalTransaction(root,first.transactionID);
  assert.deepEqual(await publishGlobalTransaction(root,first.transactionID),{committed:true});
  assert.equal((await currentGlobalState(root)).directory,first.directory);
  assert.equal(await fs.readFile(path.join(legacy,'built.txt'),'utf8'),'old-built-product');
  await assert.rejects(publishGlobalTransaction(root,second.transactionID),/changed while/);
  await discardGlobalTransaction(root,second.transactionID);
  await assert.rejects(discardGlobalTransaction(root,first.transactionID),/retained/);
  const third=await prepareGlobalTransaction(root);
  assert.equal(await fs.readFile(path.join(third.directory,'built.txt'),'utf8'),'new-built-product');
  await discardGlobalTransaction(root,third.transactionID);
  assert.equal(await fs.readFile(path.join(first.directory,'built.txt'),'utf8'),'new-built-product');
});

test('npm lifecycle environment retains user values and flattens RFC183 package metadata',async t=>{
  const root=await fixture(t);
  await writePackage(root,{name:'fixture',version:'1.2.3',config:{nested:{flag:false},values:['a','שלום'],nil:null},engines:{node:'>=24'},bin:{fixture:'./bin.cjs'},description:'not exported'});
  const env=await packageLifecycleEnvironment({cwd:root,environment:{PATH:'/custom/bin',CUSTOM:'value'},event:'postinstall',source:'echo done',initialCwd:'/initial'});
  assert.equal(env.npm_command,'install');assert.equal(env.npm_package_name,'fixture');assert.equal(env.INIT_CWD,'/initial');
  assert.equal(env.npm_package_config_nested_flag,'');assert.equal(env.npm_package_config_values_1,'שלום');
  assert.equal(env.npm_package_config_nil,'');assert.equal(env.npm_package_engines_node,'>=24');
  assert.equal(env.npm_package_bin_fixture,'./bin.cjs');assert.equal(env.npm_package_description,undefined);
  assert.equal(env.CUSTOM,'value');assert.ok(env.PATH.startsWith(path.join(root,'node_modules','.bin')+path.delimiter));
});

test('actual registry extraction and Arborist dependency hooks publish atomically and preserve unchanged builds',async t=>{
  const root=await fixture(t),runtime=path.join(root,'runtime');
  const archives=new Map(),manifests=new Map();
  const server=http.createServer((request,response)=>{
    const archive=archives.get(request.url);
    if(archive){response.end(archive);return;}
    const name=decodeURIComponent(request.url.slice(1));
    const versions=manifests.get(name);
    if(!versions){response.statusCode=404;response.end();return;}
    response.setHeader('content-type','application/json');
    response.end(JSON.stringify({name,'dist-tags':{latest:Object.keys(versions).at(-1)},versions}));
  });
  await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
  t.after(()=>new Promise(resolve=>{server.closeAllConnections();server.close(resolve);}));
  const registry=`http://127.0.0.1:${server.address().port}`;
  for(const [name,version,dependencies,optionalDependencies] of [
    ['hanlin-fixture-beta','1.0.0',{},{}],['hanlin-fixture-optional','1.0.0',{},{}],
    ['hanlin-fixture-alpha','1.0.0',{'hanlin-fixture-beta':'1.0.0'},{'hanlin-fixture-optional':'1.0.0'}],
    ['hanlin-fixture-alpha','2.0.0',{'hanlin-fixture-beta':'1.0.0'},{'hanlin-fixture-optional':'1.0.0'}],
    ['hanlin-fixture-alpha','3.0.0',{'hanlin-fixture-beta':'1.0.0'},{'hanlin-fixture-optional':'1.0.0'}],
  ]) {
    const directory=path.join(root,`${name}-${version}`,'package');
    const manifest={name,version,dependencies,optionalDependencies,main:'built.cjs',scripts:{
      preinstall:'node phase.cjs pre',install:"VALUE='שלום world' node phase.cjs build && echo installed > receipt.txt",postinstall:'node phase.cjs post',prepare:'node phase.cjs SHOULD_NOT_RUN',
    }};
    await writePackage(directory,manifest);
    await fs.writeFile(path.join(directory,'phase.cjs'),`
      const fs=require('node:fs');
      fs.appendFileSync(process.env.TRACK_FILE,JSON.stringify([process.env.npm_package_name,process.env.npm_lifecycle_event,process.argv[2]])+'\\n');
      if(process.argv[2]==='build'){
        if(process.env.npm_package_version==='3.0.0')process.exit(23);
        if(process.env.VALUE!=='שלום world')throw Error('quoting');
        fs.writeFileSync('built.cjs','module.exports='+JSON.stringify(process.env.npm_package_version));
      }
    `);
    const archivePath=path.join(root,`${name}-${version}.tgz`);
    await createTar({gzip:true,cwd:path.dirname(directory),file:archivePath},['package']);
    const archive=await fs.readFile(archivePath),url=`/${name}/-/${name}-${version}.tgz`;
    archives.set(url,archive);
    const versions=manifests.get(name)??{};
    versions[version]={...manifest,dist:{tarball:registry+url,integrity:'sha512-'+createHash('sha512').update(archive).digest('base64')}};
    manifests.set(name,versions);
  }
  const jobs=new ExecutionJobs({root:path.join(root,'jobs'),workerURL:new URL('../execution-worker.mjs',import.meta.url)});
  await jobs.initialize();
  const tracking=path.join(root,'actual-hooks.jsonl');
  const execute=async transaction=>{
    const plan=transaction.package.lifecycle;
    await verifyLifecyclePlan(transaction.packageRoot,plan);
    for(const action of plan.actions){
      const cwd=path.resolve(transaction.packageRoot,action.workingDirectory);
      const environment=await packageLifecycleEnvironment({cwd,environment:{...process.env,TRACK_FILE:tracking},event:action.script,source:action.source});
      const code=await executePortableShell(action.source,[],{cwd,environment,dispatch:async request=>{
        assert.equal(request.command,'node');
        const job=await jobs.start({executionMode:'cli',entryPoint:path.resolve(request.cwd,request.arguments[0]),arguments:request.arguments.slice(1),workspace:request.cwd,environment:request.environment,standardInputPath:undefined});
        const completed=await jobs.wait(job.executionID);
        request.stdout.write(completed.result.stdout);request.stderr.write(completed.result.stderr);
        return completed.result.exitCode;
      }});
      assert.equal(code,0);
    }
  };
  const first=await stageGlobalPackage({root:runtime,name:'hanlin-fixture-alpha',version:'1.0.0',registry});
  await assert.rejects(fs.access(tracking),error=>error.code==='ENOENT');
  assert.equal(first.package.lifecycle.actions.length,9,'optional dependency hooks must be included');
  await execute(first);await commitGlobalPackage({root:runtime,transactionID:first.transactionID});
  assert.equal((await listGlobalPackages({root:runtime}))[0].version,'1.0.0');
  const events=(await fs.readFile(tracking,'utf8')).trim().split('\n').map(JSON.parse);
  assert.deepEqual(events.map(item=>item[1]),['preinstall','preinstall','preinstall','install','install','install','postinstall','postinstall','postinstall']);
  const second=await stageGlobalPackage({root:runtime,name:'hanlin-fixture-alpha',version:'2.0.0',registry});
  assert.deepEqual(second.package.lifecycle.actions.map(item=>item.packageName),Array(3).fill('hanlin-fixture-alpha'));
  await execute(second);await commitGlobalPackage({root:runtime,transactionID:second.transactionID});
  assert.equal((await listGlobalPackages({root:runtime}))[0].version,'2.0.0');
  const failing=await stageGlobalPackage({root:runtime,name:'hanlin-fixture-alpha',version:'3.0.0',registry});
  await assert.rejects(execute(failing),error=>error.actual===23);
  await rollbackGlobalPackage({root:runtime,transactionID:failing.transactionID});
  assert.equal((await listGlobalPackages({root:runtime}))[0].version,'2.0.0');
  assert.match(await fs.readFile(path.join(second.packageRoot,'node_modules','hanlin-fixture-beta','built.cjs'),'utf8'),/1.0.0/);
  assert.match(await fs.readFile(path.join(first.packageRoot,'node_modules','hanlin-fixture-alpha','built.cjs'),'utf8'),/1.0.0/);
  const abandoned=await stageGlobalPackage({root:runtime,name:'hanlin-fixture-alpha',version:'1.0.0',registry});
  await rollbackGlobalPackage({root:runtime,transactionID:abandoned.transactionID});
  assert.equal((await listGlobalPackages({root:runtime}))[0].version,'2.0.0');
  const removed=await stageUninstallGlobalPackage({root:runtime,name:'hanlin-fixture-alpha'});
  assert.equal(removed.lifecycle.actions.length,0);
  await commitGlobalPackage({root:runtime,transactionID:removed.transactionID});
  assert.deepEqual(await listGlobalPackages({root:runtime}),[]);
});
