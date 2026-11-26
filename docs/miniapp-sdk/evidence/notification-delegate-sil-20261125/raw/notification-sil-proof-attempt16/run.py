from pathlib import Path
import subprocess,json,datetime,time,hashlib,os
D=Path(__file__).resolve().parent
utc=lambda:datetime.datetime.now(datetime.timezone.utc).isoformat()
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
s={"source":"46225e5af9aa253c8aa3b7d0d6ce2f282c88e7ad","owner":"/root/native_execution","status":"RUNNING","startedAt":utc(),"controllerPID":os.getpid(),"records":[]}
def write(): (D/"state.json").write_text(json.dumps(s,indent=2)+"\n")
write()
base=["xcrun","swiftc","-emit-object","-parse-as-library","-sdk","/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneSimulator.platform/Developer/SDKs/iPhoneSimulator27.0.sdk","-target","arm64-apple-ios27.0-simulator","-swift-version","6","-cxx-interoperability-mode=default","-warnings-as-errors","-module-cache-path","/Users/m1/builds/hanlin-ai-ce49e30d-miniapp-complete/build/primary-control/notification-signature-proof-attempt14/ModuleCache"]
try:
 for name in ["Baseline","Candidate"]:
  record={"name":name,"sourceSHA256":sha(D/(name+".swift")),"startedAt":utc(),"argv":base+[str(D/(name+".swift")),"-o",str(D/(name+".o"))]};s["records"].append(record);write();start=time.monotonic()
  with (D/(name+".log")).open("xb") as f:
   p=subprocess.Popen(record["argv"],stdout=f,stderr=subprocess.STDOUT);record["pid"]=p.pid;write();code=p.wait(timeout=90)
  record.update(exitCode=code,elapsedSeconds=time.monotonic()-start,finishedAt=utc(),logSHA256=sha(D/(name+".log")),objectSHA256=sha(D/(name+".o")) if (D/(name+".o")).exists() else None);write()
 s["status"]="PASS" if s["records"][0]["exitCode"]!=0 and s["records"][1]["exitCode"]==0 else "FAIL"
except BaseException as e:s.update(status="FAIL",error=str(e))
s["finishedAt"]=utc();write();print(json.dumps(s),flush=True)
