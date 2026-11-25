from pathlib import Path
import hashlib,itertools,json,re,subprocess,yaml
ROOT=Path(__file__).resolve().parents[4]
OUT=Path(__file__).resolve().parent
BASE="58306a098611d3691904f2a37a61b72634f48c6a"
CALLER=".github/workflows/validate-app-split.yml"
CALLEE=".github/workflows/validate-scripting-runtime.yml"
old_text=subprocess.check_output(["git","show",BASE+":"+CALLER],cwd=ROOT,text=True)
new_text=(ROOT/CALLER).read_text()
old=yaml.load(old_text,Loader=yaml.BaseLoader)
new=yaml.load(new_text,Loader=yaml.BaseLoader)
callee=yaml.load((ROOT/CALLEE).read_text(),Loader=yaml.BaseLoader)
assert isinstance(new["on"],dict) and "workflow_dispatch" in new["on"]
assert len(old["on"]["workflow_dispatch"]["inputs"])==10==len(new["on"]["workflow_dispatch"]["inputs"])
for event in ["workflow_call","workflow_dispatch"]:
    a=json.loads(json.dumps(old["on"][event]["inputs"]));b=new["on"][event]["inputs"]
    a["paired_test_scope"]["description"]=b["paired_test_scope"]["description"]
    if event=="workflow_dispatch":
        assert b["paired_test_scope"]["options"]==a["paired_test_scope"]["options"]+["miniapp_contracts"]
        a["paired_test_scope"]["options"]=b["paired_test_scope"]["options"]
    assert a==b
assert old["concurrency"]==new["concurrency"]
assert old["permissions"]==new["permissions"]==callee["permissions"]
assert set(new["jobs"])==set(old["jobs"])|{"miniapp-contracts"}
for name in ["register-original-product","release-resource-audit"]:
    assert old["jobs"][name]==new["jobs"][name]
old_app=dict(old["jobs"]["miniapps"]);new_app=dict(new["jobs"]["miniapps"])
old_if=old_app.pop("if");new_if=new_app.pop("if")
assert old_app==new_app
assert old_text.split("  miniapps:\n",1)[1].split("\n",1)[1]==new_text.split("  miniapps:\n",1)[1].split("\n",1)[1]
job=new["jobs"]["miniapp-contracts"]
assert job["uses"]=="./"+CALLEE and job["secrets"]=="inherit"
assert set(job["with"])==set(callee["on"]["workflow_call"]["inputs"])
assert job["with"]["runtime_job_foundation_only"]=="false"
assert job["with"]["force_clean_build"]=="true"
expected=json.loads((ROOT/"docs/miniapp-sdk/evidence/sdk02-sdk06-contracts-20261124/gap-map.json").read_text())["appleExecutionPlan"]["inputs"]["test_filter"]
assert job["with"]["test_filter"]==expected
methods=expected.split("/(",1)[1][:-1].split("|");assert len(methods)==8
tests=(ROOT/"Packages/HanlinPlatform/Tests/HanlinScriptCompilerTests/HanlinScriptAnalyzerTests.swift").read_text()
for method in methods: assert re.search(r"\bfunc\s+"+re.escape(method)+r"\s*\(",tests)
assert (ROOT/CALLEE).read_bytes()==subprocess.check_output(["git","show",BASE+":"+CALLEE],cwd=ROOT)
def evaluate(expression,inputs):
    expression=expression.strip()
    if expression.startswith("$"+"{{"): expression=expression[3:-2].strip()
    expression=re.sub(r"inputs\.([A-Za-z0-9_]+)",lambda m:"values["+repr(m.group(1))+"]",expression)
    expression=expression.replace("&&"," and ").replace("||"," or ")
    expression=re.sub(r"!(?!=)"," not ",expression)
    return eval(expression.strip(),{"__builtins__":{}},{"values":inputs,"format":lambda value,*args:value.format(*args)})
flags=["prepare_miniapps_registration","audit_release_resources","signed_release_archives","signing_preflight_only","paired_product_acceptance"]
scopes=old["on"]["workflow_dispatch"]["inputs"]["paired_test_scope"]["options"]+[""]
unchanged=0
for values in itertools.product([False,True],repeat=len(flags)):
    for scope in scopes:
        data=dict(zip(flags,values));data["paired_test_scope"]=scope
        assert evaluate(old_if,data)==evaluate(new_if,data)
        assert not evaluate(job["if"],data)
        unchanged+=1
new_modes=[]
for paired in [False,True]:
    for registration,audit in itertools.product([False,True],repeat=2):
        data=dict.fromkeys(flags,False)
        data.update(paired_product_acceptance=paired,prepare_miniapps_registration=registration,audit_release_resources=audit,paired_test_scope="miniapp_contracts")
        app=bool(evaluate(new_if,data));contracts=bool(evaluate(job["if"],data))
        assert app==bool(evaluate(old_if,data) and not paired)
        assert contracts==bool(paired and not registration and not audit)
        assert not(app and contracts)
        new_modes.append({"paired":paired,"registration":registration,"audit":audit,"miniapps":app,"contracts":contracts})
group_expression=new["concurrency"]["group"].rsplit("$"+"{{",1)[1].split("}}",1)[0].strip()
data=dict.fromkeys(flags,False);data.update(paired_product_acceptance=True,native_test_scope="baseline")
groups={}
for scope in ["miniapp_authoring","miniapp_contracts"]:
    data["paired_test_scope"]=scope
    groups[scope]=evaluate(group_expression,data)
assert groups=={"miniapp_authoring":"paired-miniapp_authoring","miniapp_contracts":"paired-miniapp_contracts"}
receipt={
 "schemaVersion":1,"status":"SOURCE_CHECKS_PASS","baseSourceSHA":BASE,
 "caller":{"path":CALLER,"sha256":hashlib.sha256((ROOT/CALLER).read_bytes()).hexdigest()},
 "callee":{"path":CALLEE,"sha256":hashlib.sha256((ROOT/CALLEE).read_bytes()).hexdigest(),"unchanged":True,"reference":"local ./ path at caller commit"},
 "workflowDispatchInputCount":10,"unchangedExistingModeCombinations":unchanged,
 "newModeTruthTable":new_modes,"scopeGroupSuffixes":groups,
 "concurrencyAndCancelInProgressUnchanged":True,"permissionsUnchanged":True,
 "existingMainJobBodyByteIdentical":True,"registrationAndAuditJobsUnchanged":True,
 "secretsConvention":"inherit, matching existing focused-scripting-package-tests caller",
 "selectedMethods":methods,"expectedExecutedMethods":8,
 "checks":"YAML parsing with BaseLoader, exact source/body/input comparisons and evaluation of the actual job/group expressions. No runtime tests.",
 "notEstablished":["GitHub service acceptance/dispatch","native compilation or method execution","app UI acceptance"],
 "rootPreflightReceiptSHA256":hashlib.sha256((OUT/"root-preflight.json").read_bytes()).hexdigest()
}
(OUT/"source-validation.json").write_text(json.dumps(receipt,indent=2)+"\n")
print(json.dumps({"status":receipt["status"],"dispatchInputs":10,"unchangedExistingModes":unchanged,"newModeCombinations":len(new_modes),"groupSuffixes":groups,"expectedMethods":8,"calleeUnchanged":True,"mainJobBodyByteIdentical":True},indent=2))
