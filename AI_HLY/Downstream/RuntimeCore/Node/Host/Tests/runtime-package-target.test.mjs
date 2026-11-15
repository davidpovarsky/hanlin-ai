import test from 'node:test';
import assert from 'node:assert/strict';
import {promises as fs} from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import http from 'node:http';
import {createHash,randomUUID} from 'node:crypto';
import {createRequire} from 'node:module';
import {c as createTar} from 'tar';
import pacote from 'pacote';
import {inspectManifest} from '../package-compatibility.mjs';
import {previewGlobalPackage,stageGlobalPackage,commitGlobalPackage,listGlobalPackages} from '../global-package-manager.mjs';
import {previewPackage} from '../package-installer.mjs';

const unsupported = findings => findings.filter(finding => finding.severity === 'unsupported');

test('manifest compatibility uses the actual Node version, OS and architecture', () => {
  const manifest={engines:{node:'='+process.versions.node},os:[process.platform],cpu:[process.arch]};
  assert.deepEqual(unsupported(inspectManifest(manifest)),[]);
  const mismatch=inspectManifest({engines:{node:'>=999'}}).find(finding=>finding.code==='manifest_node_engine');
  assert.ok(mismatch.message.includes(process.versions.node),mismatch.message);
  assert.ok(inspectManifest({os:['!'+process.platform]}).some(finding=>finding.code==='manifest_os'));
  assert.ok(inspectManifest({cpu:['!'+process.arch]}).some(finding=>finding.code==='manifest_cpu'));
});

test('an iOS target is not substituted with Darwin and CPU constraints remain effective', () => {
  const target={platform:'ios',architecture:'arm64'};
  assert.deepEqual(unsupported(inspectManifest({os:['any'],cpu:['any']},'24.5.0',target)),[]);
  assert.deepEqual(unsupported(inspectManifest({os:['ios','!darwin'],cpu:['arm64']},'24.5.0',target)),[]);
  const rejected=inspectManifest({os:['darwin'],cpu:['x64']},'24.5.0',target);
  assert.ok(rejected.some(finding=>finding.code==='manifest_os'&&finding.message.includes('ios')));
  assert.ok(rejected.some(finding=>finding.code==='manifest_cpu'&&finding.message.includes('arm64')));
});

async function registryFixture(t, fileCount=0) {
  const root=await fs.mkdtemp(path.join(os.tmpdir(),'hanlin-live-package-target-'));
  t.after(()=>fs.rm(root,{recursive:true,force:true}));
  const name='hanlin-observed-target-fixture',version='1.0.0',nonce=randomUUID();
  const directory=path.join(root,'source','package');
  await fs.mkdir(directory,{recursive:true});
  const manifest={name,version,main:'index.cjs',engines:{node:'='+process.versions.node},os:[process.platform],cpu:[process.arch]};
  await fs.writeFile(path.join(directory,'package.json'),JSON.stringify(manifest));
  await fs.writeFile(path.join(directory,'index.cjs'),'module.exports='+JSON.stringify(nonce));
  for(let start=0;start<fileCount;start+=64) {
    await Promise.all(Array.from({length:Math.min(64,fileCount-start)},(_,offset)=>
      fs.writeFile(path.join(directory,'resource-'+(start+offset)+'.txt'),'')));
  }
  const archivePath=path.join(root,'fixture.tgz');
  await createTar({gzip:true,cwd:path.dirname(directory),file:archivePath},['package']);
  const archive=await fs.readFile(archivePath);
  let registry;
  const server=http.createServer((request,response)=>{
    if(request.url==='/fixture.tgz'){response.end(archive);return;}
    if(decodeURIComponent(request.url.slice(1))!==name){response.statusCode=404;response.end();return;}
    response.setHeader('content-type','application/json');
    response.end(JSON.stringify({name,'dist-tags':{latest:version},versions:{[version]:{...manifest,
      dist:{tarball:registry+'/fixture.tgz',integrity:'sha512-'+createHash('sha512').update(archive).digest('base64')}}}}));
  });
  await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
  t.after(()=>new Promise(resolve=>{server.closeAllConnections();server.close(resolve);}));
  registry='http://127.0.0.1:'+server.address().port;
  return {root,name,version,nonce,registry};
}

test('actual registry preview and global install use the running interpreter target', async t => {
  const fixture=await registryFixture(t),root=path.join(fixture.root,'runtime');
  const preview=await previewGlobalPackage({...fixture,root});
  assert.deepEqual(unsupported(preview.findings),[]);
  const staged=await stageGlobalPackage({...fixture,root});
  await commitGlobalPackage({root,transactionID:staged.transactionID});
  const installed=(await listGlobalPackages({root}))[0];
  assert.deepEqual(unsupported(installed.findings),[]);
  assert.equal(createRequire(import.meta.url)(installed.packageRoot),fixture.nonce);
});

test('MCP candidate selection uses the actual interpreter against supplied registry metadata', async t => {
  const root=await fs.mkdtemp(path.join(os.tmpdir(),'hanlin-mcp-target-selection-'));
  t.after(()=>fs.rm(root,{recursive:true,force:true}));
  const name='hanlin-mcp-target-fixture';
  const compatible={name,version:'1.0.0',main:'server.cjs',engines:{node:'='+process.versions.node},os:[process.platform],cpu:[process.arch]};
  const incompatible={...compatible,version:'2.0.0',engines:{node:'>=999'}};
  // Only registry metadata is supplied here; selection/semver/manifest code and
  // the interpreter identity are real. This is not an MCP protocol/import probe.
  t.mock.method(pacote,'packument',async requested=>{
    assert.equal(requested,name);
    return {'dist-tags':{latest:'2.0.0'},versions:{'1.0.0':compatible,'2.0.0':incompatible}};
  });
  for(const version of ['1.0.0',undefined]) {
    const preview=await previewPackage({kind:'npm',name,version},{root});
    assert.equal(preview.version,'1.0.0');
    assert.deepEqual(unsupported(preview.compatibility.findings),[]);
  }
  await assert.rejects(previewPackage({kind:'npm',name,version:'2.0.0'},{root}),
    error=>error.message.includes('requires Node >=999')&&error.message.includes(process.versions.node));
});

test('actual global installation retains and executes a package beyond fifty thousand files', async t => {
  const fixture=await registryFixture(t,50_010),root=path.join(fixture.root,'runtime');
  const staged=await stageGlobalPackage({...fixture,root});
  assert.deepEqual(unsupported(staged.package.findings),[]);
  await commitGlobalPackage({root,transactionID:staged.transactionID});
  const installed=(await listGlobalPackages({root}))[0];
  const entries=await fs.readdir(installed.packageRoot);
  assert.equal(entries.filter(name=>name.startsWith('resource-')).length,50_010);
  assert.equal(await fs.readFile(path.join(installed.packageRoot,'resource-50009.txt'),'utf8'),'');
  assert.equal(createRequire(import.meta.url)(installed.packageRoot),fixture.nonce);
});
