from pathlib import Path
import subprocess,os,json,hashlib,time,datetime,traceback,shutil
BASE=Path("/Users/m1/builds/hanlin-motion-dacb4ca5-20261126")
SOURCE=BASE/"source";PROOF=BASE/"proof";OLD=BASE/"proof-efb33bf0-original"
STAGE=BASE/"revisions/95367b8c"
SHA="95367b8c06b166873dfab2143a8323a869085af2"
PARENT="efb33bf0093981abdf882031ffe56c3044902968"
BUNDLE=BASE/"motion-95367b8c.bundle"
PY="/opt/homebrew/bin/python3.12"
ENV=dict(os.environ);ENV["PATH"]="/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin"
state={"schemaVersion":1,"sourceSHA":SHA,"parentSHA":PARENT,"status":"PREPARING","startedUTC":datetime.datetime.now(datetime.timezone.utc).isoformat(),"steps":[],"pid":os.getpid()}
def save(): (STAGE/"preparation-status.json").write_text(json.dumps(state,indent=2)+"\n")
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def read(args):return subprocess.check_output(args,text=True,env=ENV,timeout=20).strip()
def run(name,args,cwd=SOURCE,timeout=180):
 begin=time.monotonic()
 with (STAGE/(name+".log")).open("w") as f:
  p=subprocess.run([str(a) for a in args],cwd=cwd,stdout=f,stderr=subprocess.STDOUT,env=ENV,timeout=timeout)
 state["steps"].append({"name":name,"command":[str(a) for a in args],"exitCode":p.returncode,"seconds":time.monotonic()-begin});save()
 assert p.returncode==0,name
try:
 v=os.statvfs(BASE);free=v.f_bavail*v.f_frsize;state["freeAtStart"]=free
 assert free>250000000+1000000000+1073741824,"BLOCKED_DISK_PREPARATION"
 assert read(["git","-C",str(SOURCE),"rev-parse","HEAD"])==PARENT
 assert not read(["git","-C",str(SOURCE),"status","--porcelain"])
 assert json.loads((BASE/"revisions/efb33bf0/retry1/status.json").read_text())["status"]=="FAILED"
 assert {p.name for p in (PROOF/"UITests").iterdir()}=={"MotionUITests.swift"}
 assert sha(PROOF/"UITests/MotionUITests.swift")=="5f714f6ad4fc5db3abec22abc5e520f4bba94d5f66740f69673ed3d401665874"
 assert sha(BUNDLE)=="4969c0aa9ab2d82a457693c55389acd71378f329e4ddb7c3b707fee79622b132"
 assert not OLD.exists()
 previous=json.loads((PROOF/"proof-inputs.json").read_text())
 assert previous["sourceRevision"]==PARENT
 lock_relative=Path("ChatMotionProof.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved")
 lock=(PROOF/lock_relative).read_bytes()
 assert len(json.loads(lock)["pins"])==8
 run("verify-bundle",["git","-C",SOURCE,"bundle","verify",BUNDLE])
 run("fetch-bundle",["git","-C",SOURCE,"fetch",BUNDLE,"refs/heads/codex/hanlin-wave1-motion-acceptance-20261126"])
 run("checkout",["git","-C",SOURCE,"checkout","--detach",SHA])
 assert not read(["git","-C",str(SOURCE),"status","--porcelain"])
 PROOF.rename(OLD)
 run("canonical-preparation",[PY,SOURCE/"docs/chat-motion/prepare_motion_ui.py","--output",PROOF])
 run("xcodegen",["/opt/homebrew/bin/xcodegen","generate","--spec","project.json"],cwd=PROOF)
 (PROOF/lock_relative).parent.mkdir(parents=True,exist_ok=True);(PROOF/lock_relative).write_bytes(lock)
 current=json.loads((PROOF/"proof-inputs.json").read_text())
 assert current["sourceRevision"]==SHA and current["fixtureMatchesRecordedRevision"]
 assert current["runtimeBinaryTargets"]==[] and len(current["sdkSourceAndResourceFiles"])==418
 old_by={x["path"]:x for x in previous["sdkSourceAndResourceFiles"]}
 new_by={x["path"]:x for x in current["sdkSourceAndResourceFiles"]}
 assert old_by.keys()==new_by.keys()
 changes=[{"path":k,"before":old_by[k],"after":new_by[k]} for k in old_by if old_by[k]!=new_by[k]]
 assert [x["path"] for x in changes]==["Packages/HanlinPresentationSDK/Sources/HanlinChatUI/Motion/HanlinAnimatedDisclosure.swift"],changes
 for name in ("App.swift","MotionUITests.swift"):
  dst=PROOF/("App" if name=="App.swift" else "UITests")/name
  assert sha(dst)==sha(SOURCE/"docs/chat-motion/MotionUI"/name)
 evidence=STAGE/"evidence";evidence.mkdir(exist_ok=True)
 for name in ("verified-environment.json","ready-environment.json"):
  shutil.copy2(BASE/"revisions/efb33bf0/retry1/evidence"/name,evidence/name)
 state.update(status="PREPARED_PASS",sourceFingerprint=current["sdkSourceAndResourceSHA256"],sourceFileCount=len(new_by),sourceChanges=changes,originalTestSHA256=sha(PROOF/"UITests/MotionUITests.swift"),priorProof=str(OLD),canonicalPinsSHA256=sha(PROOF/lock_relative))
except BaseException as e:
 state.update(status="PREPARATION_FAILED",error=str(e),traceback=traceback.format_exc())
finally:
 v=os.statvfs(BASE);state.update(finishedUTC=datetime.datetime.now(datetime.timezone.utc).isoformat(),freeAtFinish=v.f_bavail*v.f_frsize);save()
