#!/usr/bin/env node
// Some current Expo publications intentionally contain source, not XCFrameworks.
// Build the original podspecs with Expo's own generated CocoaPods project.
import {createHash} from 'node:crypto';
import {existsSync} from 'node:fs';
import {mkdir,readFile,writeFile,rm,symlink,cp,readdir} from 'node:fs/promises';
import {execFileSync} from 'node:child_process';
import path from 'node:path';
import {fileURLToPath,pathToFileURL} from 'node:url';

const here=path.dirname(fileURLToPath(import.meta.url));
const sha=bytes=>createHash('sha256').update(bytes).digest('hex');
const readJSON=async file=>JSON.parse(await readFile(file,'utf8'));
const run=(command,args,options={})=>execFileSync(command,args,{stdio:'inherit',...options});
async function originalCocoaPods() {
  try {return {command:'pod',version:execFileSync('pod',['--version'],{encoding:'utf8'}).trim()};}
  catch(error) {
    if(error.code!=='ENOENT')throw error;
    // Install the original RubyGem into this build user's tools, never into the
    // application payload or into a handwritten CocoaPods replacement.
    run('gem',['install','cocoapods','--user-install','--no-document']);
    const directory=execFileSync('ruby',['-e','print Gem.user_dir'],{encoding:'utf8'}).trim();
    const command=path.join(directory,'bin/pod');
    return {command,version:execFileSync(command,['--version'],{encoding:'utf8'}).trim()};
  }
}
async function firstFramework(root,name) {
  if(!existsSync(root))return null;
  for(const entry of await readdir(root,{withFileTypes:true})) {
    const file=path.join(root,entry.name);if(entry.isDirectory()&&entry.name===name+'.framework')return file;
    if(entry.isDirectory()) {const found=await firstFramework(file,name);if(found)return found;}
  }
  return null;
}
export function sourceBuildIdentity(lock,packageLock,xcode,producer) {
  return sha(JSON.stringify({schemaVersion:1,artifacts:lock.artifacts.filter(item=>item.source==='npm-source'),expo:lock.expo,packageLockSHA256:sha(packageLock),xcode,producerSHA256:sha(producer)}));
}
export async function buildOriginalExpoSource({root=path.resolve(here,'../..')}={}) {
  const tooling=path.join(root,'Scripts/Expo');
  const lock=await readJSON(path.join(tooling,'dependency-lock.json'));
  const selected=lock.artifacts.filter(item=>item.source==='npm-source'&&item.name==='ExpoUI');
  if(!selected.length)return;
  if(process.platform!=='darwin')throw new Error('Current original ExpoUI contains source only; building its native framework requires the macOS Xcode host build. No older binary will be substituted.');
  const xcode=execFileSync('xcodebuild',['-version'],{encoding:'utf8'}).trim();
  const input=sourceBuildIdentity(lock,await readFile(path.join(tooling,'package-lock.json')),xcode,await readFile(fileURLToPath(import.meta.url)));
  const target=path.join(root,selected[0].target),receiptPath=path.join(target,'.source-build-receipt.json');
  if(existsSync(receiptPath)) {
    const receipt=await readJSON(receiptPath);
    if(receipt.inputSHA256===input&&existsSync(path.join(target,'Info.plist'))) {console.log('[HanlinExpo] Exact original ExpoUI source build reused: '+input);return;}
  }
  const staging=path.join(root,'build/miniapp-upstreams/expo-native-source');
  await rm(staging,{recursive:true,force:true});await mkdir(staging,{recursive:true});
  const dependencies={};
  for(const name of ['expo','react','react-native','@expo/ui','expo-brownfield','expo-modules-core','expo-modules-jsi','react-native-worklets']) {
    const installed=await readJSON(path.join(tooling,'node_modules',name,'package.json'));
    const expected=(await readJSON(path.join(tooling,'package.json'))).dependencies[name];
    if(installed.version!==expected)throw new Error(`Original source producer graph mismatch: ${name} ${installed.version}, expected ${expected}`);
    dependencies[name]=installed.version;
  }
  await writeFile(path.join(staging,'package.json'),JSON.stringify({name:'hanlin-original-expo-framework-producer',version:'1.0.0',private:true,main:'index.js',dependencies},null,2)+'\n');
  await writeFile(path.join(staging,'app.json'),JSON.stringify({expo:{name:'HanlinOriginalFrameworkProducer',slug:'hanlin-original-framework-producer',platforms:['ios'],ios:{bundleIdentifier:'app.hanlin.original-framework-producer'},newArchEnabled:true}},null,2)+'\n');
  await writeFile(path.join(staging,'index.js'),"import {registerRootComponent} from 'expo';\nimport React from 'react';\nregisterRootComponent(() => null);\n");
  await symlink(path.join(tooling,'node_modules'),path.join(staging,'node_modules'),'dir');
  const env={...process.env,CI:'1',USE_FRAMEWORKS:'static',EXPO_NO_TELEMETRY:'1',RCT_NEW_ARCH_ENABLED:'1'};
  // This only generates the isolated producer project; Hanlin's real app targets
  // and their entitlements are never replaced by Expo prebuild.
  run(process.execPath,[path.join(tooling,'node_modules/expo/bin/cli'),'prebuild','--platform','ios','--no-install'],{cwd:staging,env});
  const ios=path.join(staging,'ios'),propertiesPath=path.join(ios,'Podfile.properties.json');
  const properties=existsSync(propertiesPath)?await readJSON(propertiesPath):{};
  properties['ios.deploymentTarget']='27.0';properties['ios.useFrameworks']='static';
  await writeFile(propertiesPath,JSON.stringify(properties,null,2)+'\n');
  const cocoaPods=await originalCocoaPods();
  run(cocoaPods.command,['install','--project-directory='+ios],{cwd:staging,env});
  const project=path.join(ios,'Pods/Pods.xcodeproj');
  const listing=JSON.parse(execFileSync('xcodebuild',['-list','-json','-project',project],{encoding:'utf8'}));
  if(!(listing.project?.schemes??[]).includes('ExpoUI'))throw new Error('Original Expo/CocoaPods project did not generate the ExpoUI scheme');
  const outputs=[];
  for(const [sdk,destination,architectures] of [['iphoneos','generic/platform=iOS','arm64'],['iphonesimulator','generic/platform=iOS Simulator','arm64 x86_64']]) {
    const products=path.join(staging,'products',sdk),derived=path.join(staging,'derived',sdk);
    run('xcodebuild',['build','-project',project,'-scheme','ExpoUI','-configuration','Release','-sdk',sdk,'-destination',destination,'-derivedDataPath',derived,
      'CONFIGURATION_BUILD_DIR='+products,'BUILD_LIBRARY_FOR_DISTRIBUTION=YES','SKIP_INSTALL=NO','ONLY_ACTIVE_ARCH=NO','ARCHS='+architectures,
      'CODE_SIGNING_ALLOWED=NO','CODE_SIGNING_REQUIRED=NO','CODE_SIGN_IDENTITY=','IPHONEOS_DEPLOYMENT_TARGET=27.0'],{cwd:staging,env});
    const framework=await firstFramework(products,'ExpoUI');
    if(!framework)throw new Error(`Original ExpoUI did not emit an ${sdk} framework at ${products}`);
    outputs.push(framework);
  }
  const output=path.join(staging,'ExpoUI.xcframework');
  run('xcodebuild',['-create-xcframework',...outputs.flatMap(file=>['-framework',file]),'-output',output],{env});
  const plist=JSON.parse(execFileSync('plutil',['-convert','json','-o','-',path.join(output,'Info.plist')],{encoding:'utf8'}));
  const slices=plist.AvailableLibraries??[];
  for(const simulator of [false,true])if(!slices.some(slice=>slice.SupportedPlatform==='ios'&&(slice.SupportedPlatformVariant==='simulator')===simulator&&slice.SupportedArchitectures?.includes('arm64')))throw new Error('Original ExpoUI output is missing a required iOS device/simulator slice');
  await rm(target,{recursive:true,force:true});await mkdir(path.dirname(target),{recursive:true});await cp(output,target,{recursive:true,verbatimSymlinks:true});
  const receipt={schemaVersion:1,inputSHA256:input,xcode,cocoaPods:cocoaPods.version,podLockSHA256:sha(await readFile(path.join(ios,'Podfile.lock'))),originalPackage:{name:selected[0].package,version:selected[0].version,sha256:selected[0].sha256,integrity:selected[0].sourceBuild.packageIntegrity},nativeBuild:'original Expo CLI prebuild + original CocoaPods podspec + Xcode device/simulator frameworks',slices};
  await writeFile(receiptPath,JSON.stringify(receipt,null,2)+'\n');
  await writeFile(path.join(target,'.artifact-manifest.json'),JSON.stringify({name:'ExpoUI',version:selected[0].version,sha256:selected[0].sha256,sourceBuildInputSHA256:input},null,2)+'\n');
  console.log('[HanlinExpo] Built original current ExpoUI for device and simulator: '+input);
}
if(process.argv[1]&&pathToFileURL(path.resolve(process.argv[1])).href===import.meta.url)buildOriginalExpoSource().catch(error=>{console.error(error.stack);process.exitCode=1;});
