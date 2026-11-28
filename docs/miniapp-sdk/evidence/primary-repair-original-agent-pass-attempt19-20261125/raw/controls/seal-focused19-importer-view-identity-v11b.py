from pathlib import Path
import subprocess,json,hashlib,datetime,fcntl,os,sys,time
R=Path("/Users/m1/builds/hanlin-ai-ce49e30d-miniapp-complete");C=R/"build/primary-control"
base=C/"focused19-v11b-decision-template.json";d=json.loads(base.read_text())
decision=C/"focused19-v11b-decision.json";launch=C/"focused19-v11b-launch.json"
controller=R/d["controller"]["path"];child=C/"focused-native-child-v11.py"
def digest(p):
 with Path(p).open("rb")as f:return hashlib.file_digest(f,"sha256").hexdigest()
def utc():return datetime.datetime.now(datetime.timezone.utc).isoformat()
assert digest(controller)==d["controller"]["sha256"]=="332728f7590a572aac6aaf61f5bb6e8b12a3d7d103c185da97fbfba2e5c6ddc4"
assert digest(child)==d["child"]["sha256"]=="f5bf628915da0b169468d78dac232aa9e8b4d702995051049eaa8d75274dd644"
assert digest(Path(d["originalNode"]["path"]))==d["originalNode"]["sha256"]
assert subprocess.check_output([d["originalNode"]["path"],"--version"],text=True).strip()=="v"+d["originalNode"]["version"]
assert not decision.exists()and not launch.exists()and not(R/d["outputDirectory"]).exists()
lock=(C/"native-continuation-owner.lock").open("a");fcntl.flock(lock.fileno(),fcntl.LOCK_EX|fcntl.LOCK_NB)
assert subprocess.check_output(["git","rev-parse","HEAD"],cwd=R,text=True).strip()==d["source"]
assert subprocess.check_output(["git","rev-parse","HEAD^{tree}"],cwd=R,text=True).strip()==d["sourceTree"]
assert digest(C/"state.json")==d["primaryStateSHA256"]
primary=json.loads((C/"state.json").read_text());assert primary["status"]=="PAUSED_AFTER_PHASE"and primary["activeElapsedSeconds"]==d["activeBaselineSeconds"]and primary.get("controllerPID")is None
actual_diff=hashlib.sha256(subprocess.check_output(["git","diff","--binary","HEAD"],cwd=R)).hexdigest()
assert actual_diff==d["preparedTrackedDiffSHA256"]
assert len(d["preparedPayloads"])==25
for item in d["requiredFiles"]+d["preservedLedgers"]+d["priorTerminals"]+d["priorFocusRecords"]:
 assert digest(R/item["path"])==item["sha256"],item["path"]
sdk_path=R/d["sdk"]["manifestPath"];assert digest(sdk_path)==d["sdk"]["manifestSHA256"]
sdk=json.loads(sdk_path.read_text());assert sdk["inputSHA256"]==d["sdk"]["inputSHA256"]
required={x["path"]:x["sha256"]for x in d["requiredFiles"]};assert len(required)==len(d["requiredFiles"])
assert len(sdk["sourceInputs"])==d["sdk"]["sourceInputCount"]==235
for row in sdk["sourceInputs"]:assert required[row["path"]]==row["sha256"],row["path"]
disk=subprocess.check_output(["df","-k","/System/Volumes/Data"],text=True);free=int(disk.splitlines()[-1].split()[3])*1024
components={"retainedOwnedBootDeviceAdditionalBytes":0,"conservativeBothAppsAndUIRunnersInstallBytes":2505814016,"conservativeHostRecreationBytes":713731370,"twoTimesActualFull25ResultAndExportBytes":629301248,"incrementalCompilerLinkAndResourceTemporaryBytes":1000000000}
estimate=sum(components.values());margin=400000000
assert free>=estimate+margin,{"free":free,"required":estimate+margin}
d["resourceAssessment"]={"decision":"FITS_MEASURED_NEXT_PHASE","observedAt":utc(),"observedFreeBytes":free,"df":disk,"estimatedIncrementalBytes":estimate,"concurrentAndOSAllowanceBytes":margin,"components":components,"basis":"Same authenticated E742 is retained; its existing device allocation is not counted as new. The retained measured two-app/runner byte total conservatively bounds both affected reinstalls and XCTest installation, with prior Host recreation and larger two-group result allocations reserved for this one-test continuation. The shared importer Swift source is present in both actual compiler lists, so both original incremental build-for-testing commands execute. All235 SDK inputs and13 probe outputs stay exact. No APFS clone savings assumed or globaldf change attributed to this phase.","boundary":"Both original affected consumer build/install commands and the original repair UI execute. Prior ManualInput PASS and unchanged original probe remain historical proof. Original52/companions remain separate."}
d["recordedAt"]=utc();decision.write_text(json.dumps(d,indent=2)+"\n");decision_sha=digest(decision)
fcntl.flock(lock.fileno(),fcntl.LOCK_UN);lock.close()
record={"source":d["source"],"decisionPath":str(decision),"decisionSHA256":decision_sha,"controller":d["controller"],"child":d["child"],"recordedAt":utc(),"allowanceSeconds":d["allowanceSeconds"],"activeBaselineSeconds":d["activeBaselineSeconds"],"resourceAssessment":d["resourceAssessment"],"priorContinuationGrants":d["priorContinuationGrants"],"continuationGrant":d["continuationGrant"],"nativeStarted":False}
seal=C/"focused19-v11b-seal.json";assert not seal.exists();seal.write_text(json.dumps(record,indent=2)+"\n")
print(json.dumps({"record":record,"sealSHA256":digest(seal)}))
