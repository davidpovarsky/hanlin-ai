import pathlib,json,hashlib,subprocess,datetime,shutil,time,os,xml.etree.ElementTree as ET
R=pathlib.Path("/Users/m1/builds/hanlin-miniapps-current-catalog-20261125");E=R/"evidence";H=R/"host-harness"
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def utc():return datetime.datetime.now(datetime.timezone.utc).isoformat()
def write(name,obj):
 p=E/name
 with p.open("w") as f:json.dump(obj,f,sort_keys=True,indent=2);f.write("\n");f.flush();os.fsync(f.fileno())
def source():
 m=json.loads((R/"source-manifest.json").read_text());bad=[]
 for rel,v in m["files"].items():
  p=R/"source"/rel
  if not p.is_file() or sha(p)!=v["sha256"]:bad.append(rel)
 if bad:raise RuntimeError("Source changed: "+repr(bad))
 for n in ["HanlinTransientToolCatalogTests.swift","HanlinCatalogReloadCancellationTests.swift"]:
  if sha(H/"Tests/HanlinChatCoreTests"/n)!=sha(R/"source/Packages/HanlinPlatform/Tests/HanlinChatCoreTests"/n):raise RuntimeError("Original test changed")
 return {"manifest_sha256":sha(R/"source-manifest.json"),"files":len(m["files"]),"harness_sha256":sha(H/"Package.swift"),"source_commit":m["source_commit"]}
def pins():
 return {p["identity"]:p["state"]["revision"] for p in json.loads((H/"Package.resolved").read_text())["pins"]}
expected={"swift-ai-sdk":"3f38f1302764635c9991d0d00fd7b12471a5373c","swift-argument-parser":"6a52f3251125d74daf04fcbd5e6f08a75d074382","swiftyjson":"b3dcd7dbd0d488e1a7077cb33b00f2083e382f07","zipfoundation":"02b6abe5f6eef7e3cbd5f247c5cc24e246efcfe0"}
assert pins()==expected
before=source();free=shutil.disk_usage(R).free
if free<1_200_000_000:raise RuntimeError("Actual phase cannot fit estimated0.9GB plus bounded observations")
cmd=["xcrun","swift","test","--package-path",str(H),"--scratch-path",str(R/"host-build"),"--cache-path",str(R/"host-cache"),"--force-resolved-versions","--skip-update","--verbose","-j","1","--disable-xctest","--enable-swift-testing","--no-parallel","--filter","(HanlinTransientToolCatalogTests|HanlinCatalogReloadCancellationTests)","--xunit-output",str(E/"current.xml")]
report={"schema":"hanlin.current-catalog-regressions/1","status":"RUNNING","started_utc":utc(),"source_before":before,"dependency_pins_before":pins(),"command":cmd,"controller_sha256":sha(pathlib.Path(__file__)),"toolchain":subprocess.check_output(["xcrun","swift","--version"],text=True).strip(),"provider_is_mock_fetch":True,"app_builds":0,"simulator_creations":0,"native_app_acceptance_credit":False,"free_bytes_before":free,"capacity_observations":[]}
with (E/"current.log").open("wb") as log:
 p=subprocess.Popen(cmd,stdout=log,stderr=subprocess.STDOUT,cwd=R)
 report["pid"]=p.pid;write("active.json",report)
 while p.poll() is None:
  available=shutil.disk_usage(R).free
  report["capacity_observations"].append({"time_utc":utc(),"free_bytes":available})
  if available<350_000_000:
   p.terminate();report["interrupted_reason"]="Actual remaining disk below bounded compiler/log safety allowance"
  try:p.wait(timeout=12)
  except subprocess.TimeoutExpired:pass
 rc=p.wait()
report["exit_code"]=rc;report["source_after"]=source();report["dependency_pins_after"]=pins();report["finished_utc"]=utc();report["free_bytes_after"]=shutil.disk_usage(R).free
report["log_sha256"]=sha(E/"current.log")
cases=[]
if (E/"current.xml").exists():
 report["xunit_sha256"]=sha(E/"current.xml")
 xml=ET.parse(E/"current.xml")
 for c in xml.iter("testcase"):cases.append({"classname":c.attrib.get("classname"),"name":c.attrib.get("name"),"failure_count":len(c.findall("failure"))+len(c.findall("error")),"skipped":len(c.findall("skipped"))})
report["cases"]=cases
expectedcases={("HanlinChatCoreTests.HanlinCatalogReloadCancellationTests","cancellationDuringFinalCatalogLookupStopsBeforeAnotherProviderStep()"),("HanlinChatCoreTests.HanlinTransientToolCatalogTests","restoredCatalogContinuesTheOriginalEmptyToolResult()")}
observed={(c["classname"],c["name"]) for c in cases}
report["status"]="ACTUAL_CURRENT_TWO_METHODS_PASS" if rc==0 and observed==expectedcases and len(cases)==2 and all(c["failure_count"]==0 and c["skipped"]==0 for c in cases) and report["dependency_pins_after"]==expected and report["source_before"]==report["source_after"] else "FAILED"
write("result.json",report);write("active.json",report)
print(json.dumps({k:v for k,v in report.items() if k not in {"capacity_observations","command"}}))
raise SystemExit(0 if report["status"]=="ACTUAL_CURRENT_TWO_METHODS_PASS" else 1)
