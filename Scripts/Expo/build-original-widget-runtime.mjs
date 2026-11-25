#!/usr/bin/env node
/** Build the original Expo Widgets JSC runtime, without substituting a renderer. */
import {createHash} from 'node:crypto';
import {existsSync} from 'node:fs';
import {cp,mkdir,readFile,rename,rm,writeFile} from 'node:fs/promises';
import {execFileSync} from 'node:child_process';
import path from 'node:path';
import {fileURLToPath,pathToFileURL} from 'node:url';

const here=path.dirname(fileURLToPath(import.meta.url));
const sha=value=>createHash('sha256').update(value).digest('hex');
const json=async file=>JSON.parse(await readFile(file,'utf8'));
const pretty=value=>JSON.stringify(value,null,2)+'\n';
export async function buildOriginalWidgetRuntime({root=path.resolve(here,'../..')}={}) {
  const tooling=path.join(root,'Scripts/Expo');
  const source=path.join(tooling,'node_modules/expo-widgets');
  const manifest=await json(path.join(tooling,'package.json'));
  const original=await json(path.join(source,'package.json'));
  const nativeLock=await json(path.join(tooling,'dependency-lock.json'));
  if(original.version!==manifest.dependencies['expo-widgets']||original.version!==nativeLock.expo.widgetsVersion)
    throw new Error('Original Expo Widgets JavaScript/native source versions differ.');
  const sourceManifest=await json(path.join(root,'docs/widget-engines/UPSTREAM_SOURCE_MANIFEST.json'));
  const rows=sourceManifest.files.filter(entry=>entry.local.startsWith('Packages/HanlinExpoRuntime/Sources/ExpoWidgets/Original/'));
  if(!rows.length||rows.some(entry=>entry.upstreamPublication?.package!=='expo-widgets'||entry.upstreamPublication.version!==original.version))
    throw new Error('The complete original Expo Widgets native module does not match the installed publication.');
  for(const row of rows)if(sha(await readFile(path.join(root,row.local)))!==row.localSHA256)
    throw new Error('Original Expo Widgets adaptation changed without provenance: '+row.local);
  const inputs={packageVersion:original.version,packageLockSHA256:sha(await readFile(path.join(tooling,'package-lock.json'))),
    babelSHA256:sha(await readFile(path.join(tooling,'babel.config.cjs'))),
    producerSHA256:sha(await readFile(fileURLToPath(import.meta.url))),nativeSources:rows.map(entry=>({path:entry.local,sha256:entry.localSHA256})),
    originalProducerSHA256:sha(await readFile(path.join(source,'scripts/build-bundle.mjs')))};
  const inputSHA256=sha(pretty(inputs));
  const output=path.join(root,'Packages/HanlinExpoRuntime/Sources/ExpoWidgets/Resources/ExpoWidgets.bundle');
  const receiptPath=path.join(output,'original-runtime-receipt.json');
  if(existsSync(receiptPath)) {
    const receipt=await json(receiptPath);
    if(receipt.inputSHA256===inputSHA256&&existsSync(path.join(output,'ExpoWidgets.bundle'))&&
      receipt.bundleSHA256===sha(await readFile(path.join(output,'ExpoWidgets.bundle'))))return receipt;
  }
  const staging=output+'.staging-'+process.pid;
  await rm(staging,{recursive:true,force:true});await mkdir(staging,{recursive:true});
  const run=script=>execFileSync(process.execPath,[path.join(source,'scripts',script),tooling,'ios',
    path.join(staging,script==='build-bundle.mjs'?'ExpoWidgets.bundle':'ExpoWidgetsLayoutRegistry.json')],
    {cwd:tooling,stdio:'inherit',env:{...process.env,CI:'1',EXPO_NO_TELEMETRY:'1',NODE_ENV:'production'}});
  try {
    run('build-bundle.mjs');
    run('build-layout-registry.mjs');
    const bytes=await readFile(path.join(staging,'ExpoWidgets.bundle'));
    const text=bytes.toString('utf8');
    if(!text.includes('__expoWidgetRender')||!text.includes('__expoWidgetHandlePress'))
      throw new Error('Original Expo Widgets bundle does not expose the functions called by its native JSC runtime.');
    await writeFile(path.join(staging,'Info.plist'),'<?xml version="1.0" encoding="UTF-8"?>\n<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">\n<plist version="1.0"><dict><key>CFBundleIdentifier</key><string>org.hanlin.ExpoWidgets.resources</string><key>CFBundlePackageType</key><string>BNDL</string><key>CFBundleVersion</key><string>'+original.version+'</string></dict></plist>\n');
    if(existsSync(path.join(output,'README.txt')))await cp(path.join(output,'README.txt'),path.join(staging,'README.txt'));
    const receipt={schemaVersion:1,inputSHA256,...inputs,bundleSHA256:sha(bytes),
      registrySHA256:sha(await readFile(path.join(staging,'ExpoWidgetsLayoutRegistry.json'))),
      producer:'original expo-widgets/scripts/build-bundle.mjs and build-layout-registry.mjs; original Metro config/stubs/runtime'};
    await writeFile(path.join(staging,'original-runtime-receipt.json'),pretty(receipt));
    const previous=output+'.previous-'+process.pid;await rm(previous,{recursive:true,force:true});
    let hadOutput=false;try{await rename(output,previous);hadOutput=true;}catch(error){if(error.code!=='ENOENT')throw error;}
    try{await rename(staging,output);}catch(error){if(hadOutput)await rename(previous,output);throw error;}
    await rm(previous,{recursive:true,force:true});
    console.log('[HanlinExpo] Built original Widgets JavaScript runtime '+original.version+': '+receipt.bundleSHA256);
    return receipt;
  } finally {await rm(staging,{recursive:true,force:true});}
}
if(process.argv[1]&&pathToFileURL(path.resolve(process.argv[1])).href===import.meta.url)
  buildOriginalWidgetRuntime().catch(error=>{console.error(error.stack);process.exitCode=1;});
