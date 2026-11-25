#!/usr/bin/env python3
"""Classify already-verified current prepared outputs without running their generators."""
from pathlib import Path
import subprocess,json,hashlib
W=Path("/mnt/development/projects/worktrees/hanlin-primary-sdk-preparation-20261124")
S=Path("/mnt/development/projects/transfers/hanlin-primary-ce49-20261124/prepared-snapshot-attempt9")
O=W/"docs/miniapp-sdk/evidence/primary-sdk-attempt9-20261125"
BASE="1812bff50571c9907d15cd8b4bfbe4874be24756"
def git(p):return subprocess.check_output(["git","-C",str(W),"show",BASE+":"+p])
d=json.loads((O/"prepared-source-delta.json").read_bytes())
delta={x["path"]:(S/x["contentFrom"]).read_bytes() for x in d["rows"]}
def before(p):return json.loads(git(p))
def after(p):return json.loads(delta[p])
u="Scripts/MiniApps/upstream-resolution.json";a=before(u);b=after(u)
ap={x["name"]:x for x in a["nativeArtifacts"]};bp={x["name"]:x for x in b["nativeArtifacts"]}
assert set(bp)-set(ap)=={"ExpoAsset"} and not set(ap)-set(bp)
assert all(ap[k]==bp[k] for k in ap)
inventory="docs/miniapp-sdk/source-inventory.json";i=before(inventory);j=after(inventory)
af={x["family"]:x for x in i["manifests"]};bf={x["family"]:x for x in j["manifests"]}
added=[];removed=[];semantic=[]
for family in af:
 x={v["field"]:v for v in af[family]["fields"]};y={v["field"]:v for v in bf[family]["fields"]}
 added.extend({"family":family,"field":k,"after":y[k]} for k in sorted(y.keys()-x.keys()))
 removed.extend({"family":family,"field":k} for k in sorted(x.keys()-y.keys()))
 for k in sorted(x.keys()&y.keys()):
  old={q:v for q,v in x[k].items() if q!="sources"};new={q:v for q,v in y[k].items() if q!="sources"}
  if old!=new:semantic.append({"family":family,"field":k,"before":old,"after":new})
assert len(added)==1 and added[0]["field"]=="hanlinExpo.plugins.expo-asset" and not removed
assert len(semantic)==1 and semantic[0]["field"]=="#/$defs/action/properties/id"
reach="docs/miniapp-sdk/extension-reachability.json";ra=before(reach);rb=after(reach)
assert {k:v for k,v in ra.items() if k not in ["sourceCommit","sdkSources"]}=={k:v for k,v in rb.items() if k not in ["sourceCommit","sdkSources"]}
aSources={x["path"]:x["sha256"] for x in i["sources"]};bSources={x["path"]:x["sha256"] for x in j["sources"]}
assert aSources.keys()==bSources.keys()
changedSources=[{"path":p,"beforeSHA256":aSources[p],"afterSHA256":bSources[p]} for p in sorted(aSources) if aSources[p]!=bSources[p]]
assert len(changedSources)==13
cat=json.loads((S/"files/build/app-split-evidence/prepared-native/native-artifacts.json").read_bytes())
oldcat=json.loads((S.parent/"prepared-snapshot-attempt7/files/build/app-split-evidence/prepared-native/native-artifacts.json").read_bytes())
newA={x["target"]:x for x in cat["artifacts"]};oldA={x["target"]:x for x in oldcat["artifacts"]}
binaries=[]
for target,old in oldA.items():
 new=newA[target]
 x={v["identifier"]:v for v in old.get("libraries",[])};y={v["identifier"]:v for v in new.get("libraries",[])}
 assert x==y,target
 binaries.append({"target":target,"librariesByIdentifierUnchanged":True,"libraryCount":len(x),"archiveChecksumUnchanged":old["checksum"]==new["checksum"]})
record={
"executionSource":BASE,"preparedDeltaBinding":d["canonicalBinding"],"paths":9,"payloadBytes":1150910,"modeChanges":0,
"classifications":[
{"path":"AI_HLY.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved","classification":"Serialization-only: exact parsed JSON equal; all39pin records/revisions and originHash unchanged."},
{"path":"Packages/HanlinExpoRuntime/Sources/ExpoWidgets/Resources/ExpoWidgets.bundle/original-runtime-receipt.json","classification":"Only inputSHA256 and packageLockSHA256 updated; all other original runtime receipt values unchanged."},
{"path":"Scripts/Expo/package.json","classification":"Only original @types/react devDependency19.3.0→19.3.1."},
{"path":"Scripts/Expo/package-lock.json","classification":"Exactly4JSON value changes: root @types/react pin, that package version, original tarball URL and SRI."},
{"path":u,"classification":"Existing original resolver now records ExpoAsset58.0.21 original publication/artifact and React types19.3.1; all9prior nativeArtifact records equal."},
{"path":"docs/miniapp-sdk/MANIFEST_REFERENCE.md","classification":"Original generated field reference: added ExpoAsset plugin row, published actionIdentifier schema reference, current source line anchors."},
{"path":inventory,"classification":"13actual source hashes updated,335fields vs334; one Asset field added, one published action ID schema reference updated, source anchors and2actual uncommitted package inputs recorded."},
{"path":reach,"classification":"Only sourceCommit and13sdkSources hashes changed; complete80cell matrix and other source/acceptance data equal."},
{"path":"docs/miniapp-sdk/extension-reachability.md","classification":"Generated sourceCommit provenance; reachability descriptions and80cell matrix unchanged."}],
"upstreamNativeArtifacts":{"priorCount":9,"currentCount":10,"added":bp["ExpoAsset"],"allNinePriorRowsUnchanged":True},
"manifestFieldComparison":{"added":added,"removed":removed,"changedSemanticFields":semantic,"changedSourceHashRows":changedSources,"uncommittedSourcePaths":j["uncommittedSourcePaths"]},
"nativeCatalogBinaryComparison":{"method":"Compare library dictionaries keyed by actual XCFramework slice identifier; preserve raw array order/checksum differences separately.","existingTargets":binaries,"allExistingLibraryRecordsAndBinaryHashesUnchanged":True,"addedTarget":"ExpoAsset","changedExistingArchiveChecksums":[x["target"] for x in binaries if not x["archiveChecksumUnchanged"]],"boundary":"Original catalog binary identities are equal for existing targets; source-built archive checksums differ for ExpoUI/ExpoModulesJSI. No assertion of full archive-byte equality or fresh binary reexecution."},
"productionMaterialized":False}
(O/"prepared-change-classification.json").write_text(json.dumps(record,ensure_ascii=False,indent=2)+"\n")
print(json.dumps({"status":"PASS","addedFields":len(added),"changedSemanticFields":len(semantic),"changedSourceHashes":len(changedSources),"existingNativeTargetsWithSameBinaryRecords":len(binaries),"changedExistingArchiveChecksums":record["nativeCatalogBinaryComparison"]["changedExistingArchiveChecksums"]}))
