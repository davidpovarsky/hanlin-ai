#!/usr/bin/env python3
"""Actual Apple acceptance for the owned, isolated Yams update demonstration."""
import hashlib,json,os,pathlib,re,subprocess,sys,tempfile
import importlib.util
spec=importlib.util.spec_from_file_location("swiftpm_pin",pathlib.Path(__file__).with_name("verify-swiftpm-pin.py"));pin_validator=importlib.util.module_from_spec(spec);spec.loader.exec_module(pin_validator)
REPO,NUMBER=sys.argv[1:3]
if not re.fullmatch(r"[\w.-]+/[\w.-]+",REPO) or not NUMBER.isdigit(): raise SystemExit("Invalid repository/PR")
ROOT=pathlib.Path.cwd(); OUT=ROOT/"build/upstream-updates"; OUT.mkdir(parents=True,exist_ok=True)
PACKAGE="Packages/HanlinSkillFormat"; OWNER="485933ba56952b4aef1363b88e5b4bc33bb2b94c"
VERSIONS={"6.2.1":"deaf82e867fa2cbd3cd865978b079bfcf384ac28","6.2.2":"a27b21e0c81c5bf42049b897a62aaf387e80f279"}
def call(args,**kw): return subprocess.check_output(args,**kw)
def api(path): return json.loads(call(["gh","api",f"repos/{REPO}/{path}"]))
pr=api(f"pulls/{NUMBER}"); head=call(["git","rev-parse","HEAD"],text=True).strip(); base=pr["base"]["sha"]
if pr["head"]["sha"]!=head or pr["head"]["repo"]["full_name"]!=REPO: raise SystemExit("Actual candidate HEAD/repository mismatch")
files=api(f"pulls/{NUMBER}/files?per_page=100"); paths=sorted(f["filename"] for f in files)
allowed={PACKAGE+"/Package.swift",PACKAGE+"/Package.resolved"}
if not paths or len(paths)!=pr["changed_files"] or not set(paths)<=allowed: raise SystemExit("Unscoped SwiftPM candidate")
subprocess.run(["git","fetch","--no-tags","origin",base,OWNER],check=True)
def tree(ref):
 data=call(["git","ls-tree","-r",ref,"--",PACKAGE],text=True)
 return {row.split("\t",1)[1]:row.split()[2] for row in data.splitlines()}
owned=tree(OWNER); current=tree(head); prior=tree(base)
if set(owned)!=set(current) or set(current)!=set(prior): raise SystemExit("Package file set drift")
for path,sha in owned.items():
 if path not in allowed and (current[path]!=sha or prior[path]!=sha): raise SystemExit("Owner implementation/test source changed: "+path)
for version,expected in VERSIONS.items():
 if pin_validator.upstream_revision("jpsim/Yams",version)!=expected:raise SystemExit("Original Yams tag retargeted; manual provenance review required")
def blob(ref,path): return call(["git","show",f"{ref}:{path}"])
def sha(data):return hashlib.sha256(data).hexdigest()
platform=call(["sw_vers"],text=True); toolchain=call(["swift","--version"],text=True)
if sys.platform!="darwin":raise SystemExit("Apple acceptance requires actual macOS Swift")
(OUT/"swift-toolchain.log").write_text(platform+toolchain,encoding="utf-8")
results=[]
owner_manifest=blob(OWNER,PACKAGE+"/Package.swift")
clean_env={k:v for k,v in os.environ.items() if k not in {"GH_TOKEN","GITHUB_TOKEN","RENOVATE_TOKEN","ACTIONS_RUNTIME_TOKEN","ACTIONS_ID_TOKEN_REQUEST_TOKEN"}}
for label,ref,version in [("baseline",base,"6.2.1"),("candidate",head,"6.2.2")]:
 manifest=blob(ref,PACKAGE+"/Package.swift"); resolved=blob(ref,PACKAGE+"/Package.resolved")
 expected_manifest=owner_manifest.replace(b'revision: "a27b21e0c81c5bf42049b897a62aaf387e80f279"',b'exact: "'+version.encode()+b'"')
 if manifest!=expected_manifest:raise SystemExit("Only the original owner manifest with its exact test release is accepted")
 pins=json.loads(resolved)["pins"]
 if len(pins)!=1 or pins[0]["identity"]!="yams" or pins[0]["location"]!="https://github.com/jpsim/Yams.git" or pins[0]["state"]!={"revision":VERSIONS[version],"version":version}:raise SystemExit("Committed Yams resolution mismatch")
 with tempfile.TemporaryDirectory(prefix="hanlin-swiftpm-",dir=os.environ.get("RUNNER_TEMP")) as scratch:
  root=pathlib.Path(scratch)
  for path in current:
   dst=root/pathlib.PurePosixPath(path).relative_to(PACKAGE);dst.parent.mkdir(parents=True,exist_ok=True);dst.write_bytes(blob(ref,path))
  pin_validator.verify_pin(root,version,"jpsim/Yams",VERSIONS[version])
  commands=[["swift","package","resolve","--force-resolved-versions"],["swift","package","show-dependencies","--format","json"],["swift","test","--force-resolved-versions"]]
  logs=[]
  for index,command in enumerate(commands):
   run=subprocess.run(command,cwd=root,text=True,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,timeout=600,env=clean_env)
   log=run.stdout; (OUT/f"swift-{label}-{index}.log").write_text(log,encoding="utf-8");logs.append(log)
   if run.returncode:raise SystemExit(f"{label} actual command failed: {command}; see retained log")
  if (root/"Package.resolved").read_bytes()!=resolved:raise SystemExit("Resolver changed committed lock; normalize actual resolution before acceptance")
  checkout=root/".build/checkouts/Yams"; actual=call(["git","-C",str(checkout),"rev-parse","HEAD"],text=True).strip()
  if actual!=VERSIONS[version]:raise SystemExit("Actual built source SHA mismatch")
  license_bytes=(checkout/"LICENSE").read_bytes()
  if b"MIT" not in license_bytes or b"Permission is hereby granted" not in license_bytes:raise SystemExit("Original Yams MIT license not verified")
  sbom={"bomFormat":"CycloneDX","specVersion":"1.6","version":1,"components":[{"type":"library","name":"Yams","version":version,"purl":f"pkg:swift/github.com/jpsim/Yams@{version}","licenses":[{"license":{"id":"MIT"}}],"externalReferences":[{"type":"vcs","url":f"https://github.com/jpsim/Yams/tree/{actual}"}],"properties":[{"name":"sourceCommit","value":actual},{"name":"bundledNativeTarget","value":"CYaml; exact Yams source tree"},{"name":"originalLicenseSHA256","value":sha(license_bytes)}]}]}
  (OUT/f"swift-{label}-sbom.json").write_text(json.dumps(sbom,indent=2)+"\n",encoding="utf-8")
  counts=re.findall(r"Executed (\d+) tests?, with (\d+) failures?",logs[-1])
  swift_counts=re.findall(r"Test run with (\d+) tests?[^\n]*passed",logs[-1])
  if not any(int(n)>0 and int(f)==0 for n,f in counts) and not any(int(n)>0 for n in swift_counts):raise SystemExit("No authentic executed test summary")
  results.append({"label":label,"sourceSHA":ref,"version":version,"upstreamCommit":actual,"manifestSHA256":sha(manifest),"resolvedSHA256":sha(resolved),"license":"MIT","licenseSHA256":sha(license_bytes),"status":"EXECUTED_PASS","testSummaries":counts or swift_counts})
receipt={"schemaVersion":1,"status":"EXECUTED_PASS","repository":REPO,"pullRequest":int(NUMBER),"head":head,"base":base,"changedPaths":paths,"sourceOwnerCommit":OWNER,"consumer":"HanlinSkillFormat original owner sources/tests","results":results,"toolchain":toolchain,"platform":platform,"scope":"Real macOS SwiftPM resolver, compile and package tests for both original Yams releases; no iOS simulator/app distribution claim","rollback":{"parent":base,"strategy":"Restore the isolated parent manifest and exact resolved Git SHA"}}
(OUT/"swiftpm-receipt.json").write_text(json.dumps(receipt,indent=2)+"\n",encoding="utf-8")
print(json.dumps(receipt))
