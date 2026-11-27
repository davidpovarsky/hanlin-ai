from pathlib import Path
import subprocess,json,hashlib,datetime,fcntl,os,sys,time
R=Path("/Users/m1/builds/hanlin-ai-ce49e30d-miniapp-complete");C=R/"build/primary-control"
def sha(p):
 with Path(p).open("rb")as f:return hashlib.file_digest(f,"sha256").hexdigest()
def utc():return datetime.datetime.now(datetime.timezone.utc).isoformat()
decision=C/"focused19-v11b-decision.json";assert sha(decision)=="7dd6fbe9469886c57813740b7b9e11fc44605e4d0524cc06879f9ec1170d438c"
d=json.loads(decision.read_text());controller=R/d["controller"]["path"];out=R/d["outputDirectory"]
assert sha(controller)==d["controller"]["sha256"]=="332728f7590a572aac6aaf61f5bb6e8b12a3d7d103c185da97fbfba2e5c6ddc4"
assert sha(R/d["child"]["path"])==d["child"]["sha256"]=="f5bf628915da0b169468d78dac232aa9e8b4d702995051049eaa8d75274dd644"
assert subprocess.check_output(["git","rev-parse","HEAD"],cwd=R,text=True).strip()==d["source"]
launch=C/"focused19-v11b-launch.json";log=C/"focused19-v11b-launch.log"
assert not out.exists()and not launch.exists()and not log.exists()
lock=(C/"native-continuation-owner.lock").open("a");fcntl.flock(lock.fileno(),fcntl.LOCK_EX|fcntl.LOCK_NB)
assert sha(C/"state.json")==d["primaryStateSHA256"]
primary=json.loads((C/"state.json").read_text());assert primary["status"]=="PAUSED_AFTER_PHASE"and primary["controllerPID"]is None and primary["activeElapsedSeconds"]==d["activeBaselineSeconds"]
df=subprocess.check_output(["df","-k","/System/Volumes/Data"],text=True);free=int(df.splitlines()[-1].split()[3])*1024
assert free>=d["resourceAssessment"]["estimatedIncrementalBytes"]+d["resourceAssessment"]["concurrentAndOSAllowanceBytes"]
fcntl.flock(lock.fileno(),fcntl.LOCK_UN);lock.close()
env=dict(os.environ);env["PATH"]=str(Path(d["originalNode"]["path"]).parent)+":/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin";env["DEVELOPER_DIR"]="/Applications/Xcode.app/Contents/Developer"
with log.open("xb")as output:
 p=subprocess.Popen([sys.executable,str(controller),"--decision",str(decision)],cwd=R,env=env,stdin=subprocess.DEVNULL,stdout=output,stderr=subprocess.STDOUT,start_new_session=True)
record={"schema":1,"source":d["source"],"producerSource":d["producerSource"],"observedAt":utc(),"pid":p.pid,"decision":str(decision),"decisionSHA256":sha(decision),"controller":str(controller),"controllerSHA256":sha(controller),"activeBaselineSeconds":d["activeBaselineSeconds"],"allowanceSeconds":d["allowanceSeconds"],"priorContinuationGrants":d["priorContinuationGrants"],"continuationGrant":d["continuationGrant"],"freshFreeBytes":free,"original52":"UNCHANGED_NOT_PROMOTED"}
launch.write_text(json.dumps(record,indent=2)+"\n")
time.sleep(2);state=out/"state.json"
print(json.dumps({"launch":record,"launchSHA256":sha(launch),"controllerExit":p.poll(),"state":json.loads(state.read_text())if state.exists()else None,"statePath":str(state),"stateSHA256":sha(state)if state.exists()else None}))
