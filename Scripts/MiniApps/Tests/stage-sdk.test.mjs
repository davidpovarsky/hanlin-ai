import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtemp,mkdir,readFile,writeFile,symlink,rm} from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import {copyAuthoringTree,verifyInstalledGraph} from '../stage-sdk.mjs';

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
 assert.deepEqual((await verifyInstalledGraph(root)).versions,{original:'1.2.3'});
 await writeFile(path.join(root,'node_modules/original/package.json'),'{"name":"original","version":"1.2.4"}');
 await assert.rejects(verifyInstalledGraph(root),/differs from package-lock/);
}));
