#!/usr/bin/env python3
"""Read only audit of preserved actual Mac receipts; this does not run tests."""
import hashlib,json,pathlib,re,sys,xml.etree.ElementTree as ET
BASE=pathlib.Path(__file__).resolve().parent
RAW=BASE/"raw"
def digest(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def read(p):return json.loads(p.read_text())
def require(ok,message):
 if not ok:raise RuntimeError(message)
def receipt(name):return read(RAW/"evidence"/name/"RESULT.json")
manifest=read(RAW/"RAW_MANIFEST.json")
listed={r["path"] for r in manifest["files"]}
require(len(listed)==115,"raw file inventory changed")
actual={str(p.relative_to(RAW)) for p in RAW.rglob("*") if p.is_file() and p.name!="RAW_MANIFEST.json"}
require(actual==listed,"raw file membership changed")
for row in manifest["files"]:
 p=RAW/row["path"]
 require(not p.is_symlink() and p.stat().st_size==row["bytes"] and digest(p)==row["sha256"],row["path"])
names=["archive-build-attempt03","archive-run-attempt01","archive-build-850-diagnostic01","archive-run-850-widgets01","archive-run-850-installs-repeat01"]
records={n:receipt(n) for n in names}
a,old,b,new,repeat=[records[n] for n in names]
oldsha="1abcc4749056d4c1c364f378732e137e7fead8b3"
product="850de66432fc872d349469a2a63aaa564c61f0a8"
for n,r in records.items():
 require(r["source_unchanged"] is True and r["source_before"]==r["source_after"],n+" source changed")
 require(r["source_sha"]==(oldsha if n in names[:2] else product),n+" source binding")
 require(r["dependency_checkouts"]==a["dependency_checkouts"],n+" dependency change")
 require(r["swift"]==a["swift"] and r["xcode"]==a["xcode"],n+" toolchain change")
 require(all(x["tracked_source_clean"] for x in r["dependency_checkouts"]),n+" dirty dependency")
require(len(a["dependency_checkouts"])==6,"dependency inventory changed")
require(a["status"]==b["status"]=="ORIGINAL_BUILD_COMPLETE_PENDING_TESTS","build receipt mismatch")
require(old["status"]=="FAILED" and old["tests_executed"]==0,"preserve original failure/default count")
require(new["status"]=="ORIGINAL_WIDGET_REGRESSION_12_PASS","widget run did not pass")
require(repeat["status"]=="ORIGINAL_INSTALLATION_CONTINUATION_5_PASS","installation repeat did not pass")
require(new["build_receipt_sha256"]==repeat["build_receipt_sha256"]==digest(RAW/"evidence/archive-build-850-diagnostic01/RESULT.json"),"wrong current build")
require(old["build_receipt_sha256"]==digest(RAW/"evidence/archive-build-attempt03/RESULT.json"),"wrong historical build")
oldmanifest=read(RAW/"evidence/archive-run-attempt01/SOURCE_MANIFEST.json")
newmanifest=read(RAW/"evidence/archive-run-850-widgets01/SOURCE_MANIFEST.json")
am={x["path"]:x for x in oldmanifest["files"]};bm={x["path"]:x for x in newmanifest["files"]}
reused=[p for p in am if p.startswith("Packages/") and ("/Sources/" in p or "/Tests/HanlinScriptCompilerTests/" in p or p.endswith("/Package.swift") or p.endswith("/Package.resolved"))]
require(len(reused)>100,"reused source closure too small")
require(all(am[p]==bm.get(p) for p in reused),"compiler runtime source input changed")
def compiler_binary(r):
 out=[x for x in r["actual_test_binaries"] if "/HanlinScriptCompilerTests.xctest/" in x["path"]]
 require(len(out)==1,"compiler executable inventory")
 return out[0]
require(compiler_binary(a)==compiler_binary(b),"reused compiler executable bytes changed")
require(compiler_binary(a)["sha256"]=="8878393d9ff8b8ee35d60e538f07e40ddf9d9cdacb34ccadfef3e727d6aa423b","unexpected compiler executable")
osel=read(RAW/"evidence/archive-run-attempt01/SOURCE_SELECTION.json")
nsel=read(RAW/"evidence/archive-run-850-widgets01/SOURCE_SELECTION.json")
compiler=[x for x in osel if x["module"]=="HanlinScriptCompilerTests"]
require(len(compiler)==15 and compiler==[x for x in nsel if x["module"]=="HanlinScriptCompilerTests"],"compiler oracle selection changed")
expected={(x["module"]+"."+x["suite"],x["signature"]) for x in compiler}
require(len(expected)==15,"duplicate method")
root=ET.parse(RAW/"evidence/archive-run-attempt01/archive-swift-testing.xml").getroot()
actual_cases=[];original_failures=0
for suite in root.findall("testsuite"):
 original_failures+=int(suite.attrib["failures"])
 chosen=[x for x in suite.findall("testcase") if x.attrib["classname"].startswith("HanlinScriptCompilerTests.")]
 if chosen:
  require(all(int(suite.attrib[k])==0 for k in ["errors","failures","skipped"]),"compiler suite failure")
  require(len(chosen)==int(suite.attrib["tests"]),"mixed compiler suite")
  for case in chosen:
   require(not list(case),"compiler case has failure/error/skip payload")
   actual_cases.append((case.attrib["classname"],case.attrib["name"]))
require(len(actual_cases)==15 and set(actual_cases)==expected,"original XML method inventory changed")
require(original_failures==5,"original failed widget history must remain intact")
log=(RAW/"evidence/archive-run-attempt01/run.log").read_text()
require("Test run with 15 tests in 2 suites passed" in log,"missing original compiler run summary")
invocations=[]
for c in compiler:
 display=c["display"] if c["arguments"] else '"'+c["display"]+'"'
 if c["arguments"]:
  require(c["signature"]=="rejectsEscapingPaths(path:)","unknown parameter method")
  require(c["arguments"]==["../script.json","/script.json","C:/script.json","folder/../../script.json"],"escaping inputs changed")
  for arg in c["arguments"]:
   needle='path \u2192 "'+arg+'" to '+c["signature"]+' started.'
   require(log.count(needle)==1,"missing/duplicate original parameter "+arg)
  require(log.count("Test rejectsEscapingPaths(path:) with 4 test cases passed")==1,"parameter aggregate not passed")
 else:
  require(log.count("Test "+display+" passed after")==1,"original method not passed "+c["method"])
 for arg in c["arguments"] or [None]:
  invocations.append({"class":c["module"]+"."+c["suite"],"method":c["signature"],"argument":arg,"status":"Passed","evidence":"original compiler bundle XML+log at "+oldsha,"reuse":"byte-identical complete original test executable; unchanged source closure and six native dependency checkouts"})
require(len(invocations)==18,"wrong compiler invocation count")
widget_selection=[x for x in nsel if x["module"]=="HanlinScriptExtensionsTests"]
expected_widgets={(x["module"]+"."+x["suite"],x["signature"],arg) for x in widget_selection for arg in x["arguments"]}
require(len(expected_widgets)==12,"widget selection changed")
for n,r,count in [(names[3],new,12),(names[4],repeat,5)]:
 require(r["tests_started"]==r["tests_executed"]==r["verified_passed_invocations"]==count,n+" invocation count")
 rows=r["runtime"]["invocations"]
 actual_set={(x["class"],x["method"],x["argument"]) for x in rows}
 allowed=expected_widgets if count==12 else {x for x in expected_widgets if x[1]=="installAndVerifiedLoader(name:)"}
 require(len(rows)==count and actual_set==allowed and all(x["status"]=="Passed" for x in rows),n+" runtime results")
 xml=ET.parse(RAW/"evidence"/n/"archive-swift-testing.xml").getroot()
 cases=[]
 for suite in xml.findall("testsuite"):
  require(all(int(suite.attrib[k])==0 for k in ["errors","failures","skipped"]),n+" XML failure")
  for case in suite.findall("testcase"):
   require(not list(case),n+" XML child failure")
   cases.append((case.attrib["classname"],case.attrib["name"]))
 require(set(cases)=={x[:2] for x in allowed} and len(cases)==(2 if count==12 else 1),n+" XML methods")
 for row in r["runtime"]["original_widget_receipts"]+r["runtime"]["xml_results"]:
  require(digest(RAW/"evidence"/n/row["path"])==row["sha256"],n+" output hash")
 for key in ["maktabah_live_credit","ordinary_app_ui_credit","springboard_credit"]:require(r["runtime"][key] is False,n+" scope")
invocations += [dict(x,evidence="actual native widget run at "+product) for x in new["runtime"]["invocations"]]
require(len(invocations)==30 and len({(x["class"],x["method"],x["argument"]) for x in invocations})==30,"double-counted original invocation")
graph=receipt("graph-check-850de664");g=json.loads(graph["output"])
require(graph["status"]=="PASS" and graph["source"]==product and graph["command"]["exit"]==0,"graph failed")
require(g["applicationSourceCount"]==523 and g["targets"]==114 and g["localPackageEdgesRemaining"]==0,"graph shape")
result={
 "schema":1,"qualification":"30 unique original archive invocations qualified:18 byte-identical compiler invocations reused from actual original run plus12 actual widget invocations on final source",
 "source":product,"core":"abf0921c6e89e6521cc2b510ff11016b45a0ef08","zipfoundation_version":"0.9.20","zipfoundation_revision":"22787ffb59de99e5dc1fbfe80b19c97a904ad48d",
 "unique_methods":17,"unique_invocations_passed":30,"additional_original_installation_repeat_invocations":5,
 "reused_original_compiler":{"source":oldsha,"methods":15,"invocations":18,"unchanged_relevant_source_files":len(reused),"unchanged_inputs":reused,"unchanged_test_binary":compiler_binary(a),"six_dependency_checkouts":a["dependency_checkouts"]},
 "invocations":invocations,"additional_repeat":repeat["runtime"]["invocations"],
 "historical_failure":{"whole_run_status":"FAILED","widget_issues":5,"raw_default_tests_executed_field":0,"explanation":"Original controller left tests_executed at its failure default; raw XML and log explicitly retain actual18 compiler passes and5 widget issues. This audit does not relabel that whole run as successful.","actions_issue":"One original ScriptWidget-Actions prepare failure was not reproducible in two subsequent original installation processes. Diagnostic reason is now retained, but its earlier cause is not claimed identified or fixed."},
 "canonical_graph":{"application_source_files":523,"targets":114,"remaining_local_package_edges":0},
 "raw_manifest_sha256":digest(RAW/"RAW_MANIFEST.json"),
 "result_receipts":[{"path":str((RAW/"evidence"/n/"RESULT.json").relative_to(BASE)),"sha256":digest(RAW/"evidence"/n/"RESULT.json")} for n in names+["graph-check-850de664","source-retarget-850de664"]],
 "scope":{"native_macos_original_archive_regression":True,"app_build":False,"maktabah_ui_live":False,"ios_expo_widget_raster":False,"sdk_native_acceptance":False,"testflight":False}
}
out=BASE/"QUALIFICATION.json";out.write_text(json.dumps(result,indent=2,ensure_ascii=True)+"\n")
print(json.dumps({"qualification":result["qualification"],"sha256":digest(out),"unchanged_relevant_source_files":len(reused),"raw_files":len(listed)}))
