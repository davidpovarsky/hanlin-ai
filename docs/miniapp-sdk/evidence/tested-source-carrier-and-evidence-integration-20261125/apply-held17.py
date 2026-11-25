from pathlib import Path
import os,json,hashlib,subprocess,datetime
R=Path("/mnt/development/projects/worktrees/hanlin-miniapps-sdk-completion-20261123")
B=Path("/mnt/development/projects/transfers/hanlin-primary-ce49-20261124")
EXPECTED={" M AGENTS.md","?? Scripts/Expo/node_modules","?? Scripts/NativeScript/node_modules"}
out=B/"sdk19-reconciliation/root-held17-integration-receipt.json"
journal=B/"sdk19-reconciliation/root-held17-integration-journal.json"
assert not out.exists()and not journal.exists(),"Inspect actual HEAD and durable progress before retry"
def sha(raw):return hashlib.sha256(raw).hexdigest()
def git(*args):return subprocess.check_output(["git","-c","gc.auto=0",*args],cwd=R,text=True,timeout=60)
def utc():return datetime.datetime.now(datetime.timezone.utc).isoformat()
def save(path,value):
 tmp=path.with_name(path.name+".tmp")
 with tmp.open("x")as f:json.dump(value,f,indent=2);f.write("\n");f.flush();os.fsync(f.fileno())
 tmp.replace(path)
def snapshot_protected():
 result={}
 for name in ["AGENTS.md","Scripts/Expo/node_modules","Scripts/NativeScript/node_modules"]:
  p=R/name;s=p.lstat()
  result[name]={"mode":s.st_mode,"inode":s.st_ino,"bytes":s.st_size,"link":os.readlink(p)if p.is_symlink()else None}
  if p.is_file()and not p.is_symlink():result[name]["sha256"]=sha(p.read_bytes())
 return result
carrier_path=B/"sdk19-reconciliation/root-prepared25-materialization-receipt.json"
carrier=json.loads(carrier_path.read_text());assert carrier["phase"]=="COMMITTED_AND_VERIFIED"
protected=snapshot_protected();assert protected==carrier["protectedAfter"]
head=git("rev-parse","HEAD").strip();assert head==carrier["carrierCommit"]
assert set(git("status","--porcelain=v1","--untracked-files=normal").splitlines())==EXPECTED
assert not git("diff","--cached","--name-only").strip()
assert sha((R/"AGENTS.md").read_bytes())=="f27d4554d8dda88996d1511b361e8b8e5520cb08e8198c5fbc7816b1fbc9aa9f"
plan_path=B/"sdk19-reconciliation/held-evidence-integration-plan-d4a0b115-v4.json"
raw=plan_path.read_bytes();assert sha(raw)=="0007222d7ca90bb05be917f90a6d73d36a318ae2d74e0e561a3e4bb1c958b576"
plan=json.loads(raw);commits=plan["orderedCommits"];assert len(commits)==17
union=set();patches=[]
tracked=set(git("ls-tree","-r","--name-only","HEAD").splitlines())
for row in commits:
 original=row["commit"]
 entries=git("diff-tree","--no-commit-id","--raw","--no-renames","-r",original).splitlines()
 assert len(entries)==row["expectedPaths"]
 paths=[]
 for entry in entries:
  meta,name=entry.split("\t")
  fields=meta.split()
  assert fields[0]==":000000"and fields[1]=="100644"and fields[-1]=="A"
  assert name.startswith("docs/miniapp-sdk/evidence/")and name not in union
  assert not(R/name).exists()and not(R/name).is_symlink()
  assert name not in tracked
  paths.append(name);union.add(name)
 patches.append((row,paths))
assert len(union)==1587 and plan["expectedTotalPaths"]==1587
assert sha(("\n".join(sorted(union))+"\n").encode())==plan["unionPathSetSHA256"]
state={"schema":1,"phase":"EXACT17_DISJOINT_PATCHES_VERIFIED","startedAt":utc(),"carrierCommit":head,"planSHA256":sha(raw),"expectedPaths":1587,"applied":[]}
save(journal,state)
for row,paths in patches:
 before=git("rev-parse","HEAD").strip()
 result=git("-c","user.name=ChatGPT","-c","user.email=chatgpt@users.noreply.github.com","cherry-pick",row["commit"])
 after=git("rev-parse","HEAD").strip()
 assert git("rev-parse","HEAD^").strip()==before
 assert set(git("diff-tree","--no-commit-id","--name-status","-r","HEAD").splitlines())=={"A\t"+n for n in paths}
 # Equal trees at each owned leaf establish exact original evidence blobs and modes.
 assert git("ls-tree","-r","HEAD","--",*paths)==git("ls-tree","-r",row["commit"],"--",*paths)
 state["applied"].append({"heldCommit":row["commit"],"appliedCommit":after,"parent":before,"pathCount":len(paths)})
 state.update(phase="APPLYING_EXACT_HELD_EVIDENCE",lastCommitAt=utc())
 save(journal,state)
assert set(git("diff","--name-status",head,"HEAD").splitlines())=={"A\t"+n for n in union}
sdk_path=B/"standalone-sdk08-kit-only/kit/MiniAppSDK/miniapp-sdk.json"
sdk_raw=sdk_path.read_bytes();assert sha(sdk_raw)=="4505c28495d8b6ecd1073254e0e395adcc898cc02dd1d40699591f51db4dee92"
inputs=json.loads(sdk_raw)["sourceInputs"];assert len(inputs)==235
for row in inputs:assert sha((R/row["path"]).read_bytes())==row["sha256"],row["path"]
consumer_path=B/"focused19-v11-recovery-inputs.json";consumer_raw=consumer_path.read_bytes()
assert sha(consumer_raw)=="eaccf3795eb755f1bfad0a89794a7ee59dbb4d8b0673d69e690b4bf5fbfa2524"
consumer=json.loads(consumer_raw)["sourceHashes"];assert len(consumer)==15
for name,h in consumer.items():assert sha((R/name).read_bytes())==h,name
assert set(git("status","--porcelain=v1","--untracked-files=normal").splitlines())==EXPECTED
assert not git("diff","--cached","--name-only").strip()
assert sha((R/"AGENTS.md").read_bytes())=="f27d4554d8dda88996d1511b361e8b8e5520cb08e8198c5fbc7816b1fbc9aa9f"
assert snapshot_protected()==protected
state.update(phase="INTEGRATED_AND_VERIFIED",finishedAt=utc(),head=git("rev-parse","HEAD").strip(),SDKSourceInputsVerified=235,consumerSourceInputsVerified=15,totalAddedPaths=len(union),protectedStateUnchanged=True,boundary="Evidence-only additions after exact prepared-source carrier; no source, generated SDK, original products or native tests changed.")
save(out,state);save(journal,state)
print(json.dumps({"status":state["phase"],"head":state["head"],"carrierCommit":head,"appliedCommits":len(state["applied"]),"addedPaths":1587,"receipt":str(out),"receiptBytes":out.stat().st_size,"receiptSHA256":sha(out.read_bytes()),"sourceBindingsPreserved":True}))
