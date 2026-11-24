#!/usr/bin/env node
/** Original npm installation provenance shared by native preparation and SDK staging. */
import {createHash} from 'node:crypto';
import {execFileSync} from 'node:child_process';
import {readFile,readdir,realpath,rename,stat,writeFile} from 'node:fs/promises';
import path from 'node:path';
import {fileURLToPath,pathToFileURL} from 'node:url';

const sha = value => createHash('sha256').update(value).digest('hex');
const readJSON = async file => JSON.parse(await readFile(file,'utf8'));
export const receiptName = '.hanlin-miniapp-install.json';
export const excludedDirectories = new Set(['.git','.bin','.cache','prebuilds','Pods','DerivedData']);
export const isNativeDirectory = name => /\.(?:xcframework|framework|app)$/.test(name);
export const isAuthoringFile = name => name !== receiptName &&
  !/\.(?:a|o|dylib|so|node|dll|exe|pdb|xcframework|framework|app|tgz|tar|gz|zip)$/i.test(name) &&
  /(?:\.(?:[cm]?js|jsx|tsx?|json|map|md|txt|yaml|yml|css|html|wasm|png|jpe?g|webp|gif|svg|ttf|otf)$|(?:^|\/)(?:LICENSE|NOTICE|COPYING|AUTHORS)(?:\.[^/]*)?$)/i.test(name);

async function inventory(source,{prefix='',excluded=new Set(),ancestors=new Set()}={}) {
  const canonical=await realpath(source);
  if(ancestors.has(canonical))throw new Error('SDK source symlink cycle: '+source);
  const nextAncestors=new Set(ancestors).add(canonical),files=[];
  for(const entry of (await readdir(source,{withFileTypes:true})).sort((a,b)=>a.name.localeCompare(b.name))) {
    const relative=path.posix.join(prefix,entry.name);
    if(excluded.has(relative)||excludedDirectories.has(entry.name)||isNativeDirectory(entry.name))continue;
    const full=path.join(source,entry.name),info=entry.isSymbolicLink()?await stat(full):entry;
    if(info.isDirectory())files.push(...await inventory(full,{prefix:relative,excluded,ancestors:nextAncestors}));
    else if(info.isFile()&&isAuthoringFile(entry.name)) {
      const bytes=await readFile(full);files.push({path:relative,sha256:sha(bytes),bytes:bytes.length});
    }
  }
  return files;
}
async function inputIdentity(toolingRoot) {
  return {schemaVersion:1,packageSHA256:sha(await readFile(path.join(toolingRoot,'package.json'))),
    lockSHA256:sha(await readFile(path.join(toolingRoot,'package-lock.json'))),
    policySHA256:sha(await readFile(fileURLToPath(import.meta.url))),
    node:process.versions.node,platform:process.platform,architecture:process.arch};
}
const same = (a,b) => JSON.stringify(a)===JSON.stringify(b);
function mismatch(before,after,allowed=new Map()) {
  const previous=new Map(before.map(file=>[file.path,file]));
  for(const file of after) {
    const old=previous.get(file.path);previous.delete(file.path);
    if(old&&old.sha256===file.sha256&&old.bytes===file.bytes)continue;
    const change=allowed.get(file.path);
    if(old&&change&&change.beforeSHA256===old.sha256&&change.afterSHA256===file.sha256)continue;
    return file.path;
  }
  return previous.keys().next().value;
}
async function verifyLocalPackage(toolingRoot,relative,target) {
  const installed=path.join(toolingRoot,relative),source=path.resolve(toolingRoot,target);
  // A source link must point at this checkout; a copied package must contain the
  // same retained original source bytes. Equal package versions are insufficient.
  const installedFiles=await inventory(installed,{excluded:new Set(['node_modules'])});
  const sourceFiles=await inventory(source,{excluded:new Set(['node_modules'])});
  const stale=mismatch(sourceFiles,installedFiles);
  if(stale)throw new Error('Installed local SDK source differs from this checkout: '+relative+'/'+stale);
}
export async function inspectInstalledGraph(toolingRoot) {
  const root=await readJSON(path.join(toolingRoot,'package.json'));
  const lock=await readJSON(path.join(toolingRoot,'package-lock.json'));
  if(!lock.packages)throw new Error('SDK package-lock has no complete package graph');
  const localPaths=new Set(),installedPackages=[];
  const direct={...root.dependencies,...root.devDependencies,...root.optionalDependencies},versions={};
  for(const [relative,locked] of Object.entries(lock.packages)) {
    if(!relative.startsWith('node_modules/'))continue;
    const full=path.resolve(toolingRoot,relative);
    if(!full.startsWith(path.resolve(toolingRoot,'node_modules')+path.sep))throw new Error('Invalid installed package path: '+relative);
    let installed;
    try{installed=await readJSON(path.join(full,'package.json'));}
    catch(error){if(error.code==='ENOENT'&&(locked.optional||locked.devOptional))continue;throw error;}
    if(locked.link) {
      const name=relative.slice('node_modules/'.length),request=direct[name];
      const target=request?.startsWith('file:')?request.slice(5):locked.resolved;
      if(!target)throw new Error('Local SDK package has no source: '+relative);
      await verifyLocalPackage(toolingRoot,relative,target);
      localPaths.add(relative);
    } else if(locked.version!==installed.version||(!locked.integrity&&!locked.inBundle)) {
      throw new Error('Installed SDK package differs from package-lock: '+relative);
    }
    installedPackages.push({path:relative,name:installed.name,version:installed.version,integrity:locked.integrity??null,link:!!locked.link});
  }
  for(const [name,requested] of Object.entries(direct)) {
    const relative='node_modules/'+name,locked=lock.packages[relative];
    if(!locked)throw new Error('Direct SDK package missing from package-lock: '+name);
    let installed;
    try{installed=await readJSON(path.join(toolingRoot,relative,'package.json'));}
    catch(error){if(error.code==='ENOENT'&&Object.hasOwn(root.optionalDependencies??{},name))continue;throw error;}
    if(requested.startsWith('file:')&&(await stat(path.resolve(toolingRoot,requested.slice(5)))).isDirectory()) {
      await verifyLocalPackage(toolingRoot,relative,requested.slice(5));localPaths.add(relative);
    }
    versions[name]=installed.version;
  }
  return {root,lock,versions,localPaths,installedPackages:installedPackages.sort((a,b)=>a.path.localeCompare(b.path))};
}
async function capture(toolingRoot) {
  const graph=await inspectInstalledGraph(toolingRoot);
  const files=await inventory(path.join(toolingRoot,'node_modules'),{prefix:'node_modules',excluded:graph.localPaths});
  return {graph,inputs:await inputIdentity(toolingRoot),files};
}
async function readReceipt(toolingRoot) {
  try{return await readJSON(path.join(toolingRoot,'node_modules',receiptName));}
  catch(error){if(error.code==='ENOENT')throw new Error('No verified original npm installation receipt. Run Scripts/MiniApps/install-tooling.mjs for '+toolingRoot);throw error;}
}
async function writeReceipt(toolingRoot,receipt) {
  const file=path.join(toolingRoot,'node_modules',receiptName),temporary=file+'.tmp-'+process.pid;
  await writeFile(temporary,JSON.stringify(receipt)+'\n');await rename(temporary,file);
}
export async function verifyInstalledGraph(toolingRoot) {
  const receipt=await readReceipt(toolingRoot),current=await capture(toolingRoot);
  if(!same(receipt.inputs,current.inputs))throw new Error('Installed SDK input fingerprint is stale: '+toolingRoot);
  if(!same(receipt.packages,current.graph.installedPackages))throw new Error('Installed SDK transitive graph changed: '+toolingRoot);
  const stale=mismatch(receipt.files,current.files);
  if(stale)throw new Error('Installed SDK original file is missing or changed: '+stale);
  return {...current.graph,installation:{inputs:receipt.inputs,files:current.files.length,contentSHA256:sha(JSON.stringify(current.files)),command:receipt.command}};
}
export async function ensureInstalledTooling({toolingRoot,ignoreScripts=false,npmArguments=[]}={}) {
  toolingRoot=path.resolve(toolingRoot);
  try {
    const graph=await verifyInstalledGraph(toolingRoot);
    return {status:'reused',toolingRoot,files:graph.installation.files,packages:graph.installedPackages.length};
  } catch(error) {
    console.error('[MiniApps] Preparing original npm inputs: '+error.message);
  }
  const inputs=await inputIdentity(toolingRoot);
  const args=['ci',...(ignoreScripts?['--ignore-scripts']:[]),'--no-audit','--no-fund',...npmArguments,'--prefix',toolingRoot];
  execFileSync(process.platform==='win32'?'npm.cmd':'npm',args,{stdio:'inherit'});
  const current=await capture(toolingRoot);
  if(!same(inputs,current.inputs))throw new Error('SDK package inputs changed during npm ci');
  await writeReceipt(toolingRoot,{schemaVersion:1,inputs:current.inputs,packages:current.graph.installedPackages,files:current.files,command:['npm',...args]});
  return {status:'installed',toolingRoot,files:current.files.length,packages:current.graph.installedPackages.length};
}
/** Called only after prepare-types authenticated each original and corrected file. */
export async function resealInstalledTooling(toolingRoot,changes) {
  const receipt=await readReceipt(toolingRoot),current=await capture(toolingRoot);
  if(!same(receipt.inputs,current.inputs)||!same(receipt.packages,current.graph.installedPackages))throw new Error('SDK graph changed during declaration preparation');
  const allowed=new Map(changes.map(change=>[change.path,change]));
  const stale=mismatch(receipt.files,current.files,allowed);
  if(stale)throw new Error('Unapproved SDK file changed during declaration preparation: '+stale);
  if(!same(receipt.files,current.files))await writeReceipt(toolingRoot,{...receipt,files:current.files});
  return {files:current.files.length,contentSHA256:sha(JSON.stringify(current.files))};
}
if(process.argv[1]&&import.meta.url===pathToFileURL(path.resolve(process.argv[1])).href) {
  const args=process.argv.slice(2),value=name=>args.find(arg=>arg.startsWith(name+'='))?.slice(name.length+1);
  const repository=value('--repository')??path.resolve(path.dirname(fileURLToPath(import.meta.url)),'../..');
  const engine=value('--engine'),folder={expo:'Expo',nativescript:'NativeScript'}[engine];
  const toolingRoot=value('--tooling-root')??(folder?path.join(repository,'Scripts',folder):undefined);
  if(!toolingRoot)throw new Error('Specify --engine=expo|nativescript or --tooling-root=<path>');
  if(args.includes('--verify')) {
    const graph=await verifyInstalledGraph(toolingRoot);console.log(JSON.stringify({status:'verified',packages:graph.installedPackages.length,files:graph.installation.files}));
  } else console.log(JSON.stringify(await ensureInstalledTooling({toolingRoot,ignoreScripts:args.includes('--ignore-scripts')})));
}
