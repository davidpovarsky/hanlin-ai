import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtemp,readFile,rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import path from 'node:path';
import {expoRanges,latestMetadata,reactTypesSelection,compilerSelections,generatedHostVersions,generatedExpoHostVersions,generatedNativeAPIHostVersions} from '../resolve-upstreams.mjs';
import {mergeOriginal,originalInHostTarget} from '../refresh-original-sources.mjs';
import {sourceBuildIdentity} from '../../Expo/build-original-expo-source.mjs';

test('Expo uses its published coherent matrix rather than unrelated latest React or Worklets',()=>{
  const matrix={'@expo/ui':'~58.0.29','expo-brownfield':'~58.0.20',react:'19.3.0','react-native':'0.88.1','react-native-worklets':'0.13.0'};
  const ranges=expoRanges({version:'58.0.26',dependencies:{'expo-modules-core':'~58.1.0','expo-asset':'~58.0.21'}},matrix);
  assert.equal(ranges.react,'19.3.0');assert.equal(ranges['react-native-worklets'],'0.13.0');assert.equal(ranges['expo-modules-core'],'~58.1.0');assert.equal(ranges['expo-asset'],'~58.0.21');
  assert.throws(()=>expoRanges({version:'58.0.26',dependencies:{}},{}),/does not specify/);
  assert.throws(()=>expoRanges({version:'58.0.26',dependencies:{'expo-modules-core':'~58.1.0'}},matrix),/does not specify expo-asset/);
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
  const text=generatedHostVersions({expo:{expo:'58.0.26','@expo/ui':'58.0.29','expo-widgets':'58.0.29','react-native':'0.88.1','@nativescript/react-native':'9.1.2','react-native-worklets':'0.13.0'},nativescript:{'@nativescript/ios':'9.1.1','@nativescript/core':'9.1.4','@nativescript/swift-ui':'4.0.2'},scriptwidget:{revision:'4da256d58247bbafb9a5cd443a285250b97b3c4b'}});
  assert.match(text,/expoSDKVersion = "58\.0\.26"/);assert.match(text,/reactNativeWorkletsVersion = "0\.13\.0"/);assert.match(text,/nativeApiVersion = "9\.1\.2"/);assert.match(text,/nativeScriptCoreVersion = "9\.1\.4"/);assert.match(text,/scriptWidgetRevision = "4da256/);
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

test('prepared widget namespace keeps original universal layout without importing the React Yoga hook',()=>{
  const source=Buffer.from('public struct UIBaseView {\n  var body: some View {\n    UniversalPercentageParentBoundary(content: innerView)\n      .publishZeroContentOrigin(props.shadowNodeProxy)\n  }\n}\nextension View {\n  func publishZeroContentOrigin(_ shadowNodeProxy: ExpoSwiftUI.ShadowNodeProxy) -> some View { self }\n}\n');
  const result=originalInHostTarget(source,'Packages/HanlinExpoWidgetSubset/Sources/HanlinExpoWidgetSubset/ExpoUI/UIBaseView.swift').toString();
  assert.match(result,/UniversalPercentageParentBoundary/);
  assert.doesNotMatch(result,/publishZeroContentOrigin|ShadowNodeProxy/);
});

test('public Native API metadata uses the same real Worklets and React Native versions',()=>{
  const source=generatedNativeAPIHostVersions({expo:{'@nativescript/react-native':'9.1.2','react-native-worklets':'0.13.0','react-native':'0.88.1'}});
  assert.match(source,/workletsVersion = "0\.13\.0"/);
  assert.match(source,/reactNativeVersion = "0\.88\.1"/);
  assert.throws(()=>generatedNativeAPIHostVersions({expo:{}}),/Missing exact/);
});

test('React declaration resolution intersects original Expo and RN ranges including disjunctions',()=>{
  const selection=reactTypesSelection({version:'58.0.26',devDependencies:{'@types/react':'~19.3.0'}},{version:'0.88.1',peerDependencies:{'@types/react':'^19.1.1 || ^20.0.0'}},'19.2.0');
  assert.equal(selection.requested,'^19.1.1 ~19.3.0 || ^20.0.0 ~19.3.0');
  assert.equal(selection.mode,'original-compatible-range');
  assert.deepEqual(selection.constraints.map(item=>item.source),['react-native@0.88.1 peerDependencies','expo@58.0.26 devDependencies']);
  assert.deepEqual(reactTypesSelection({version:'x'},{version:'y'},'19.3.0').mode,'explicit-pin');
});
test('an unconstrained original NativeScript compiler peer preserves the verified per-engine toolchains',()=>{
  const selected=compilerSelections({devDependencies:{typescript:'npm:@typescript/typescript6@6.0.2'}},{devDependencies:{typescript:'5.9.3'}},new Map([['@nativescript/vite',{peerDependencies:{typescript:'*'}}]]));
  assert.equal(selected.expo.requested,'npm:@typescript/typescript6@6.0.2');
  assert.equal(selected.nativescript.requested,'5.9.3');assert.equal(selected.nativescript.upstreamPeerRange,'*');
});

// Exact original @expo/ui58.0.29 input that failed the real WidgetKit target.
// The next input below changes only a default to exercise a later refresh.
test('SlotView refresh preserves native children and upstream changes without a React shadow hook',async()=>{
  const original=await readFile(new URL('./Fixtures/expo-ui-58.0.29/SlotView.swift',import.meta.url));
  const target='Packages/HanlinExpoWidgetSubset/Sources/HanlinExpoWidgetSubset/ExpoUI/SlotView.swift';
  const cache=await mkdtemp(path.join(tmpdir(),'hanlin-slot-refresh-'));
  const local=Buffer.from(original.toString()+'\n// Existing host customization.\n');
  try {
    const unchanged=await mergeOriginal({local,previous:original,next:original,cache,label:'same original SlotView',target});
    assert.doesNotMatch(unchanged.toString(),/publishZeroContentOrigin|shadowNodeProxy/);
    assert.match(unchanged.toString(),/public var body: some View \{\s+Children\(\)\s+\}/);
    assert.match(unchanged.toString(),/@Field var name: String = ""/);
    assert.match(unchanged.toString(),/@Field var extraProps: \[String: Any\]\?/);
    const helpers=original.toString().slice(original.toString().indexOf('  func extra<T>')).trimEnd();
    assert.ok(unchanged.toString().includes(helpers),'all original extra/slot/filter helpers must be retained');
    assert.match(unchanged.toString(),/Existing host customization/);
    const next=Buffer.from(original.toString().replace('@Field var name: String = ""','@Field var name: String = "updated original default"'));
    const advanced=await mergeOriginal({local:unchanged,previous:original,next,cache,label:'advanced original SlotView',target});
    assert.match(advanced.toString(),/@Field var name: String = "updated original default"/);
    assert.match(advanced.toString(),/Children\(\)/);
    assert.ok(advanced.toString().includes(helpers));
    assert.match(advanced.toString(),/Existing host customization/);
    assert.doesNotMatch(advanced.toString(),/publishZeroContentOrigin|shadowNodeProxy/);
    const foreground=await mergeOriginal({local:original,previous:original,next:original,cache,label:'foreground SlotView',target:'Packages/HanlinExpoRuntime/OriginalExpoUI/SlotView.swift'});
    assert.deepEqual(foreground,original,'the complete foreground React implementation must remain unchanged');
  } finally {await rm(cache,{recursive:true,force:true});}
});
