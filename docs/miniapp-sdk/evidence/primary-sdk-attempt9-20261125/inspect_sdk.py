#!/usr/bin/env python3
"""Inspect existing SDK9 archive in place; never invoke product tooling or native tools."""
from pathlib import Path, PurePosixPath
from datetime import datetime,timezone
import subprocess,json,hashlib,zipfile,gzip,re,ast,plistlib,difflib,time
W=Path("/mnt/development/projects/worktrees/hanlin-primary-sdk-preparation-20261124")
ROOT=Path("/mnt/development/projects/transfers/hanlin-primary-ce49-20261124")
S=ROOT/"prepared-snapshot-attempt9";P=ROOT/"prepared-snapshot-attempt7"
OUT=W/"docs/miniapp-sdk/evidence/primary-sdk-attempt9-20261125"
BASE="1812bff50571c9907d15cd8b4bfbe4874be24756"
HOST="AI_HLY/Downstream/RuntimeCore/Node/Host/miniapp-authoring.mjs"
HOST_SHA="fa5121902e231d5d44ad08bf47699784fd4d0bc2a98102f3a156e6e4ae79b9b9"
def sha(b):return hashlib.sha256(b).hexdigest()
def canonical(v):return json.dumps(v,ensure_ascii=False,separators=(",",":")).encode()
def emit(n,v):(OUT/n).write_text(json.dumps(v,ensure_ascii=False,indent=2)+"\n")
def difference(a,b,p=""):
 if type(a)!=type(b):return [{"pointer":p,"before":a,"after":b}]
 if isinstance(a,dict):
  out=[]
  for k in sorted(a.keys()|b.keys()):
   out+=([{"pointer":p+"/"+k,"before":a.get(k),"after":b.get(k)}] if k not in a or k not in b else difference(a[k],b[k],p+"/"+k))
  return out
 if isinstance(a,list):
  if len(a)!=len(b):return [{"pointer":p,"beforeLength":len(a),"afterLength":len(b)}]
  return [v for i,(x,y) in enumerate(zip(a,b)) for v in difference(x,y,p+"/"+str(i))]
 return [] if a==b else [{"pointer":p,"before":a,"after":b}]
cache={}
def git(p,base=BASE):
 key=(base,p)
 if key not in cache:cache[key]=subprocess.check_output(["git","-C",str(W),"show",base+":"+p])
 return cache[key]
clock=time.monotonic();started=datetime.now(timezone.utc).isoformat()
r=json.loads((S/"receipt.json").read_bytes())
transfer=json.loads((OUT/"transfer-verification.json").read_bytes())
assert transfer["snapshotReceiptSHA256"]==sha((S/"receipt.json").read_bytes())=="74663345cae2bb65b7de8b1eb6981bfeeb3319288de6b89a7f15bf8aa7ffb608"
assert r["sourceHEAD"]==BASE
delta=json.loads((S/r["trackedDeltaPath"]).read_bytes())
overlay={v["path"]:(S/v["contentFrom"]).read_bytes() for v in delta}
def current(p):return overlay[p] if p in overlay else git(p)
mb=(S/r["sdkManifest"]["snapshotPath"]).read_bytes();m=json.loads(mb)
priorb=(P/"extracted-sdk/miniapp-sdk.json").read_bytes();prior=json.loads(priorb)
assert sha(mb)==r["sdkManifest"]["sha256"]
assert sha(priorb)=="6a5ce216ab722741314a893f8bb226773da27c9d6151f6cbc28f46901b8fcb94"
assert sha(canonical(m["sourceInputs"]))==m["inputSHA256"]==r["sdkIdentity"]["inputSHA256"]
inputs={x["path"]:x for x in m["sourceInputs"]};oldInputs={x["path"]:x for x in prior["sourceInputs"]}
files={x["path"]:x for x in m["files"]};oldFiles={x["path"]:x for x in prior["files"]}
assert len(inputs)==len(m["sourceInputs"])==222 and len(files)==len(m["files"])==25661
assert inputs.keys()==oldInputs.keys() and files.keys()==oldFiles.keys()
changedInputs=[{"path":p,"before":oldInputs[p],"after":inputs[p]} for p in sorted(inputs) if inputs[p]!=oldInputs[p]]
changedFiles=[{"path":p,"before":oldFiles[p],"after":files[p]} for p in sorted(files) if files[p]!=oldFiles[p]]
assert len(changedInputs)==len(changedFiles)==11
sourceRows=[]
for p,v in inputs.items():
 actual=sha(current(p));assert actual==v["sha256"],p
 sourceRows.append({**v,"actualSHA256":actual,"fromPreparedPayload":p in overlay,"matches":True})
emit("sdk-source-binding.json",{"executionSource":BASE,"inputSHA256":m["inputSHA256"],"sourceInputCount":len(inputs),"sourceInputsAtGitBase":sum(not x["fromPreparedPayload"] for x in sourceRows),"sourceInputsFromPreparedPayload":sum(x["fromPreparedPayload"] for x in sourceRows),"rows":sourceRows})
ziprow=next(v for v in transfer["files"] if v["path"]=="build/runtime-host/RuntimeHostResources.zip")
assert (S/ziprow["snapshotPath"]).stat().st_size==ziprow["bytes"]
assert sha(git(HOST))==HOST_SHA
with zipfile.ZipFile(S/ziprow["snapshotPath"]) as z,zipfile.ZipFile(P/"files/build/runtime-host/RuntimeHostResources.zip") as oz:
 names=z.namelist();assert len(names)==len(set(names))
 actualNames={n[len("MiniAppSDK/"):] for n in names if n.startswith("MiniAppSDK/") and not n.endswith("/") and n!="MiniAppSDK/miniapp-sdk.json"}
 assert actualNames==set(files) and z.read("MiniAppSDK/miniapp-sdk.json")==mb
 sdkVerifiedBytes=0
 for p,v in files.items():
  h=hashlib.sha256();size=0
  with z.open("MiniAppSDK/"+p) as stream:
   for block in iter(lambda:stream.read(1024*1024),b""):h.update(block);size+=len(block)
  assert h.hexdigest()==v["sha256"] and size==v["bytes"],p
  sdkVerifiedBytes+=size
 assert z.read("miniapp-authoring.mjs")==git(HOST)
 assert r["hostModule"]=={"archiveMember":"miniapp-authoring.mjs","bytes":len(git(HOST)),"sha256":HOST_SHA,"appSourceArchiveSHA256":ziprow["sha256"]}
 assert not any(n.startswith("Tests/") for n in names)
 outer={n:info for info in z.infolist() if not (n:=info.filename).startswith("MiniAppSDK/") and not n.endswith("/")}
 oldOuter={n:info for info in oz.infolist() if not (n:=info.filename).startswith("MiniAppSDK/") and not n.endswith("/")}
 assert outer.keys()==oldOuter.keys() and len(outer)==3102
 hostRows=[]
 for p in sorted(outer):
  old=sha(oz.read(p));new=sha(z.read(p))
  hostRows.append({"path":p,"beforeSHA256":old,"afterSHA256":new,"bytes":outer[p].file_size,"changed":old!=new})
 hostChanged=[x for x in hostRows if x["changed"]]
 assert [x["path"] for x in hostChanged]==["miniapp-authoring.mjs"]
 emit("host-member-comparison.json",{"beforeArchiveSHA256":"c4e85e967f873ffbe907990c5d9d612b5b6f95871b4e85c736ec0799f09cb1af","afterArchiveSHA256":ziprow["sha256"],"scope":"Every actual uncompressed outside-SDK Host member compared in place","changed":len(hostChanged),"unchanged":len(hostRows)-len(hostChanged),"rows":hostRows})
 expo=m["engines"]["expo"];pkg=json.loads(current("Scripts/Expo/package.json"));lock=json.loads(current("Scripts/Expo/package-lock.json"))
 declared={**pkg.get("dependencies",{}),**pkg.get("devDependencies",{}),**pkg.get("optionalDependencies",{})}
 assert set(expo["packageVersions"])==set(declared) and len(declared)==21
 assert expo["packageVersions"]["expo-asset"]==expo["hostContract"]["plugins"]["expo-asset"]=="58.0.21"
 assert expo["packageVersions"]["@types/react"]=="19.3.1"
 assert expo["installation"]["inputs"]["packageSHA256"]==sha(current("Scripts/Expo/package.json"))
 assert expo["installation"]["inputs"]["lockSHA256"]==sha(current("Scripts/Expo/package-lock.json"))
 packages=[]
 for name,version in expo["packageVersions"].items():
  p="expo/node_modules/"+name+"/package.json";pb=z.read("MiniAppSDK/"+p);package=json.loads(pb)
  assert package["version"]==version,(name,version,package["version"])
  resources={"name":name,"packageJSON":p}
  types=package.get("types",package.get("typings"))
  if isinstance(types,str):
   resources["types"]=str(PurePosixPath(p).parent/types)
   assert resources["types"] in files,(name,resources["types"])
  packages.append({"name":name,"version":version,"packageJSONSHA256":sha(pb),"resourceLocators":resources})
 assetPkg=next(x for x in packages if x["name"]=="expo-asset")
 assert assetPkg["resourceLocators"]["types"]=="expo/node_modules/expo-asset/build/index.d.ts"
 assetRows=[{"path":p,"sha256":v["sha256"],"bytes":v["bytes"],"unchangedFromSDK7":v==oldFiles[p]} for p,v in files.items() if p.startswith("expo/node_modules/expo-asset/")]
 assert assetRows and all(x["unchangedFromSDK7"] for x in assetRows)
 fx=z.read("MiniAppSDK/expo/node_modules/expo/src/Expo.fx.tsx").decode()
 assetBridge=z.read("MiniAppSDK/expo/node_modules/expo-asset/src/ExpoAsset.ts").decode()
 assert "expo-asset" in fx and "requireNativeModule" in assetBridge and "ExpoAsset" in assetBridge
 emit("expo-asset-sdk-authority.json",{"source":BASE,"hostModuleSHA256":HOST_SHA,"packageVersionsCount":21,"packages":packages,"assetPackage":assetPkg,"assetMembers":assetRows,"assetMemberCount":len(assetRows),"allAssetOriginalPublishedMemberBytesUnchangedFromSDK7":True,"hostPluginVersion":expo["hostContract"]["plugins"]["expo-asset"],"upstreamAssetVersion":m["upstream"]["expo"]["assetVersion"],"toolingInstallation":expo["installation"],"publicResourceContract":{"implementation":HOST,"lines":[53,87],"derivation":"Source readMiniAppSDK maps each actual packageVersions key to package.json and its types/typings field; locators above are independently derived from actual archive bytes.","endpointExecutedByThisInspector":False},"canonicalResolverAuthority":"Existing TypeScript module/type/config and Metro authority consumes the same actual packageVersions keys; Asset is now included.","nativeBinaryPolicy":m["nativeBinaries"]})
 correctionBytes=(S/"files/build/acceptance/expo-type-declarations/corrections.json").read_bytes();corrections=json.loads(correctionBytes)
 producer=current("Scripts/Expo/prepare-types.mjs")
 assert producer==git("Scripts/Expo/prepare-types.mjs","fd81d602d3b25f09162a659e1e0cf0582e91a93a")
 patchtext=producer.decode().split("const patches = [\n",1)[1].split("\n];",1)[0]
 chunks=re.findall(r"  \{(?:package: '[^']+', )?file: '[^']+',[\s\S]*?(?=\n  \{|\Z)",patchtext);assert len(chunks)==len(corrections["patches"])==5
 correctionRows=[]
 originalProof=json.loads(git("docs/miniapp-sdk/evidence/EXPO_SDK_TYPES_2026-11-14.json"))
 for chunk,receiptPatch in zip(chunks,corrections["patches"]):
  fields={k:re.search(r"\b"+k+r": '([^']*)'",chunk).group(1) for k in ["file","originalSHA256","source","sourceSHA256"]}
  match=re.search(r"\bpackage: '([^']+)'",chunk);package=match.group(1) if match else "react-native"
  replacements=ast.literal_eval(re.search(r"replacements: (\[\[[\s\S]*?\]\]),",chunk).group(1))
  p="expo/node_modules/"+package+"/"+("types/ios/" if match else "types_generated/")+fields["file"]
  body=z.read("MiniAppSDK/"+p);original=body.decode()
  for before,after in replacements:assert original.count(after)==1;original=original.replace(after,before,1)
  assert sha(original.encode())==fields["originalSHA256"]
  reproduced=original
  for before,after in replacements:assert reproduced.count(before)==1;reproduced=reproduced.replace(before,after,1)
  assert reproduced.encode()==body and files[p]["sha256"]==receiptPatch["correctedSHA256"]==sha(body)
  assert all(receiptPatch[k]==v for k,v in fields.items()) and receiptPatch["package"]==package
  assert receiptPatch==next(x for x in originalProof["declarationCorrections"]["patches"] if x["package"]==package and x["file"]==fields["file"])
  member="MiniAppSDK/expo/node_modules/"+package+"/"+fields["source"]
  if member in names:implementation=z.read(member);authority=member
  else:authority="Packages/HanlinExpoNativeAPI/Sources/HanlinExpoNativeAPICore/nativescript/"+fields["source"];implementation=current(authority)
  assert sha(implementation)==fields["sourceSHA256"]
  correctionRows.append({**receiptPatch,"packageVersion":expo["packageVersions"][package],"SDKPath":p,"bytes":len(body),"exactSubstitutions":replacements,"reconstructedOriginalSHA256":sha(original.encode()),"implementationAuthority":authority,"actualImplementationSHA256":sha(implementation),"unchangedFromSDK7":files[p]==oldFiles[p],"publication":{k:lock["packages"]["node_modules/"+package].get(k) for k in ["version","resolved","integrity"]}})
 assert all(x["unchangedFromSDK7"] for x in correctionRows)
 assert corrections["reactNative"]=="0.88.1" and corrections["nativeAPI"]=="9.1.2"
 typesPaths=[p for p in files if p.startswith("expo/node_modules/@types/react/") and files[p]!=oldFiles[p]]
 typeChanges=[]
 for p in sorted(typesPaths):
  before=oz.read("MiniAppSDK/"+p).decode();after=z.read("MiniAppSDK/"+p).decode()
  typeChanges.append({"path":p,"before":oldFiles[p],"after":files[p],"diff":"".join(difflib.unified_diff(before.splitlines(True),after.splitlines(True),fromfile="19.3.0/"+p,tofile="19.3.1/"+p))})
 assert len(typeChanges)==4
 emit("declaration-transforms-and-react-update.json",{"status":"ACTUAL_BYTES_BOUND_NO_NEW_TRANSFORMS","correctionProducer":"Scripts/Expo/prepare-types.mjs","producerSHA256":sha(producer),"producerUnchangedSinceSDK7":True,"actualCorrectionReceiptSHA256":sha(correctionBytes),"currentPackages":{"react-native":"0.88.1","@nativescript/react-native":"9.1.2"},"historicalEvidence":{"path":"docs/miniapp-sdk/evidence/EXPO_SDK_TYPES_2026-11-14.json","sha256":sha(git("docs/miniapp-sdk/evidence/EXPO_SDK_TYPES_2026-11-14.json")),"historicalReactNativeVersion":"0.88.0","boundary":"The same affected original declaration/implementation hashes remain current at0.88.1; the historical release/other execution facts are not relabeled."},"patchedFileCount":5,"exactSubstitutionCount":sum(len(x["exactSubstitutions"]) for x in correctionRows),"patches":correctionRows,"originalUIExports":corrections.get("originalUIExports"),"separateOriginalReactTypeUpdate":{"before":"19.3.0","after":"19.3.1","lockedPublication":lock["packages"]["node_modules/@types/react"],"changedMembers":typeChanges,"source":"Existing original upstream resolver during actual attempt8, preserved into attempt9; not a new Hanlin declaration patch."},"boundary":"Original publication identities and explicit deterministic compatibility transforms are distinct. No claim that every shipped declaration is byte-unmodified. No compiler or type patch producer rerun by inspector."})
 aliasPath="docs/miniapp-sdk/evidence/primary-typescript-alias-identity-20261124/receipt.json";aliasBytes=git(aliasPath)
 assert sha(aliasBytes)=="20a4f5c5abf3c294e3a6f522ca3e840b73d869755b26f3935f04b27079eb9043"
 expectedAlias={"expo/node_modules/typescript/lib/typescript.js":"d3f3cd2b04b7f466f4484df921b744223f7bd1f3e353ec9110bdf52695b983d5","expo/node_modules/typescript/package.json":"d9b8fb53c67c947fece83bcb73fa8512227ea6a12b110e096fdab8ecdc02b655","expo/node_modules/@typescript/old/lib/typescript.js":"569177652966bd528c319171c7dd22860dbf72bde116cbc4f644f1d02bb12e39","expo/node_modules/@typescript/old/package.json":"9332e97c30d3e53ed54910b89207ed657fb444066484df6e5b6965bf130865e9"}
 for p,digest in expectedAlias.items():assert sha(z.read("MiniAppSDK/"+p))==digest and files[p]==oldFiles[p]
 assert expo["typescript"]==prior["engines"]["expo"]["typescript"]=={"packageName":"@typescript/typescript6","packageVersion":"6.0.2","compilerVersion":"6.0.3"}
 assert declared["typescript"]=="npm:@typescript/typescript6@6.0.2"
 emit("compiler-identity-binding.json",{"priorEvidence":aliasPath,"priorReceiptSHA256":sha(aliasBytes),"actualMembers":expectedAlias,"allFourOriginalBytesUnchanged":True,"manifestCompilerIdentity":expo["typescript"],"declaredAlias":declared["typescript"],"packageLockSHA256":sha(current("Scripts/Expo/package-lock.json")),"boundary":"Current whole lock changed for ExpoAsset and original React types; existing TypeScript alias/implementation binding remains identical. Compiler API was not re-executed."})
 docBytes=(S/"files/build/app-split-evidence/miniapp-documentation-snippets.json").read_bytes();doc=json.loads(docBytes)
 oldDoc=json.loads((P/"files/build/app-split-evidence/miniapp-documentation-snippets.json").read_bytes())
 assert doc["status"]=="EXECUTED_PASS" and doc["sdk"]=={"manifestSHA256":sha(mb),"inputSHA256":m["inputSHA256"]}
 assert doc["sourceBlockCount"]==14 and doc["jsonBlockCount"]==7 and len(doc["excluded"])==8
 for row in doc["documentation"]:
  p=row["path"];assert z.read("MiniAppSDK/"+p)==current(p) and row["sha256"]==row["stagedSDKSHA256"]==sha(current(p)) and row["stagedSDKMatches"]
 for row in doc["checkerInputs"]:assert sha(current(row["path"]))==row["sha256"]
 assert doc["registration"]["nativeSessionSHA256"]==sha(current(doc["registration"]["nativePath"]))
 projects=[]
 for project in doc["projects"]:
  v=project["validation"];assert v["succeeded"] and v["diagnostics"]==[] and v["sdk"]["manifestSHA256"]==sha(mb)
  assert v["sdk"]["packageVersions"]==m["engines"][project["engine"]]["packageVersions"]
  old=next(x for x in oldDoc["projects"] if x["name"]==project["name"])
  projects.append({"name":project["name"],"engine":project["engine"],"succeeded":True,"diagnostics":0,"compilerVersion":v["sdk"]["compilerVersion"],"typecheck":v["typecheck"],"sameSnippets":project["snippets"]==old["snippets"],"sameContext":project["context"]==old["context"],"sameTypecheckOptions":v["typecheck"]==old["validation"]["typecheck"]})
 assert len(projects)==4
 emit("documentation-execution-binding.json",{"status":"EXECUTED_PASS","actualReportSHA256":sha(docBytes),"source":BASE,"sdk":doc["sdk"],"projects":projects,"sourceFences":14,"jsonFences":7,"nonAuthoringExclusions":8,"checkerInputs":doc["checkerInputs"],"documentation":doc["documentation"],"registration":doc["registration"],"boundary":doc["boundary"],"inspectionDidNotRerunCompiler":True})
groups={}
for name,predicate in [("declarations",lambda p:p.endswith((".d.ts",".d.mts",".d.cts"))),("examples",lambda p:p.startswith("examples/")),("public-docs",lambda p:p.startswith("docs/")),("original-compiler-entrypoints",lambda p:p in [m["engines"]["expo"]["typescriptPath"],m["engines"]["nativescript"]["typescriptPath"]])]:
 selected=[p for p in files if predicate(p)]
 groups[name]={"members":len(selected),"unchanged":sum(files[p]==oldFiles[p] for p in selected),"changed":[p for p in selected if files[p]!=oldFiles[p]]}
emit("sdk-reconciliation.json",{"source":BASE,"archiveSHA256":ziprow["sha256"],"manifestSHA256":sha(mb),"inputSHA256":m["inputSHA256"],"allActualSDKMembersVerified":len(files),"actualSDKMemberBytesVerified":sdkVerifiedBytes,"changedInputs":changedInputs,"unchangedInputs":len(inputs)-len(changedInputs),"changedMembers":changedFiles,"unchangedMembers":len(files)-len(changedFiles),"groupComparison":groups,"metadataDifferences":difference({k:v for k,v in prior.items() if k not in ["files","sourceInputs","inputSHA256"]},{k:v for k,v in m.items() if k not in ["files","sourceInputs","inputSHA256"]}),"boundary":"Every current SDK member hash/size and exact member set verified against the retained manifest; no extraction, repack or product execution."})
inv=json.loads(overlay["docs/miniapp-sdk/source-inventory.json"]);reach=json.loads(overlay["docs/miniapp-sdk/extension-reachability.json"])
assert inv["sourceCommit"]==reach["sourceCommit"]==BASE
sourceBindings=[]
for group,values in [("inventory.sources",inv["sources"]),("reachability.sdkSources",reach["sdkSources"])]:
 for row in values:assert sha(current(row["path"]))==row["sha256"];sourceBindings.append({"group":group,**row})
refs=[]
def collect(v,context):
 if isinstance(v,dict):
  p=v.get("file") or v.get("path")
  if isinstance(p,str) and isinstance(v.get("sha256"),str):
   body=current(p);assert sha(body)==v["sha256"],(context,p)
   row={"context":context,"path":p,"sha256":sha(body)}
   if isinstance(v.get("line"),int):assert 1<=v["line"]<=len(body.splitlines());row["line"]=v["line"]
   refs.append(row)
  for k,x in v.items():
   if isinstance(x,(dict,list)):collect(x,context+"."+k)
 elif isinstance(v,list):
  for i,x in enumerate(v):collect(x,context+"."+str(i))
collect(reach["sourceRefs"],"reachability.sourceRefs");collect(inv["manifests"],"inventory.manifests")
assert len(inv["sources"])==93 and len(reach["matrix"])==80 and inv["manifestCoverage"]["fieldCount"]==335
expoFamily=next(x for x in inv["manifests"] if x["family"]=="expo prepared package.json")
assetField=next(x for x in expoFamily["fields"] if x["field"]=="hanlinExpo.plugins.expo-asset")
assert assetField["semantics"]=="Exact installed original Expo Asset version."
emit("shipped-provenance-binding.json",{"source":BASE,"inventorySourceCount":93,"reachabilityCells":80,"manifestFields":335,"expoAssetField":assetField,"inventoryUncommittedSourcePaths":inv["uncommittedSourcePaths"],"reachabilityUncommittedSourcePaths":reach["uncommittedSourcePaths"],"allSourceHashesAndLineBoundsVerified":True,"sourceRows":sourceBindings,"sourceRefs":refs,"boundary":"Source inventory and80reachability cells are not application or physical-device acceptance."})
catBytes=(S/"files/build/app-split-evidence/prepared-native/native-artifacts.json").read_bytes();cat=json.loads(catBytes)
oldCat=json.loads((P/"files/build/app-split-evidence/prepared-native/native-artifacts.json").read_bytes())
assert cat["sourceCommit"]==BASE and cat["state"]=="prepared" and cat["missingTargets"]==[] and len(cat["requiredTargets"])==15
nativeInputs=[]
for p,digest in cat["inputSHA256"].items():assert sha(current(p))==digest;nativeInputs.append({"path":p,"sha256":digest,"sameAsSDK7":oldCat["inputSHA256"].get(p)==digest})
comparison={}
for key in ["artifacts","supportArtifacts"]:
 a={x["target"]:x for x in oldCat[key]};b={x["target"]:x for x in cat[key]}
 comparison[key]={"added":sorted(b.keys()-a.keys()),"removed":sorted(a.keys()-b.keys()),"existing":[{"target":k,"sameContentMetadata":{p:v for p,v in a[k].items() if p!="url"}=={p:v for p,v in b[k].items() if p!="url"},"differences":difference({p:v for p,v in a[k].items() if p!="url"},{p:v for p,v in b[k].items() if p!="url"})} for k in sorted(a.keys()&b.keys())]}
assert comparison["artifacts"]["added"]==["ExpoAsset"] and comparison["artifacts"]["removed"]==[]
assetCat=next(x for x in cat["artifacts"] if x["target"]=="ExpoAsset")
assetReceiptBytes=(S/"files/Packages/HanlinExpoRuntime/Artifacts/ExpoAsset.xcframework/.source-build-receipt.json").read_bytes();assetReceipt=json.loads(assetReceiptBytes)
assetManifest=json.loads((S/"files/Packages/HanlinExpoRuntime/Artifacts/ExpoAsset.xcframework/.artifact-manifest.json").read_bytes())
assetBindingsBytes=(S/r["expoAssetBindingsPath"]).read_bytes();assetBindings=json.loads(assetBindingsBytes)
assert sha(assetBindingsBytes)==r["expoAssetBindingsSHA256"] and assetBindings["originalSourceReceipt"]==assetReceipt
assert all(x["sha256"]==x["preparedTargetSHA256"] for x in assetBindings["files"])
assert len(assetBindings["files"])==23
packageLock=json.loads(current("Scripts/Expo/package-lock.json"));assetLock=packageLock["packages"]["node_modules/expo-asset"]
assert assetReceipt["originalPackage"]["version"]==assetLock["version"]=="58.0.21"
assert assetReceipt["originalPackage"]["integrity"]==assetLock["integrity"]
assert assetReceipt["inputSHA256"]==assetManifest["sourceBuildInputSHA256"]=="a85fc86c413d87679e62878cc4b7b512e925c36806a9b383daf095dab9c55159"
assert assetReceipt["originalPackage"]["sha256"]==assetManifest["sha256"]=="2bfbb115da9111702530e5df550eac7e2a074aa12b6297fcc332744767623126"
assert assetReceipt["podLockSHA256"]==sha((S/"files/build/miniapp-upstreams/expo-native-source/ios/Podfile.lock").read_bytes())
plistBytes=(S/"files/Packages/HanlinExpoRuntime/Artifacts/ExpoAsset.xcframework/Info.plist").read_bytes()
assert plistlib.loads(plistBytes)["AvailableLibraries"]==assetReceipt["slices"]
for lib in assetCat["libraries"]:
 row=next(x for x in assetBindings["files"] if x["path"]==lib["binary"])
 assert row["sha256"]==lib["binarySHA256"]
emit("expo-asset-native-binding.json",{"status":"ORIGINAL_PRODUCER_AND_CATALOG_BOUND","sourceBuildReceiptSHA256":sha(assetReceiptBytes),"sourceBuildInputSHA256":assetReceipt["inputSHA256"],"originalNpmTarballSHA256":assetReceipt["originalPackage"]["sha256"],"originalPackage":assetReceipt["originalPackage"],"artifactManifest":assetManifest,"catalogArtifact":assetCat,"stagedToPreparedMemberComparison":{"actualOwnerReceiptSHA256":sha(assetBindingsBytes),"members":len(assetBindings["files"]),"allMatch":True,"binaryMatchesCatalog":True},"sourceReceipt":assetReceipt,"boundary":"Original completed Mac source products, owner-observed23member stage/target comparison and catalog binary hashes are bound. Full native export binaries were not downloaded/extracted again; no native application pass inferred."})
emit("native-catalog-binding.json",{"catalogSHA256":sha(catBytes),"contentSHA256":cat["contentSHA256"],"source":BASE,"inputBindings":nativeInputs,"requiredTargets":cat["requiredTargets"],"missingTargets":cat["missingTargets"],"comparison":comparison,"acceptance":cat["acceptance"],"boundary":"Exporter catalog/source-input proof; original native and consumer tests remain separately observed."})
stateBytes=(S/"controller-state-at-capture.json").read_bytes();state=json.loads(stateBytes)
assert state["source"]==BASE and state["attempt"]==9 and state["status"]=="PAUSED_AFTER_PHASE" and state["phase"]=="split-inputs"
for name,v in r["phaseReceipts"].items():assert v["status"]=="PASS" and v["exitCode"]==0 and state["phases"][name]==v
advance=json.loads((S/"files/build/primary-control/source-advance-1812bff5/receipt.json").read_bytes())
assert advance["target"]==BASE and advance["targetTree"]==r["sourceTree"] and not advance["nativeStarted"]
for p,digest in advance["sourceHashes"].items():assert sha(git(p))==digest
assert len(advance["workingFiles"])==9 and all(x["preserved"] for x in advance["workingFiles"])
priorFailure=advance["priorFailure"]
failedLog=(S/"files/build/primary-control/logs-attempt8/split-native-preparation.log").read_bytes()
assert priorFailure["status"]=="FAIL" and priorFailure["exitCode"]==1 and sha(failedLog)==priorFailure["logSHA256"]
assert b"Unmapped manifest field drift: expo embedded plugins" in failedLog
admission=json.loads((S/"files/build/primary-control/capacity-admission-attempt9.json").read_bytes())
assert admission["source"]==BASE and admission["status"]=="ADMITTED_CONTROLLER_STARTED"
logBytes=(S/"files/build/primary-control/logs-attempt9/split-native-preparation.log").read_bytes();log=logBytes.decode()
assert sha(logBytes)==r["phaseReceipts"]["split-native-preparation"]["logSHA256"]
counts={k:int(re.search("ℹ "+k+r" (\d+)",log).group(1)) for k in ["tests","pass","fail","skipped"]}
assert counts=={"tests":170,"pass":169,"fail":0,"skipped":1}
skips=[l for l in log.splitlines() if "# SKIP" in l];assert len(skips)==1 and "actual Node job crosses 300 seconds" in skips[0]
assert "Exact original ExpoAsset source build reused: "+assetReceipt["inputSHA256"] in log
assert "PASS: SDK source inventory matches 93 sources and 176 local public exports." in log
assert "PASS: 80 unique source-backed reachability cells; no E2E pass inferred." in log
metadata=json.loads((S/"files/build/runtime-host/host-metadata.json").read_bytes())
assert metadata["archiveSha256"]==ziprow["sha256"] and metadata["tests"]==metadata["jitlessArchiveSmoke"]=="passed"
hostSourceChanges=subprocess.check_output(["git","-C",str(W),"diff","--name-only","fd81d602d3b25f09162a659e1e0cf0582e91a93a",BASE,"--","AI_HLY/Downstream/RuntimeCore/Node/Host"],text=True).splitlines()
hostSourceRows=[{"path":p,"sha256":sha(git(p)),"shippedAsHostMember":p[len("AI_HLY/Downstream/RuntimeCore/Node/Host/"):] in outer} for p in hostSourceChanges]
emit("host-archive-binding.json",{"archiveSHA256":ziprow["sha256"],"archiveBytes":ziprow["bytes"],"moduleSHA256":HOST_SHA,"metadata":metadata,"actualHostTestCounts":counts,"existingSkippedTest":skips[0],"changedHostSourcesSinceSDK7":hostSourceRows,"testsNotShipped":True,"boundary":"170actual Host tests:169passed,0failed,1existing opt-in long-duration test skipped. Counts are not the52application cases; regression sources affect producer fingerprint but are not shipped."})
emit("execution-checkpoint.json",{"capturedAtUTC":r["capturedAt"],"source":BASE,"tree":r["sourceTree"],"attempt":9,"sourceAdvanceAtUTC":advance["utc"],"sourceAdvanceReceiptSHA256":sha((S/"files/build/primary-control/source-advance-1812bff5/receipt.json").read_bytes()),"capacityAdmission":admission,"priorAttempt8Failure":priorFailure,"priorAttempt8LogSHA256":sha(failedLog),"phaseReceipts":r["phaseReceipts"],"controllerStateSHA256":sha(stateBytes),"statusAtCapture":state["status"],"phaseAtCapture":state["phase"],"hostLifecycleClassification":"REUSED_RECORDED_PASS_FROM_ATTEMPT8; receipt/log identity and original time preserved, not re-executed in attempt9","nativePreparationClassification":"EXECUTED_PASS","nativeExportClassification":"EXECUTED_PASS","consumerBuildsAtCapture":"NOT_RUN_ON_THIS_PREPARED_IDENTITY","applicationAcceptance":"NOT_ESTABLISHED_BY_THIS_SNAPSHOT","boundary":"Later actual consumer/runtime observations supersede this dated paused checkpoint without modifying raw proof."})
summary={"status":"PASS","recordedAtUTC":datetime.now(timezone.utc).isoformat(),"inspectionStartedAtUTC":started,"elapsedSeconds":time.monotonic()-clock,"source":BASE,"archiveSHA256":ziprow["sha256"],"manifestSHA256":sha(mb),"inputSHA256":m["inputSHA256"],"actualSDKMembersVerified":len(files),"actualSDKBytesVerified":sdkVerifiedBytes,"changedInputs":len(changedInputs),"unchangedInputs":len(inputs)-len(changedInputs),"changedSDKMembers":len(changedFiles),"unchangedSDKMembers":len(files)-len(changedFiles),"changedOutsideSDKHostMembers":len(hostChanged),"unchangedOutsideSDKHostMembers":len(hostRows)-len(hostChanged),"declarationGroups":groups,"expoPackageVersionKeys":21,"expoAssetVersion":"58.0.21","reactTypesVersion":"19.3.1","pinnedDeclarationCorrections":5,"exactDeclarationSubstitutions":sum(len(x["exactSubstitutions"]) for x in correctionRows),"documentProjects":4,"diagnostics":0,"nativeRequiredTargets":15,"missingTargets":0,"hostTests":counts,"applicationAcceptance":"NOT_ESTABLISHED"}
emit("inspection-summary.json",summary);print(json.dumps(summary,ensure_ascii=False))
