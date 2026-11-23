#!/usr/bin/env node
/** Assemble authoring SDK from the exact packages used by the native host build. */
import {createHash} from 'node:crypto';
import {cp, mkdir, readFile, readdir, realpath, rename, rm, stat, writeFile} from 'node:fs/promises';
import path from 'node:path';
import {fileURLToPath, pathToFileURL} from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
export const repositoryRoot = path.resolve(here, '../..');
const sha = value => createHash('sha256').update(value).digest('hex');
const readJSON = async p => JSON.parse(await readFile(p, 'utf8'));
const writeJSON = async (p, data) => writeFile(p, JSON.stringify(data, null, 2) + '\n');
const noNative = /(?:\.(?:a|o|dylib|so|node|dll|exe|pdb|xcframework|framework|app|tgz|tar|gz|zip)$)/i;
const sourceFile = /(?:\.(?:[cm]?js|jsx|tsx?|json|map|md|txt|yaml|yml|css|html|wasm|png|jpe?g|webp|gif|svg|ttf|otf)$|(?:^|\/)(?:LICENSE|NOTICE|COPYING|AUTHORS)(?:\.[^/]*)?$)/i;
const excludedDirectories = new Set(['.git', '.bin', '.cache', 'prebuilds', 'Pods', 'DerivedData']);
const isNativeDirectory = name => /\.(?:xcframework|framework|app)$/.test(name);

/** No rewrites: every retained source byte is copied from the installed upstream. */
export async function copyAuthoringTree(source, destination, receipt, label, ancestors = new Set()) {
  const canonical = await realpath(source);
  if (ancestors.has(canonical)) throw new Error('SDK source symlink cycle: ' + label);
  const nextAncestors = new Set(ancestors).add(canonical);
  await mkdir(destination, {recursive:true});
  for (const item of (await readdir(source, {withFileTypes:true})).sort((a,b)=>a.name.localeCompare(b.name))) {
    if (excludedDirectories.has(item.name) || isNativeDirectory(item.name)) continue;
    const src = path.join(source,item.name), dest = path.join(destination,item.name);
    const relative = path.posix.join(label,item.name);
    const info = item.isSymbolicLink() ? await stat(src) : item;
    if (info.isDirectory()) {
      await copyAuthoringTree(src,dest,receipt,relative,nextAncestors);
    } else if (info.isFile() && !noNative.test(item.name) && sourceFile.test(item.name)) {
      const bytes = await readFile(src);
      await writeFile(dest,bytes);
      receipt.push({path:relative,sha256:sha(bytes),bytes:bytes.length});
    }
  }
}

export async function verifyInstalledGraph(toolingRoot) {
  const lock = await readJSON(path.join(toolingRoot,'package-lock.json'));
  const root = await readJSON(path.join(toolingRoot,'package.json'));
  const direct = {...root.dependencies,...root.devDependencies};
  const versions = {};
  for (const [name, requested] of Object.entries(direct)) {
    const packagePath = path.join(toolingRoot,'node_modules',name,'package.json');
    const installed = await readJSON(packagePath);
    const locked = lock.packages?.['node_modules/' + name];
    // Local Hanlin packages are versioned by their source digest, npm packages by integrity.
    if (!requested.startsWith('file:') && (!locked?.integrity || locked.version !== installed.version)) {
      throw new Error('Installed SDK package differs from package-lock: ' + name);
    }
    versions[name] = installed.version;
  }
  return {root,lock,versions};
}

export const sdkInputs = [
 'Scripts/Expo/package.json','Scripts/Expo/package-lock.json','Scripts/Expo/dependency-lock.json',
 'Scripts/Expo/babel.config.cjs','Scripts/Expo/metro.config.cjs','Scripts/Expo/prepare-types.mjs',
 'Scripts/NativeScript/package.json','Scripts/NativeScript/package-lock.json','Scripts/NativeScript/dependency-lock.json',
 'Scripts/ExpoNativeAPI/dependency-lock.json','Tools/SwiftUIBridge/configuration.json',
 'docs/widget-engines/UPSTREAM_SOURCE_MANIFEST.json','docs/miniapp-sdk/source-inventory.json',
 'docs/miniapp-sdk/extension-reachability.json'
];

export async function inputReceipt(root=repositoryRoot) {
  const files=[];
  for(const relative of sdkInputs) {
    const bytes=await readFile(path.join(root,relative));
    files.push({path:relative,sha256:sha(bytes)});
  }
  for(const relative of ['Scripts/MiniApps','Packages/HanlinExpoUI','Packages/HanlinExpoNativeAPIJS',
    'Packages/HanlinNativeScriptRuntime/Sources/HanlinNativeScriptRuntime/Resources/NativeScriptSharedRuntime/@hanlin/host-services',
    'docs/miniapp-sdk','docs/hanlin-nativescript-guide.md','docs/hanlin-expo-runtime.md']) {
    async function walk(src,prefix) {
      const info=await stat(src);
      if(info.isFile()) {
        files.push({path:prefix,sha256:sha(await readFile(src))});return;
      }
      for(const entry of (await readdir(src,{withFileTypes:true})).sort((a,b)=>a.name.localeCompare(b.name))) {
        if(['node_modules','Tests','evidence','.git'].includes(entry.name)||entry.name.includes('.bak.'))continue;
        await walk(path.join(src,entry.name),path.posix.join(prefix,entry.name));
      }
    }
    await walk(path.join(root,relative),relative);
  }
  const unique=[...new Map(files.map(f=>[f.path,f])).values()].sort((a,b)=>a.path.localeCompare(b.path));
  return {files:unique,sha256:sha(JSON.stringify(unique))};
}

export async function stageSDK({root=repositoryRoot,output,engines:requestedEngines=['expo','nativescript','scriptwidget']}={}) {
  if(!requestedEngines.length || requestedEngines.some(x=>!['expo','nativescript','scriptwidget'].includes(x)))throw new Error('Unknown SDK engine selection');
  if(!output)throw new Error('SDK output directory is required');
  const inputs=await inputReceipt(root);
  const staging=output+'.staging-'+process.pid;
  await rm(staging,{recursive:true,force:true});
  await mkdir(staging,{recursive:true});
  const files=[],engines={};
  const nativeLock=await readJSON(path.join(root,'Scripts/NativeScript/dependency-lock.json'));
  const expoLock=await readJSON(path.join(root,'Scripts/Expo/dependency-lock.json'));
  const nativeAPILock=await readJSON(path.join(root,'Scripts/ExpoNativeAPI/dependency-lock.json'));
  try {
    for(const [engine,folder] of [['expo','Expo'],['nativescript','NativeScript']]) {
      if(!requestedEngines.includes(engine))continue;
      const source=path.join(root,'Scripts',folder);
      const graph=await verifyInstalledGraph(source);
      const destination=path.join(staging,engine);
      await mkdir(destination,{recursive:true});
      await copyAuthoringTree(path.join(source,'node_modules'),path.join(destination,'node_modules'),files,engine+'/node_modules');
      if(engine==='nativescript') {
        const hostServices=path.join(root,'Packages/HanlinNativeScriptRuntime/Sources/HanlinNativeScriptRuntime/Resources/NativeScriptSharedRuntime/@hanlin/host-services');
        await copyAuthoringTree(hostServices,path.join(destination,'node_modules/@hanlin/host-services'),files,'nativescript/node_modules/@hanlin/host-services');
        graph.versions['@hanlin/host-services']=(await readJSON(path.join(hostServices,'package.json'))).version;
      }

      for(const name of ['package.json','package-lock.json',...(engine==='expo'?['babel.config.cjs','metro.config.cjs']:[])]) {
        const bytes=await readFile(path.join(source,name));
        await writeFile(path.join(destination,name),bytes);
        files.push({path:engine+'/'+name,sha256:sha(bytes),bytes:bytes.length});
      }
      const compilerOptions={target:'ES2023',module:'ESNext',moduleResolution:'Bundler',
        strict:true,skipLibCheck:false,noEmit:true,allowJs:true,checkJs:false,resolveJsonModule:true,
        allowSyntheticDefaultImports:true,esModuleInterop:true};
      if(engine==='expo') {
        compilerOptions.jsx='react-jsx';
        compilerOptions.lib=['ES2023'];
        compilerOptions.types=['react','react-native'];
        compilerOptions.customConditions=['react-native'];
      } else {
        compilerOptions.lib=['ES2023'];
        compilerOptions.types=['@nativescript/core/global-types','@nativescript/types'];
        compilerOptions.experimentalDecorators=true;
        // NativeScript's original consumer configuration skips checking the
        // internals of upstream .d.ts files. Strict user/API checking remains on;
        // callers can explicitly request declaration-body diagnostics as well.
        compilerOptions.skipLibCheck=true;
      }
      await writeJSON(path.join(destination,'tsconfig.json'),{compilerOptions});
      engines[engine]={toolingRoot:engine,tsconfigPath:engine+'/tsconfig.json',
        typescriptPath:engine+'/node_modules/typescript/lib/typescript.js',
        packageVersions:graph.versions,
        typeCheckingPolicy:{strictSource:true,checkOriginalDeclarationBodies:engine==='expo',
          explanation:engine==='expo'?'Original declarations and source are checked.':'Original NativeScript consumer mode: source is strict; original declaration bodies are not revalidated. Set skipLibCheck:false for SDK declaration diagnostics.'},
        docs:engine==='expo'?['docs/hanlin-expo-runtime.md','docs/miniapp-sdk/README.md']:['docs/hanlin-nativescript-guide.md','docs/miniapp-sdk/README.md'],
        capabilities:engine==='expo'?['foreground','native-ui','host-services','prepared-widgets']:['foreground','native-ui','host-services','esm-package'],
        build:{nativeHostRebuildRequiredForNativeDependencyChanges:true}};
    }
    const expected={
      expo:{expo:expoLock.expo.sdkVersion,'@expo/ui':expoLock.expo.uiVersion,'react-native':expoLock.expo.reactNativeVersion,'react':expoLock.expo.reactVersion,
        '@nativescript/react-native':nativeAPILock.nativeApi.version,'react-native-worklets':nativeAPILock.worklets.version},
      nativescript:{'@nativescript/core':nativeLock.nativeScript.coreVersion,'@nativescript/ios':nativeLock.nativeScript.iosRuntimeVersion,
        '@nativescript/swift-ui':nativeLock.swiftUI.version}
    };
    for(const [engine,packages] of Object.entries(expected))for(const [name,version]of Object.entries(packages)) {
      if(engines[engine] && engines[engine].packageVersions[name]!==version)throw new Error('Native/author SDK mismatch: '+engine+' '+name);
    }
    await cp(path.join(root,'docs/miniapp-sdk'),path.join(staging,'docs/miniapp-sdk'),{recursive:true});
    for(const file of ['hanlin-expo-runtime.md','hanlin-nativescript-guide.md']) {
      await cp(path.join(root,'docs',file),path.join(staging,'docs',file));
    }
    if(requestedEngines.includes('scriptwidget')) {
    const widgetManifest=await readJSON(path.join(root,'docs/widget-engines/UPSTREAM_SOURCE_MANIFEST.json'));
    const widgetCommits=[...new Set(widgetManifest.files.filter(x=>x.repository==='everettjf/scriptwidget').map(x=>x.commit))];
    await mkdir(path.join(staging,'scriptwidget'),{recursive:true});
    await cp(path.join(root,'Scripts/MiniApps/scriptwidget'),path.join(staging,'scriptwidget'),{recursive:true});
    if(!engines.expo)await copyAuthoringTree(path.join(root,'Scripts/Expo/node_modules/typescript'),path.join(staging,'scriptwidget/typescript'),files,'scriptwidget/typescript');
    engines.scriptwidget={toolingRoot:'scriptwidget',tsconfigPath:'scriptwidget/tsconfig.json',
      typescriptPath:engines.expo?.typescriptPath??'scriptwidget/typescript/lib/typescript.js',packageVersions:{'everettjf/scriptwidget':widgetCommits.join(',')},
      docs:['docs/miniapp-sdk/SCRIPTWIDGET_AUTHORING.md'],capabilities:['prepared-widgets'],
      upstreamTypingStatus:'Original completion catalog plus explicit Hanlin host declarations; not a claim that the full upstream application services are embedded.'};
    }
    // Include generated configs, original catalogs, host declarations and documentation too.
    const recorded=new Set(files.map(x=>x.path));
    async function collect(directory,prefix='') {
      for(const entry of await readdir(directory,{withFileTypes:true})) {
        const relative=path.posix.join(prefix,entry.name),absolute=path.join(directory,entry.name);
        if(entry.isDirectory())await collect(absolute,relative);
        else if(entry.isFile()&&!recorded.has(relative)) {
          const bytes=await readFile(absolute);files.push({path:relative,sha256:sha(bytes),bytes:bytes.length});
        }
      }
    }
    await collect(staging);
    const manifest={schemaVersion:1,inputSHA256:inputs.sha256,engines,
      upstream:{expo:expoLock.expo,nativescript:nativeLock.nativeScript,scriptwidget:engines.scriptwidget?.packageVersions},
      files:files.sort((a,b)=>a.path.localeCompare(b.path)),
      sourceInputs:inputs.files,
      nativeBinaries:'Native host binaries are installed by the host build. This SDK contains original JavaScript and declaration sources.'};
    await writeJSON(path.join(staging,'miniapp-sdk.json'),manifest);
    const old=output+'.previous-'+process.pid;
    await rm(old,{recursive:true,force:true});
    let hadOutput=false;
    try {await rename(output,old);hadOutput=true;}catch(e){if(e.code!=='ENOENT')throw e;}
    try{await rename(staging,output);}catch(e){if(hadOutput)await rename(old,output);throw e;}
    await rm(old,{recursive:true,force:true});
    return {output,inputSHA256:inputs.sha256,files:files.length,engines:Object.keys(engines)};
  } catch(error) {
    await rm(staging,{recursive:true,force:true});throw error;
  }
}
if(process.argv[1]&&import.meta.url===pathToFileURL(path.resolve(process.argv[1])).href) {
  const args=process.argv.slice(2);
  const value=name=>args.find(x=>x.startsWith(name+'='))?.slice(name.length+1);
  if(args.includes('--fingerprint')) console.log(JSON.stringify(await inputReceipt(value('--repository')??repositoryRoot)));
  else console.log(JSON.stringify(await stageSDK({root:value('--repository')??repositoryRoot,output:value('--output'),engines:value('--engines')?.split(',')})));
}