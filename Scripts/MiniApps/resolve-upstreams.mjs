#!/usr/bin/env node
// Resolve one original upstream graph before native compilation. A failed update
// fails the build; a new JavaScript graph is never paired with old native inputs.
import {createHash} from 'node:crypto';
import {createReadStream, createWriteStream, existsSync} from 'node:fs';
import {mkdir, readFile, writeFile, rename, rm} from 'node:fs/promises';
import {execFileSync} from 'node:child_process';
import {pipeline} from 'node:stream/promises';
import {Readable} from 'node:stream';
import {tmpdir} from 'node:os';
import path from 'node:path';
import {fileURLToPath, pathToFileURL} from 'node:url';
import {refreshOriginalSources} from './refresh-original-sources.mjs';
import {fetchOriginalResponse} from './upstream-fetch.mjs';

const here=path.dirname(fileURLToPath(import.meta.url));
const json=async file=>JSON.parse(await readFile(file,'utf8'));
const hash=bytes=>createHash('sha256').update(bytes).digest('hex');
const pretty=value=>JSON.stringify(value,null,2)+'\n';
function run(command,args,options={}) { return execFileSync(command,args,{encoding:'utf8',maxBuffer:32*1024*1024,...options}); }

export function latestMetadata(result) {
  const values=Array.isArray(result)?result:[result];
  const selected=values.at(-1);
  if(!selected?.name||!selected?.version||!selected?.dist?.tarball||!selected?.dist?.integrity)throw new Error('Incomplete original npm publication metadata');
  return selected;
}
export async function resolvePublication(name,range='latest') {
  return latestMetadata(JSON.parse(run('npm',['view',`${name}@${range}`,'--json','--registry=https://registry.npmjs.org'])));
}
export function expoRanges(expo,bundled) {
  const required=['@expo/ui','expo-brownfield','react','react-native','react-native-worklets'];
  for(const name of required)if(!bundled[name])throw new Error(`Original Expo ${expo.version} matrix does not specify ${name}`);
  const expoOwned=['expo-modules-core','expo-asset'];
  for(const name of expoOwned)if(!expo.dependencies?.[name])throw new Error('Expo publication does not specify '+name);
  return Object.fromEntries([...required.map(name=>[name,bundled[name]]),...expoOwned.map(name=>[name,expo.dependencies[name]])]);
}
export function reactTypesSelection(expo,reactNative,pinned) {
  const constraints=[
    {source:'react-native@'+reactNative.version+' peerDependencies',range:reactNative.peerDependencies?.['@types/react']},
    {source:'expo@'+expo.version+' devDependencies',range:expo.devDependencies?.['@types/react']}
  ].filter(item=>typeof item.range==='string'&&item.range.trim());
  if(!constraints.length)return {mode:'explicit-pin',requested:pinned,constraints,reason:'Original selected publications provide no React declaration version constraint.'};
  // Semver has conjunction and || but no grouping. Distribute the conjunction
  // so that neither original publication's compatibility range is weakened.
  let alternatives=[''];
  for(const {range} of constraints)alternatives=alternatives.flatMap(left=>range.split('||').map(right=>(left+' '+right.trim()).trim()));
  return {mode:'original-compatible-range',requested:alternatives.join(' || '),constraints};
}
export function compilerSelections(expoPackage,nsPackage,publications) {
  return {
    expo:{mode:'explicit-verified-host-toolchain',requested:expoPackage.devDependencies.typescript,
      upstreamPeerRange:publications.get('expo')?.peerDependencies?.typescript??null,
      reason:'Retain the explicitly verified host compiler. Original consumer peer constraints remain part of npm graph resolution; an absent or unconstrained peer does not select an arbitrary newest compiler.'},
    nativescript:{mode:'explicit-verified-host-toolchain',requested:nsPackage.devDependencies.typescript,
      upstreamPeerRange:publications.get('@nativescript/vite')?.peerDependencies?.typescript??null,
      reason:'Retain the verified NativeScript host compiler; an unconstrained original Vite peer does not select an arbitrary newest compiler.'}
  };
}
async function fileDigest(file,algorithm='sha256',encoding='hex') {
  const digest=createHash(algorithm);for await(const chunk of createReadStream(file))digest.update(chunk);return digest.digest(encoding);
}
async function request(url) {
  return fetchOriginalResponse(url,{timeoutMs:120000,accept:'application/json'});
}
async function download(url,file) {
  await mkdir(path.dirname(file),{recursive:true});
  const temporary=file+`.tmp-${process.pid}`;
  try {const response=await request(url);await pipeline(Readable.fromWeb(response.body),createWriteStream(temporary));await rename(temporary,file);}
  finally {await rm(temporary,{force:true});}
}
async function publicationArchive(publication,cache) {
  const file=path.join(cache,publication.name.replaceAll('/','_')+'-'+publication.version+'.tgz');
  if(!existsSync(file))await download(publication.dist.tarball,file);
  const integrity=publication.dist.integrity.split(/\s+/).find(item=>item.startsWith('sha512-'))??publication.dist.integrity.split(/\s+/)[0];
  const separator=integrity.indexOf('-'),algorithm=integrity.slice(0,separator),expected=integrity.slice(separator+1);
  if(!['sha512','sha256','sha1'].includes(algorithm)||await fileDigest(file,algorithm,'base64')!==expected)throw new Error(`Original npm integrity mismatch: ${publication.name}@${publication.version}`);
  return {file,sha256:await fileDigest(file),paths:new Set(run('tar',['-tzf',file]).trim().split('\n'))};
}
function member(archive,relative) {return run('tar',['-xOf',archive.file,'package/'+relative]);}
function sourceRecord(publication,archive) {return {package:publication.name,version:publication.version,tarball:publication.dist.tarball,integrity:publication.dist.integrity,sha256:archive.sha256};}
async function mavenArtifact(url,cache) {
  // Maven Central publishes a digest next to each release. The native preparer
  // authenticates the actual archive bytes against this digest before extraction.
  const response=await fetch(url+'.sha256',{signal:AbortSignal.timeout(60000)});
  if(response.ok) {const digest=(await response.text()).trim().split(/\s+/)[0];if(/^[a-f0-9]{64}$/i.test(digest))return digest.toLowerCase();}
  const file=path.join(cache,path.basename(new URL(url).pathname));
  if(!existsSync(file))await download(url,file);
  return fileDigest(file);
}
function gitTagRevision(repository,version) {
  const lines=run('git',['ls-remote','--tags',repository,`refs/tags/${version}`,`refs/tags/${version}^{}`,`refs/tags/v${version}`,`refs/tags/v${version}^{}`]).trim().split('\n').filter(Boolean);
  const selected=lines.find(line=>line.endsWith('^{}'))??lines[0];
  const revision=selected?.split(/\s+/)[0];if(!/^[a-f0-9]{40}$/.test(revision??''))throw new Error(`No exact original NativeScript iOS tag ${version}`);return revision;
}
export function generatedHostVersions(versions) {
  const expo=versions.expo,ns=versions.nativescript;
  const fields={nativeScriptRuntimeVersion:ns['@nativescript/ios'],nativeScriptCoreVersion:ns['@nativescript/core'],nativeScriptSwiftUIVersion:ns['@nativescript/swift-ui'],expoSDKVersion:expo.expo,expoUIVersion:expo['@expo/ui'],expoAssetVersion:expo['expo-asset'],expoWidgetsVersion:expo['expo-widgets'],reactNativeVersion:expo['react-native'],nativeApiVersion:expo['@nativescript/react-native'],reactNativeWorkletsVersion:expo['react-native-worklets']};
  for(const [name,value] of Object.entries(fields))if(!/^\d+\.\d+\.\d+(?:[-+][\w.-]+)?$/.test(value??''))throw new Error(`Missing exact host version: ${name}`);
  const revision=versions.scriptwidget?.revision;
  if(revision&&!/^[a-f0-9]{40}$/.test(revision))throw new Error('Missing exact ScriptWidget source revision');
  return '// Generated from the exact upstream package and native dependency locks.\n// Updated together by Scripts/MiniApps/resolve-upstreams.mjs before the host build.\npublic enum HanlinMiniAppHostVersions {\n'+Object.entries(fields).map(([name,value])=>`    public static let ${name} = ${JSON.stringify(value)}`).join('\n')+(revision?`\n    public static let scriptWidgetRevision = ${JSON.stringify(revision)}`:'')+'\n}\n';
}
export function generatedNativeScriptHostVersions(versions) {
  const ns=versions.nativescript;
  const fields={runtimeVersion:ns['@nativescript/ios'],coreVersion:ns['@nativescript/core'],swiftUIVersion:ns['@nativescript/swift-ui']};
  for(const [name,value] of Object.entries(fields))if(!/^\d+\.\d+\.\d+(?:[-+][\w.-]+)?$/.test(value??''))throw new Error(`Missing exact NativeScript host version: ${name}`);
  return '// Generated from the same exact original NativeScript inputs as the importer.\nenum HanlinNativeScriptHostVersions {\n'+Object.entries(fields).map(([name,value])=>`    static let ${name} = ${JSON.stringify(value)}`).join('\n')+'\n}\n';
}

export function generatedExpoHostVersions(versions,hermesVersion) {
  const expo=versions.expo;
  const fields={runtimeVersion:expo['@expo/ui'],expoSDKVersion:expo.expo,expoUIVersion:expo['@expo/ui'],reactNativeVersion:expo['react-native'],hermesVersion,nativeApiVersion:expo['@nativescript/react-native'],workletsVersion:expo['react-native-worklets'],nativeApiAbiIdentity:`rn${expo['react-native']}-hermes${hermesVersion}`};
  if(Object.values(fields).some(value=>typeof value!=='string'||!value.length))throw new Error('Incomplete actual Expo host version graph');
  return '// Generated from the same exact original inputs used by the native framework producer.\nenum HanlinExpoHostVersions {\n'+Object.entries(fields).map(([name,value])=>`    static let ${name} = ${JSON.stringify(value)}`).join('\n')+'\n}\n';
}

export function generatedNativeAPIHostVersions(versions) {
  const fields={nativeApiVersion:versions.expo['@nativescript/react-native'],
    workletsVersion:versions.expo['react-native-worklets'],reactNativeVersion:versions.expo['react-native']};
  for(const [name,value] of Object.entries(fields))if(!/^\d+\.\d+\.\d+(?:[-+][\w.-]+)?$/.test(value??''))throw new Error('Missing exact Native API host version: '+name);
  return '// Generated from the exact original Native API and React Native build graph.\nenum HanlinExpoNativeAPIHostVersions {\n'+
    Object.entries(fields).map(([name,value])=>`    static let ${name} = ${JSON.stringify(value)}`).join('\n')+'\n}\n';
}

// Keep the public metadata in the same write/rollback set as its peer packages
// and native consumers. All upstream callable exports remain byte-for-byte intact.
export function updatedNativeAPIFacadeVersions(source, versions) {
  const fields={UPSTREAM_VERSION:versions.expo['@nativescript/react-native'],
    WORKLETS_VERSION:versions.expo['react-native-worklets']};
  for(const [name,value] of Object.entries(fields)) {
    if(!/^\d+\.\d+\.\d+(?:[-+][\w.-]+)?$/.test(value??''))throw new Error('Missing exact Native API facade version: '+name);
    const pattern=new RegExp('^(export const '+name+' = )"[^"\\r\\n]*"(;)$','gm');
    if([...source.matchAll(pattern)].length!==1)throw new Error('Expected one exported Native API facade version: '+name);
    source=source.replace(pattern,(_,prefix,suffix)=>prefix+JSON.stringify(value)+suffix);
  }
  return source;
}

// The original C++ runtime stringizes this bare macro token as its native version.
// Keep the local SwiftPM input in the same resolver write/rollback set as npm.
export function updatedWorkletsPackageVersion(source, versions) {
  const version=versions.expo['react-native-worklets'];
  if(!/^\d+\.\d+\.\d+(?:[-+][\w.-]+)?$/.test(version??''))throw new Error('Missing exact Worklets compiler version');
  // Accept the former quoted input only to repair it to the original podspec form.
  const pattern=/"-DWORKLETS_VERSION=(?:\d+\.\d+\.\d+(?:[-+][\w.-]+)?|\\"\d+\.\d+\.\d+(?:[-+][\w.-]+)?\\")"/g;
  if([...source.matchAll(pattern)].length!==1||(source.match(/-DWORKLETS_VERSION\b/g)??[]).length!==1)
    throw new Error('Expected one literal Worklets compiler version in the native package');
  return source.replace(pattern,JSON.stringify('-DWORKLETS_VERSION='+version));
}

// Runtime identity follows the installed original Expo UI graph. The reviewed
// Apple API inventory and the independent Hanlin bridge ABI remain unchanged.
export const expoBridgeRuntimeMetadataPaths = Object.freeze([
  'Tools/SwiftUIBridge/configuration.json',
  'Generated/SwiftUIBridge/bridge-manifest.ts',
  'Packages/HanlinExpoUI/src/generated/bridge-manifest.ts',
  'Generated/SwiftUIBridge/HanlinGeneratedViews.swift',
  'Packages/HanlinExpoRuntime/Sources/HanlinExpoRuntime/Generated/HanlinGeneratedViews.swift',
]);

export async function updatedExpoBridgeRuntimeMetadata(read, versions) {
  const runtimeVersion = versions.expo?.['@expo/ui'];
  if (!/^\d+\.\d+\.\d+(?:[-+][\w.-]+)?$/.test(runtimeVersion ?? '')) {
    throw new Error('Missing exact Expo UI runtime version');
  }
  const files = new Map();
  for (const file of expoBridgeRuntimeMetadataPaths) {
    const source = await read(file);
    let pattern;
    if (file.endsWith('.json')) {
      if (typeof JSON.parse(source).runtimeVersion !== 'string') throw new Error('Missing Expo public runtime metadata: '+file);
      pattern = /^([ \t]*"runtimeVersion"\s*:\s*")[^"\r\n]+(")/gm;
    } else if (file.endsWith('.ts')) {
      pattern = /^(export const HANLIN_EXPO_RUNTIME_VERSION = ')[^'\r\n]+(' as const;)$/gm;
    } else {
      pattern = /^([ \t]*public static let runtimeVersion = ")[^"\r\n]+(")$/gm;
    }
    if ([...source.matchAll(pattern)].length !== 1) throw new Error('Expected one Expo public runtime metadata declaration: '+file);
    files.set(file, source.replace(pattern, (_, prefix, suffix) => prefix+runtimeVersion+suffix));
  }
  return files;
}

export async function resolveUpstreams({root=path.resolve(here,'../..'),cache=path.join(tmpdir(),'hanlin-miniapp-upstreams'),apply=false,report=path.join(root,'build/acceptance/miniapp-upstreams/resolution.json')}={}) {
  await mkdir(cache,{recursive:true});
  const expoPackage=await json(path.join(root,'Scripts/Expo/package.json'));
  const nsPackage=await json(path.join(root,'Scripts/NativeScript/package.json'));
  const expoLock=await json(path.join(root,'Scripts/Expo/dependency-lock.json'));
  const nsLock=await json(path.join(root,'Scripts/NativeScript/dependency-lock.json'));
  const nativeLock=await json(path.join(root,'Scripts/ExpoNativeAPI/dependency-lock.json'));
  const publications=new Map(),archives=new Map();
  const resolvePackage=async(name,range='latest')=>{const publication=await resolvePublication(name,range);publications.set(name,publication);return publication;};
  const archive=async name=>{if(!archives.has(name))archives.set(name,await publicationArchive(publications.get(name),cache));return archives.get(name);};
  const expo=await resolvePackage('expo');
  const bundled=JSON.parse(member(await archive('expo'),'bundledNativeModules.json'));
  for(const [name,range] of Object.entries(expoRanges(expo,bundled)))await resolvePackage(name,range);
  const core=publications.get('expo-modules-core');
  await resolvePackage('expo-modules-jsi',core.dependencies?.['expo-modules-jsi']??(()=>{throw new Error('Original Core does not specify its JSI dependency');})());
  await resolvePackage('expo-widgets',bundled['expo-widgets']??'latest');
  await resolvePackage('@nativescript/react-native');
  for(const name of ['@nativescript/core','@nativescript/ios','@nativescript/swift-ui','@nativescript/types','@nativescript/vite'])await resolvePackage(name);
  const rn=publications.get('react-native');
  const reactTypes=reactTypesSelection(expo,rn,expoPackage.devDependencies['@types/react']);
  if(reactTypes.mode==='original-compatible-range')await resolvePackage('@types/react',reactTypes.requested);
  const compilers=compilerSelections(expoPackage,nsPackage,publications);
  for(const name of ['@react-native/codegen','@react-native/metro-config'])await resolvePackage(name,rn.version);
  await resolvePackage('babel-preset-expo',expo.dependencies['babel-preset-expo']);
  const rnArchive=await archive('react-native');
  const hermes=member(rnArchive,'sdks/hermes-engine/version.properties').match(/^HERMES_VERSION_NAME=(.+)$/m)?.[1]?.trim();
  if(!hermes)throw new Error('Original React Native publication has no Hermes identity');
  const nsCore=publications.get('@nativescript/core').version,nsIOS=publications.get('@nativescript/ios').version;
  if(nsCore.split('.')[0]!==nsIOS.split('.')[0])throw new Error(`Original NativeScript stable Core/runtime major mismatch: ${nsCore}/${nsIOS}`);
  const versions={expo:{},nativescript:{}};
  for(const [name,publication] of publications)versions[name.startsWith('@nativescript/')&&name!=='@nativescript/react-native'?'nativescript':'expo'][name]=publication.version;
  const originals={};
  for(const name of ['expo','@expo/ui','expo-asset','expo-brownfield','expo-modules-core','expo-modules-jsi','expo-widgets','react-native','react-native-worklets','@nativescript/react-native','@nativescript/swift-ui'])originals[name]=sourceRecord(publications.get(name),await archive(name));
  const updatedExpo=structuredClone(expoLock);
  updatedExpo.expo={sdkVersion:expo.version,uiVersion:versions.expo['@expo/ui'],assetVersion:versions.expo['expo-asset'],widgetsVersion:versions.expo['expo-widgets'],brownfieldVersion:versions.expo['expo-brownfield'],modulesCoreVersion:versions.expo['expo-modules-core'],reactNativeVersion:rn.version,reactVersion:versions.expo.react,hermesVersion:hermes};
  for(const item of updatedExpo.artifacts) {
    if(item.package) {
      const publication=publications.get(item.package),input=await archive(item.package);
      Object.assign(item,{version:publication.version,tarball:publication.dist.tarball,sha256:input.sha256});
      const expectedSubpath=item.subpath??(['ExpoUI','ExpoAsset'].includes(item.name)?'package/prebuilds/output/release/xcframeworks/'+item.name+'.tar.gz':item.name==='ExpoModulesJSI'?'package/apple/Products/ExpoModulesJSI.xcframework':undefined);
      if(!expectedSubpath)throw new Error(`Original native artifact layout is unknown: ${item.name}`);
      if(![...input.paths].some(value=>value===expectedSubpath||value.startsWith(expectedSubpath+'/'))) {
        if(!['ExpoUI','ExpoAsset','ExpoModulesJSI'].includes(item.name))throw new Error(`Original ${item.package}@${item.version} removed ${item.subpath}; no source producer for ${item.name}`);
        item.source='npm-source';item.sourceBuild={producer:item.name==='ExpoModulesJSI'?'original-swiftpm':'original-cocoapods',packageIntegrity:publication.dist.integrity};
        delete item.subpath;
      } else {item.subpath=expectedSubpath;item.source=item.name==='ExpoModulesJSI'?'npm-extract':'npm';delete item.sourceBuild;}
    } else {
      item.url=item.url.replaceAll(expoLock.expo.reactNativeVersion,rn.version).replaceAll(expoLock.expo.hermesVersion,hermes);
      item.sha256=await mavenArtifact(item.url,cache);
    }
  }
  const nsSPMRevision=gitTagRevision(nsLock.nativeScript.iosSPMRepository,nsIOS);
  const updatedNS=structuredClone(nsLock);
  Object.assign(updatedNS.nativeScript,{coreVersion:nsCore,iosRuntimeVersion:nsIOS,iosSPMTagRevision:nsSPMRevision});
  const swiftUI=publications.get('@nativescript/swift-ui'),swiftArchive=await archive('@nativescript/swift-ui');
  Object.assign(updatedNS.swiftUI,{version:swiftUI.version,registryTarball:swiftUI.dist.tarball,integrity:swiftUI.dist.integrity,shasum:swiftUI.dist.shasum,tarballSHA256:swiftArchive.sha256});
  for(const file of Object.keys(updatedNS.swiftUI.runtimeFiles))updatedNS.swiftUI.runtimeFiles[file]=hash(member(swiftArchive,file));
  updatedNS.swiftUI.upstreamNativeContract.sha256=hash(member(swiftArchive,updatedNS.swiftUI.upstreamNativeContract.path));
  const updatedNative=structuredClone(nativeLock);
  for(const [name,key] of [['@nativescript/react-native','nativeApi'],['react-native-worklets','worklets']]) {
    const publication=publications.get(name),input=await archive(name);
    Object.assign(updatedNative[key],{version:publication.version,distIntegrity:publication.dist.integrity,tarballUrl:publication.dist.tarball,sha256:input.sha256});
  }
  if(updatedNative.nativeApi.version!==nativeLock.nativeApi.version) {
    // Requiring the actual published schema is necessary when the bridge changes;
    // removing its native codegen identity would silently accept a different API.
    const current=member(await archive('@nativescript/react-native'),'package.json');
    const codegen=JSON.parse(current).codegenConfig;
    if(JSON.stringify(codegen)!==JSON.stringify({name:nativeLock.nativeApi.codegen.name,type:nativeLock.nativeApi.codegen.type,jsSrcsDir:nativeLock.nativeApi.codegen.jsSrcsDir}))throw new Error('Native API codegen contract changed; regenerate its exact schema before native compilation');
  }
  updatedNative.runtimeClosure={reactNativeVersion:rn.version,reactVersion:versions.expo.react,expoSdkVersion:expo.version,hermesVersion:hermes};
  for(const name of Object.keys(expoPackage.dependencies))if(versions.expo[name])expoPackage.dependencies[name]=versions.expo[name];
  for(const name of Object.keys(expoPackage.devDependencies))if(versions.expo[name])expoPackage.devDependencies[name]=versions.expo[name];
  for(const name of Object.keys(expoPackage.overrides))if(versions.expo[name])expoPackage.overrides[name]=versions.expo[name];
  for(const kind of ['dependencies','devDependencies'])for(const name of Object.keys(nsPackage[kind]))if(versions.nativescript[name])nsPackage[kind][name]=versions.nativescript[name];
  const files=new Map([
    ['Scripts/Expo/package.json',pretty(expoPackage)],['Scripts/Expo/dependency-lock.json',pretty(updatedExpo)],
    ['Scripts/NativeScript/package.json',pretty(nsPackage)],['Scripts/NativeScript/dependency-lock.json',pretty(updatedNS)],
    ['Scripts/ExpoNativeAPI/dependency-lock.json',pretty(updatedNative)],
    ['Packages/HanlinExpoNativeAPI/Package.swift',updatedWorkletsPackageVersion(await readFile(path.join(root,'Packages/HanlinExpoNativeAPI/Package.swift'),'utf8'),versions)],
    ['Packages/HanlinPlatform/Sources/HanlinScriptCompiler/HanlinMiniAppHostVersions.swift',generatedHostVersions(versions)],
    ['Packages/HanlinNativeScriptRuntime/Sources/HanlinNativeScriptRuntime/HanlinNativeScriptHostVersions.swift',generatedNativeScriptHostVersions(versions)],
    ['Packages/HanlinExpoRuntime/Sources/HanlinExpoRuntime/HanlinExpoHostVersions.swift',generatedExpoHostVersions(versions,hermes)],
    ['Packages/HanlinExpoNativeAPI/Sources/HanlinExpoNativeAPI/HanlinExpoNativeAPIHostVersions.swift',generatedNativeAPIHostVersions(versions)],
    ['Packages/HanlinExpoNativeAPIJS/src/index.ts',updatedNativeAPIFacadeVersions(await readFile(path.join(root,'Packages/HanlinExpoNativeAPIJS/src/index.ts'),'utf8'),versions)]
  ]);
  for(const [file,content] of await updatedExpoBridgeRuntimeMetadata(file=>readFile(path.join(root,file),'utf8'),versions))files.set(file,content);
  for(const name of ['Packages/HanlinExpoUI/package.json','Packages/HanlinExpoNativeAPIJS/package.json']) {
    const local=await json(path.join(root,name));for(const dependency of Object.keys(local.peerDependencies??{}))if(versions.expo[dependency])local.peerDependencies[dependency]=versions.expo[dependency];files.set(name,pretty(local));
  }
  for(const name of ['Fixtures/ExpoSwiftUIProbe/package.json','Fixtures/ExpoNativeAPIProbe/package.json','Fixtures/ExpoWidgetsProbe/package.json']) {
    let fixture;
    if(existsSync(path.join(root,name)))fixture=await json(path.join(root,name));
    else {try {fixture=JSON.parse(run('git',['-C',root,'show','HEAD:'+name]));}catch {continue;}}
    for(const dependency of Object.keys(fixture.dependencies??{}))if(versions.expo[dependency])fixture.dependencies[dependency]=versions.expo[dependency];
    for(const [dependency,localPath] of [['@hanlin/expo-ui','Packages/HanlinExpoUI/package.json'],['@hanlin/expo-native-api','Packages/HanlinExpoNativeAPIJS/package.json']]) {
      if(fixture.dependencies?.[dependency])fixture.dependencies[dependency]=JSON.parse(files.get(localPath)).version;
    }
    if(fixture.hanlinExpo) {
      fixture.hanlinExpo.runtimeVersion=versions.expo['@expo/ui'];
      for(const dependency of Object.keys(fixture.hanlinExpo.plugins??{}))if(versions.expo[dependency])fixture.hanlinExpo.plugins[dependency]=versions.expo[dependency];
    }
    files.set(name,pretty(fixture));
  }
  const spmPath='Packages/HanlinNativeScriptRuntime/Package.swift';
  const spm=await readFile(path.join(root,spmPath),'utf8');
  const oldExact=`exact: "${nsLock.nativeScript.iosRuntimeVersion}"`;
  if(spm.split(oldExact).length!==2)throw new Error('NativeScript SwiftPM exact version input does not match native lock');
  files.set(spmPath,spm.replace(oldExact,`exact: "${nsIOS}"`));
  const resolvedPath='AI_HLY.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved';
  if(existsSync(path.join(root,resolvedPath))) {
    const resolved=await json(path.join(root,resolvedPath));
    for(const pin of resolved.pins??[])if(pin.identity==='ios-spm')pin.state={revision:nsSPMRevision,version:nsIOS};
    files.set(resolvedPath,pretty(resolved));
  }
  const sourceUpdate=await refreshOriginalSources({root,cache,publications,archives});
  for(const [name,bytes] of sourceUpdate.files)files.set(name,bytes);
  versions.scriptwidget={revision:sourceUpdate.receipt.scriptWidgetCommit};
  files.set('Packages/HanlinPlatform/Sources/HanlinScriptCompiler/HanlinMiniAppHostVersions.swift',generatedHostVersions(versions));
  // Validate the original completion catalog before touching the host checkout.
  // The candidate also retains the precise merged bytes for review/reproduction.
  const candidate=path.join(cache,'candidate-inputs');
  await rm(candidate,{recursive:true,force:true});
  for(const [name,bytes] of files) {const target=path.join(candidate,name);await mkdir(path.dirname(target),{recursive:true});await writeFile(target,bytes);}
  for(const name of ['Scripts/MiniApps/generate-scriptwidget-types.mjs','Scripts/MiniApps/scriptwidget/upstream/package.json']) {
    const target=path.join(candidate,name);await mkdir(path.dirname(target),{recursive:true});await writeFile(target,await readFile(path.join(root,name)));
  }
  run(process.execPath,[path.join(candidate,'Scripts/MiniApps/generate-scriptwidget-types.mjs')],{stdio:'inherit'});
  files.set('Scripts/MiniApps/scriptwidget/components.d.ts',await readFile(path.join(candidate,'Scripts/MiniApps/scriptwidget/components.d.ts')));
  const receipt={schemaVersion:1,typingSelection:{react:reactTypes,compilers},versions,hermesVersion:hermes,originals,iosSPM:{repository:nsLock.nativeScript.iosSPMRepository,version:nsIOS,revision:nsSPMRevision},sourceUpdates:sourceUpdate.receipt,nativeArtifacts:updatedExpo.artifacts};
  files.set('Scripts/MiniApps/upstream-resolution.json',pretty(receipt));
  const changes=[];
  for(const [name,content] of files) {const before=existsSync(path.join(root,name))?await readFile(path.join(root,name)):Buffer.alloc(0);if(hash(before)!==hash(content))changes.push({path:name,beforeSHA256:hash(before),afterSHA256:hash(content)});}
  await mkdir(path.dirname(report),{recursive:true});
  const evidence={...receipt,checkedAt:new Date().toISOString(),status:apply?'applying':'resolved',changes};
  await writeFile(report,pretty(evidence));
  if(apply) {
    const backup=new Map();
    const rollbackNames=[...files.keys(),'Scripts/Expo/package-lock.json','Scripts/NativeScript/package-lock.json','Scripts/MiniApps/scriptwidget/components.d.ts','Package.swift','docs/agent-sdk/unified-package-manifest.json'];
    try {
      for(const name of rollbackNames)backup.set(name,existsSync(path.join(root,name))?await readFile(path.join(root,name)):null);
      for(const [name,content] of files) {const full=path.join(root,name);await mkdir(path.dirname(full),{recursive:true});await writeFile(full,content);}
      for(const engine of ['Expo','NativeScript'])run('npm',['install','--package-lock-only','--ignore-scripts','--no-audit','--no-fund','--prefix',path.join(root,'Scripts',engine)],{stdio:'inherit'});
      run(process.execPath,[path.join(root,'Scripts/MiniApps/generate-scriptwidget-types.mjs')],{stdio:'inherit'});
      run('python3',[path.join(root,'Scripts/SDK/generate_manifest.py')],{cwd:root,stdio:'inherit'});
      evidence.status='applied-awaiting-native-build';
      evidence.packageLockSHA256=Object.fromEntries(await Promise.all(['Expo','NativeScript'].map(async engine=>[engine,hash(await readFile(path.join(root,'Scripts',engine,'package-lock.json')))])));
      await writeFile(report,pretty(evidence));
    } catch(error) {
      for(const [name,content] of backup) {if(content===null)await rm(path.join(root,name),{force:true});else await writeFile(path.join(root,name),content);}
      evidence.status='failed-inputs-restored';evidence.error=String(error);await writeFile(report,pretty(evidence));throw error;
    }
  }
  console.log(`MiniApp originals ${apply?'applied':'resolved'}: Expo ${expo.version}, React Native ${rn.version}, NativeScript ${nsCore}/${nsIOS}; ${changes.length} source input changes. Report: ${report}`);
  return evidence;
}
if(process.argv[1]&&pathToFileURL(path.resolve(process.argv[1])).href===import.meta.url) {
  const value=name=>process.argv.find(arg=>arg.startsWith(`--${name}=`))?.slice(name.length+3);
  const root=value('repository')??path.resolve(here,'../..');
  const report=value('report')??path.join(root,'build/acceptance/miniapp-upstreams/resolution.json');
  resolveUpstreams({root,cache:value('cache'),report,apply:process.argv.includes('--apply')}).catch(async error=>{
    console.error(error.stack);process.exitCode=1;
    let evidence={schemaVersion:1,checkedAt:new Date().toISOString(),status:'failed-resolution-no-new-host-built'};
    if(existsSync(report)) {try {evidence=await json(report);}catch{}}
    evidence.status=evidence.status==='failed-inputs-restored'?evidence.status:'failed-resolution-no-new-host-built';evidence.error=String(error);
    await mkdir(path.dirname(report),{recursive:true});await writeFile(report,pretty(evidence));
  });
}
