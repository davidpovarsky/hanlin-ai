"""Diagnostic-only execution around the unchanged original paired acceptance prefix.
Original 52-case acceptance is never executed or claimed by this wrapper.
No product or test source is mutated.
"""
from pathlib import Path
import argparse, datetime, hashlib, importlib.util, json, os, shutil, signal, subprocess, sys, threading, time, traceback

parser=argparse.ArgumentParser()
parser.add_argument("--source",required=True)
parser.add_argument("--output",required=True)
args=parser.parse_args()
ROOT=Path.cwd().resolve()
OUT=Path(args.output).resolve()
OUT.mkdir(parents=True,exist_ok=False)
sys.path.insert(0,str(ROOT/"Scripts/ProductSplit"))
spec=importlib.util.spec_from_file_location("original_paired_acceptance",ROOT/"Scripts/ProductSplit/run_paired_acceptance.py")
paired=importlib.util.module_from_spec(spec);spec.loader.exec_module(paired)
observer_spec=importlib.util.spec_from_file_location("diagnostic_observer",Path(__file__).with_name("diagnostic-observer-attempt12.py"))
observations=importlib.util.module_from_spec(observer_spec);observer_spec.loader.exec_module(observations)
paired.EVIDENCE=OUT/"paired-prefix"
UI=ROOT/"HanlinMiniAppsUITests/HanlinMiniAppsUITests.swift"
RUNNER=ROOT/"Scripts/ProductSplit/run_paired_acceptance.py"
original_ui=UI.read_bytes()
original_runner=RUNNER.read_bytes()
def sha(data):return hashlib.sha256(data).hexdigest()
def utc():return datetime.datetime.now(datetime.timezone.utc).isoformat()
def git(*argv):return subprocess.check_output(["git",*argv],cwd=ROOT).decode().strip()
if git("rev-parse","HEAD")!=args.source:raise RuntimeError("Diagnostic source differs from published source")
for rel,raw in [(UI.relative_to(ROOT),original_ui),(RUNNER.relative_to(ROOT),original_runner)]:
 if subprocess.check_output(["git","show",args.source+":"+str(rel)],cwd=ROOT)!=raw:
  raise RuntimeError("Original diagnostic input is not exact committed source: "+str(rel))
(OUT/"inputs").mkdir()
(OUT/"inputs/HanlinMiniAppsUITests.original.swift").write_bytes(original_ui)
state={"owner":"/root/native_execution","schema":1,"source":args.source,"tree":git("rev-parse","HEAD^{tree}"),
 "startedAt":utc(),"pid":os.getpid(),"status":"RUNNING","phase":"original-build-install-fixture-prefix",
 "scope":"One original Modular selector on the exact published original Expo fixture and UI source; fresh container. Prior passing parity and SDK-only cases are not rerun.",
 "original52":"NOT_RUN","original25":"NOT_RUN","original27":"NOT_RUN",
 "original52RequiresIndependentRun":True,
 "uiSource":{"path":str(UI.relative_to(ROOT)),"originalSHA256":sha(original_ui),
 "delta":"No source variant. Exact published child interaction, explicit Disclosure state, entry/version-scoped API text and original Host locale remount."},
 "originalRunner":{"path":str(RUNNER.relative_to(ROOT)),"sha256":sha(original_runner),"unchanged":True},
 "errors":[],"cases":{},"sourceRestored":True,"originalTestRebuild":"NOT_RUN"}
started=time.monotonic()
def save():
 state["observedAt"]=utc();state["elapsedSeconds"]=time.monotonic()-started
 temp=OUT/"state.json.tmp";temp.write_text(json.dumps(state,indent=2)+"\n");temp.replace(OUT/"state.json")
 print(json.dumps({k:state.get(k) for k in ["observedAt","status","phase","elapsedSeconds","sourceRestored","originalTestRebuild"]}),flush=True)
save()
original_command=paired.command
def execute(argv,name,timeout=60,allow_failure=False):
 state["phase"]=name;save()
 return original_command(argv,name,timeout=timeout,allow_failure=allow_failure)

prefix="HanlinMiniAppsUITests/MiniAppsProductionRuntimeUITests/"
modular=[prefix+"testStandaloneModularSearchLoadsActualSefariaText"]
state["selectors"]={"modular":modular}
state["hostArchiveSHA256"]=sha((ROOT/"AI_HLY/RuntimeHostResources.zip").read_bytes())
state["observerSHA256"]=sha(Path(__file__).with_name("diagnostic-observer-attempt12.py").read_bytes())
if state["hostArchiveSHA256"]!="86733eba5d80156edf52da87f0f371c208122d6e60f618f182990330514984c3":raise RuntimeError("Prepared SDK10 Host identity changed")
modular_source=ROOT/"Scripts/Expo/miniapps/modular-text-search/App.tsx"
modular_raw=modular_source.read_bytes()
if sha(modular_raw)!="4e8389eb6a232e6ed5db8273dd2686e45ab04edabd2e86bfea74cbdf862e5b7c":raise RuntimeError("Published Modular fixture source differs")
if subprocess.check_output(["git","show",args.source+":"+str(modular_source.relative_to(ROOT))],cwd=ROOT)!=modular_raw:raise RuntimeError("Modular fixture is not exact committed source")
state["modularSource"]={"path":str(modular_source.relative_to(ROOT)),"sha256":sha(modular_raw),"scope":"Actual original CLI build/import below uses preserved SDK10; runtime screenshots retain search orientation and detail/fulltext behavior."}
observer=None
container=None
simulator=None
result_bundles=[]
checkpoint_reached=False
class DiagnosticCheckpoint(BaseException):pass
class DiagnosticCancellation(BaseException):pass
def terminate_owned(signum,frame):
 raise DiagnosticCancellation("Owned continuation cancellation; restore source and stop owned subprocesses")
signal.signal(signal.SIGTERM,terminate_owned)

def testcase_argv(original,selectors,result,action="test-without-building"):
 argv=[];i=0
 while i<len(original):
  value=original[i]
  if value.startswith("-only-testing:"):i+=1;continue
  if value=="-resultBundlePath":i+=2;continue
  argv.append(action if value=="test-without-building" else value);i+=1
 argv+=["-resultBundlePath",str(result)]
 if action=="test-without-building":argv+=["-only-testing:"+selector for selector in selectors]
 return argv

def ui_binary_identity(label):
 derived=Path(os.environ["SPLIT_DERIVED_DATA"])/"Build/Products/Debug-iphonesimulator"
 rows=[]
 for bundle in sorted(derived.glob("*UITests-Runner.app/PlugIns/*.xctest")):
  if bundle.stem!="HanlinMiniAppsUITests":continue
  executable=bundle/bundle.stem
  if executable.is_file():
   raw=executable.read_bytes();rows.append({"path":str(executable),"bytes":len(raw),"sha256":sha(raw)})
 state.setdefault("testBinaries",{})[label]=rows
 if not rows:raise RuntimeError("Built original MiniApps UI test binary was not located")
 save()

def current_case():
 for name,case in state["cases"].items():
  if case.get("status")=="RUNNING":return name
 return state.get("phase")

def export_result(result,label):
 if not result.exists():return
 code,_=execute(["xcrun","xcresulttool","export","attachments","--path",str(result),
  "--output-path",str(OUT/(label+"-attachments"))],label+"-attachments-export.log",timeout=60,allow_failure=True)
 state.setdefault("attachmentExports",[]).append({"result":str(result),"exit":code})
 markers=[];pattern=("HANLIN_IMPORT_","HANLIN_NS_","HANLIN_EXPO_","NativeScript script execution failed","[runtime not ready]","Unhandled JS Exception")
 for path in sorted(result.rglob("StandardOutputAndStandardError-com.itorah.hanlinminiapps.txt")):
  with path.open(errors="replace") as stream:
   for index,line in enumerate(stream,1):
    if any(token in line for token in pattern):
     markers.append({"file":str(path.relative_to(result)),"line":index,"text":line.rstrip()})
 (OUT/(label+"-runtime-markers.json")).write_text(json.dumps(markers,indent=2)+"\n")
 state.setdefault("runtimeMarkers",{})[label]={"count":len(markers),"path":label+"-runtime-markers.json"}
 save()

def run_case_group(original,selectors,label,timeout):
 result=paired.EVIDENCE/(label+".xcresult")
 result_bundles.append((result,label))
 case={"status":"RUNNING","startedAt":utc(),"selectors":selectors,"originalUI":UI.read_bytes()==original_ui}
 state["cases"][label]=case;save()
 code,_=execute(testcase_argv(original,selectors,result),label+".log",timeout=timeout,allow_failure=True)
 case.update(exitCode=code,finishedAt=utc())
 case["resultFinalized"]=(result/"Info.plist").is_file()
 try:
  case["summary"]=paired.verify_native_result(result,label,selectors,len(selectors),code)
  case["status"]="PASS"
 except Exception as error:
  case.update(status="FAIL",error=str(error));state["errors"].append(label+": "+str(error))
 log=paired.EVIDENCE/(label+".log")
 if log.is_file():
  raw=log.read_bytes();case["log"]={"path":str(log),"bytes":len(raw),"sha256":sha(raw)}
 save()

def focused_checkpoint(original):
 global checkpoint_reached,container,simulator,observer
 checkpoint_reached=True
 if UI.read_bytes()!=original_ui or RUNNER.read_bytes()!=original_runner:
  raise RuntimeError("Published runner/test source drift before focused execution")
 original_selectors=[arg.removeprefix("-only-testing:") for arg in original if arg.startswith("-only-testing:")]
 if len(original_selectors)!=25:raise RuntimeError("Original runner did not request the unchanged25-case scope")
 if "-collect-test-diagnostics" not in original or original[original.index("-collect-test-diagnostics")+1]!="never":
  raise RuntimeError("Reviewed original verbose-diagnostics selection is absent")
 state["interceptedOriginal25Selectors"]=original_selectors
 (OUT/"intercepted-original-command.json").write_text(json.dumps({"argv":original,"executed":False,
  "reason":"Separate focused diagnostic; original25+27 must run afterward."},indent=2)+"\n")
 container=Path((paired.EVIDENCE/"authoring-mini-data-container.txt").read_text().strip())
 state["dataContainer"]=str(container)
 simulator=(paired.EVIDENCE/"created-simulator.txt").read_text().strip();state["simulator"]=simulator
 derived=Path(os.environ["SPLIT_DERIVED_DATA"])/"Build/Products/Debug-iphonesimulator"
 state["installedMetadataBinding"]=observations.bind_metadata(ROOT,OUT,derived,simulator,args.source)
 ui_binary_identity("exactPublishedSource")
 state["originalTestRebuild"]="PASS"
 observer=observations.Observer(ROOT,OUT,simulator,container,state["hostArchiveSHA256"],current_case)
 state["runtimeObserver"]=observer.start();save()
 run_case_group(original,modular,"ModularFocusedDiagnostic",600)
 case=state["cases"]["ModularFocusedDiagnostic"]
 if case.get("exitCode")==-1 or not case.get("resultFinalized"):
  state["errors"].append("Modular command timed out or has no finalized result; no further native command launched.")
  save();raise DiagnosticCheckpoint()
 export_result(*result_bundles[-1])
 raise DiagnosticCheckpoint()

def hooked(argv,name,timeout=60,allow_failure=False):
 if name=="original-runtimes.log":focused_checkpoint(argv)
 return execute(argv,name,timeout,allow_failure)
paired.command=hooked
try:
 result=paired.main()
 state["errors"].append("Original setup stopped before diagnostic checkpoint; inspect paired-prefix state/logs.")
 state["prefixExit"]=result
except DiagnosticCheckpoint:
 pass
except BaseException as error:
 state["errors"].append(type(error).__name__+": "+str(error))
 (OUT/"wrapper-error.txt").write_text(traceback.format_exc())
finally:
 if observer is not None:state["runtimeObserver"]=observer.stop()
 if UI.read_bytes()!=original_ui:
  state["errors"].append("Unexpected source drift; no restoration or source mutation attempted.")
  state["originalTestRebuild"]="REQUIRED"
 state["sourceRestored"]=UI.read_bytes()==original_ui
 state["originalRunner"]["unchanged"]=RUNNER.read_bytes()==original_runner
 source_state=paired.EVIDENCE/"acceptance.json"
 if source_state.is_file():
  # Preserve original main's partial-state bytes verbatim, never present it as52-case acceptance.
  source_state.rename(paired.EVIDENCE/"original-prefix-state.json")
 state["checkpointReached"]=checkpoint_reached
 if simulator:
  try:
   check=subprocess.run(["xcrun","simctl","list","devices","-j"],capture_output=True,text=True,timeout=20)
   devices=[d for group in json.loads(check.stdout)["devices"].values() for d in group]
   owned=next(d for d in devices if d["udid"]==simulator)
   process_rows=subprocess.check_output(["ps","-axo","pid=,ppid=,stat=,command="],text=True).splitlines()
   remaining=[row for row in process_rows if "/Devices/"+simulator+"/" in row and "-Runner.app/" in row]
   state["ownedSimulatorCleanup"]={"simulator":simulator,"state":owned["state"],"remainingOwnedRunners":remaining}
   if owned["state"]!="Shutdown" or remaining:
    state["errors"].append("Owned simulator/runner cleanup incomplete; no further native action may start without diagnosis.")
  except Exception as error:
   state["errors"].append("Unable to confirm owned simulator cleanup: "+str(error))
 state["status"]="DIAGNOSTIC_COMPLETE" if checkpoint_reached and not state["errors"] and state["sourceRestored"] and state["originalTestRebuild"]=="PASS" else "DIAGNOSTIC_FAILED"
 state["finishedAt"]=utc();state["phase"]=None;save()
sys.exit(0 if state["status"]=="DIAGNOSTIC_COMPLETE" else 1)
