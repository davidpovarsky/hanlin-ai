// Advance vendored native renderer sources with a real three-way merge. Local
// host adaptations remain visible, and a conflict stops compilation with a diff.
import {createHash} from 'node:crypto';
import {existsSync} from 'node:fs';
import {mkdir,readFile,writeFile,rm,readdir} from 'node:fs/promises';
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
function swiftBlockEnd(text,opening) {
  let depth=1,quoted=false,escaped=false,index=opening+1;
  for(;index<text.length&&depth;index++) {
    const character=text[index];
    if(quoted){if(escaped)escaped=false;else if(character==='\\')escaped=true;else if(character==='"')quoted=false;continue;}
    if(character==='"')quoted=true;else if(character==='{')depth++;else if(character==='}')depth--;
  }
  if(depth)throw new Error('Unbalanced original Swift declaration');return index;
}
export function originalInHostTarget(bytes,local) {
  if(!local.startsWith('Packages/HanlinExpoWidgetSubset/Sources/HanlinExpoWidgetSubset/'))return bytes;
  // This existing extension target compiles the original Core/UI widget types
  // together in one module. The original source's imports of those same modules
  // are namespace changes, not replacements for their implementation.
  let text=bytes.toString().replace(/^import (ExpoModulesCore|ExpoUI)\r?\n/gm,'');
  if(local.endsWith('/ExpoUI/UIBaseView.swift')) {
    // The existing extension target owns SwiftUI rendering, while the original
    // foreground ExpoUI framework owns Expo Module view registration. Preserve
    // that existing separation when upstream edits its registration builder.
    const registration=text.indexOf('/**\n Common UI Builder in expo-ui.');
    if(registration!==-1)text=text.slice(0,registration).trimEnd()+'\n';
  }
  if(local.endsWith('/ExpoUI/Modifiers/WidgetModifiers.swift'))text=text.replace('internal func registerWidgetModifiers()', 'public func registerWidgetModifiers()');
  if(local.endsWith('/Core/Upstream/Core/Coding/JavaScriptCodable+Color.swift')) {
    // Widgets hand native SwiftUI an already prepared Any/JSON tree. The full
    // foreground Core framework owns the JavaScriptActor/JSI decode overloads.
    // Keep the complete original shared color conversion implementation here.
    text=text.replace(/^import ExpoModulesJSI\r?\n/gm,'');
    for(const name of ['UIColor','CGColor','Color']) {
      const start=text.indexOf(`extension ${name}: @retroactive JavaScriptDecodable`);
      if(start!==-1){const end=swiftBlockEnd(text,text.indexOf('{',start));text=text.slice(0,start)+text.slice(end);}
    }
    const bridge=text.indexOf('private func colorFromJavaScriptValue(');
    if(bridge!==-1){const start=text.lastIndexOf('@JavaScriptActor',bridge),end=swiftBlockEnd(text,text.indexOf('{',bridge));text=text.slice(0,start)+text.slice(end);}
    text=text.replace('  if let value = value as? Int {\n    return try colorFromArgb(UInt64(value))',
      '  if let value = value as? Int {\n    guard value >= 0, UInt64(value) <= UInt64(UInt32.max) else { throw Conversions.ConvertingException<UIColor>(value) }\n    return try colorFromArgb(UInt64(value))');
    text=text.replace('private func colorFromNumber(_ value: Double) throws -> UIColor {\n  return',
      'private func colorFromNumber(_ value: Double) throws -> UIColor {\n  guard value.isFinite, value >= 0, value <= Double(UInt32.max) else { throw Conversions.ConvertingException<UIColor>(value) }\n  return');
  }
  return Buffer.from(text);
}
export function registrationBlocks(text) {
  const blocks=[];
  for(const match of text.matchAll(/^\s{4}register\("([^"\n]+)"\)\s*\{/gm)) {
    let depth=1,index=match.index+match[0].length,quoted=false,escaped=false;
    for(;index<text.length&&depth;index++) {
      const character=text[index];
      if(quoted) {if(escaped)escaped=false;else if(character==='\\')escaped=true;else if(character==='"')quoted=false;continue;}
      if(character==='"')quoted=true;else if(character==='{')depth++;else if(character==='}')depth--;
    }
    if(depth)throw new Error('Unbalanced original modifier registration: '+match[1]);
    blocks.push({key:match[1],start:match.index,end:index});
  }
  return blocks;
}
export function originalWidgetRegistry(bytes,removedKeys) {
  let text=bytes.toString();
  for(const block of registrationBlocks(text).reverse())if(removedKeys.has(block.key))text=text.slice(0,block.start)+text.slice(block.end);
  return Buffer.from(text.replace(/\n[ \t]*\n(?:[ \t]*\n)+/g,'\n\n'));
}
async function swiftFiles(root) {
  const result=[];if(!existsSync(root))return result;
  for(const entry of await readdir(root,{withFileTypes:true})) {
    const file=path.join(root,entry.name);
    if(entry.isDirectory())result.push(...await swiftFiles(file));else if(entry.name.endsWith('.swift'))result.push(file);
  }
  return result;
}
const swiftCode=text=>text.replace(/"""[\s\S]*?"""|"(?:\\.|[^"\\])*"/g,' ').replace(/\/\*[\s\S]*?\*\/|\/\/[^\n]*/g,' ');
const declaredTypes=text=>[...swiftCode(text).matchAll(/\b(?:class|struct|enum|protocol|typealias)\s+([A-Za-z_]\w*)/g)].map(match=>match[1]);

async function closeOriginalWidgetTypes({root,cache,files,manifest,changes,publications,archives}) {
  const prefix='Packages/HanlinExpoWidgetSubset/Sources/HanlinExpoWidgetSubset/';
  const target=new Map();
  for(const file of await swiftFiles(path.join(root,prefix)))target.set(path.relative(root,file),await readFile(file));
  for(const [file,bytes] of files)if(file.startsWith(prefix)&&file.endsWith('.swift'))target.set(file,bytes);
  const originals=[],index=new Map();
  for(const [name,folder] of [['@expo/ui','ExpoUI'],['expo-modules-core','Core/Upstream'],['expo-widgets','ExpoWidgets']]) {
    const publication=publications.get(name),archive=archives.get(name);
    const extracted=path.join(cache,'original-swift',name.replaceAll('/','_')+'-'+publication.version);
    const marker=path.join(extracted,'.archive-sha256');
    if(!existsSync(marker)||(await readFile(marker,'utf8'))!==archive.sha256) {
      await rm(extracted,{recursive:true,force:true});await mkdir(extracted,{recursive:true});
      execFileSync('tar',['-xzf',archive.file,'-C',extracted,'package/ios']);await writeFile(marker,archive.sha256);
    }
    for(const file of await swiftFiles(path.join(extracted,'package/ios'))) {
      const relative=path.relative(path.join(extracted,'package'),file),bytes=await readFile(file);
      const item={name,folder,relative,bytes,publication,archive};originals.push(item);
      for(const type of declaredTypes(bytes.toString())) {if(!index.has(type))index.set(type,[]);index.get(type).push(item);}
    }
  }
  let advanced=true;
  while(advanced) {
    advanced=false;
    const texts=[...target.values()].map(bytes=>bytes.toString());
    const available=new Set(texts.flatMap(declaredTypes));
    const requested=new Set(texts.flatMap(text=>[...swiftCode(text).matchAll(/\b[A-Z][A-Za-z0-9_]*\b/g)].map(match=>match[0])));
    for(const type of requested) {
      if(available.has(type))continue;
      const candidates=[...new Set(index.get(type)??[])];
      if(candidates.length!==1)continue; // Swift/SDK names and ambiguous nested names remain compiler-resolved.
      const item=candidates[0];
      const upstream='packages/'+(item.name==='@expo/ui'?'expo-ui':item.name)+'/'+item.relative;
      if(manifest.files.some(entry=>entry.repository==='expo/expo'&&entry.upstream===upstream))continue;
      const local=prefix+item.folder+'/'+item.relative.slice('ios/'.length);
      if(target.has(local))continue;
      const adapted=originalInHostTarget(item.bytes,local);
      target.set(local,adapted);files.set(local,adapted);advanced=true;
      manifest.files.push({repository:'expo/expo',upstream,upstreamBlob:blob(item.bytes),local,localSHA256:sha(adapted),byteIdentical:Buffer.compare(adapted,item.bytes)===0,
        upstreamPublication:{package:item.name,version:item.publication.version,tarball:item.publication.dist.tarball,sha256:item.archive.sha256,path:item.relative},
        adaptation:'Complete original dependency of the current widget renderer; shared original widget type namespace.'});
      changes.push({path:local,originalAfterSHA256:sha(item.bytes),added:true,requiredType:type});
      for(const declaration of declaredTypes(adapted.toString()))available.add(declaration);
    }
  }
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
    let mergeLocal=local,mergePrevious=originalInHostTarget(previous,entry.local),mergeNext=originalInHostTarget(next,entry.local);
    if(entry.local.endsWith('/Core/Convertibles+Color.swift')&&next.toString().includes('return try uiColorFromAny(value)')) {
      // Upstream moved this implementation to JavaScriptCodable+Color.swift.
      // The two existing numeric conversion guards move with that exact code.
      mergeLocal=Buffer.from(local.toString()
        .replace('      guard value >= 0, UInt64(value) <= UInt64(UInt32.max) else { throw Conversions.ConvertingException<UIColor>(value) }\n','')
        .replace('      guard value.isFinite, value >= 0, value <= Double(UInt32.max) else { throw Conversions.ConvertingException<UIColor>(value) }\n',''));
    }
    if(entry.local.endsWith('/ExpoUI/Modifiers/ViewModifierRegistry.swift')) {
      const localKeys=new Set(registrationBlocks(local.toString()).map(block=>block.key));
      const removedKeys=new Set(registrationBlocks(previous.toString()).map(block=>block.key).filter(key=>!localKeys.has(key)));
      // Preserve existing target registrations, update their original bodies,
      // and include every newly introduced upstream registration and its source.
      mergeLocal=originalWidgetRegistry(local,new Set());mergePrevious=originalWidgetRegistry(mergePrevious,removedKeys);mergeNext=originalWidgetRegistry(mergeNext,removedKeys);
    }
    const merged=await mergeOriginal({local:mergeLocal,previous:mergePrevious,next:mergeNext,cache,label:entry.local+' <- '+entry.upstream});
    files.set(entry.local,merged);
    const changed=sha(previous)!==sha(next);
    if(changed)changes.push({path:entry.local,originalBeforeSHA256:sha(previous),originalAfterSHA256:sha(next),adapted:Buffer.compare(merged,next)!==0});
    entry.upstreamBlob=blob(next);entry.localSHA256=sha(merged);entry.byteIdentical=Buffer.compare(merged,next)===0;
    if(identity.commit)entry.commit=identity.commit;
    else {entry.upstreamPublication=identity;entry.baseGitCommit??=entry.commit;delete entry.commit;}
  }
  // Current original UIBaseView / stacks use Expo's universal-layout support.
  // Include that original implementation, rather than substituting a layout
  // shim or silently keeping the old UIBaseView behavior.
  for(const relative of ['ios/UniversalLayout.swift','ios/Modifiers/WidgetKitModifiers.swift']) {
    const name='@expo/ui',archive=archives.get(name),publication=publications.get(name);
    const upstream='packages/expo-ui/'+relative;
    if(!archive?.paths.has('package/'+relative)||manifest.files.some(entry=>entry.repository==='expo/expo'&&entry.upstream===upstream))continue;
    const local='Packages/HanlinExpoWidgetSubset/Sources/HanlinExpoWidgetSubset/ExpoUI/'+relative.slice('ios/'.length);
    const original=tarMember(archive.file,relative),adapted=originalInHostTarget(original,local);
    files.set(local,adapted);
    manifest.files.push({repository:'expo/expo',upstream,upstreamBlob:blob(original),local,localSHA256:sha(adapted),byteIdentical:Buffer.compare(original,adapted)===0,
      upstreamPublication:{package:name,version:publication.version,tarball:publication.dist.tarball,sha256:archive.sha256,path:relative},
      adaptation:'Complete original universal layout implementation in the shared original widget type namespace.'});
    changes.push({path:local,originalAfterSHA256:sha(original),added:true});
  }
  {
    const name='expo-modules-core',relative='ios/Core/Coding/JavaScriptCodable+Color.swift',archive=archives.get(name),publication=publications.get(name);
    const upstream='packages/'+name+'/'+relative;
    if(archive.paths.has('package/'+relative)&&!manifest.files.some(entry=>entry.repository==='expo/expo'&&entry.upstream===upstream)) {
      const local='Packages/HanlinExpoWidgetSubset/Sources/HanlinExpoWidgetSubset/Core/Upstream/Core/Coding/JavaScriptCodable+Color.swift';
      const original=tarMember(archive.file,relative),adapted=originalInHostTarget(original,local);files.set(local,adapted);
      manifest.files.push({repository:'expo/expo',upstream,upstreamBlob:blob(original),local,localSHA256:sha(adapted),byteIdentical:false,
        upstreamPublication:{package:name,version:publication.version,tarball:publication.dist.tarball,sha256:archive.sha256,path:relative},
        adaptation:'Original Any/JSON color conversion with existing checked numeric conversions; foreground original Core owns the JSI decode overloads.'});
      changes.push({path:local,originalAfterSHA256:sha(original),added:true});
    }
  }
  // Keep the complete original foreground module, including newly published files.
  const fullWidgetsRoot='Packages/HanlinExpoRuntime/Sources/ExpoWidgets/Original/';
  if(manifest.files.some(entry=>entry.local.startsWith(fullWidgetsRoot))) {
    const name='expo-widgets',archive=archives.get(name),publication=publications.get(name);
    const knownFiles=new Set(manifest.files.map(entry=>entry.local));
    for(const item of [...archive.paths].sort()) {
      if(!item.startsWith('package/ios/')||!item.endsWith('.swift'))continue;
      const relative=item.slice('package/'.length),local=fullWidgetsRoot+relative.slice('ios/'.length);
      if(knownFiles.has(local))continue;
      if(existsSync(path.join(root,local)))throw new Error('New original Expo Widgets source collides with host source: '+local);
      const original=tarMember(archive.file,relative);
      const adapted=original.toString().includes('import Foundation')?original:Buffer.from('import Foundation\n'+original);
      files.set(local,adapted);
      manifest.files.push({repository:'expo/expo',upstream:'packages/expo-widgets/'+relative,
        upstreamBlob:blob(original),local,localSHA256:sha(adapted),byteIdentical:Buffer.compare(original,adapted)===0,
        upstreamPublication:{package:name,version:publication.version,tarball:publication.dist.tarball,sha256:archive.sha256,path:relative},
        adaptation:'Complete original ExpoWidgets source; explicit Foundation import replaces CocoaPods umbrella scope.'});
      changes.push({path:local,originalAfterSHA256:sha(original),added:true});
    }
  }
  await closeOriginalWidgetTypes({root,cache,files,manifest,changes,publications,archives});
  const widgetModifier='Packages/HanlinExpoWidgetSubset/Sources/HanlinExpoWidgetSubset/ExpoUI/Modifiers/WidgetModifiers.swift';
  const hasOriginalWidgetInstaller=files.get(widgetModifier)?.toString().includes('public func registerWidgetModifiers()');
  files.set('Packages/HanlinExpoWidgetSubset/Sources/HanlinExpoWidgetSubset/HanlinExpoWidgetOriginalBootstrap.swift',
    '// Generated from the original widget registration layout.\n@MainActor\npublic enum HanlinExpoWidgetOriginalBootstrap {\n    private static var installed = false\n    public static func install() {\n        guard !installed else { return }\n        installed = true\n        _ = ViewModifierRegistry.shared\n'+(hasOriginalWidgetInstaller?'        registerWidgetModifiers()\n':'')+'    }\n}\n');
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
  const serviceRoot='Packages/HanlinPlatform/Sources/HanlinScriptWidgetOriginal/Original/';
  if(manifest.files.some(entry=>entry.local.startsWith(serviceRoot))) {
    const originalRoot='Shared/ScriptWidgetRuntime/';
    const knownServiceFiles=new Set(manifest.files.map(entry=>entry.local));
    for(const item of tree.tree??[]) {
      if(item.type!=='blob'||!item.path.startsWith(originalRoot)||!item.path.endsWith('.swift'))continue;
      const relative=item.path.slice(originalRoot.length);
      if(!['Common/','Plugin/','Widget/API/','Widget/Runtime/'].some(folder=>relative.startsWith(folder))&&relative!=='Widget/Component/ScriptWidgetRuntimeElement.swift')continue;
      const local=serviceRoot+relative;if(knownServiceFiles.has(local))continue;
      if(existsSync(path.join(root,local)))throw new Error('New original service source collides with a host file: '+local);
      const bytes=await source(raw('everettjf/scriptwidget',commit,item.path),cache);files.set(local,bytes);
      manifest.files.push({repository:'everettjf/scriptwidget',commit,upstream:item.path,upstreamBlob:blob(bytes),local,localSHA256:sha(bytes),byteIdentical:true,adaptation:'Original service/core dependency in the dedicated original ScriptWidget module.'});
      changes.push({path:local,originalAfterSHA256:sha(bytes),added:true});
    }
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
