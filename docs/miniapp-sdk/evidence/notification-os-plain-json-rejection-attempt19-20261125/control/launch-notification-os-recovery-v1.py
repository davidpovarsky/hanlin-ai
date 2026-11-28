from pathlib import Path
import base64,datetime,fcntl,hashlib,json,os,subprocess,sys,time
R=Path("/Users/m1/builds/hanlin-notification-os-recovery-20261125")
P=R/"recovery";ID="notification-os-recovery-v1";O=R/"build"/ID
CONTROLLER_SHA="4e1917d8e0422a74cdb561cf25ea444cae7fa2d10669924f1501fb220156d630"
DECISION_SHA="92df2d1dc2a829c7bb6e61effaad715af3923ba92a326cca1dee9c76de2383b7"
def sha(p):
 with Path(p).open("rb")as f:return hashlib.file_digest(f,"sha256").hexdigest()
def utc():return datetime.datetime.now(datetime.timezone.utc).isoformat()
controller=P/(ID+".py");decision=P/(ID+"-decision.json")
assert sha(controller)==CONTROLLER_SHA
assert sha(decision)==DECISION_SHA
assert sha(P/"receipt.json")=="3a51b93378c45a565a50355c7735d094a769b4c433808a06b1412e5ba22e1dba"
assert sha(P/"preparation-ledger.json")=="5c09ded5e075df3247287ed62e71e6abc52e6e15c4aa4f25c1c7892b71ad4886"
receipt=json.loads((P/"receipt.json").read_text());ledger=json.loads((P/"preparation-ledger.json").read_text());d=json.loads(decision.read_text())
assert receipt["root"]==str(R)and receipt["status"]=="PREPARED_SOURCE_AND_NEW_SHUTDOWN_DEVICE"
assert receipt["source"]==d["source"]=="d4a0b115b106d4250ea40ad66153d5156847a07c"
assert d["root"]==str(R)and d["id"]==ID
assert receipt["simulator"]["udid"]=="2EFAD83F-45A2-4A8B-B326-16B83BC56DA9"
assert sha(P/"created-simulator.txt")=="3fdea4fa8c32d9a1978142f494fae431c2054d535b3be1e604a8ed23650f7d79"
assert (P/"created-simulator.txt").read_text().strip()==receipt["simulator"]["udid"]
assert ledger["maximumActiveSeconds"]==900 and ledger["activeElapsedSeconds"]==1.332704125001328
assert ledger["remainingAllowanceSeconds"]==900-ledger["activeElapsedSeconds"]
for key in ["historicalLedger","historicalPrimary","historicalTerminal","historicalCleanupReconciliation"]:
 authority=receipt[key];assert sha(authority["path"])==authority["sha256"]
launch=P/(ID+"-launch.json");log=P/(ID+"-launch.log")
assert not O.exists()and not launch.exists()and not log.exists()
lock=(P/"native-owner.lock").open("a");fcntl.flock(lock.fileno(),fcntl.LOCK_EX|fcntl.LOCK_NB)
df=subprocess.check_output(["/bin/df","-k",str(R)],text=True,timeout=10)
free=int(df.splitlines()[-1].split()[3])*1024
assert free>=10000000000,"Conservative fresh-device recovery admission reserve"
assert not O.exists()
fcntl.flock(lock.fileno(),fcntl.LOCK_UN);lock.close()
env=dict(os.environ);env.update(PATH="/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin",DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer",GITHUB_WORKSPACE=str(R),GITHUB_SHA=receipt["source"],SPLIT_EVIDENCE=str(O),SPLIT_DERIVED_DATA="/Users/m1/caches/DerivedData/hanlin-ai-ce49e30d-miniapp-complete",PAIRED_TEST_SCOPE="miniapp_complete",RUNNER_TEMP=str(R/"build/primary-temp"))
argv=[sys.executable,str(controller),"--decision",str(decision)]
with log.open("xb")as output:
 process=subprocess.Popen(argv,cwd=R,env=env,stdin=subprocess.DEVNULL,stdout=output,stderr=subprocess.STDOUT,start_new_session=True)
record={"schema":1,"observedAt":utc(),"root":str(R),"source":receipt["source"],"id":ID,"pid":process.pid,"argv":argv,"controllerSHA256":CONTROLLER_SHA,"decisionSHA256":DECISION_SHA,"simulator":receipt["simulator"]["udid"],"maximumActiveSeconds":900,"preparationChargedSeconds":ledger["activeElapsedSeconds"],"remainingAllowanceSeconds":ledger["remainingAllowanceSeconds"],"historicalOSChargedSeconds":897.3027506670041,"historicalPrimaryActiveSeconds":25204.83441242004,"freshFreeBytes":free,"phaseExecution":"NOT_RUN_AT_DISPATCH","environment":{key:env[key]for key in ["PATH","DEVELOPER_DIR","GITHUB_WORKSPACE","GITHUB_SHA","SPLIT_EVIDENCE","SPLIT_DERIVED_DATA","PAIRED_TEST_SCOPE","RUNNER_TEMP"]}}
with launch.open("x")as f:f.write(json.dumps(record,indent=2)+"\n")
time.sleep(2)
files=[launch,decision]
state=O/"state.json"
if state.exists():files.append(state)
print(json.dumps({"result":{"status":"DISPATCHED_ONCE","launch":record,"controllerExit":process.poll(),"state":json.loads(state.read_text())if state.exists()else None,"logTail":log.read_text()[-2000:]},"files":[{"sourcePath":str(p),"name":ID+"-first-state.json"if p==state else p.name,"bytes":p.stat().st_size,"sha256":sha(p),"base64":base64.b64encode(p.read_bytes()).decode()}for p in files]}))
