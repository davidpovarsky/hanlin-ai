#!/usr/bin/env python3
"""Read retained actual preparation output; no product tool, test or native query."""
from pathlib import Path
from datetime import datetime, timezone
import subprocess,json,hashlib,gzip,difflib,time
W=Path("/mnt/development/projects/worktrees/hanlin-primary-sdk-preparation-20261124")
S=Path("/mnt/development/projects/transfers/hanlin-primary-ce49-20261124/prepared-snapshot-attempt9")
OUT=W/"docs/miniapp-sdk/evidence/primary-sdk-attempt9-20261125"
BASE="1812bff50571c9907d15cd8b4bfbe4874be24756"
EXPECTED_RECEIPT="74663345cae2bb65b7de8b1eb6981bfeeb3319288de6b89a7f15bf8aa7ffb608"
def sha(b): return hashlib.sha256(b).hexdigest()
def canonical(v): return json.dumps(v,ensure_ascii=False,separators=(",",":")).encode()
def emit(name,v):
 p=OUT/name;p.parent.mkdir(parents=True,exist_ok=True);p.write_text(json.dumps(v,ensure_ascii=False,indent=2)+"\n")
def git(p): return subprocess.check_output(["git","-C",str(W),"show",BASE+":"+p])
def diff(a,b,p=""):
 if type(a)!=type(b):return [{"pointer":p,"before":a,"after":b}]
 if isinstance(a,dict):
  rows=[]
  for k in sorted(a.keys()|b.keys()):
   if k not in a or k not in b:rows.append({"pointer":p+"/"+k,"before":a.get(k),"after":b.get(k)})
   else:rows+=diff(a[k],b[k],p+"/"+k)
  return rows
 if isinstance(a,list):
  if len(a)!=len(b):return [{"pointer":p,"beforeLength":len(a),"afterLength":len(b)}]
  rows=[]
  for i,(x,y) in enumerate(zip(a,b)):rows+=diff(x,y,p+"/"+str(i))
  return rows
 return [] if a==b else [{"pointer":p,"before":a,"after":b}]
started=datetime.now(timezone.utc).isoformat();clock=time.monotonic()
rb=(S/"receipt.json").read_bytes();assert sha(rb)==EXPECTED_RECEIPT
r=json.loads(rb);assert r["sourceHEAD"]==BASE
assert r["sourceTree"]==subprocess.check_output(["git","-C",str(W),"rev-parse",BASE+"^{tree}"],text=True).strip()
verified=[]
for row in r["files"]:
 p=S/row["snapshotPath"];h=hashlib.sha256()
 with p.open("rb") as f:
  for block in iter(lambda:f.read(1024*1024),b""):h.update(block)
 assert p.stat().st_size==row["bytes"] and h.hexdigest()==row["sha256"],row["path"]
 verified.append({**row,"actualSHA256":h.hexdigest(),"verified":True})
assert len(verified)==23
db=(S/r["trackedDeltaPath"]).read_bytes();assert sha(db)==r["trackedDeltaSHA256"]
delta=json.loads(db);assert len(delta)==r["trackedDeltaCount"]==9
rows=[];diffs=[]
for row in delta:
 p=row["path"];before=git(p);after=(S/row["contentFrom"]).read_bytes()
 assert sha(before)==row["headSHA256"] and sha(after)==row["sha256"] and len(after)==row["bytes"],p
 mode=subprocess.check_output(["git","-C",str(W),"ls-tree",BASE,"--",p],text=True).split()[0]
 assert mode==row["headMode"]=="100644" and row["mode"]=="0o644"
 record={"path":p,"beforeSHA256":sha(before),"afterSHA256":sha(after),"bytes":len(after),"contentFrom":row["contentFrom"],"beforeMode":mode,"afterMode":"100644","contentChanged":before!=after,"modeChanged":False}
 if p.endswith(".json") or p.endswith("Package.resolved"):
  a=json.loads(before);b=json.loads(after);record["semanticDifferences"]=diff(a,b)
  if p.endswith("Package.resolved"):
   ap={x["identity"]:x for x in a["pins"]};bp={x["identity"]:x for x in b["pins"]}
   record["pinComparison"]={"beforeCount":len(ap),"afterCount":len(bp),"added":sorted(bp.keys()-ap.keys()),"removed":sorted(ap.keys()-bp.keys()),"changes":[{"identity":k,"before":ap[k],"after":bp[k],"revisionUnchanged":ap[k]["state"].get("revision")==bp[k]["state"].get("revision")} for k in sorted(ap.keys()&bp.keys()) if ap[k]!=bp[k]],"allExistingRevisionsUnchanged":all(ap[k]["state"].get("revision")==bp[k]["state"].get("revision") for k in ap.keys()&bp.keys()),"originHashBefore":a.get("originHash"),"originHashAfter":b.get("originHash")}
 if p.endswith(".md"):
  diffs.extend(difflib.unified_diff(before.decode().splitlines(True),after.decode().splitlines(True),fromfile="published/"+p,tofile="prepared/"+p))
 rows.append(record)
bindingRows=[{k:row[k] for k in ["path","beforeSHA256","afterSHA256","bytes","contentFrom"]} for row in sorted(rows,key=lambda x:x["path"])]
binding={"algorithm":"SHA256 of compact UTF-8 JSON rows sorted by path; keys path,beforeSHA256,afterSHA256,bytes,contentFrom","sha256":sha(canonical(bindingRows))}
asset=(S/r["expoAssetBindingsPath"]).read_bytes();assert sha(asset)==r["expoAssetBindingsSHA256"]
manifest=(S/r["sdkManifest"]["snapshotPath"]).read_bytes();assert len(manifest)==r["sdkManifest"]["bytes"] and sha(manifest)==r["sdkManifest"]["sha256"]
emit("transfer-verification.json",{"recordedAtUTC":started,"source":BASE,"sourceTree":r["sourceTree"],"snapshotReceiptSHA256":EXPECTED_RECEIPT,"files":verified,"additionalBoundMembers":[{"path":r["trackedDeltaPath"],"sha256":sha(db)},{"path":r["sdkManifest"]["snapshotPath"],"sha256":sha(manifest),"bytes":len(manifest)},{"path":r["expoAssetBindingsPath"],"sha256":sha(asset),"bytes":len(asset)}]})
emit("prepared-source-delta.json",{"executionSource":BASE,"ledgerSHA256":sha(db),"canonicalBinding":binding,"paths":len(rows),"payloadBytes":sum(x["bytes"] for x in rows),"contentChanges":sum(x["contentChanged"] for x in rows),"modeChanges":0,"materializedByThisLane":False,"rows":rows})
(OUT/"prepared-provenance.diff").write_text("".join(diffs))
retained=[]
def retain(path,b,compress=False):
 target="raw/"+path+(".gz" if compress else "");dest=OUT/target;dest.parent.mkdir(parents=True,exist_ok=True)
 body=gzip.compress(b,mtime=0) if compress else b;dest.write_bytes(body)
 retained.append({"path":target,"bytes":len(body),"sha256":sha(body),"originalBytes":len(b),"originalSHA256":sha(b),"compression":"gzip" if compress else None})
retain("snapshot-receipt.json",rb);retain("tracked-delta.json",db);retain("miniapp-sdk.json",manifest,True);retain("expo-asset-produced-bindings.json",asset)
seen=set()
for row in verified:
 if row["path"]=="build/runtime-host/RuntimeHostResources.zip":continue
 retain(row["path"],(S/row["snapshotPath"]).read_bytes(),row["path"].endswith("logs-attempt8/split-native-preparation.log"));seen.add(row["path"])
for row in delta:
 if row["path"] not in seen:retain(row["path"],(S/row["contentFrom"]).read_bytes());seen.add(row["path"])
state=S/"controller-state-at-capture.json"
if state.exists():retain("controller-state-at-capture.json",state.read_bytes())
emit("retained-raw-files.json",retained)
summary={"status":"VERIFIED","recordedAtUTC":datetime.now(timezone.utc).isoformat(),"elapsedSeconds":time.monotonic()-clock,"source":BASE,"sourceTree":r["sourceTree"],"verifiedTransferMembers":len(verified),"archive":next(x for x in verified if x["path"].endswith("RuntimeHostResources.zip")),"preparedPaths":len(rows),"preparedBytes":sum(x["bytes"] for x in rows),"canonicalBinding":binding,"preparedRows":[{k:v for k,v in x.items() if k not in ["semanticDifferences"]} for x in rows],"semanticDifferenceCounts":{x["path"]:len(x.get("semanticDifferences",[])) for x in rows},"nativeStatusAtCapture":r["controllerStatusAtCapture"],"rawMembersRetained":len(retained)}
emit("transfer-inspection-summary.json",summary)
print(json.dumps(summary,ensure_ascii=False))
