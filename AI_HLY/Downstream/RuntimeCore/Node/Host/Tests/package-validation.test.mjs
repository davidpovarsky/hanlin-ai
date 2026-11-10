import test from 'node:test';
import assert from 'node:assert/strict';
import {promises as fs} from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import {createHash} from 'node:crypto';
import {ExecutionJobs} from '../execution-jobs.mjs';
import {validateGlobalPackage} from '../package-validation.mjs';

async function fixture(t,manifest,files) {
  const root=await fs.mkdtemp(path.join(os.tmpdir(),'hanlin-package-validation-'));
  t.after(()=>fs.rm(root,{recursive:true,force:true}));
  const directory=path.join(root,'node_modules',manifest.name);
  await fs.mkdir(directory,{recursive:true});
  await fs.writeFile(path.join(directory,'package.json'),JSON.stringify(manifest));
  for(const [name,source] of Object.entries(files)) {
    const target=path.join(directory,name);await fs.mkdir(path.dirname(target),{recursive:true});await fs.writeFile(target,source);
  }
  const jobs=new ExecutionJobs({root:path.join(root,'jobs'),workerURL:new URL('../execution-worker.mjs',import.meta.url)});
  await jobs.initialize();
  const probe=async()=>{
    const name=JSON.stringify(manifest.name);
    const started=await jobs.start({moduleKind:'esm',workspace:directory,source:`
      import {validateGlobalPackage} from ${JSON.stringify(new URL('../package-validation.mjs',import.meta.url).href)};
      import {createRequire} from 'node:module';
      const require=createRequire(import.meta.url);
      export default await validateGlobalPackage({name:${name},packageRoot:${JSON.stringify(directory)},importLibrary:async()=>{
        try{import.meta.resolve(${name});}catch(error){if(error.code!=='ERR_PACKAGE_PATH_NOT_EXPORTED')throw error;require(${name});return 'require';}
        await import(${name});return 'import';
      }});`});
    return jobs.wait(started.executionID);
  };
  return {root,directory,jobs,probe};
}

test('command-only package validation hashes actual entries without executing invented CLI arguments',async t=>{
  const source="#!/usr/bin/env node\nrequire('node:fs').writeFileSync('CLI_EXECUTED',process.argv[2]);console.log('שלום actual cli');process.exit(23);\n";
  const {directory,jobs,probe}=await fixture(t,{name:'command-only',version:'1.0.0',bin:{actual:'bin.cjs'}},{'bin.cjs':source});
  const checked=await probe();
  assert.equal(checked.state,'completed',JSON.stringify(checked));
  assert.equal(checked.result.value.executed,false);
  assert.equal(checked.result.value.validationMode,'command-entry-files');
  const entry=checked.result.value.commands[0];
  assert.equal(entry.bytes,Buffer.byteLength(source));
  assert.equal(entry.sha256,createHash('sha256').update(source).digest('hex'));
  await assert.rejects(fs.access(path.join(directory,'CLI_EXECUTED')),error=>error.code==='ENOENT');
  const actual=await jobs.start({executionMode:'cli',entryPoint:entry.entryPoint,workspace:directory,arguments:['actual-argument']});
  const completed=await jobs.wait(actual.executionID);
  assert.equal(completed.result.exitCode,23);
  assert.match(completed.result.stdout,/שלום actual cli/);
  assert.equal(await fs.readFile(path.join(directory,'CLI_EXECUTED'),'utf8'),'actual-argument');
});

test('actual Worker loads import and require-only public roots from the staged package generation',async t=>{
  for(const [name,exports,files,loader] of [
    ['import-root',{import:'./entry.mjs'},{'entry.mjs':"export default 'actual staged import';"},'import'],
    ['require-root',{require:'./entry.cjs'},{'entry.cjs':"module.exports='actual staged require';"},'require'],
  ]) {
    const {probe}=await fixture(t,{name,version:'1.0.0',exports},files);
    const result=await probe();
    assert.equal(result.state,'completed',JSON.stringify(result));
    assert.equal(result.result.value.executed,true);
    assert.equal(result.result.value.loader,loader);
  }
});

test('an actual root dependency failure is not hidden by CLI or require fallback',async t=>{
  const {probe}=await fixture(t,{name:'broken-library',version:'1.0.0',exports:{import:'./entry.mjs',require:'./safe.cjs'},bin:{cli:'safe.cjs'}},
    {'entry.mjs':"import 'missing-actual-dependency';",'safe.cjs':"module.exports=42;"});
  const result=await probe();
  assert.equal(result.state,'failed');
  assert.match(result.result.stderr,/missing-actual-dependency/);
});

test('subpath metadata does not pretend a nonexistent root was imported; invalid bin targets still fail',async t=>{
  const {directory,probe}=await fixture(t,{name:'subpaths-only',version:'1.0.0',exports:{'./feature':'./feature.mjs'}},{'feature.mjs':'export default 42;'});
  const result=await probe();
  assert.equal(result.state,'completed');
  assert.equal(result.result.value.executed,false);
  assert.deepEqual(result.result.value.exportedSubpaths,['./feature']);
  await assert.rejects(validateGlobalPackage({name:'changed-name',packageRoot:directory}),/identity changed/);
  await fs.writeFile(path.join(directory,'package.json'),JSON.stringify({name:'subpaths-only',version:'1.0.0',bin:{bad:'missing.cjs'}}));
  await assert.rejects(validateGlobalPackage({name:'subpaths-only',packageRoot:directory}),error=>error.code==='ENOENT');
});
