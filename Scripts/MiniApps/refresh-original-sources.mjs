// Advance vendored native renderer sources with a real three-way merge. Local
// host adaptations remain visible, and a conflict stops compilation with a diff.
import {createHash} from 'node:crypto';
import {existsSync} from 'node:fs';
import {mkdir,readFile,writeFile,rm} from 'node:fs/promises';
import {execFileSync,spawnSync} from 'node:child_process';
import path from 'node:path';

const sha=bytes=>createHash('sha256').update(bytes).digest('hex');
const blob=bytes=>createHash('sha1').update(`blob ${Buffer.byteLength(bytes)}\0`).update(bytes).digest('hex');
const pretty=value=>JSON.stringify(value,null,2)+'\n';
const json=async file=>JSON.parse(await readFile(file,'utf8'));
async function source(url,cache) {
  const cached=cache?path.join(cache,'immutable-originals',sha(url)):null;
  if(cached&&existsSync(cached))return readFile(cached);
  const response=await fetch(url,{headers:{'User-Agent':'Hanlin-MiniApp-Upstream-Resolver'},signal:AbortSignal.timeout(60000)});
  if(!response.ok)throw new Error(`Original source fetch failed (${response.status}): ${url}`);
  const bytes=Buffer.from(await response.arrayBuffer());
  if(cached){await mkdir(path.dirname(cached),{recursive:true});await writeFile(cached,bytes);}
  return bytes;
}
const raw=(repository,commit,file)=>`https://raw.githubusercontent.com/${repository}/${commit}/${file}`;
function tarMember(archive,relative) {return execFileSync('tar',['-xOf',archive,'package/'+relative],{maxBuffer:16*1024*1024});}

export async function mergeOriginal({local,previous,next,cache,label}) {
  if(Buffer.compare(previous,next)===0)return local;
  if(Buffer.compare(local,previous)===0)return next;
  const directory=path.join(cache,'merge-'+sha(label));await mkdir(directory,{recursive:true});
  const paths=['local','previous','upstream'].map(name=>path.join(directory,name));
  await Promise.all(paths.map((file,index)=>writeFile(file,[local,previous,next][index])));
  const result=spawnSync('git',['merge-file','--diff3','-p',...paths],{maxBuffer:16*1024*1024});
  if(result.status!==0) {
    const conflict=path.join(directory,'conflict.diff');await writeFile(conflict,result.stdout??Buffer.alloc(0));
    throw new Error(`Original source merge needs repair: ${label}; three-way conflict: ${conflict}. Current host inputs were not changed.`);
  }
  await rm(directory,{recursive:true,force:true});return result.stdout;
}
async function previousOriginal(entry,cache) {
  if(entry.upstreamPublication) {
    const item=entry.upstreamPublication;
    const file=path.join(cache,item.package.replaceAll('/','_')+'-'+item.version+'.tgz');
    if(!existsSync(file))await writeFile(file,await source(item.tarball,cache));
    if(sha(await readFile(file))!==item.sha256)throw new Error(`Previous original package hash changed: ${item.package}@${item.version}`);
    return tarMember(file,item.path);
  }
  if(!/^[a-f0-9]{40}$/.test(entry.commit??''))throw new Error(`Missing immutable original commit for ${entry.local}`);
  return source(raw(entry.repository,entry.commit,entry.upstream),cache);
}
function npmMapping(entry) {
  const mappings=[['packages/expo-ui/','@expo/ui'],['packages/expo-modules-core/','expo-modules-core'],['packages/expo-widgets/','expo-widgets']];
  for(const [prefix,name] of mappings)if(entry.upstream.startsWith(prefix))return {name,relative:entry.upstream.slice(prefix.length)};
  throw new Error(`No original npm source mapping for ${entry.upstream}`);
}

export async function refreshOriginalSources({root,cache,publications,archives}) {
  const manifestPath='docs/widget-engines/UPSTREAM_SOURCE_MANIFEST.json';
  const manifest=await json(path.join(root,manifestPath));
  const rows=execFileSync('git',['ls-remote','https://github.com/everettjf/scriptwidget.git','HEAD'],{encoding:'utf8'}).trim().split('\n');
  const commit=rows.map(line=>line.split(/\s+/)[0]).find(value=>/^[a-f0-9]{40}$/.test(value));
  if(!commit)throw new Error('No immutable original ScriptWidget HEAD revision');
  const files=new Map(),changes=[],adapterContracts=[];
  // These are authored host integrations that cite upstream contracts, not
  // renamed copies of an upstream source file. Some have several provenance
  // rows pointing to a single implementation. Never replace them with a whole
  // unrelated upstream app implementation through a textual three-way merge.
  const hostAdapters=new Set([
    'Packages/HanlinPlatform/Sources/HanlinScriptExtensions/ScriptWidget/HanlinScriptWidgetRuntime.swift',
    'Packages/HanlinPlatform/Sources/HanlinWidgetCompiler/Resources/prepare-widget.js',
    'Packages/HanlinExpoRuntime/Sources/HanlinExpoWidgetNative/HanlinExpoWidgetNative.swift',
  ]);
  for(const entry of manifest.files) {
    const full=path.join(root,entry.local);
    const local=files.get(entry.local)??await readFile(full);
    const previous=await previousOriginal(entry,cache);
    let next,identity;
    if(entry.repository==='everettjf/scriptwidget') {
      next=await source(raw(entry.repository,commit,entry.upstream),cache);identity={repository:entry.repository,commit,path:entry.upstream};
    } else if(entry.repository==='expo/expo') {
      let mapping=npmMapping(entry),publication=publications.get(mapping.name),archive=archives.get(mapping.name);
      if(!publication||!archive)throw new Error(`Original source archive missing: ${mapping.name}`);
      if(!archive.paths.has('package/'+mapping.relative)) {
        const candidates=[];
        for(const name of ['@expo/ui','expo-modules-core','expo-widgets'])for(const file of archives.get(name)?.paths??[]) {
          if(file.startsWith('package/')&&path.basename(file)===path.basename(mapping.relative))candidates.push({name,relative:file.slice('package/'.length)});
        }
        if(candidates.length!==1)throw new Error(`Original ${entry.upstream} moved or was removed; expected one current original counterpart, found ${candidates.length}`);
        const previousPath=entry.upstream;mapping=candidates[0];publication=publications.get(mapping.name);archive=archives.get(mapping.name);
        const packageDirectory=mapping.name==='@expo/ui'?'expo-ui':mapping.name;
        entry.upstream='packages/'+packageDirectory+'/'+mapping.relative;
        entry.relocation={previousUpstream:previousPath,currentUpstream:entry.upstream};
      }
      next=tarMember(archive.file,mapping.relative);
      identity={package:mapping.name,version:publication.version,tarball:publication.dist.tarball,sha256:archive.sha256,path:mapping.relative};
    } else throw new Error(`Unsupported original repository ${entry.repository}`);
    if(hostAdapters.has(entry.local)) {
      const reference=path.join(cache,'adapter-contracts',sha(entry.upstream)+'.swift');await mkdir(path.dirname(reference),{recursive:true});await writeFile(reference,next);
      const contract={local:entry.local,upstream:entry.upstream,identity,originalSHA256:sha(next),changed:sha(previous)!==sha(next),hostSHA256:sha(local),implementation:'Hanlin host adapter; original renderer source and original app service coverage are separate'};
      adapterContracts.push(contract);entry.sourceRole='host-adapter';entry.latestUpstreamContract=contract;entry.localSHA256=sha(local);
      continue;
    }
    const merged=await mergeOriginal({local,previous,next,cache,label:entry.local+' <- '+entry.upstream});
    files.set(entry.local,merged);
    const changed=sha(previous)!==sha(next);
    if(changed)changes.push({path:entry.local,originalBeforeSHA256:sha(previous),originalAfterSHA256:sha(next),adapted:Buffer.compare(merged,next)!==0});
    entry.upstreamBlob=blob(next);entry.localSHA256=sha(merged);entry.byteIdentical=Buffer.compare(merged,next)===0;
    if(identity.commit)entry.commit=identity.commit;
    else {entry.upstreamPublication=identity;entry.baseGitCommit??=entry.commit;delete entry.commit;}
  }
  // Include newly added files inside the original ScriptWidget component tree.
  // The full app and unrelated services are not part of this renderer target.
  const tree=JSON.parse((await source(`https://api.github.com/repos/everettjf/scriptwidget/git/trees/${commit}?recursive=1`,cache)).toString());
  if(tree.truncated)throw new Error('Original ScriptWidget tree listing is truncated');
  const prefix='Shared/ScriptWidgetRuntime/Widget/Component/';
  const originalPrefix='Packages/HanlinPlatform/Sources/HanlinScriptExtensions/ScriptWidget/Original/Component/';
  const known=new Set(manifest.files.filter(entry=>entry.repository==='everettjf/scriptwidget').map(entry=>entry.upstream));
  for(const item of tree.tree??[]) {
    if(item.type!=='blob'||!item.path.startsWith(prefix)||!item.path.endsWith('.swift')||known.has(item.path))continue;
    const local=originalPrefix+item.path.slice(prefix.length),bytes=await source(raw('everettjf/scriptwidget',commit,item.path),cache);
    if(existsSync(path.join(root,local)))throw new Error(`New original source collides with a host file: ${local}`);
    files.set(local,bytes);manifest.files.push({repository:'everettjf/scriptwidget',commit,upstream:item.path,upstreamBlob:blob(bytes),local,localSHA256:sha(bytes),byteIdentical:true,adaptation:'New original component; native compilation required.'});
    changes.push({path:local,originalAfterSHA256:sha(bytes),added:true});
  }
  // Multiple source records can contribute to one host adapter. Its final local
  // digest must be shared by all records after every successful merge.
  for(const entry of manifest.files)if(files.has(entry.local))entry.localSHA256=sha(files.get(entry.local));
  manifest.schemaVersion=2;
  manifest.nativeLinkStatus='SOURCE_INPUTS_UPDATED_REQUIRES_CURRENT_HOST_NATIVE_BUILD';
  delete manifest.generatedAt;
  files.set(manifestPath,pretty(manifest));
  const catalogRoot='Scripts/MiniApps/scriptwidget/upstream';
  const catalog=await json(path.join(root,catalogRoot,'provenance.json'));
  for(const item of catalog.files) {
    const bytes=await source(raw('everettjf/scriptwidget',commit,item.upstream),cache);
    files.set(path.join(catalogRoot,item.local),bytes);item.commit=commit;item.sha256=sha(bytes);
  }
  files.set(path.join(catalogRoot,'provenance.json'),pretty(catalog));
  return {files,receipt:{scriptWidgetCommit:commit,changedNativeSources:changes,adapterContracts,manifestSHA256:sha(files.get(manifestPath)),catalogSHA256:sha(files.get(path.join(catalogRoot,'provenance.json')))}};
}
