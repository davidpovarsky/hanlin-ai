from pathlib import Path
import os,json,hashlib,subprocess,datetime
R=Path("/mnt/development/projects/worktrees/hanlin-miniapps-sdk-completion-20261123")
B=Path("/mnt/development/projects/transfers/hanlin-primary-ce49-20261124")
SOURCE="d4a0b115b106d4250ea40ad66153d5156847a07c"
TREE="f7a6596a1ef53d8d962ceb9f619460ffa19ee91e"
EXPECTED={" M AGENTS.md","?? Scripts/Expo/node_modules","?? Scripts/NativeScript/node_modules"}
out=B/"sdk19-reconciliation/root-prepared25-materialization-receipt.json"
journal=B/"sdk19-reconciliation/root-prepared25-materialization-journal.json"
assert not out.exists() and not journal.exists(),"Read prior receipt/journal before any retry"
def sha(raw):return hashlib.sha256(raw).hexdigest()
def git(*args):return subprocess.check_output(["git","-c","gc.auto=0",*args],cwd=R,text=True,timeout=60)
def utc():return datetime.datetime.now(datetime.timezone.utc).isoformat()
def snapshot_protected():
 result={}
 for name in ["AGENTS.md","Scripts/Expo/node_modules","Scripts/NativeScript/node_modules"]:
  p=R/name;s=p.lstat()
  result[name]={"mode":s.st_mode,"inode":s.st_ino,"bytes":s.st_size,"link":os.readlink(p)if p.is_symlink()else None}
  if p.is_file()and not p.is_symlink():result[name]["sha256"]=sha(p.read_bytes())
 return result
def save(path,value):
 tmp=path.with_name(path.name+".tmp")
 with tmp.open("x")as f:json.dump(value,f,indent=2);f.write("\n");f.flush();os.fsync(f.fileno())
 tmp.replace(path)
assert git("rev-parse","HEAD").strip()==SOURCE and git("rev-parse","HEAD^{tree}").strip()==TREE
assert not git("diff","--cached","--name-only").strip()
assert set(git("status","--porcelain=v1","--untracked-files=normal").splitlines())==EXPECTED
assert sha((R/"AGENTS.md").read_bytes())=="f27d4554d8dda88996d1511b361e8b8e5520cb08e8198c5fbc7816b1fbc9aa9f"
protected=snapshot_protected()
plan_path=B/"sdk19-reconciliation/prepared-source-materialization-d4a0b115.json"
raw=plan_path.read_bytes();assert sha(raw)=="eae3a25e5f0b2ad56e461ccebbaeb03e8a61f9e50d9de4e5b1f415174024effd"
plan=json.loads(raw);rows=plan["rows"];assert len(rows)==25
payload={}
for row in rows:
 name=row["path"];p=R/name;source=Path(row["payload"])
 assert p.resolve().is_relative_to(R.resolve())and not p.is_symlink()
 assert row["beforeGitMode"]==row["afterGitMode"]=="100644"
 assert git("ls-files","-s","--",name).split()[0]=="100644"
 current=p.read_bytes();before=subprocess.check_output(["git","show",SOURCE+":"+name],cwd=R,timeout=30)
 assert sha(current)==sha(before)==row["beforeSHA256"],name
 data=source.read_bytes();assert len(data)==row["afterBytes"]and sha(data)==row["afterSHA256"],name
 assert row["contentChanged"] is True and name not in payload
 payload[name]=data
sdk_path=B/"standalone-sdk08-kit-only/kit/MiniAppSDK/miniapp-sdk.json"
sdk_raw=sdk_path.read_bytes();assert sha(sdk_raw)=="4505c28495d8b6ecd1073254e0e395adcc898cc02dd1d40699591f51db4dee92"
sdk=json.loads(sdk_raw);inputs=sdk["sourceInputs"];assert len(inputs)==235
consumer_path=B/"focused19-v11-recovery-inputs.json"
consumer_raw=consumer_path.read_bytes();assert sha(consumer_raw)=="eaccf3795eb755f1bfad0a89794a7ee59dbb4d8b0673d69e690b4bf5fbfa2524"
consumer=json.loads(consumer_raw)["sourceHashes"];assert len(consumer)==15
for row in inputs:
 name=row["path"];assert sha(payload[name]if name in payload else(R/name).read_bytes())==row["sha256"],name
for name,h in consumer.items():assert sha(payload[name]if name in payload else(R/name).read_bytes())==h,name
def verify_git_payload(treeish):
 if treeish==":":
  listing=git("ls-files","-s","--",*sorted(payload)).splitlines()
  modes={}
  for entry in listing:
   meta,name=entry.split("\t");fields=meta.split()
   assert fields[2]=="0"
   modes[name]=fields[0]
 else:
  listing=git("ls-tree","-r",treeish,"--",*sorted(payload)).splitlines()
  modes={entry.split("\t")[1]:entry.split("\t")[0].split()[0]for entry in listing}
 assert set(modes)==set(payload)
 for row in rows:
  name=row["path"];assert modes[name]=="100644"
  spec=":"+name if treeish==":" else treeish+":"+name
  blob=subprocess.check_output(["git","show",spec],cwd=R,timeout=30)
  assert len(blob)==row["afterBytes"]and sha(blob)==row["afterSHA256"],name
state={"schema":1,"phase":"PREIMAGES_AND_PROSPECTIVE_CLOSURE_VERIFIED","startedAt":utc(),"sourceBefore":SOURCE,"sourceTreeBefore":TREE,"planSHA256":sha(raw),"pathCount":25,"sdkProducer":"a2c8a1b1be746461272ba77254603304567c309d","nativeConsumerSource":SOURCE,"SDKManifestSHA256":sha(sdk_raw),"protectedBefore":protected}
save(journal,state)
for name,data in payload.items():
 p=R/name
 with p.open("wb")as f:f.write(data);f.flush();os.fsync(f.fileno())
 p.chmod(0o644)
assert set(git("diff","--name-only","HEAD").splitlines())==set(payload)|{"AGENTS.md"}
for row in inputs:assert sha((R/row["path"]).read_bytes())==row["sha256"],row["path"]
for name,h in consumer.items():assert sha((R/name).read_bytes())==h,name
assert snapshot_protected()==protected
state.update(phase="EXACT25_MATERIALIZED_AND_CLOSURE_VERIFIED");save(journal,state)
git("add","--sparse","-f","--",*sorted(payload))
assert set(git("diff","--cached","--name-status").splitlines())=={"M\t"+n for n in payload}
verify_git_payload(":")
state.update(phase="EXACT25_STAGED");save(journal,state)
result=git("-c","user.name=ChatGPT","-c","user.email=chatgpt@users.noreply.github.com","commit","-m","build(miniapps): retain exact tested upstream SDK and probe artifacts")
head=git("rev-parse","HEAD").strip()
verify_git_payload("HEAD")
assert git("rev-parse","HEAD^").strip()==SOURCE
assert set(git("diff-tree","--no-commit-id","--name-status","-r","HEAD").splitlines())=={"M\t"+n for n in payload}
assert set(git("status","--porcelain=v1","--untracked-files=normal").splitlines())==EXPECTED
assert not git("diff","--cached","--name-only").strip()and snapshot_protected()==protected
for row in inputs:assert sha((R/row["path"]).read_bytes())==row["sha256"],row["path"]
for name,h in consumer.items():assert sha((R/name).read_bytes())==h,name
state.update(phase="COMMITTED_AND_VERIFIED",finishedAt=utc(),carrierCommit=head,carrierTree=git("rev-parse","HEAD^{tree}").strip(),SDKSourceInputsVerified=235,consumerSourceInputsVerified=15,paths=rows,protectedAfter=snapshot_protected(),commitOutput=result,boundary="Exact already-tested native d4a source plus 25 prepared payloads recorded in Git. No new compilation or native execution; existing products retain actual d4a consumer and a2 SDK producer identities.")
save(out,state);save(journal,state)
print(json.dumps({"status":state["phase"],"carrierCommit":head,"carrierTree":state["carrierTree"],"receipt":str(out),"receiptBytes":out.stat().st_size,"receiptSHA256":sha(out.read_bytes()),"pathCount":25,"SDKSourceInputsVerified":235,"consumerSourceInputsVerified":15,"protectedStateUnchanged":True}))
