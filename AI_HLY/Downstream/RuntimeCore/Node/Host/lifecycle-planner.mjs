import { createHash } from 'node:crypto';
import { promises as fs } from 'node:fs';
import path from 'node:path';
import { validatePortableShell } from './portable-shell.mjs';

const installEvents=['preinstall','install','postinstall'];
const projectEvents=[...installEvents,'prepublish','preprepare','prepare','postprepare'];
const eventsFor=context=>context==='project'?projectEvents:context==='link'?['preinstall','prepare','install','postinstall']:installEvents;

function action(manifest,integrity,event,source,directory='.',origin='manifest') {
  return {script:event,kind:'portableShell',command:null,arguments:[],source,workingDirectory:directory,
    packageName:manifest.name,packageVersion:manifest.version,packageIntegrity:integrity??null,sourceOrigin:origin};
}
function actionsFor(entry,events,rejected) {
  const actions=[];
  for(const event of events) {
    const source=entry.scripts[event];
    if(source==null)continue;
    if(typeof source!=='string') {rejected.push({script:event,reason:'npm lifecycle scripts must be strings.'});continue;}
    try {validatePortableShell(source);}
    catch(error){rejected.push({script:event,reason:String(error.message??error)});continue;}
    actions.push(action(entry.manifest,entry.integrity,event,source,entry.directory,
      entry.implicitInstall&&event==='install'?'node-gyp-default':'manifest'));
  }
  return actions;
}
export function lifecycleFingerprint(plan) {
  const identity={schemaVersion:2,context:plan.context??'project',packageName:plan.packageName,
    packageVersion:plan.packageVersion,integrity:plan.integrity??null,
    actions:plan.actions.map(item=>({script:item.script,kind:item.kind,command:item.command??null,
      arguments:item.arguments??[],source:item.source??null,workingDirectory:item.workingDirectory??'.',
      packageName:item.packageName??null,packageVersion:item.packageVersion??null,
      packageIntegrity:item.packageIntegrity??null,sourceOrigin:item.sourceOrigin??'manifest'}))};
  return createHash('sha256').update(JSON.stringify(identity)).digest('hex');
}
function finish(manifest,integrity,context,actions,rejected) {
  const plan={schemaVersion:2,context,packageName:manifest.name,packageVersion:manifest.version,
    integrity:integrity??null,actions,rejected,requiresApproval:false,executable:rejected.length===0};
  plan.scriptHash=lifecycleFingerprint(plan);
  return plan;
}

/** Public Yarn parser validates syntax; execute the original source unchanged. */
export function planLifecycle(manifest,integrity=null,{context='project'}={}) {
  const rejected=[];
  const entry={manifest,integrity,scripts:manifest.scripts??{},directory:'.'};
  return finish(manifest,integrity,context,actionsFor(entry,eventsFor(context),rejected),rejected);
}

/** Public Arborist Node.children/Link.target traversal; no private rebuild API. */
export async function planLifecycleTree(tree,{identity,includeRoot=false,rootContext='registry',previousPackages={}}={}) {
  const root=await fs.realpath(tree.path);
  const lock=JSON.parse(await fs.readFile(path.join(root,'package-lock.json'),'utf8'));
  const entries=[],seen=new Set();
  const rootNode=tree.isLink?tree.target:tree;
  if(!rootNode)throw new Error('The installed tree root link has no target.');
  const queue=[...(includeRoot?[tree]:[]),...rootNode.children.values()];
  for(let index=0;index<queue.length;index++) {
    const node=queue[index],target=node.isLink?node.target:node;
    if(!target)throw new Error('An installed package link has no target.');
    let directory;
    try{directory=await fs.realpath(target.path);}catch(error){if(error.code==='ENOENT')continue;throw error;}
    if(seen.has(directory))continue;
    seen.add(directory);
    const relative=path.relative(root,directory);
    if(relative==='..'||relative.startsWith('..'+path.sep)||path.isAbsolute(relative))throw new Error('A lifecycle package escapes its staged transaction.');
    const manifest=JSON.parse(await fs.readFile(path.join(directory,'package.json'),'utf8'));
    const scripts={...(manifest.scripts??{})};
    let implicitInstall=false;
    if(!scripts.install&&!scripts.preinstall){
      try{if((await fs.stat(path.join(directory,'binding.gyp'))).isFile()){scripts.install='node-gyp rebuild';implicitInstall=true;}}
      catch(error){if(error.code!=='ENOENT')throw error;}
    }
    const key=relative.split(path.sep).join('/');
    const unchanged=previousPackages[key] && JSON.stringify(previousPackages[key])===JSON.stringify(lock.packages?.[key]);
    if(!unchanged)entries.push({manifest,scripts,directory:key||'.',integrity:node===tree?identity?.integrity:lock.packages?.[key]?.integrity??null,
      context:node===tree?rootContext:node.isLink?'link':'registry',implicitInstall,root:node===tree,
      depth:key.split('/').filter(part=>part==='node_modules').length});
    queue.push(...target.children.values());
  }
  entries.sort((a,b)=>a.depth-b.depth||(a.directory<b.directory?-1:a.directory>b.directory?1:0));
  const rejected=[],actions=[];
  const deps=entries.filter(entry=>!(entry.root&&entry.context==='project'));
  // npm's dependency build phase precedes linked prepare/install phases.
  for(const linked of [false,true]) {
    for(const event of linked?['preinstall','prepare','install','postinstall']:installEvents) {
      for(const entry of deps.filter(item=>(item.context==='link')===linked)) actions.push(...actionsFor(entry,[event],rejected));
    }
  }
  for(const entry of entries.filter(item=>item.root&&item.context==='project'))actions.push(...actionsFor(entry,projectEvents,rejected));
  const rootManifest=identity??tree.package;
  return finish({name:rootManifest.packageName??rootManifest.name,version:rootManifest.packageVersion??rootManifest.version},
    rootManifest.integrity??null,'installed-tree',actions,rejected);
}

/** Reject stale source or changed plans before executing the first side effect. */
export async function verifyLifecyclePlan(packageRoot,plan) {
  if(plan.schemaVersion!==2||plan.scriptHash!==lifecycleFingerprint(plan))throw new Error('Lifecycle plan identity changed.');
  const root=await fs.realpath(packageRoot);
  for(const item of plan.actions) {
    if(item.kind!=='portableShell'||typeof item.source!=='string')throw new Error('Unsupported lifecycle plan action.');
    const directory=await fs.realpath(path.resolve(root,item.workingDirectory??'.'));
    const relative=path.relative(root,directory);
    if(relative==='..'||relative.startsWith('..'+path.sep)||path.isAbsolute(relative))throw new Error('Lifecycle working directory escapes its transaction.');
    const manifest=JSON.parse(await fs.readFile(path.join(directory,'package.json'),'utf8'));
    if(manifest.name!==item.packageName||manifest.version!==item.packageVersion)throw new Error('Lifecycle package identity changed.');
    if(item.sourceOrigin==='node-gyp-default') {
      if(manifest.scripts?.preinstall||manifest.scripts?.install||item.source!=='node-gyp rebuild'||!(await fs.stat(path.join(directory,'binding.gyp'))).isFile())throw new Error('Native build lifecycle identity changed.');
    } else if(manifest.scripts?.[item.script]!==item.source)throw new Error('Lifecycle script changed after staging.');
    validatePortableShell(item.source);
  }
  return {verified:true};
}
