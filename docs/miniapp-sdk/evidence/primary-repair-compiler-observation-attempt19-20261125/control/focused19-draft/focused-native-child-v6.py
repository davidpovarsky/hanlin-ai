"""Run only the remaining original repair UI on the retained owned simulator.
Authenticate the completed original probe, ManualInput PASS and Mini build; rebuild only AI.
This focused continuation cannot promote or aggregate the original 25+27 result.
"""
from pathlib import Path
import argparse,datetime,hashlib,importlib.util,json,os,plistlib,shutil,signal,subprocess,sys,time,traceback,uuid

SOURCE="958cf666da7be83b9b63e46e3013e3344fb31585"
PRIOR_SOURCE="6c006c948f0a6f371f7fc68b90e393f43734f8dd"
ORIGINAL_SETUP_SOURCE="62dfff9aebd0a272486c7770d4f77ba603d535ab"
PRODUCER_SOURCE="a2c8a1b1be746461272ba77254603304567c309d"
RUNNER_SHA="a99b6194f8dd20bc30998ff2ad9e86ec219415a00615b250c65670f7dfcdba7d"
UI_SHA="da0fa21f26b677f4d18f8e1972208b39e30401a127e9dd2a9643e0fe8d7ad17c"
MANUAL_SELECTOR="HanlinMiniAppsUITests/MiniAppsProductionRuntimeUITests/testStandaloneExpoManualInputLayoutAndDataAdapters"
AI=["AI_HLYUITests/MiniAppAuthoringUITests/testTypeErrorRepairsThroughOriginalAgentBuildAndCompanionImport"]
SOURCE_PATHS=[
 "AI_HLY/ChatView.swift","AI_HLYTests/HanlinOriginalScriptWidgetLiveActivityTests.swift",
 "HanlinMiniAppsUITests/HanlinMiniAppsUITests.swift",
 "Packages/HanlinExpoRuntime/Sources/HanlinExpoRuntime/HanlinExpoUIModule.swift",
 "Packages/HanlinExpoUI/src/manual-components.tsx",
 "Scripts/ProductSplit/run_paired_acceptance.py","Scripts/ProductSplit/test_run_paired_acceptance.py",
 "Fixtures/ExpoSwiftUIProbe/ManualAdapterProbe.tsx",
 "AI_HLY/Downstream/AgentDiagnostics/AgentRuntimeUIAcceptanceProvider.swift",
 "AI_HLYUITests/MiniAppAuthoringUITests.swift","Scripts/Expo/build-probe.mjs",
 "AI_HLY/Downstream/ChatCore/HanlinAppHostIntegration.swift"]
def digest(path):
 h=hashlib.sha256()
 with Path(path).open("rb")as f:
  for b in iter(lambda:f.read(1024*1024),b""):h.update(b)
 return h.hexdigest()
def utc():return datetime.datetime.now(datetime.timezone.utc).isoformat()
def write(path,value):
 p=Path(path);tmp=p.with_name(p.name+".tmp");tmp.write_text(json.dumps(value,indent=2)+"\n");tmp.replace(p)
def main():
 p=argparse.ArgumentParser();p.add_argument("--source",required=True);p.add_argument("--output",type=Path,required=True);args=p.parse_args()
 root=Path.cwd().resolve();ctrl=root/"build/primary-control";out=args.output.resolve()
 assert args.source==SOURCE and out.is_relative_to(ctrl)and not out.exists()
 assert subprocess.check_output(["git","rev-parse","HEAD"],cwd=root,text=True).strip()==SOURCE
 recovery_path=ctrl/"focused19-v6-recovery-inputs.json"
 recovery=json.loads(recovery_path.read_text())
 assert recovery["schema"]==3 and recovery["source"]==SOURCE
 assert recovery["producerSource"]==PRODUCER_SOURCE and recovery["priorConsumerSource"]==PRIOR_SOURCE
 def checked(key,json_value=True):
  row=recovery[key];path=Path(row["path"]).resolve()
  assert path.is_relative_to(ctrl)and not path.is_symlink()and digest(path)==row["sha256"],key
  return json.loads(path.read_text())if json_value else path
 prior=checked("priorTerminal");prior_child=checked("priorChild");reuse=checked("miniProductObservation")
 observed=checked("reuseObservation");old_built=checked("priorBuiltBindings");prefix=checked("priorPrefixState")
 impact=checked("miniSourceImpact")
 fixture=checked("priorFixtureProduction");staged=checked("priorStagedInputs")
 assert impact["queriedFiles"]==43 and not impact["missing"]and not impact["matchingChangedPaths"]
 for row in impact["fileLists"]:
  f=Path(row["path"]);assert f.stat().st_size==row["bytes"]and digest(f)==row["sha256"],str(f)
 original_command_record=checked("originalTestCommand")
 command_path=checked("originalCommands",False)
 original_commands=[json.loads(x)for x in command_path.read_text().splitlines()if x]
 assert prior["status"]=="FOCUSED_FAILED"and prior["chargeCommitted"]and prior["chargedSeconds"]==713.0760274589993
 assert not prior["sourceErrors"]and not prior["cleanupErrors"]and not prior["remainingOwnedProcessGroup"]
 assert prior["cumulativeFocusedSeconds"]==2096.609411210011
 assert prior_child["source"]==PRIOR_SOURCE and not prior_child["sourceErrors"]and not prior_child["cleanupErrors"]
 for name,passed,failed in [("FocusedManual1",1,0),("FocusedRepair1",0,1)]:
  g=prior_child["groups"][name];s=g["summary"]
  assert g["resultFinalized"]and s["passedTests"]==passed and s["failedTests"]==failed and s["skippedTests"]==0
 manual=prior_child["groups"]["FocusedManual1"]
 assert manual["status"]=="PASS"and manual["exitCode"]==0 and manual["selectors"]==[MANUAL_SELECTOR]
 assert {("/pixel.png",200),("/missing.png",404)}<={(x["path"],x["status"])for x in prior_child["nativeAdapterRequests"]}
 assert fixture["source"]==PRIOR_SOURCE and fixture["exitCode"]==0 and fixture["argv"]==["node","Scripts/Expo/build-probe.mjs"]
 assert len(fixture["after"])==13 and len({x["path"]for x in fixture["after"]})==13
 for row in fixture["after"]:
  f=root/row["path"];assert f.stat().st_size==row["bytes"]and digest(f)==row["sha256"],row["path"]
 assert staged["source"]==PRIOR_SOURCE and len(staged["unchanged"])==10
 assert reuse["source"]==PRODUCER_SOURCE and len(reuse["files"])==5697 and not reuse["symlinks"]
 assert reuse["originalMiniBuildCommand"]["exit"]==0 and reuse["originalMiniBuildCommand"]["completion_recorded"]
 assert not any(x["modifiedAfterBuildTerminal"]for x in reuse["files"])
 assert observed["source"]==ORIGINAL_SETUP_SOURCE and observed["miniFilesVerified"]==5697 and not observed["miniDifferences"]
 assert prefix["sha"]==ORIGINAL_SETUP_SOURCE and prefix["build"]=="PASS_WITH_AUTHENTICATED_MINI_REUSE"
 assert prefix["app_group"]["status"]=="EXECUTED_PASS"and old_built["source"]==PRIOR_SOURCE
 ownership=Path(reuse["ownership"]["path"])
 assert ownership.is_relative_to(ctrl)and digest(ownership)==reuse["ownership"]["sha256"]
 simulator=str(uuid.UUID(ownership.read_text().strip())).upper()
 assert simulator==observed["device"]["udid"]==reuse["ownership"]["device"]
 runner_path=root/"Scripts/ProductSplit/run_paired_acceptance.py"
 assert digest(runner_path)==RUNNER_SHA and digest(root/"HanlinMiniAppsUITests/HanlinMiniAppsUITests.swift")==UI_SHA
 sources={n:digest(root/n)for n in SOURCE_PATHS}
 assert sources==recovery["sourceHashes"]
 for n,h in sources.items():
  assert hashlib.sha256(subprocess.check_output(["git","show",SOURCE+":"+n],cwd=root)).hexdigest()==h,n
 derived=Path(os.environ["SPLIT_DERIVED_DATA"]);products=derived/"Build/Products/Debug-iphonesimulator"
 def verify_mini_products():
  actual=set()
  for name in ["HanlinMiniApps.app","HanlinMiniAppsUITests-Runner.app"]:
   product=products/name;assert product.is_dir()
   for f in product.rglob("*"):
    assert not f.is_symlink(),str(f)
    if f.is_file():actual.add(str(f))
  assert actual=={x["path"]for x in reuse["files"]}
  for row in reuse["files"]:
   f=Path(row["path"]);assert f.stat().st_size==row["bytes"]and digest(f)==row["sha256"],str(f)
 verify_mini_products()
 for row in old_built["files"]:
  f=Path(row["path"]);assert f.stat().st_size==row["size"]and digest(f)==row["sha256"],str(f)
 devices=json.loads(subprocess.check_output(["xcrun","simctl","list","devices","-j"],text=True,timeout=20))
 found=[(rt,d)for rt,ds in devices["devices"].items()for d in ds if d["udid"]==simulator]
 assert len(found)==1 and found[0][0]==observed["runtime"]and found[0][1]["state"]=="Shutdown"
 assert found[0][1]["deviceTypeIdentifier"]==observed["device"]["deviceTypeIdentifier"]
 original=original_command_record["argv"]
 selected=[x.removeprefix("-only-testing:")for x in original if x.startswith("-only-testing:")]
 assert len(selected)==25 and MANUAL_SELECTOR in selected and "test-without-building"in original
 assert original[original.index("-destination")+1]=="platform=iOS Simulator,id="+simulator
 assert original[original.index("-collect-test-diagnostics")+1]=="never"
 out.mkdir();sys.path.insert(0,str(root/"Scripts/ProductSplit"))
 spec=importlib.util.spec_from_file_location("original_paired_focused19_final",runner_path)
 paired=importlib.util.module_from_spec(spec);spec.loader.exec_module(paired)
 assert paired.TEST_SCOPE=="miniapp_complete"and paired.TEST_PLANS["miniapp_complete"][1]==27
 assert original_command_record["original27Selectors"]==paired.TEST_PLANS["miniapp_complete"][0]
 assert AI[0].rsplit("/",1)[0]in paired.TEST_PLANS["miniapp_complete"][0]
 paired.EVIDENCE=out/"paired-prefix";paired.EVIDENCE.mkdir()
 (paired.EVIDENCE/"created-simulator.txt").write_bytes(ownership.read_bytes())
 write(out/"intercepted-original-command.json",original_command_record)
 state={"schema":1,"owner":"/root/native_execution","source":SOURCE,"tree":subprocess.check_output(["git","rev-parse","HEAD^{tree}"],cwd=root,text=True).strip(),
  "status":"RUNNING","startedAt":utc(),"pid":os.getpid(),"phase":"authenticated-reuse",
  "original52":"NOT_RUN","original25":"NOT_RUN","original27":"NOT_RUN",
  "scope":"Only original repair UI; previous ten focused passes are retained separately, not aggregated into original52.",
  "selectors":{"FocusedRepair1":AI},"groups":{},"errors":[],"sourceErrors":[],"cleanupErrors":[],
  "originalRunnerSHA256":RUNNER_SHA,"sourceHashes":sources,"hostArchiveSHA256":digest(root/"AI_HLY/RuntimeHostResources.zip"),
  "recoveryInputSHA256":digest(recovery_path),"simulator":simulator,"miniBuildProducerSource":PRODUCER_SOURCE,
  "SDKProducerSource":PRODUCER_SOURCE,"reusedSetup":[{"status":"REUSED_AUTHENTICATED_OWNED_DEVICE","authority":reuse["ownership"]},
  {"status":"REUSED_EXECUTED_PASS","authority":recovery["miniProductObservation"],"producerSource":PRODUCER_SOURCE}],
  "checkpointReached":False,
  "reusedManualProof":{"authority":recovery["priorChild"],"group":manual,"nativeAdapterRequests":prior_child["nativeAdapterRequests"]},
  "fixtureProduction":{**recovery["priorFixtureProduction"],"outputs":13,"status":"REUSED_ORIGINAL_PRODUCER_PASS"},
  "nativeAdapterProof":"Prior actual ManualInput PASS retained; no image test or server in this one-case continuation"}
 started=time.monotonic()
 def save():
  state["observedAt"]=utc();state["elapsedSeconds"]=time.monotonic()-started;write(out/"state.json",state)
  print(json.dumps({k:state.get(k)for k in ["observedAt","status","phase","elapsedSeconds","simulator"]}),flush=True)
 save()
 original_command=paired.command
 def execute(argv,name,timeout=60,allow_failure=False):
  state["phase"]=name;save()
  return original_command(argv,name,timeout=timeout,allow_failure=allow_failure)
 paired.command=execute
 class StopAfterUnfinalized(BaseException):pass
 class FocusCancellation(BaseException):pass
 def cancel(signum,frame):raise FocusCancellation("Owned focused phase cancellation")
 signal.signal(signal.SIGTERM,cancel);signal.signal(signal.SIGINT,cancel)
 def command_for(log):
  matches=[x for x in original_commands if x["log"]==log]
  assert len(matches)==1 and matches[0]["exit"]==0
  return list(matches[0]["argv"])
 def make_test(selectors,label,scheme):
  argv=[];i=0
  while i<len(original):
   v=original[i]
   if v.startswith("-only-testing:"):i+=1;continue
   if v=="-resultBundlePath":i+=2;continue
   if v=="-scheme":argv.extend([v,scheme]);i+=2;continue
   argv.append(v);i+=1
  argv+=["-resultBundlePath",str(paired.EVIDENCE/(label+".xcresult"))]
  if scheme=="AI_HLY":argv+=["-test-timeouts-enabled","YES","-maximum-test-execution-time-allowance","600"]
  return argv+["-only-testing:"+s for s in selectors]
 def bind_products():
  rows=[]
  for name in ["HanlinMiniApps.app","AI_Hanlin.app"]:
   app=products/name;info=plistlib.loads((app/"Info.plist").read_bytes())
   members=[app/"Info.plist",app/info["CFBundleExecutable"],*app.glob("*.debug.dylib")]
   members+=list(app.rglob("RuntimeHostResources.zip"))
   for extension in app.glob("PlugIns/*.appex"):
    ep=plistlib.loads((extension/"Info.plist").read_bytes())
    members+=[extension/"Info.plist",extension/ep["CFBundleExecutable"],*extension.glob("*.debug.dylib")]
   for member in members:
    if member.name=="RuntimeHostResources.zip":assert digest(member)==state["hostArchiveSHA256"]
    rows.append({"path":str(member),"size":member.stat().st_size,"sha256":digest(member)})
  expected={"HanlinMiniAppsUITests","AI_HLYUITests","AI_HLYTests"};found=set()
  for bundle in products.rglob("*.xctest"):
   if bundle.stem not in expected:continue
   info=plistlib.loads((bundle/"Info.plist").read_bytes());found.add(bundle.stem)
   for member in [bundle/"Info.plist",bundle/info["CFBundleExecutable"],*bundle.glob("*.debug.dylib")]:
    rows.append({"path":str(member),"size":member.stat().st_size,"sha256":digest(member)})
  assert found==expected
  record={"source":SOURCE,"observedAt":utc(),"hostArchiveSHA256":state["hostArchiveSHA256"],"files":rows,
   "miniBuildProducerSource":PRODUCER_SOURCE,"aiBuildProducerSource":SOURCE,"SDKProducerSource":PRODUCER_SOURCE,
   "authenticatedMiniReuse":recovery["miniProductObservation"],"fixtureProduction":state["fixtureProduction"]}
  path=out/"built-input-bindings.json";write(path,record)
  state["builtInputBindings"]={"path":str(path),"sha256":digest(path),"count":len(rows)};save()
 def run_group(selectors,label,scheme,timeout):
  result=paired.EVIDENCE/(label+".xcresult");argv=make_test(selectors,label,scheme)
  row={"status":"RUNNING","startedAt":utc(),"selectors":selectors,"expectedTests":1,"commandTimeoutSeconds":timeout,
   "argv":argv,"resultBundle":str(result)};state["groups"][label]=row;save()
  code,_=execute(argv,label+".log",timeout=timeout,allow_failure=True)
  row.update(exitCode=code,finishedAt=utc(),resultFinalized=(result/"Info.plist").is_file())
  try:
   assert row["resultFinalized"],"Actual xcresult is not finalized"
   row["summary"]=paired.verify_native_result(result,label,selectors,1,code);row["status"]="PASS"
  except Exception as e:
   row.update(status="FAIL",error=type(e).__name__+": "+str(e));state["errors"].append(label+": "+str(e))
  for suffix,key in [("-summary.json","summarySHA256"),("-nodes.json","nodesSHA256"),("-selected-tests.log","selectorVerifierSHA256"),(".log","logSHA256")]:
   f=paired.EVIDENCE/(label+suffix)
   if f.is_file():
    row[key]=digest(f)
    if suffix=="-summary.json":row["summary"]=json.loads(f.read_text())
  save()
  if code==-1 or not row["resultFinalized"]:raise StopAfterUnfinalized("No next native command after timed out/unfinalized test")
  code,_=execute(["xcrun","xcresulttool","export","attachments","--path",str(result),"--output-path",str(out/(label+"-attachments"))],
   label+"-attachments-export.log",timeout=60,allow_failure=True)
  state.setdefault("attachmentExports",[]).append({"label":label,"result":str(result),"exitCode":code})
  if code:state["errors"].append(label+" attachment export failed")
  save()
 try:
  execute(["xcrun","simctl","boot",simulator],"boot.log")
  execute(["xcrun","simctl","bootstatus",simulator,"-b"],"bootstatus.log",timeout=300)
  a2ui=command_for("original-a2ui-generator.log");a2ui[a2ui.index("--evidence")+1]=str(paired.EVIDENCE/"original-a2ui-schemas")
  execute(a2ui,"original-a2ui-generator.log",timeout=360)
  ai_build=command_for("ai-build.log");assert ai_build[ai_build.index("-scheme")+1]=="AI_HLY"and"build-for-testing"in ai_build
  ai_build[ai_build.index("-resultBundlePath")+1]=str(paired.EVIDENCE/"AIBuild.xcresult")
  execute(ai_build,"ai-build.log",timeout=1800)
  assert (paired.EVIDENCE/"AIBuild.xcresult/Info.plist").is_file()
  verify_mini_products()
  state["originalTestBuilds"]="PASS_WITH_AUTHENTICATED_MINI_REUSE";bind_products()
  for bundle,name in [("com.itorah.chavrusachat","AI_Hanlin.app"),("com.itorah.hanlinminiapps","HanlinMiniApps.app")]:
   app=products/name;info=plistlib.loads((app/"Info.plist").read_bytes());assert info["CFBundleIdentifier"]==bundle
   execute([sys.executable,"Scripts/Runtime/validate_ios_system_resources.py","--repository-root",str(root),"--app",str(app)],
    bundle+"-ios-system-resources.json")
   execute(["codesign","--verify","--deep","--strict",str(app)],bundle+"-signature.log")
   proof=paired.read_simulator_entitlements(app/info["CFBundleExecutable"])
   ent=root/("AI_HLY/AI_HLY.entitlements"if bundle=="com.itorah.chavrusachat"else"HanlinMiniAppsApp/HanlinMiniApps.entitlements")
   required=plistlib.loads(ent.read_bytes())["com.apple.security.application-groups"]
   assert set(required).issubset(proof["entitlements"].get("com.apple.security.application-groups",[]))
   write(paired.EVIDENCE/(bundle+"-embedded-entitlements.json"),proof)
  execute(["xcrun","simctl","install",simulator,str(products/"AI_Hanlin.app")],"com.itorah.chavrusachat-install.log",timeout=300)
  groups={}
  for app in ["com.itorah.chavrusachat","com.itorah.hanlinminiapps"]:
   _,raw=execute(["xcrun","simctl","get_app_container",simulator,app,paired.GROUP],app+"-group-container.txt",timeout=5)
   groups[app]=str(Path(raw.strip()).resolve(strict=True))
  assert len(set(groups.values()))==1 and groups==prefix["app_group"]["containers"]
  state["app_group"]={"status":"EXECUTED_PASS","containers":groups}
  _,raw=execute(["xcrun","simctl","get_app_container",simulator,"com.itorah.hanlinminiapps","data"],"authoring-mini-data-container.txt",timeout=5)
  documents=Path(raw.strip()).resolve(strict=True)/"Documents"
  replacement=staged["replacement"]
  doc_rows=staged["unchanged"]+[{"name":replacement["name"],**replacement["after"]}]
  assert len(doc_rows)==11 and len({x["name"]for x in doc_rows})==11
  for row in doc_rows:
   f=documents/row["name"];assert not f.is_symlink()and f.stat().st_size==row["bytes"]and digest(f)==row["sha256"],row["name"]
  staging={**staged,"observedAt":utc(),"source":SOURCE,"documentsRoot":str(documents),
   "status":"REUSED_VERIFIED_EXACT","authority":recovery["priorStagedInputs"],"mutationPerformed":False}
  sp=out/"staged-inputs.json";write(sp,staging);state["stagedInputs"]={"path":str(sp),"sha256":digest(sp)}
  state["checkpointReached"]=True;save()
  run_group(AI,"FocusedRepair1","AI_HLY",2100)
 except BaseException as e:
  state["errors"].append(type(e).__name__+": "+str(e));(out/"wrapper-error.txt").write_text(traceback.format_exc())
 finally:
  try:
   result=subprocess.run(["xcrun","simctl","shutdown",simulator],text=True,capture_output=True,timeout=30)
   devices=json.loads(subprocess.check_output(["xcrun","simctl","list","devices","-j"],text=True,timeout=20))
   found=[x for ds in devices["devices"].values()for x in ds if x["udid"]==simulator]
   rows=subprocess.check_output(["ps","-axo","pid=,ppid=,state=,command="],text=True,timeout=10).splitlines()
   live=[x for x in rows if "/Devices/"+simulator+"/"in x and "-Runner.app/"in x and not x.split(None,3)[2].startswith("Z")]
   state["ownedSimulatorCleanup"]={"device":simulator,"ownershipPath":str(paired.EVIDENCE/"created-simulator.txt"),
    "exitCode":result.returncode,"stdout":result.stdout,"stderr":result.stderr,"state":found[0]["state"]if len(found)==1 else"UNKNOWN","remainingOwnedRunners":live}
   if len(found)!=1 or found[0]["state"]!="Shutdown"or live:state["cleanupErrors"].append("Owned simulator cleanup incomplete")
  except Exception as e:state["cleanupErrors"].append(str(e))
  for name,h in sources.items():
   if digest(root/name)!=h:state["sourceErrors"].append(name)
  if digest(root/"AI_HLY/RuntimeHostResources.zip")!=state["hostArchiveSHA256"]:state["sourceErrors"].append("Shipping Host archive changed")
  passed=all(state["groups"].get(label,{}).get("status")=="PASS"for label in ["FocusedRepair1"])
  state["status"]="FOCUSED_PASS"if passed and state["checkpointReached"]and not state["errors"]and not state["sourceErrors"]and not state["cleanupErrors"]else"FOCUSED_FAILED"
  state["phase"]=None;state["finishedAt"]=utc();save()
 return 0 if state["status"]=="FOCUSED_PASS"else 1
if __name__=="__main__":raise SystemExit(main())
