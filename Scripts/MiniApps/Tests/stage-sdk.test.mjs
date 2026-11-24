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
