#!/usr/bin/env python3
"""Compare frozen prepared SDK10 bytes in place. No compiler, generator or native execution."""
from pathlib import Path
from datetime import datetime,timezone
import json,hashlib,subprocess,zipfile,plistlib,re,time
W=Path("/mnt/development/projects/worktrees/hanlin-primary-sdk-preparation-20261124")
R=Path("/mnt/development/projects/transfers/hanlin-primary-ce49-20261124")
S=R/"prepared-snapshot-attempt10";P=R/"prepared-snapshot-attempt9"
O=W/"docs/miniapp-sdk/evidence/primary-sdk-attempt10-20261125"
E=W/"docs/miniapp-sdk/evidence/primary-sdk-attempt9-20261125"
BASE="fda6948ca6a1f541293a1a1dd20e97f75eb0a527";OLD="1812bff50571c9907d15cd8b4bfbe4874be24756"
def sha(v):return hashlib.sha256(v).hexdigest()
def canonical(v):return json.dumps(v,ensure_ascii=False,separators=(",",":")).encode()
def emit(n,v):(O/n).write_text(json.dumps(v,ensure_ascii=False,indent=2)+"\n")
cache={}
def git(p,base=BASE):
 key=(base,p)
 if key not in cache:cache[key]=subprocess.check_output(["git","-C",str(W),"show",base+":"+p])
 return cache[key]
def difference(a,b,path=""):
 if type(a)!=type(b):return [{"pointer":path,"before":a,"after":b}]
 if isinstance(a,dict):
  rows=[]
  for k in sorted(a.keys()|b.keys()):
   rows+=([{"pointer":path+"/"+k,"before":a.get(k),"after":b.get(k)}] if k not in a or k not in b else difference(a[k],b[k],path+"/"+k))
  return rows
 if isinstance(a,list):
  if len(a)!=len(b):return [{"pointer":path,"beforeLength":len(a),"afterLength":len(b)}]
  return [v for i,(x,y) in enumerate(zip(a,b)) for v in difference(x,y,path+"/"+str(i))]
 return [] if a==b else [{"pointer":path,"before":a,"after":b}]
started=datetime.now(timezone.utc).isoformat();clock=time.monotonic()
rb=(S/"receipt.json").read_bytes();r=json.loads(rb)
assert sha(rb)=="20ee3233d5094aec1e3f476fecfa66dd43c9b64129f8e235a96529a6e9cfbb35" and r["sourceHEAD"]==BASE
transfer=json.loads((O/"transfer-verification.json").read_bytes())
delta=json.loads((S/"tracked-delta.json").read_bytes())
overlay={x["path"]:(S/x["contentFrom"]).read_bytes() for x in delta}
def current(p):return overlay[p] if p in overlay else git(p)
mb=(S/"extracted-sdk/miniapp-sdk.json").read_bytes();m=json.loads(mb)
ob=(P/"extracted-sdk/miniapp-sdk.json").read_bytes();old=json.loads(ob)
assert sha(ob)=="6fbba77d588e292b291864f0cae9e5eb5d602a4e2f208379ce1c331dedf412c9"
assert sha(mb)==r["sdkManifest"]["sha256"] and sha(canonical(m["sourceInputs"]))==m["inputSHA256"]==r["sdkIdentity"]["inputSHA256"]
inputs={x["path"]:x for x in m["sourceInputs"]};oi={x["path"]:x for x in old["sourceInputs"]}
files={x["path"]:x for x in m["files"]};of={x["path"]:x for x in old["files"]}
assert len(inputs)==len(m["sourceInputs"])==222 and len(files)==len(m["files"])==25661
assert inputs.keys()==oi.keys() and files.keys()==of.keys()
changedInputs=[{"path":p,"before":oi[p],"after":inputs[p]} for p in sorted(inputs) if inputs[p]!=oi[p]]
changedFiles=[{"path":p,"before":of[p],"after":files[p]} for p in sorted(files) if files[p]!=of[p]]
expected=["docs/miniapp-sdk/extension-reachability.json","docs/miniapp-sdk/extension-reachability.md","docs/miniapp-sdk/source-inventory.json"]
assert [x["path"] for x in changedInputs]==[x["path"] for x in changedFiles]==expected
metadataKeys=set(m)-{"files","sourceInputs","inputSHA256"}
assert all(m[k]==old[k] for k in metadataKeys)
sourceRows=[]
for p,row in inputs.items():
 h=sha(current(p));assert h==row["sha256"],p
 sourceRows.append({**row,"actualSHA256":h,"fromPreparedPayload":p in overlay})
emit("sdk-source-binding.json",{"source":BASE,"inputSHA256":m["inputSHA256"],"sourceInputs":sourceRows,"allMatch":True})
ziprow=next(x for x in transfer["files"] if x["path"]=="build/runtime-host/RuntimeHostResources.zip")
host="AI_HLY/Downstream/RuntimeCore/Node/Host/miniapp-authoring.mjs"
assert sha(git(host))=="fa5121902e231d5d44ad08bf47699784fd4d0bc2a98102f3a156e6e4ae79b9b9"
previousEvidenceReceipt=(E/"receipt.json").read_bytes()
assert sha(previousEvidenceReceipt)=="a0e0c906735a77251bd403c1d8ce42013fc173e90caca727c8decac0cd14ba9d"
priorMembers={x["path"]:x for x in json.loads(previousEvidenceReceipt)["files"]}
reused=[]
def prior_report(name):
 b=(E/name).read_bytes();row=priorMembers[name]
 assert sha(b)==row["sha256"] and len(b)==row["bytes"]
 reused.append({"path":"docs/miniapp-sdk/evidence/primary-sdk-attempt9-20261125/"+name,"sha256":sha(b),"bytes":len(b)})
 return json.loads(b)
patchProof=prior_report("declaration-transforms-and-react-update.json")
compilerProof=prior_report("compiler-identity-binding.json")
assetProof=prior_report("expo-asset-sdk-authority.json")
sdkBytes=0
with zipfile.ZipFile(S/ziprow["snapshotPath"]) as z,zipfile.ZipFile(P/"files/build/runtime-host/RuntimeHostResources.zip") as oz:
 names=z.namelist();assert len(names)==len(set(names))
 actual={n[len("MiniAppSDK/"):] for n in names if n.startswith("MiniAppSDK/") and not n.endswith("/") and n!="MiniAppSDK/miniapp-sdk.json"}
 assert actual==set(files) and z.read("MiniAppSDK/miniapp-sdk.json")==mb
 for p,row in files.items():
  body=z.read("MiniAppSDK/"+p)
  assert len(body)==row["bytes"] and sha(body)==row["sha256"],p
  sdkBytes+=len(body)
 assert z.read("miniapp-authoring.mjs")==git(host)
 assert r["hostModule"]["sha256"]==sha(git(host)) and r["hostModule"]["appSourceArchiveSHA256"]==ziprow["sha256"]
 assert not any(n.startswith("Tests/") for n in names)
 outer=sorted(n for n in names if not n.startswith("MiniAppSDK/") and not n.endswith("/"))
 oldOuter=sorted(n for n in oz.namelist() if not n.startswith("MiniAppSDK/") and not n.endswith("/"))
 assert outer==oldOuter and len(outer)==3102
 outerRows=[]
 for p in outer:
  a=oz.read(p);b=z.read(p);assert a==b,p
  outerRows.append({"path":p,"bytes":len(b),"sha256":sha(b)})
 emit("host-member-comparison.json",{"beforeArchiveSHA256":"3c94ebea1e314c280031ac475e2d42b63ebcf2dc2eb32d2c6e31905e3eda3240","afterArchiveSHA256":ziprow["sha256"],"scope":"Every actual outside-SDK Host member compared byte-for-byte in place.","members":3102,"changed":[],"unchanged":3102,"canonicalMembersSHA256":sha(canonical(outerRows)),"canonicalAlgorithm":"SHA256 of compact UTF-8 JSON, sorted path; each row keys path,bytes,sha256","moduleSHA256":sha(git(host)),"moduleBytes":len(git(host))})
 correctionsBytes=(S/"files/build/acceptance/expo-type-declarations/corrections.json").read_bytes()
 assert sha(correctionsBytes)==patchProof["actualCorrectionReceiptSHA256"]
 assert sha(current("Scripts/Expo/prepare-types.mjs"))==patchProof["producerSHA256"]
 corrections=json.loads(correctionsBytes);boundPatches=[]
 for p in patchProof["patches"]:
  assert files[p["SDKPath"]]==of[p["SDKPath"]] and files[p["SDKPath"]]["sha256"]==p["correctedSHA256"]
  authority=p["implementationAuthority"]
  body=z.read(authority) if authority.startswith("MiniAppSDK/") else current(authority)
  assert sha(body)==p["sourceSHA256"]
  boundPatches.append({"package":p["package"],"packageVersion":p["packageVersion"],"SDKPath":p["SDKPath"],"originalSHA256":p["originalSHA256"],"correctedSHA256":p["correctedSHA256"],"sourceSHA256":p["sourceSHA256"],"exactSubstitutionCount":len(p["exactSubstitutions"]),"unchangedFromSDK9":True})
 assert len(boundPatches)==5 and sum(p["exactSubstitutionCount"] for p in boundPatches)==7
 for p,h in compilerProof["actualMembers"].items():assert files[p]["sha256"]==h and files[p]==of[p]
 assert m["engines"]["expo"]["typescript"]==compilerProof["manifestCompilerIdentity"]
 for p in assetProof["assetMembers"]:assert files[p["path"]]["sha256"]==p["sha256"] and files[p["path"]]==of[p["path"]]
 assert len(m["engines"]["expo"]["packageVersions"])==21
 assert m["engines"]["expo"]["packageVersions"]["expo-asset"]==m["engines"]["expo"]["hostContract"]["plugins"]["expo-asset"]=="58.0.21"
 assert m["engines"]["expo"]["packageVersions"]["@types/react"]=="19.3.1"
 emit("unchanged-original-library-bindings.json",{"source":BASE,"priorEvidenceReceiptSHA256":sha(previousEvidenceReceipt),"reusedProofs":reused,"sameEntireEngineAndUpstreamMetadata":True,"expoAsset":{"version":"58.0.21","originalPackageMembers":len(assetProof["assetMembers"]),"allUnchanged":True,"samePackageVersionAndPluginAuthority":True},"reactTypes":{"version":"19.3.1","unchangedFromActualSDK9":True,"existingAutomaticUpdate":"Original resolver selected 19.3.1 during attempt8, preserved through9 and10; no new declaration edit."},"declarationCompatibility":{"producerSHA256":patchProof["producerSHA256"],"receiptSHA256":sha(correctionsBytes),"files":5,"exactSubstitutions":7,"patches":boundPatches,"existingTransformOnly":True},"compiler":{"originalMembers":compilerProof["actualMembers"],"identity":compilerProof["manifestCompilerIdentity"],"declaredAlias":compilerProof["declaredAlias"],"notExecutedByInspector":True},"boundary":"Original publication identities include five explicit, existing deterministic declaration compatibility corrections. No claim that every shipped declaration byte is unmodified. Reuse is justified by exact current member/producer/receipt identity; no compiler or patch producer rerun."})
 docBytes=(S/"files/build/app-split-evidence/miniapp-documentation-snippets.json").read_bytes();doc=json.loads(docBytes)
 oldDoc=json.loads((P/"files/build/app-split-evidence/miniapp-documentation-snippets.json").read_bytes())
 assert doc["status"]=="EXECUTED_PASS" and doc["sdk"]=={"manifestSHA256":sha(mb),"inputSHA256":m["inputSHA256"]}
 for row in doc["documentation"]:
  p=row["path"];assert z.read("MiniAppSDK/"+p)==current(p) and row["sha256"]==row["stagedSDKSHA256"]==sha(current(p)) and row["stagedSDKMatches"]
 for row in doc["checkerInputs"]:assert sha(current(row["path"]))==row["sha256"]
 assert doc["registration"]["nativeSessionSHA256"]==sha(current(doc["registration"]["nativePath"]))
 projects=[]
 for p in doc["projects"]:
  v=p["validation"];op=next(x for x in oldDoc["projects"] if x["name"]==p["name"])
  assert v["succeeded"] and v["diagnostics"]==[] and v["sdk"]["manifestSHA256"]==sha(mb)
  assert v["sdk"]["packageVersions"]==m["engines"][p["engine"]]["packageVersions"]
  assert p["snippets"]==op["snippets"] and p["context"]==op["context"] and v["typecheck"]==op["validation"]["typecheck"]
  projects.append({"name":p["name"],"engine":p["engine"],"succeeded":True,"diagnostics":0,"compilerVersion":v["sdk"]["compilerVersion"],"typecheck":v["typecheck"],"sameOriginalSnippetsContextAndOptions":True})
 assert len(projects)==4 and doc["sourceBlockCount"]==14 and doc["jsonBlockCount"]==7 and len(doc["excluded"])==8
 emit("documentation-execution-binding.json",{"status":"EXECUTED_PASS","actualReportSHA256":sha(docBytes),"source":BASE,"sdk":doc["sdk"],"projects":projects,"sourceFences":14,"jsonFences":7,"nonAuthoringExclusions":8,"checkerInputs":doc["checkerInputs"],"registration":doc["registration"],"boundary":doc["boundary"],"noCompilerRerunByInspector":True})
groups={}
for name,predicate in [("declarations",lambda p:p.endswith((".d.ts",".d.mts",".d.cts"))),("examples",lambda p:p.startswith("examples/")),("public-docs",lambda p:p.startswith("docs/")),("original-compiler-entrypoints",lambda p:p in [m["engines"]["expo"]["typescriptPath"],m["engines"]["nativescript"]["typescriptPath"]])]:
 selected=[p for p in files if predicate(p)];groups[name]={"members":len(selected),"unchanged":sum(files[p]==of[p] for p in selected),"changed":[p for p in selected if files[p]!=of[p]]}
emit("sdk-reconciliation.json",{"source":BASE,"archiveSHA256":ziprow["sha256"],"archiveBytes":ziprow["bytes"],"manifestSHA256":sha(mb),"inputSHA256":m["inputSHA256"],"actualSDKMembersVerified":len(files),"actualSDKBytesVerified":sdkBytes,"changedInputs":changedInputs,"unchangedInputs":219,"changedMembers":changedFiles,"unchangedMembers":25658,"groupComparison":groups,"otherManifestMetadataDifferences":[],"boundary":"All actual SDK member hashes/sizes and exact path set verified in place, plus every outside-SDK Host member compared. No extraction/repack/product tool run."})
provenance=[]
for path,key in [("docs/miniapp-sdk/source-inventory.json","sources"),("docs/miniapp-sdk/extension-reachability.json","sdkSources")]:
 inv=json.loads(overlay[path]);prev=json.loads((P/"tracked-delta"/path).read_bytes())
 assert inv["sourceCommit"]==BASE
 for row in inv[key]:assert sha(current(row["path"]))==row["sha256"],row["path"]
 assert {k:v for k,v in inv.items() if k not in ["sourceCommit",key]}=={k:v for k,v in prev.items() if k not in ["sourceCommit",key]}
 a={x["path"]:x for x in prev[key]};b={x["path"]:x for x in inv[key]}
 assert a.keys()==b.keys()
 provenance.append({"path":path,"changedTopLevelKeys":["sourceCommit",key],"sourceRows":inv[key],"changedSourceRows":[{"path":p,"before":a[p],"after":b[p]} for p in sorted(a) if a[p]!=b[p]]})
inv=json.loads(overlay["docs/miniapp-sdk/source-inventory.json"]);reach=json.loads(overlay["docs/miniapp-sdk/extension-reachability.json"])
assert len(inv["sources"])==93 and inv["manifestCoverage"]["fieldCount"]==335 and len(reach["matrix"])==80
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
emit("shipped-provenance-binding.json",{"source":BASE,"inventorySources":93,"manifestFields":335,"reachabilityCells":80,"matrixAndNonProvenanceSemanticsUnchanged":True,"sourceGroups":provenance,"sourceReferences":refs,"boundary":"Source coverage and reachability are not application/physical acceptance."})
catBytes=(S/"files/build/app-split-evidence/prepared-native/native-artifacts.json").read_bytes();cat=json.loads(catBytes)
oldCat=json.loads((P/"files/build/app-split-evidence/prepared-native/native-artifacts.json").read_bytes())
assert cat["sourceCommit"]==BASE and cat["state"]=="prepared" and cat["missingTargets"]==[] and len(cat["requiredTargets"])==15
nativeInputs=[]
for p,h in cat["inputSHA256"].items():
 assert sha(current(p))==h,p
 nativeInputs.append({"path":p,"sha256":h,"unchangedFromSDK9":oldCat["inputSHA256"].get(p)==h})
nativeComparison={}
for key in ("artifacts","supportArtifacts"):
 a={x["target"]:x for x in oldCat[key]};b={x["target"]:x for x in cat[key]};assert a.keys()==b.keys()
 nativeComparison[key]=[]
 for target in sorted(a):
  al={x["identifier"]:x for x in a[target].get("libraries",[])};bl={x["identifier"]:x for x in b[target].get("libraries",[])}
  assert al==bl,target
  nativeComparison[key].append({"target":target,"libraryRecordsAndBinaryHashesUnchanged":True if bl else None,"libraryCount":len(bl),"libraryRecordScope":"Actual framework library records" if bl else "No library records in support archive; checksum changes are reported separately","metadataDifferences":difference({k:v for k,v in a[target].items() if k not in ["url","libraries"]},{k:v for k,v in b[target].items() if k not in ["url","libraries"]})})
assetBytes=(S/"expo-asset-produced-bindings.json").read_bytes();asset=json.loads(assetBytes)
srBytes=(S/"files/Packages/HanlinExpoRuntime/Artifacts/ExpoAsset.xcframework/.source-build-receipt.json").read_bytes();sr=json.loads(srBytes)
am=json.loads((S/"files/Packages/HanlinExpoRuntime/Artifacts/ExpoAsset.xcframework/.artifact-manifest.json").read_bytes())
assert sha(assetBytes)==r["expoAssetBindingsSHA256"] and asset["originalSourceReceipt"]==sr
assert len(asset["files"])==23 and all(x["sha256"]==x["preparedTargetSHA256"] for x in asset["files"])
assetCat=next(x for x in cat["artifacts"] if x["target"]=="ExpoAsset")
for lib in assetCat["libraries"]:assert next(x for x in asset["files"] if x["path"]==lib["binary"])["sha256"]==lib["binarySHA256"]
lock=json.loads(current("Scripts/Expo/package-lock.json"));assetLock=lock["packages"]["node_modules/expo-asset"]
assert sr["originalPackage"]["version"]==assetLock["version"]=="58.0.21" and sr["originalPackage"]["integrity"]==assetLock["integrity"]
assert sr["inputSHA256"]==am["sourceBuildInputSHA256"]=="a85fc86c413d87679e62878cc4b7b512e925c36806a9b383daf095dab9c55159"
assert sr["originalPackage"]["sha256"]==am["sha256"]=="2bfbb115da9111702530e5df550eac7e2a074aa12b6297fcc332744767623126"
assert sr["podLockSHA256"]==sha((S/"files/build/miniapp-upstreams/expo-native-source/ios/Podfile.lock").read_bytes())
assert plistlib.loads((S/"files/Packages/HanlinExpoRuntime/Artifacts/ExpoAsset.xcframework/Info.plist").read_bytes())["AvailableLibraries"]==sr["slices"]
emit("native-catalog-binding.json",{"catalogSHA256":sha(catBytes),"source":BASE,"contentSHA256":cat["contentSHA256"],"inputs":nativeInputs,"requiredTargets":cat["requiredTargets"],"missingTargets":[],"comparison":nativeComparison,"asset":{"sourceReceiptSHA256":sha(srBytes),"sourceBuildInputSHA256":sr["inputSHA256"],"originalNpmTarballSHA256":sr["originalPackage"]["sha256"],"ownerStageTargetBindingSHA256":sha(assetBytes),"members":23,"allStageTargetAndCatalogBinariesMatch":True,"slices":sr["slices"]},"acceptance":cat["acceptance"],"boundary":"Retained actual producer/exporter bindings; no new binary download or native execution by inspector. Framework library bytes are unchanged while wrapper/catalog input identity changes."})
stateBytes=(S/"controller-state-at-capture.json").read_bytes();state=json.loads(stateBytes)
assert state["source"]==BASE and state["attempt"]==10 and state["status"]=="PAUSED_AFTER_PHASE" and state["phase"]=="split-inputs"
for name,v in r["phaseReceipts"].items():assert v["status"]=="PASS" and v["exitCode"]==0 and state["phases"][name]==v
advanceBytes=(S/"files/build/primary-control/source-advance-fda6948c/receipt.json").read_bytes();advance=json.loads(advanceBytes)
assert advance["target"]==BASE and advance["targetTree"]==r["sourceTree"] and not advance["nativeStarted"]
for p,h in advance["sourceHashes"].items():assert sha(git(p))==h
assert len(advance["workingFiles"])==9 and all(x["preserved"] for x in advance["workingFiles"])
admission=json.loads((S/"files/build/primary-control/admission-attempt10.json").read_bytes())
assert admission["source"]==BASE and admission["status"]=="CONTROLLER_STARTED"
logBytes=(S/"files/build/primary-control/logs-attempt10/split-native-preparation.log").read_bytes();log=logBytes.decode()
assert sha(logBytes)==r["phaseReceipts"]["split-native-preparation"]["logSHA256"]
counts={k:int(re.search("ℹ "+k+r" (\d+)",log).group(1)) for k in ["tests","pass","fail","skipped"]}
assert counts=={"tests":170,"pass":169,"fail":0,"skipped":1}
skips=[l for l in log.splitlines() if "# SKIP" in l];assert len(skips)==1 and "actual Node job crosses 300 seconds" in skips[0]
assert "Exact original ExpoAsset source build reused: "+sr["inputSHA256"] in log
assert "PASS: SDK source inventory matches 93 sources and 176 local public exports." in log and "PASS: 80 unique source-backed reachability cells; no E2E pass inferred." in log
metadata=json.loads((S/"files/build/runtime-host/host-metadata.json").read_bytes())
assert metadata["archiveSha256"]==ziprow["sha256"] and metadata["tests"]==metadata["jitlessArchiveSmoke"]=="passed"
emit("execution-checkpoint.json",{"capturedAt":r["capturedAt"],"source":BASE,"tree":r["sourceTree"],"attempt":10,"sourceAdvanceAt":advance["utc"],"sourceAdvanceReceiptSHA256":sha(advanceBytes),"sourceHashes":advance["sourceHashes"],"inputClosureReason":advance["inputClosureReason"],"capacityAdmission":admission,"phaseReceipts":r["phaseReceipts"],"controllerStateSHA256":sha(stateBytes),"controllerStatus":"PAUSED_AFTER_PHASE","controllerPhase":"split-inputs","lifecycle":"REUSED_RECORDED_PASS_FROM_ATTEMPT8; original timestamp and receipt preserved","nativePreparation":"EXECUTED_PASS","nativeArtifactExport":"EXECUTED_PASS","hostMetadata":metadata,"actualHostTests":counts,"existingOptInSkippedTest":skips[0],"consumerBuildsAtCapture":"NOT_RUN_ON_SDK10","original52":"NOT_RUN","applicationAcceptance":"NOT_ESTABLISHED","boundary":"Dated producer checkpoint only. Later actual consumer bindings/runtime results remain separate."})
prepared=json.loads((O/"prepared-source-delta.json").read_bytes())
priorDelta=json.loads((P/"tracked-delta.json").read_bytes());priorByPath={x["path"]:x for x in priorDelta}
classification=[]
for row in prepared["rows"]:
 p=row["path"];same=priorByPath[p]["sha256"]==row["afterSHA256"]
 classification.append({"path":p,"beforeSHA256":row["beforeSHA256"],"afterSHA256":row["afterSHA256"],"bytes":row["bytes"],"contentFrom":row["contentFrom"],"beforeMode":row["beforeMode"],"afterMode":row["afterMode"],"samePreparedBytesAsSDK9":same,"reason":"Previously verified prepared output preserved byte-for-byte." if same else "Current source provenance only; exact updated source hashes and commit bound by shipped-provenance-binding.json."})
assert sum(x["samePreparedBytesAsSDK9"] for x in classification)==6
emit("prepared-materialization-plan.json",{"source":BASE,"snapshotRoot":str(S),"snapshotReceiptSHA256":sha(rb),"trackedLedgerSHA256":r["trackedDeltaSHA256"],"canonicalBinding":prepared["canonicalBinding"],"paths":9,"payloadBytes":prepared["payloadBytes"],"modeChanges":0,"materialized":False,"rows":classification,"instructions":"Apply only after verifying each exact before hash and Git mode against the chosen integration base. Read contentFrom within this immutable snapshot; preserve 100644. This lane has not applied production files."})
summary={"status":"PASS","observedAt":datetime.now(timezone.utc).isoformat(),"inspectionStartedAt":started,"elapsedSeconds":time.monotonic()-clock,"source":BASE,"archiveSHA256":ziprow["sha256"],"archiveBytes":ziprow["bytes"],"manifestSHA256":sha(mb),"manifestBytes":len(mb),"inputSHA256":m["inputSHA256"],"actualSDKMembersVerified":len(files),"actualSDKBytesVerified":sdkBytes,"changedInputs":3,"unchangedInputs":219,"changedSDKMembers":3,"unchangedSDKMembers":25658,"unchangedOutsideSDKHostMembers":3102,"changedOutsideSDKHostMembers":0,"groups":groups,"originalDeclarationCompatibilityFiles":5,"originalDeclarationSubstitutions":7,"documentationProjects":4,"documentationDiagnostics":0,"nativeRequiredTargets":15,"missingNativeTargets":0,"hostTests":counts,"preparedSourceRows":9,"preparedSourceBytes":prepared["payloadBytes"],"preparedCanonicalBinding":prepared["canonicalBinding"],"consumerAndAcceptance":"PENDING_SEPARATE_ACTUAL_OBSERVATION"}
emit("inspection-summary.json",summary);print(json.dumps(summary))
