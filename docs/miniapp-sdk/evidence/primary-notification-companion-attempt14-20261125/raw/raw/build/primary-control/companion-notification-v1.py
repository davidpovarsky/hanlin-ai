from pathlib import Path
import os,sys,json,subprocess,time,datetime,hashlib,signal,traceback,re
R=Path("/Users/m1/builds/hanlin-ai-ce49e30d-miniapp-complete");C=R/"build/primary-control";O=C/"companion-native-v1";D=O/"notification-package";H="b0cf26a668a698682f5307252f14cf0af8c6d00a"
utc=lambda:datetime.datetime.now(datetime.timezone.utc).isoformat()
sha=lambda p:hashlib.sha256(Path(p).read_bytes()).hexdigest()
def write(p,x):
 t=p.with_suffix(p.suffix+".tmp");t.write_text(json.dumps(x,indent=2)+"\n");t.replace(p)
def livegroup(pgid):
 rows=[]
 for line in subprocess.check_output(["ps","-axo","pid=,pgid=,stat=,command="],text=True).splitlines():
  v=line.split(None,3)
  if len(v)==4 and int(v[1])==pgid and not v[2].startswith("Z"):rows.append({"pid":int(v[0]),"pgid":int(v[1]),"stat":v[2],"command":v[3]})
 return rows
assert subprocess.check_output(["git","rev-parse","HEAD"],cwd=R,text=True).strip()==H
before=json.loads((C/"state.json").read_text());assert before["status"]=="PAUSED_AFTER_PHASE" and before["source"]==H
assert not O.exists();O.mkdir();D.mkdir()
df=subprocess.check_output(["df","-k","/System/Volumes/Data"],text=True);free=int(df.splitlines()[1].split()[3])*1024
assert free>1500000000,"Specific incremental package compile/headroom allowance does not fit"
argv=["swift","test","--package-path","Packages/HanlinPlatform","--filter","HanlinNotificationInvocationTests"]
test="Packages/HanlinPlatform/Tests/HanlinScriptExtensionsTests/HanlinNotificationInvocationTests.swift"
assert sha(R/test)=="918dac76ba987164dfc80ea47ff3365d4a4fa42cecc87ee36db863721c9e1667"
decision={"schema":1,"id":"companion-native-v1","owner":"/root/native_execution","source":H,"sourceTree":subprocess.check_output(["git","rev-parse","HEAD^{tree}"],cwd=R,text=True).strip(),"allowanceSeconds":1200,"scope":["HanlinNotificationInvocationTests","AI_HLYTests/HanlinUnifiedHostServicesE2ETests/actualNativeScriptImportsTheGeneratedTypedFacadeAndCallsEveryEngine"],"authorization":{"by":"/root","scope":"separate bounded native companion; package suite may execute before paired52, NS5 after final AI products","noDuplicateStorageCase":True},"activeBaselineSeconds":before["activeElapsedSeconds"],"originalPlanMaximumActiveSeconds":12600,"paired4500Separate":True,"suiteSourceSHA256":sha(R/test),"expectedTestFunctions":8,"expectedParameterInstances":9,"note":"First test has two engine arguments; Swift Testing summary may count8 functions. Preserve actual parameter events.","packageCommand":argv,"storage":{"observedFreeBytes":free,"df":df,"estimatedIncrementalAndHeadroomBytes":1500000000,"basis":"Reuse existing isolated Packages/HanlinPlatform/.build; only changed notification/platform module and tests compile. No simulator/device install or native framework production."},"preparedDiffSHA256":hashlib.sha256(subprocess.check_output(["git","diff","--binary","HEAD"],cwd=R)).hexdigest(),"sealedAt":utc()}
write(O/"decision.json",decision);(D/"primary-state-before.json").write_bytes((C/"state.json").read_bytes())
ledger={"schema":1,"id":"companion-native-v1","source":H,"maximumActiveSeconds":1200,"activeElapsedSeconds":0,"charges":[],"remainingSelectors":["HanlinNotificationInvocationTests","AI_HLYTests/HanlinUnifiedHostServicesE2ETests/actualNativeScriptImportsTheGeneratedTypedFacadeAndCallsEveryEngine"]}
write(O/"ledger.json",ledger)
s={"status":"RUNNING","source":H,"controllerPID":os.getpid(),"startedAt":utc(),"argv":argv,"log":str(D/"swift-notification-suite.log"),"expectedTestFunctions":8,"NS5":"NOT_RUN"};write(D/"state.json",s)
primary=before.copy();primary.update(status="RUNNING",phase="companion-notification-package",controllerPID=os.getpid());write(C/"state.json",primary)
env=os.environ.copy();env.update(PATH=str(R)+"-tools/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin",DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer")
start=time.monotonic();p=None
try:
 with (D/"swift-notification-suite.log").open("wb") as f:
  p=subprocess.Popen(argv,cwd=R,env=env,stdout=f,stderr=subprocess.STDOUT,start_new_session=True);s["pid"]=p.pid;write(D/"state.json",s)
  while True:
   remaining=1200-(time.monotonic()-start)
   if remaining<=0:raise TimeoutError("Separate1200 companion active allowance exhausted")
   try:code=p.wait(timeout=min(30,remaining));break
   except subprocess.TimeoutExpired:
    s["elapsedSeconds"]=time.monotonic()-start;s["logBytes"]=(D/"swift-notification-suite.log").stat().st_size
    raw=subprocess.check_output(["df","-k","/System/Volumes/Data"],text=True);s.setdefault("diskObservations",[]).append({"at":utc(),"freeBytes":int(raw.splitlines()[1].split()[3])*1024});write(D/"state.json",s)
 s.update(status="PROCESS_PASS_REQUIRES_EXACT_TEST_REVIEW" if code==0 else "FAIL",exitCode=code,processFinishedAt=utc());write(D/"state.json",s)
except BaseException as e:
 s.update(status="FAIL",error=str(e),processFinishedAt=utc());write(D/"state.json",s);(D/"exception.txt").write_text(traceback.format_exc())
finally:
 if p is not None:
  remain=livegroup(p.pid)
  if remain:
   os.killpg(p.pid,signal.SIGTERM)
   try:p.wait(timeout=10)
   except subprocess.TimeoutExpired:pass
   for _ in range(20):
    if not livegroup(p.pid):break
    time.sleep(.25)
   if livegroup(p.pid):os.killpg(p.pid,signal.SIGKILL)
  if p.poll() is None:p.wait(timeout=10)
  s["remainingOwnedProcessGroup"]=livegroup(p.pid)
  if s["remainingOwnedProcessGroup"]:s["status"]="CLEANUP_FAILED"
 s.update(finishedAt=utc(),elapsedSeconds=time.monotonic()-start,logSHA256=sha(D/"swift-notification-suite.log"),logBytes=(D/"swift-notification-suite.log").stat().st_size)
 assert subprocess.check_output(["git","rev-parse","HEAD"],cwd=R,text=True).strip()==H
 assert sha(R/test)==decision["suiteSourceSHA256"]
 current=json.loads((C/"state.json").read_text());assert current["activeElapsedSeconds"]==before["activeElapsedSeconds"]
 charge={"id":"companion-native-v1-notification-package","source":H,"status":s["status"],"argv":argv,"elapsedSeconds":s["elapsedSeconds"],"statePath":str(D/"state.json"),"logSHA256":s["logSHA256"],"exitCode":s.get("exitCode")}
 ledger["activeElapsedSeconds"]+=s["elapsedSeconds"];ledger["charges"].append(charge);write(O/"ledger.json",ledger)
 current["activeElapsedSeconds"]+=s["elapsedSeconds"];current.setdefault("companionCharges",[]).append(charge);current.update(status="PAUSED_AFTER_PHASE",phase=before.get("phase"),controllerPID=None,finishedAt=utc());write(C/"state.json",current);write(D/"state.json",s)
sys.exit(0 if s.get("exitCode")==0 and not s.get("remainingOwnedProcessGroup") else 1)
