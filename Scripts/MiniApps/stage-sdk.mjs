#!/usr/bin/env node
/** Assemble authoring SDK from the exact packages used by the native host build. */
import {createHash} from 'node:crypto';
import {cp, mkdir, readFile, readdir, realpath, rename, rm, stat, writeFile} from 'node:fs/promises';
import path from 'node:path';
import {createRequire} from 'node:module';
import {fileURLToPath, pathToFileURL} from 'node:url';
import {isAuthoringFile,excludedDirectories,isNativeDirectory,isGeneratedNativeOutput,verifyInstalledGraph} from './install-tooling.mjs';
export {verifyInstalledGraph,inspectInstalledGraph} from './install-tooling.mjs';

const here = path.dirname(fileURLToPath(import.meta.url));
export const repositoryRoot = path.resolve(here, '../..');
const sha = value => createHash('sha256').update(value).digest('hex');
const readJSON = async p => JSON.parse(await readFile(p, 'utf8'));
const writeJSON = async (p, data) => writeFile(p, JSON.stringify(data, null, 2) + '\n');

/** No rewrites: every retained source byte is copied from the installed upstream. */
export async function copyAuthoringTree(source, destination, receipt, label, ancestors = new Set(), excludeDependencyTrees = false) {
  const canonical = await realpath(source);
  if (ancestors.has(canonical)) throw new Error('SDK source symlink cycle: ' + label);
  const nextAncestors = new Set(ancestors).add(canonical);
  await mkdir(destination, {recursive:true});
  for (const item of (await readdir(source, {withFileTypes:true})).sort((a,b)=>a.name.localeCompare(b.name))) {
    if (excludedDirectories.has(item.name) || isNativeDirectory(item.name) || (excludeDependencyTrees && item.name === 'node_modules')) continue;
    const src = path.join(source,item.name), dest = path.join(destination,item.name);
    const relative = path.posix.join(label,item.name);
    if (isGeneratedNativeOutput(relative)) continue;
    const info = item.isSymbolicLink() ? await stat(src) : item;
    if (info.isDirectory()) {
      await copyAuthoringTree(src,dest,receipt,relative,nextAncestors,excludeDependencyTrees);
    } else if (info.isFile() && isAuthoringFile(item.name)) {
      const bytes = await readFile(src);
      await writeFile(dest,bytes);
      receipt.push({path:relative,sha256:sha(bytes),bytes:bytes.length});
    }
  }
}

export async function compilerIdentity(toolingRoot) {
  const packageFile=path.join(toolingRoot,'node_modules/typescript/package.json');
  const installed=await readJSON(packageFile);
  const compiler=createRequire(packageFile)('./lib/typescript.js');
  if(typeof compiler.version!=='string')throw new Error('Installed TypeScript compiler has no version');
  return {packageName:installed.name,packageVersion:installed.version,compilerVersion:compiler.version};
}

/** Keep npm alias implementations with the actual compiler, also in a partial SDK. */
export async function copyCompilerClosure(source,destination,files,label,ancestors=new Set()) {
  const canonical=await realpath(source);
  if(ancestors.has(canonical))throw new Error('Compiler dependency cycle: '+canonical);
  const next=new Set(ancestors).add(canonical);
  await copyAuthoringTree(source,destination,files,label,new Set(),true);
  const packageFile=path.join(source,'package.json'),pkg=await readJSON(packageFile),require=createRequire(packageFile);
  for(const name of Object.keys(pkg.dependencies??{})) {
    const dependency=path.dirname(require.resolve(name+'/package.json'));
    await copyCompilerClosure(dependency,path.join(destination,'node_modules',name),files,path.posix.join(label,'node_modules',name),next);
  }
}

export const sdkInputs = [
 'Scripts/Expo/package.json','Scripts/Expo/package-lock.json','Scripts/Expo/dependency-lock.json',
 'Scripts/Expo/babel.config.cjs','Scripts/Expo/metro.config.cjs','Scripts/Expo/prepare-types.mjs',
 'Scripts/Expo/build-original-widget-runtime.mjs','Scripts/Expo/sync-original-ui-exports.mjs',
 'Scripts/NativeScript/package.json','Scripts/NativeScript/package-lock.json','Scripts/NativeScript/dependency-lock.json',
 'Scripts/ExpoNativeAPI/dependency-lock.json','Tools/SwiftUIBridge/configuration.json',
 'Packages/HanlinExpoNativeAPI/Sources/HanlinExpoNativeAPI/HanlinExpoNativeAPIManager.swift',
 'Packages/HanlinExpoNativeAPI/Sources/HanlinExpoNativeAPI/HanlinExpoNativeAPIHostVersions.swift',
 'Packages/HanlinPlatform/Package.swift',
 'docs/widget-engines/UPSTREAM_SOURCE_MANIFEST.json','docs/miniapp-sdk/source-inventory.json',
 'docs/miniapp-sdk/extension-reachability.json'
];

const excludedSDKInputNames = new Set(['node_modules','Tests','evidence','.git']);
const includesSDKInputName = name => !excludedSDKInputNames.has(name) && !name.includes('.bak.');
const exampleSourceRoot = 'Scripts/MiniApps/Examples';
const assistantExampleSourceRoot = 'Scripts/MiniApps/AssistantExamples';
// These are output roots of the public authoring/Metro tools, not arbitrary
// resource names. Authored build/dist directories and resource ZIPs survive.
const exampleOutputRoots = new Set(['.hanlin-build','.hanlin-authoring','.metro-cache']);
const includesSDKSourcePath = relative => {
  if (!relative.split('/').every(includesSDKInputName)) return false;
  const sourceRoot=[exampleSourceRoot,assistantExampleSourceRoot].find(root=>relative.startsWith(root+'/'));
  if (!sourceRoot) return true;
  const [,projectChild] = relative.slice(sourceRoot.length+1).split('/');
  return !exampleOutputRoots.has(projectChild);
};

export async function collectSDKSourceInputs(source,prefix) {
  const files=[];
  async function walk(src,relative) {
    if (!includesSDKSourcePath(relative)) return;
    const info=await stat(src);
    if(info.isFile()) {
      files.push({path:relative,sha256:sha(await readFile(src))});return;
    }
    for(const entry of (await readdir(src,{withFileTypes:true})).sort((a,b)=>a.name.localeCompare(b.name))) {
      await walk(path.join(src,entry.name),path.posix.join(relative,entry.name));
    }
  }
  await walk(source,prefix);
  return files;
}

/** Export complete authored projects unchanged, with paths in this exact SDK. */
export async function copySDKExamples(source,destination,requestedEngines=['expo','nativescript'],exportPrefix='examples') {
  const catalog=await readJSON(path.join(source,'index.json'));
  if(catalog.schemaVersion!==1 || !Array.isArray(catalog.projects)) throw new Error('Unsupported SDK example index');
  const projects=[],ids=new Set();
  await mkdir(destination,{recursive:true});
  for(const project of catalog.projects) {
    if(!['expo','nativescript'].includes(project.engine) || typeof project.directory!=='string' ||
      !project.directory || project.directory!==path.basename(project.directory) ||
      ['.','..'].includes(project.directory) || ids.has(project.id)) throw new Error('Invalid SDK example index entry');
    ids.add(project.id);
    if(!requestedEngines.includes(project.engine)) continue;
    const projectRoot=path.join(source,project.directory);
    const author=await readJSON(path.join(projectRoot,'hanlin.authoring.json'));
    if(author.schemaVersion!==1 || author.engine!==project.engine) throw new Error('SDK example authoring engine mismatch: '+project.id);
    for(const file of ['script.json','package.json',author.tsconfig,author.entry]) {
      if(typeof file!=='string' || !file) throw new Error('Incomplete SDK example: '+project.id);
      const relative=path.relative(projectRoot,path.resolve(projectRoot,file));
      if(relative==='..' || relative.startsWith('..'+path.sep) || path.isAbsolute(relative)) throw new Error('SDK example source leaves its project: '+project.id);
      if(!(await stat(path.join(projectRoot,file))).isFile()) throw new Error('Missing SDK example file: '+project.id+'/'+file);
    }
    const canonicalRoot=path.resolve(projectRoot);
    await cp(canonicalRoot,path.join(destination,project.directory),{recursive:true,
      filter:entry=>includesSDKSourcePath(path.posix.join(exampleSourceRoot,project.directory,
        path.relative(canonicalRoot,entry).split(path.sep).join('/')))});
    projects.push({...project,path:exportPrefix+'/'+project.directory,entry:author.entry});
  }
  await writeJSON(path.join(destination,'index.json'),{schemaVersion:1,projects});
  return projects;
}

// Ship the same public documentation tree that contributes to the SDK identity.
// Build evidence stays in the repository; original API/type packages are separate.
export async function copySDKDocumentation(source,destination) {
  const sourceRoot=path.resolve(source);
  await cp(sourceRoot,destination,{recursive:true,
    filter:entry=>entry===sourceRoot || includesSDKInputName(path.basename(entry))});
}

export async function inputReceipt(root=repositoryRoot) {
  const files=[];
  for(const relative of sdkInputs) {
    const bytes=await readFile(path.join(root,relative));
    files.push({path:relative,sha256:sha(bytes)});
  }
  for(const relative of ['Scripts/MiniApps','Packages/HanlinExpoUI','Packages/HanlinExpoNativeAPIJS',
    'Packages/HanlinNativeScriptRuntime/Sources/HanlinNativeScriptRuntime/Resources/NativeScriptSharedRuntime/@hanlin/host-services',
    'Packages/HanlinPlatform/Sources/HanlinScriptWidgetOriginal',
    'Packages/HanlinExpoRuntime/Sources/ExpoWidgets',
    'Packages/HanlinPlatform/Sources/HanlinScriptExtensions/ScriptWidget/HanlinScriptWidgetRuntime.swift',
    'docs/miniapp-sdk','docs/hanlin-nativescript-guide.md','docs/hanlin-expo-runtime.md']) {
    files.push(...await collectSDKSourceInputs(path.join(root,relative),relative));
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
  const bridgeConfiguration=await readJSON(path.join(root,'Tools/SwiftUIBridge/configuration.json'));
  const nativeAPIContractSource=await readFile(path.join(root,'Packages/HanlinExpoNativeAPI/Sources/HanlinExpoNativeAPI/HanlinExpoNativeAPIManager.swift'),'utf8');
  const nativeApiContractVersion=nativeAPIContractSource.match(/static let contractVersion\s*=\s*"([^"]+)"/)?.[1];
  if(!nativeApiContractVersion)throw new Error('Actual native API host contract version is missing');

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

      const assistantTypesRoot=path.join(destination,'node_modules/@hanlin/assistant-tools');
      await mkdir(assistantTypesRoot,{recursive:true});
      await cp(path.join(root,'Scripts/MiniApps/assistant-tools.d.ts'),path.join(assistantTypesRoot,'index.d.ts'));
      await writeJSON(path.join(assistantTypesRoot,'package.json'),{
        name:'@hanlin/assistant-tools',version:'1.0.0',types:'index.d.ts',private:true,
        description:'Data and function signatures for the existing Hanlin assistant tool transports; type-only.'
      });
      graph.versions['@hanlin/assistant-tools']='1.0.0';
      await cp(path.join(root,'Scripts/MiniApps/assistant-tools.schema.json'),path.join(staging,'assistant-tools.schema.json'));

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
        packageVersions:graph.versions,typescript:await compilerIdentity(source),installation:graph.installation,
        ...(engine==='expo'?{hostContract:{runtimeVersion:expoLock.expo.uiVersion,expoSDKVersion:expoLock.expo.sdkVersion,
          bridgeVersion:bridgeConfiguration.bridgeVersion,nativeApiContractVersion,
          nativeApiAbiIdentity:`rn${expoLock.expo.reactNativeVersion}-hermes${expoLock.expo.hermesVersion}`,
          plugins:{'@expo/ui':expoLock.expo.uiVersion,'expo-asset':expoLock.expo.assetVersion,'expo-widgets':expoLock.expo.widgetsVersion,'@hanlin/expo-ui':bridgeConfiguration.bridgeVersion,
            '@nativescript/react-native':nativeAPILock.nativeApi.version,'react-native-worklets':nativeAPILock.worklets.version}}}:{}),
        typeCheckingPolicy:{strictSource:true,checkOriginalDeclarationBodies:engine==='expo',
          explanation:engine==='expo'?'Original declarations and source are checked.':'Original NativeScript consumer mode: source is strict; original declaration bodies are not revalidated. Set skipLibCheck:false for SDK declaration diagnostics.'},
        docs:engine==='expo'?['docs/hanlin-expo-runtime.md','docs/miniapp-sdk/README.md','docs/miniapp-sdk/EXPO_WIDGETS_ORIGINAL.md']:['docs/hanlin-nativescript-guide.md','docs/miniapp-sdk/README.md'],
        capabilities:engine==='expo'?['foreground','native-ui','host-services','prepared-widgets','original-widget-api','original-live-activity-api']:['foreground','native-ui','host-services','esm-package'],
        assistantTools:{manifestSchemaPath:'assistant-tools.schema.json',typesPackage:'@hanlin/assistant-tools',
          module:'Dedicated prepared program, separate from foreground app',configurationVersion:1},
        build:{nativeHostRebuildRequiredForNativeDependencyChanges:true}};
    }
    const expected={
      expo:{expo:expoLock.expo.sdkVersion,'@expo/ui':expoLock.expo.uiVersion,'expo-asset':expoLock.expo.assetVersion,'expo-widgets':expoLock.expo.widgetsVersion,'react-native':expoLock.expo.reactNativeVersion,'react':expoLock.expo.reactVersion,
        '@nativescript/react-native':nativeAPILock.nativeApi.version,'react-native-worklets':nativeAPILock.worklets.version},
      nativescript:{'@nativescript/core':nativeLock.nativeScript.coreVersion,'@nativescript/ios':nativeLock.nativeScript.iosRuntimeVersion,
        '@nativescript/swift-ui':nativeLock.swiftUI.version}
    };
    for(const [engine,packages] of Object.entries(expected))for(const [name,version]of Object.entries(packages)) {
      if(engines[engine] && engines[engine].packageVersions[name]!==version)throw new Error('Native/author SDK mismatch: '+engine+' '+name);
    }
    const exampleProjects=await copySDKExamples(path.join(root,exampleSourceRoot),path.join(staging,'examples'),requestedEngines);
    const assistantExamples=await copySDKExamples(path.join(root,assistantExampleSourceRoot),path.join(staging,'assistant-examples'),requestedEngines,'assistant-examples');
    for(const engine of ['expo','nativescript']) if(engines[engine]) {
      engines[engine].examples=exampleProjects.filter(project=>project.engine===engine);
      engines[engine].assistantToolExamples=assistantExamples.filter(project=>project.engine===engine);
      engines[engine].docs.push('docs/miniapp-sdk/EXAMPLES.md','docs/miniapp-sdk/ASSISTANT_TOOLS_AND_COMPOSER.md');
    }
    await copySDKDocumentation(path.join(root,'docs/miniapp-sdk'),path.join(staging,'docs/miniapp-sdk'));
    for(const file of ['hanlin-expo-runtime.md','hanlin-nativescript-guide.md']) {
      await cp(path.join(root,'docs',file),path.join(staging,'docs',file));
    }
    if(requestedEngines.includes('scriptwidget')) {
    const widgetManifest=await readJSON(path.join(root,'docs/widget-engines/UPSTREAM_SOURCE_MANIFEST.json'));
    const widgetCommits=[...new Set(widgetManifest.files.filter(x=>x.repository==='everettjf/scriptwidget').map(x=>x.commit))];
    await mkdir(path.join(staging,'scriptwidget'),{recursive:true});
    await cp(path.join(root,'Scripts/MiniApps/scriptwidget'),path.join(staging,'scriptwidget'),{recursive:true});
    // Generate against this build's real original native registrations. A new
    // unsupported signature fails staging instead of publishing invented types.
    const {generateScriptWidgetServiceTypes}=await import(pathToFileURL(path.join(root,'Scripts/MiniApps/generate-scriptwidget-service-types.mjs')).href);
    const serviceTypes=await generateScriptWidgetServiceTypes({root,output:path.join(staging,'scriptwidget')});
    const {generateScriptWidgetManifest}=await import(pathToFileURL(path.join(root,'Scripts/MiniApps/generate-scriptwidget-manifest.mjs')).href);
    await generateScriptWidgetManifest({root,output:path.join(staging,'scriptwidget')});
    if(!engines.expo) {
      await verifyInstalledGraph(path.join(root,'Scripts/Expo'));
      await copyCompilerClosure(path.join(root,'Scripts/Expo/node_modules/typescript'),path.join(staging,'scriptwidget/typescript'),files,'scriptwidget/typescript');
    }
    engines.scriptwidget={toolingRoot:'scriptwidget',tsconfigPath:'scriptwidget/tsconfig.json',
      typescriptPath:engines.expo?.typescriptPath??'scriptwidget/typescript/lib/typescript.js',
      typescript:engines.expo?.typescript??await compilerIdentity(path.join(root,'Scripts/Expo')),packageVersions:{'everettjf/scriptwidget':widgetCommits.join(',')},
      docs:['docs/miniapp-sdk/SCRIPTWIDGET_AUTHORING.md','docs/miniapp-sdk/SCRIPTWIDGET_CONTROLS.md'],capabilities:['prepared-widgets','original-native-services','original-control-widgets'],
      packageManifestSchemaPath:'scriptwidget/widget-manifest.schema.json',
      packageManifestValidatorPath:'scriptwidget/manifest-validation.mjs',
      nativeAPIManifestPath:'scriptwidget/native-api.json',
      nativeAPISummary:{globals:serviceTypes.globals,objects:serviceTypes.nativeObjects,methods:serviceTypes.nativeMethods},
      upstreamTypingStatus:'Original component catalog and declarations generated from the original native JSExport APIs and explicit Hanlin host additions embedded in this exact build.'};
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
    const manifest={schemaVersion:1,inputSHA256:inputs.sha256,engines,examplesIndexPath:'examples/index.json',assistantExamplesIndexPath:'assistant-examples/index.json',
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