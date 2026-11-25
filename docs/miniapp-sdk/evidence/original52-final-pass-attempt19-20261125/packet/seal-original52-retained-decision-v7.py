"""Seal the original paired52 retained-product decision after actual focused Repair PASS.
This script does not build, install, stage, launch tests, or change historical records.
"""
from pathlib import Path
import ast,datetime,fcntl,hashlib,importlib.util,json,math,subprocess,uuid

ROOT=Path("/Users/m1/builds/hanlin-ai-ce49e30d-miniapp-complete")
CTRL=ROOT/"build/primary-control"
SOURCE="d4a0b115b106d4250ea40ad66153d5156847a07c"
TREE="f7a6596a1ef53d8d962ceb9f619460ffa19ee91e"
SDK_SOURCE="a2c8a1b1be746461272ba77254603304567c309d"
MINI_SOURCE="d4a0b115b106d4250ea40ad66153d5156847a07c"
CONTROLLER=CTRL/"paired52-v5h.py"
CONTROLLER_SHA="04d3f71d81436f95043e8bd84029c17aa4b7b06b7d91f3a5f73fa68d1967cd68"
CHILD=CTRL/"original52-retained-child-v7.py"
CHILD_SHA="04ff68e1ebc6ccd7069363c0aa32894af4b28a815d73a9c8fc6e6d5c3bc5128a"
FOCUS_DECISION_SHA="7dd6fbe9469886c57813740b7b9e11fc44605e4d0524cc06879f9ec1170d438c"
OLD_DECISION_SHA="62177d808a5c0101dd87548307ece8c3d6c542a8bc56d6c0c93d3fdc4ade7e1d"
def digest(path):
 with Path(path).open("rb")as f:return hashlib.file_digest(f,"sha256").hexdigest()
def utc():return datetime.datetime.now(datetime.timezone.utc).isoformat()
def canonical(value):return hashlib.sha256(json.dumps(value,sort_keys=True,separators=(",",":")).encode()).hexdigest()
def ref(path,absolute=False):
 p=Path(path).resolve();assert p.is_relative_to(ROOT)and p.is_file()and not p.is_symlink()
 return{"path":str(p)if absolute else p.relative_to(ROOT).as_posix(),"bytes":p.stat().st_size,"sha256":digest(p)}
def read(path):return json.loads(Path(path).read_text())
def main():
 lock=(CTRL/"native-continuation-owner.lock").open("a");fcntl.flock(lock.fileno(),fcntl.LOCK_EX|fcntl.LOCK_NB)
 assert digest(CONTROLLER)==CONTROLLER_SHA and digest(CHILD)==CHILD_SHA
 out=CTRL/"paired52-continuation-v5"
 decision_path=CTRL/"paired52-continuation-v5-decision.json"
 assert not out.exists()and not decision_path.exists()
 assert subprocess.check_output(["git","rev-parse","HEAD"],cwd=ROOT,text=True).strip()==SOURCE
 assert subprocess.check_output(["git","rev-parse","HEAD^{tree}"],cwd=ROOT,text=True).strip()==TREE
 primary_path=CTRL/"state.json";plan_path=CTRL/"plan.json"
 primary=read(primary_path);plan=read(plan_path)
 assert primary["source"]==plan["sha"]==SOURCE and plan["maximumActiveSeconds"]==12600
 assert primary["status"]=="PAUSED_AFTER_PHASE"and primary["phase"]=="split-inputs"and primary["controllerPID"]is None
 assert primary["planSHA256"]==digest(plan_path)
 fdir=CTRL/"focused19-v11";focus=read(fdir/"state.json");native=read(fdir/"native-result/state.json")
 assert focus["source"]==native["source"]==SOURCE and native["tree"]==TREE
 assert focus["status"]==native["status"]=="FOCUSED_PASS"and focus["chargeCommitted"]
 assert not focus["remainingOwnedProcessGroup"]and not focus["cleanupErrors"]and not focus["sourceErrors"]
 assert not native["cleanupErrors"]and not native["sourceErrors"]and not native["errors"]
 assert native["original52"]=="NOT_RUN"and set(native["groups"])=={"FocusedRepair1"}
 g=native["groups"]["FocusedRepair1"];summary=g["summary"]
 assert g["status"]=="PASS"and g["exitCode"]==0 and g["resultFinalized"]
 assert summary["totalTestCount"]==summary["passedTests"]==1 and summary["failedTests"]==summary["skippedTests"]==0
 assert primary["activeElapsedSeconds"]==focus["cumulativeActiveSeconds"]
 fdp=fdir/"decision.json";assert digest(fdp)==focus["decisionSHA256"]==FOCUS_DECISION_SHA
 fd=read(fdp);assert fd["source"]==SOURCE
 old_path=CTRL/"paired52-continuation-v4/decision.json";assert digest(old_path)==OLD_DECISION_SHA
 old=read(old_path)
 recovery=read(CTRL/"focused19-v11-recovery-inputs.json")
 assert native["recoveryInputSHA256"]==digest(CTRL/"focused19-v11-recovery-inputs.json")
 original_path=Path(recovery["originalTestCommand"]["path"]);original=read(original_path)
 assert digest(original_path)==recovery["originalTestCommand"]["sha256"]
 mini=[x.removeprefix("-only-testing:")for x in original["argv"]if x.startswith("-only-testing:")]
 ai=original["original27Selectors"];assert len(mini)==25 and original["originalExpected27"]==27
 # Original AI suite selections expand to27 actual cases; preserve their exact plan.
 runner_path=ROOT/"Scripts/ProductSplit/run_paired_acceptance.py"
 assert digest(runner_path)==next(x["sha256"]for x in fd["requiredFiles"]if x["path"]==runner_path.relative_to(ROOT).as_posix())
 plans=ast.literal_eval(next(n.value for n in ast.parse(runner_path.read_text()).body if isinstance(n,ast.Assign)and any(isinstance(t,ast.Name)and t.id=="TEST_PLANS"for t in n.targets)))
 assert ai==plans["miniapp_authoring"][0]+plans["miniapp_sdk04"][0]
 assert original["originalExpected27"]==plans["miniapp_authoring"][1]+plans["miniapp_sdk04"][1]
 built_path=Path(native["builtInputBindings"]["path"]);built=read(built_path)
 assert digest(built_path)==native["builtInputBindings"]["sha256"]
 assert built["source"]==built["aiBuildProducerSource"]==SOURCE and built["miniBuildProducerSource"]==MINI_SOURCE and built["SDKProducerSource"]==SDK_SOURCE
 assert native["originalTestBuilds"]==built["originalTestBuilds"]=="PASS"
 assert native["miniBuildProducerSource"]==native["aiBuildProducerSource"]==SOURCE and native["SDKProducerSource"]==SDK_SOURCE
 assert "authenticatedMiniReuse"not in built and "authenticatedAIReuse"not in built
 assert len(native["reusedSetup"])==1 and native["reusedSetup"][0]["status"]=="REUSED_AUTHENTICATED_OWNED_DEVICE"
 staged_path=Path(native["stagedInputs"]["path"]);staged=read(staged_path)
 assert digest(staged_path)==native["stagedInputs"]["sha256"]and staged["source"]==SOURCE
 staging=staged["unchanged"]+[{"name":staged["replacement"]["name"],**staged["replacement"]["after"]}]
 staging.sort(key=lambda x:x["name"]);assert len(staging)==11
 ownership=fdir/"native-result/paired-prefix/created-simulator.txt"
 device=str(uuid.UUID(ownership.read_text().strip())).upper()
 assert device==native["simulator"]=="E742FBCD-8FF0-4130-B143-7F8328637138"
 assert native["ownedSimulatorCleanup"]["state"]=="Shutdown"and not native["ownedSimulatorCleanup"]["remainingOwnedRunners"]
 setup_path=Path(recovery["priorPrefixState"]["path"]);setup=read(setup_path)
 assert digest(setup_path)==recovery["priorPrefixState"]["sha256"]
 modal=setup["external_modal_fixture"];verifier=Path(modal["verify_command"][0])
 assert modal["status"]=="REAL_IMPORT_AND_INCOMING_REQUEST_STAGED"and modal["simulator_udid"]==device
 pending=Path(modal["shared_group_container"])/"MiniAppsBridge/v1/requests/4f2ecda0-9c21-46a2-b2e1-8cd4f017c623.json"
 pending_raw=pending.read_bytes();record=json.loads(pending_raw)
 assert record["request"]["id"].lower()=="4f2ecda0-9c21-46a2-b2e1-8cd4f017c623"and record.get("result")is None and record["acknowledged"]is False
 fixtures_path=Path(recovery["priorFixtureProduction"]["path"])
 assert digest(fixtures_path)==native["fixtureProduction"]["sha256"]
 d={k:v for k,v in old.items()if k not in["resourceAssessment","sealedAt","controllerSHA256"]}
 charges=[];priors=[]
 for number in[1,2,3,4]:
  ident="paired52-continuation-v"+str(number);p=CTRL/ident/"state.json";row=read(p)
  assert row["id"]==ident and row["status"]=="FAILED"and not row["cleanupErrors"]and not row["sourceErrors"]and not row["remainingOwnedProcessGroup"]
  charges.append(row["chargedSeconds"]);priors.append({"id":ident,"stateSHA256":digest(p),"chargedSeconds":row["chargedSeconds"]})
 prior_charge=math.fsum(charges);allowance=7500-prior_charge
 assert allowance==3720.3727040829836
 assert [x["chargedSeconds"]for x in primary["continuationCharges"]]==charges
 d.update(id="paired52-continuation-v5",source=SOURCE,sourceTree=TREE,outputDirectory="build/primary-control/paired52-continuation-v5",
  allowanceSeconds=allowance,priorContinuationChargedSeconds=prior_charge,priorContinuations=priors,
  planSHA256=digest(plan_path),primaryStateSHA256=digest(primary_path),activeBaselineSeconds=primary["activeElapsedSeconds"],
  preparedTrackedDiffSHA256=hashlib.sha256(subprocess.check_output(["git","diff","--binary","HEAD"],cwd=ROOT)).hexdigest(),
  controllerSHA256=CONTROLLER_SHA,child={"path":str(CHILD.relative_to(ROOT)),"sha256":CHILD_SHA},
  sdk=fd["sdk"],originalNode=fd["originalNode"],derivedData=fd["derivedData"],
  preparedPayloads=fd["preparedPayloads"],producerSource=SDK_SOURCE,
  groups={"OriginalRuntimes":{"expected":25,"selectors":mini},"Paired":{"expected":27,"selectors":ai}},
  commandCeilingsSeconds={"OriginalRuntimes":2400,"Paired":2100},
  separateAdditionalCeilingFromActualLaunch=allowance,
  authorization={"by":"/root","scope":"one original paired52 continuation","basis":"Fresh original25+27 on authenticated retained E742 products and staged inputs after actual repaired-app acceptance. Original4500 grant plus explicit2400/600 additions minus all four prior paired charges; all focused and companion charges remain separate and monotonic. No build/install/preparation, no focused-count aggregation."})
 d["setup"]={"focusTerminal":ref(fdir/"state.json"),"focusChild":ref(fdir/"native-result/state.json"),
  "manualFocusChild":recovery["priorChild"],"builtInputBindings":ref(built_path),"originalMiniCommand":ref(original_path),
  "originalSetup":ref(setup_path),"fixtureProduction":ref(fixtures_path),"ownership":ref(ownership),
  "stagedInputs":ref(staged_path),"modalVerifier":ref(verifier)}
 d["productFiles"]=built["files"];d["stagedFiles"]=staging
 d["simulator"]={"udid":device,"ownership":ref(ownership),"reuse":"Retained warm owned focus simulator; no claim of fresh cold installation."}
 d["modalPending"]={"path":str(pending),"bytes":len(pending_raw),"sha256":hashlib.sha256(pending_raw).hexdigest()}
 assert native["reusedManualProof"]["authority"]==d["setup"]["manualFocusChild"]
 required={x["path"]:{"path":x["path"],"sha256":x["sha256"]}for x in old["requiredFiles"]}
 for x in fd["requiredFiles"]:required[x["path"]]={"path":x["path"],"sha256":x["sha256"]}
 metadata="build/runtime-host/host-metadata.json"
 required[metadata]={"path":metadata,"sha256":digest(ROOT/metadata)}
 def add(row):
  p=(ROOT/row["path"]).resolve();assert p.is_relative_to(ROOT)
  name=p.relative_to(ROOT).as_posix();required[name]={"path":name,"sha256":row["sha256"]}
 for row in d["setup"].values():add(row)
 for row in[ref(CONTROLLER),ref(CHILD),ref(fdir/"ledger.json"),ref(fdp),ref(CTRL/"focused19-v6-cleanup-reconciliation.json")]:add(row)
 for row in fd["preservedLedgers"]:add(row)
 for row in fd["priorFocusRecords"]:add(row)
 d["generationProvenance"]={**primary["generation"],"consumerSource":SOURCE,"retainedWithoutRerun":True}
 assert d["generationProvenance"]["source"]==SDK_SOURCE
 for step in primary["generation"]["steps"]:
  p=Path(step["log"]);assert digest(p)==step["logSHA256"];add(ref(p))
 add(ref(Path(primary["generation"]["prefixState"])))
 d["requiredFiles"]=list(required.values())
 for row in d["requiredFiles"]:
  p=ROOT/row["path"];assert p.is_file()and digest(p)==row["sha256"],row["path"]
 sdk=read(ROOT/d["sdk"]["manifestPath"]);assert len(sdk["sourceInputs"])==235
 for row in sdk["sourceInputs"]:assert required[row["path"]]["sha256"]==row["sha256"]
 terminals={x["path"]:x for x in fd["priorTerminals"]}
 terminals[str((fdir/"state.json").relative_to(ROOT))]={"path":str((fdir/"state.json").relative_to(ROOT)),"sha256":digest(fdir/"state.json")}
 d["priorTerminals"]=list(terminals.values())
 preserved={x["path"]:x for x in fd["preservedLedgers"]}
 for row in fd["priorFocusRecords"]:preserved[row["path"]]=row
 for row in[ref(fdir/"state.json"),ref(fdir/"ledger.json"),ref(fdp),ref(fdir/"native-result/state.json")]:
  preserved[row["path"]]={"path":row["path"],"sha256":row["sha256"]}
 d["preservedLedgers"]=list(preserved.values())
 d["prerequisites"]=[{"id":x["id"],"recordSHA256":canonical(primary["phases"][x["id"]])}for x in plan["phases"]if x["id"]!="split-paired-acceptance"]
 for row in d["prerequisites"]:assert primary["phases"][row["id"]]["status"]in["PASS","REUSED_VERIFIED_SKIP"]
 phase=next(x for x in plan["phases"]if x["id"]=="split-paired-acceptance")
 assert digest(CTRL/"phases/split-paired-acceptance.sh")==phase["scriptSHA256"]==d["phaseScriptSHA256"]
 components={"retainedDeviceNewAllocationBytes":0,"conservativeProductAndRunnerInstallAllowanceBytes":2505814016,
  "twoHostUncompressedRecreationsBytes":713731370,"twoLargestRetainedResultsBytes":2309439488,
  "twoRetainedFullDiagnosticExportBoundsBytes":1323308972,"temporaryAuthoringWorkspacesBytes":500000000}
 need=sum(components.values());margin=500000000
 disk=subprocess.check_output(["df","-k","/System/Volumes/Data"],text=True);free=int(disk.splitlines()[-1].split()[3])*1024
 assert free>=need+margin,{"free":free,"required":need+margin}
 d["resourceAssessment"]={"decision":"FITS_MEASURED_NEXT_PHASE","observedAt":utc(),"observedFreeBytes":free,"df":disk,
  "estimatedIncrementalBytes":need,"concurrentAndOSAllowanceBytes":margin,"components":components,
  "basis":"Retained E742 and actual built products reused; no compilation/source preparation. Product/runner and two Host expansion allowances retain prior measured conservative sizes. Two results reserve twice the largest retained1,154,719,744-byte result; two exports reserve twice the independently retained661,654,486-byte diagnostic export. A bounded500MB authoring workspace allowance covers real original repair/compiler work; global disk changes are not attributed to this phase."}
 d["sealedAt"]=utc()
 assert not decision_path.exists();decision_path.write_text(json.dumps(d,indent=2)+"\n")
 receipt={"schema":1,"status":"SEALED_NOT_LAUNCHED","source":SOURCE,"SDKProducerSource":SDK_SOURCE,
  "decision":str(decision_path),"decisionSHA256":digest(decision_path),"requiredCount":len(required),"productCount":len(d["productFiles"]),"stagedCount":len(staging),
  "activeBaselineSeconds":d["activeBaselineSeconds"],"allowanceSeconds":allowance,"focusTerminal":d["setup"]["focusTerminal"],"focusChild":d["setup"]["focusChild"],"original52":"NOT_RUN"}
 rp=CTRL/"paired52-continuation-v5-decision-receipt.json";assert not rp.exists();rp.write_text(json.dumps(receipt,indent=2)+"\n")
 print(json.dumps(receipt))
if __name__=="__main__":main()
