import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtemp,mkdir,readFile,writeFile,symlink,rm} from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import {createRequire} from 'node:module';
import {copyAuthoringTree,inspectInstalledGraph,compilerIdentity,copyCompilerClosure} from '../stage-sdk.mjs';

async function fixture(fn) {
 const root=await mkdtemp(path.join(os.tmpdir(),'hanlin-miniapp-sdk-'));
 try{await fn(root);}finally{await rm(root,{recursive:true,force:true});}
}
test('original declaration and JS bytes survive nested iOS trees and local package links',()=>fixture(async root=>{
 const source=path.join(root,'source'),destination=path.join(root,'sdk');
 await mkdir(path.join(source,'types/ios'),{recursive:true});
 await writeFile(path.join(source,'types/ios/UIKit.d.ts'),'declare class UIView {}\n');
 await writeFile(path.join(source,'index.js'),'export const upstream = 1;\n');
 await writeFile(path.join(source,'LICENSE'),'original license');
 await mkdir(path.join(root,'local'),{recursive:true});
 await writeFile(path.join(root,'local/package.json'),'{"name":"@hanlin/example"}');
 await symlink(path.join(root,'local'),path.join(source,'local'));
 const receipt=[];
 await copyAuthoringTree(source,destination,receipt,'node_modules/example');
 assert.equal(await readFile(path.join(destination,'types/ios/UIKit.d.ts'),'utf8'),'declare class UIView {}\n');
 assert.equal(await readFile(path.join(destination,'index.js'),'utf8'),'export const upstream = 1;\n');
 assert.equal(await readFile(path.join(destination,'local/package.json'),'utf8'),'{"name":"@hanlin/example"}');
 assert.equal(receipt.length,4);
 assert.ok(receipt.every(f=>/^[a-f0-9]{64}$/.test(f.sha256)));
}));
test('desktop native binaries and frameworks are omitted from mobile authoring closure',()=>fixture(async root=>{
 const source=path.join(root,'source'),destination=path.join(root,'sdk');
 await mkdir(path.join(source,'native/Example.xcframework'),{recursive:true});
 await writeFile(path.join(source,'native/binding.node'),'not a mobile binary');
 await writeFile(path.join(source,'native/Example.xcframework/Info.plist'),'native bundle');
 await writeFile(path.join(source,'index.js'),'module.exports = {};');
 const receipt=[];
 await copyAuthoringTree(source,destination,receipt,'node_modules/example');
 assert.deepEqual(receipt.map(x=>x.path),['node_modules/example/index.js']);
}));
test('cycles in installed symlinks report a source problem rather than partially publishing',()=>fixture(async root=>{
 await mkdir(path.join(root,'source'));
 await symlink(path.join(root,'source'),path.join(root,'source/loop'));
 await assert.rejects(copyAuthoringTree(path.join(root,'source'),path.join(root,'sdk'),[],'example'),/symlink cycle/);
}));
test('installed SDK graph must match the exact native build lock',()=>fixture(async root=>{
 await mkdir(path.join(root,'node_modules/original'),{recursive:true});
 await writeFile(path.join(root,'package.json'),JSON.stringify({dependencies:{original:'1.2.3'}}));
 await writeFile(path.join(root,'package-lock.json'),JSON.stringify({packages:{'node_modules/original':{version:'1.2.3',integrity:'sha512-original'}}}));
 await writeFile(path.join(root,'node_modules/original/package.json'),'{"name":"original","version":"1.2.3"}');
 assert.deepEqual((await inspectInstalledGraph(root)).versions,{original:'1.2.3'});
 await writeFile(path.join(root,'node_modules/original/package.json'),'{"name":"original","version":"1.2.4"}');
 await assert.rejects(inspectInstalledGraph(root),/differs from package-lock/);
}));

test('compiler metadata distinguishes original npm alias version from real compiler version and retains its closure',()=>fixture(async root=>{
  const tooling=path.join(root,'tooling'),alias=path.join(tooling,'node_modules/typescript'),implementation=path.join(tooling,'node_modules/@typescript/old');
  await mkdir(path.join(alias,'lib'),{recursive:true});await mkdir(path.join(implementation,'lib'),{recursive:true});
  await writeFile(path.join(alias,'package.json'),JSON.stringify({name:'@typescript/typescript6',version:'6.0.2',main:'lib/typescript.js',dependencies:{'@typescript/old':'npm:typescript@^6'}}));
  await writeFile(path.join(alias,'lib/typescript.js'),'module.exports = require("@typescript/old");\n');
  await writeFile(path.join(implementation,'package.json'),JSON.stringify({name:'typescript',version:'6.0.3',main:'lib/typescript.js'}));
  await writeFile(path.join(implementation,'lib/typescript.js'),'module.exports = {version:"6.0.3"};\n');
  assert.deepEqual(await compilerIdentity(tooling),{packageName:'@typescript/typescript6',packageVersion:'6.0.2',compilerVersion:'6.0.3'});
  const output=path.join(root,'standalone/typescript'),files=[];
  await copyCompilerClosure(alias,output,files,'scriptwidget/typescript');
  const require=createRequire(path.join(output,'package.json'));
  assert.equal(require('./lib/typescript.js').version,'6.0.3');
  assert.ok(files.some(file=>file.path==='scriptwidget/typescript/node_modules/@typescript/old/lib/typescript.js'));
}));


test('SDK documentation and complete example staging retain exact source without known outputs', async () => {
  const fs = await import('node:fs/promises');
  const {copySDKDocumentation,copySDKExamples,collectSDKSourceInputs} = await import('../stage-sdk.mjs');
  const {createHash} = await import('node:crypto');
  const {tmpdir} = await import('node:os');
  const work = await fs.mkdtemp(path.join(tmpdir(), 'hanlin-sdk-docs-'));
  const source = path.join(work, 'source'), destination = path.join(work, 'sdk-docs');
  try {
    await fs.mkdir(path.join(source, 'reference', 'images'), {recursive:true});
    const guide = await fs.readFile(new URL('../../../docs/miniapp-sdk/README.md', import.meta.url));
    const nested = await fs.readFile(new URL('../../../docs/miniapp-sdk/IMPORT_REPAIR.md', import.meta.url));
    const image = Buffer.from([0,1,2,255]);
    await fs.writeFile(path.join(source, 'README.md'), guide);
    await fs.writeFile(path.join(source, 'reference', 'IMPORT_REPAIR.md'), nested);
    await fs.writeFile(path.join(source, 'reference', 'images', 'public-asset.bin'), image);
    for (const folder of ['evidence', 'reference/evidence', 'Tests', 'node_modules', '.git']) {
      await fs.mkdir(path.join(source, folder), {recursive:true});
      await fs.writeFile(path.join(source, folder, 'intermediate.json'), '{"intermediate":true}');
    }
    await fs.writeFile(path.join(source, 'README.bak.old.md'), 'old guide');
    await copySDKDocumentation(source, destination);
    assert.deepEqual(await fs.readFile(path.join(destination, 'README.md')), guide);
    assert.deepEqual(await fs.readFile(path.join(destination, 'reference', 'IMPORT_REPAIR.md')), nested);
    assert.deepEqual(await fs.readFile(path.join(destination, 'reference', 'images', 'public-asset.bin')), image);
    for (const excluded of ['evidence', 'reference/evidence', 'Tests', 'node_modules', '.git', 'README.bak.old.md']) {
      await assert.rejects(fs.access(path.join(destination, excluded)), {code:'ENOENT'}, excluded+' is outside the existing SDK source-input policy');
    }

    const examples=path.join(work,'source-examples'),sdkExamples=path.join(work,'sdk','examples');
    await fs.cp(new URL('../Examples/',import.meta.url),examples,{recursive:true});
    const prefix='Scripts/MiniApps/Examples';
    const initialInputs=await collectSDKSourceInputs(examples,prefix);
    const catalog=JSON.parse(await fs.readFile(path.join(examples,'index.json'),'utf8'));
    assert.equal(catalog.projects.length,4);
    const first=catalog.projects[0].directory;
    const excludedOutputs=['.hanlin-build/run/package/bundle.js','.hanlin-build/run/MiniApp.hanlinExpo',
      '.hanlin-authoring/validation.json','.metro-cache/data','node_modules/installed/index.js',
      '.git/index','evidence/raw.log','README.bak.old.md'];
    for(const file of excludedOutputs) {
      const target=path.join(examples,first,file);
      await fs.mkdir(path.dirname(target),{recursive:true});
      await fs.writeFile(target,'generated output must not become authored source');
    }
    assert.deepEqual(await collectSDKSourceInputs(examples,prefix),initialInputs,
      'Known output/cache bytes must not alter the actual SDK input fingerprint');
    // A ZIP resource is data. Neither its suffix nor an authored build/dist
    // directory makes it generated output. Preserve explicit resources too.
    const resourceZIP=Buffer.from('UEsFBgAAAAAAAAAAAAAAAAAAAAAAAA==','base64');
    const resources=new Map([['assets/catalog.zip',resourceZIP],['build/source.txt',Buffer.from('authored build resource')],
      ['dist/source.txt',Buffer.from('authored dist resource')]]);
    for(const [file,bytes] of resources) {
      const target=path.join(examples,first,file);
      await fs.mkdir(path.dirname(target),{recursive:true});await fs.writeFile(target,bytes);
    }
    const descriptorPath=path.join(examples,first,'hanlin.authoring.json');
    const author=JSON.parse(await fs.readFile(descriptorPath,'utf8'));
    await fs.writeFile(descriptorPath,JSON.stringify({...author,resources:['assets','build','dist']},null,2)+'\n');
    const expectedInputs=await collectSDKSourceInputs(examples,prefix);
    for(const [file,bytes] of resources) assert.ok(expectedInputs.some(input=>input.path===prefix+'/'+first+'/'+file &&
      input.sha256===createHash('sha256').update(bytes).digest('hex')));
    const projects=await copySDKExamples(examples,sdkExamples,['expo','nativescript','scriptwidget']);
    assert.deepEqual(projects.map(project=>[project.engine,project.level]),[
      ['expo','hello-world'],['expo','complete-app'],['nativescript','hello-world'],['nativescript','complete-app']]);
    const emitted=JSON.parse(await fs.readFile(path.join(sdkExamples,'index.json'),'utf8'));
    assert.deepEqual(emitted,{schemaVersion:1,projects});
    for(const project of projects) {
      assert.equal(project.path,'examples/'+project.directory);
      const descriptor=JSON.parse(await fs.readFile(path.join(sdkExamples,project.directory,'hanlin.authoring.json'),'utf8'));
      assert.equal(project.entry,descriptor.entry);
      assert.equal(project.engine,descriptor.engine);
    }
    for(const input of expectedInputs) {
      const relative=input.path.slice(prefix.length+1);
      if(relative==='index.json') continue; // Index adds actual exported paths/entry metadata.
      const actual=await fs.readFile(path.join(sdkExamples,relative));
      assert.deepEqual(actual,await fs.readFile(path.join(examples,relative)),relative+' must remain byte-identical');
      assert.equal(createHash('sha256').update(actual).digest('hex'),input.sha256);
    }
    for(const file of excludedOutputs) await assert.rejects(fs.access(path.join(sdkExamples,first,file)),{code:'ENOENT'});
    const expoOnly=path.join(work,'expo-only');
    assert.equal((await copySDKExamples(examples,expoOnly,['expo'])).length,2);
    await assert.rejects(fs.access(path.join(expoOnly,'sdk-only-table-share')),{code:'ENOENT'});
    const widgetsOnly=path.join(work,'widgets-only');
    assert.deepEqual(await copySDKExamples(examples,widgetsOnly,['scriptwidget']),[]);
    assert.deepEqual(await fs.readdir(widgetsOnly),['index.json']);
  } finally {
    await fs.rm(work, {recursive:true,force:true});
  }
});
