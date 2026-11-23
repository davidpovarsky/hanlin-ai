import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtemp,rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import path from 'node:path';
import {expoRanges,latestMetadata,generatedHostVersions,generatedExpoHostVersions} from '../resolve-upstreams.mjs';
import {mergeOriginal,originalInHostTarget} from '../refresh-original-sources.mjs';
import {sourceBuildIdentity} from '../../Expo/build-original-expo-source.mjs';

test('Expo uses its published coherent matrix rather than unrelated latest React or Worklets',()=>{
  const matrix={'@expo/ui':'~58.0.29','expo-brownfield':'~58.0.20',react:'19.3.0','react-native':'0.88.1','react-native-worklets':'0.13.0'};
  const ranges=expoRanges({version:'58.0.26',dependencies:{'expo-modules-core':'~58.1.0'}},matrix);
  assert.equal(ranges.react,'19.3.0');assert.equal(ranges['react-native-worklets'],'0.13.0');assert.equal(ranges['expo-modules-core'],'~58.1.0');
  assert.throws(()=>expoRanges({version:'58.0.26',dependencies:{}},{}),/does not specify/);
});
test('a package publication must contain its original integrity',()=>{
  assert.throws(()=>latestMetadata({name:'expo',version:'58.0.26',dist:{tarball:'https://registry.npmjs.org/expo.tgz'}}),/Incomplete/);
});
test('native source identity changes for native versions, installed graph, Xcode, and producer',()=>{
  const lock={expo:{uiVersion:'58.0.29'},artifacts:[{name:'ExpoUI',source:'npm-source',sha256:'a'}]};
  const identity=sourceBuildIdentity(lock,'graph','Xcode27','original producer');
  assert.notEqual(identity,sourceBuildIdentity(lock,'new graph','Xcode27','original producer'));
  assert.notEqual(identity,sourceBuildIdentity(lock,'graph','Xcode27.1','original producer'));
  assert.notEqual(identity,sourceBuildIdentity(lock,'graph','Xcode27','changed producer'));
  assert.notEqual(identity,sourceBuildIdentity({...lock,expo:{uiVersion:'58.0.30'}},'graph','Xcode27','original producer'));
});
test('generated runtime metadata uses exact native and original ScriptWidget identities',()=>{
  const text=generatedHostVersions({expo:{expo:'58.0.26','@expo/ui':'58.0.29','expo-widgets':'58.0.20','react-native':'0.88.1'},nativescript:{'@nativescript/ios':'9.1.1','@nativescript/core':'9.1.4','@nativescript/swift-ui':'4.0.2'},scriptwidget:{revision:'4da256d58247bbafb9a5cd443a285250b97b3c4b'}});
  assert.match(text,/expoSDKVersion = "58\.0\.26"/);assert.match(text,/nativeScriptCoreVersion = "9\.1\.4"/);assert.match(text,/scriptWidgetRevision = "4da256/);
});
test('three-way native refresh preserves host adaptations and applies upstream changes',async()=>{
  const cache=await mkdtemp(path.join(tmpdir(),'hanlin-original-merge-'));
  try {
    const previous=Buffer.from('first\nsecond\nthird\nfourth\nfifth\n');
    const local=Buffer.from('host first\nsecond\nthird\nfourth\nfifth\n');
    const next=Buffer.from('first\nsecond\nthird\nfourth\nnew upstream fifth\n');
    const merged=await mergeOriginal({local,previous,next,cache,label:'Component.swift'});
    assert.equal(merged.toString(),'host first\nsecond\nthird\nfourth\nnew upstream fifth\n');
  } finally {await rm(cache,{recursive:true,force:true});}
});
test('conflicting native changes produce a repair diff and fail instead of discarding adaptations',async()=>{
  const cache=await mkdtemp(path.join(tmpdir(),'hanlin-original-conflict-'));
  try {await assert.rejects(mergeOriginal({local:Buffer.from('host\n'),previous:Buffer.from('original\n'),next:Buffer.from('upstream\n'),cache,label:'Component.swift'}),/three-way conflict/);}
  finally {await rm(cache,{recursive:true,force:true});}
});

test('original widget imports use the existing unified widget target namespace',()=>{
  const original=Buffer.from('import SwiftUI\nimport ExpoModulesCore\nimport ExpoUI\npublic struct OriginalView {}\n');
  const target='Packages/HanlinExpoWidgetSubset/Sources/HanlinExpoWidgetSubset/ExpoUI/AccessoryWidgetBackgroundView.swift';
  assert.equal(originalInHostTarget(original,target).toString(),'import SwiftUI\npublic struct OriginalView {}\n');
  assert.equal(originalInHostTarget(original,'Packages/Other/OriginalView.swift'),original);
});
test('actual native host ABI metadata changes with the original React Native and Hermes graph',()=>{
  const text=generatedExpoHostVersions({expo:{expo:'58.0.26','@expo/ui':'58.0.29','react-native':'0.88.1','@nativescript/react-native':'9.1.2','react-native-worklets':'0.13.0'}},'260318099.0.5');
  assert.match(text,/runtimeVersion = "58\.0\.29"/);
  assert.match(text,/nativeApiAbiIdentity = "rn0\.88\.1-hermes260318099\.0\.5"/);
});
