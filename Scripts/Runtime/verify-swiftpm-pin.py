#!/usr/bin/env python3
"""Verify an exact original SwiftPM release and its resolved Git commit; never resolve/build."""
import hashlib,json,os,pathlib,re,subprocess,sys

def verify_pin(root,version,repository,expected):
 if not re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+",version) or not re.fullmatch(r"[\w.-]+/[\w.-]+",repository) or not re.fullmatch(r"[a-f0-9]{40}",expected):raise ValueError("Invalid stable source pin")
 root=pathlib.Path(root).resolve()
 manifest=(root/"Package.swift").read_bytes()
 url="https://github.com/"+repository+".git"
 # Only trusted repository manifests: original SwiftPM evaluates the active declaration.
 clean_env={k:v for k,v in os.environ.items() if k not in {"GH_TOKEN","GITHUB_TOKEN","RENOVATE_TOKEN","ACTIONS_RUNTIME_TOKEN","ACTIONS_ID_TOKEN_REQUEST_TOKEN"}}
 try:
  model=json.loads(subprocess.check_output(["swift","package","dump-package"],cwd=root,env=clean_env,stderr=subprocess.PIPE,timeout=90))
  toolchain=subprocess.check_output(["swift","--version"],env=clean_env,text=True,timeout=15).strip()
 except (subprocess.SubprocessError,ValueError) as error:raise ValueError("Authoritative SwiftPM manifest evaluation failed") from error
 declarations=[item for dependency in model.get("dependencies",[]) for item in dependency.get("sourceControl",[])
  if item.get("identity","").lower()==repository.split("/")[1].lower()]
 if len(declarations)!=1 or declarations[0].get("location",{}).get("remote")!=[{"urlString":url}] or declarations[0].get("requirement")!={"exact":[version]}:
  raise ValueError("Exact active original release requirement mismatch or duplicate declaration")
 resolved=json.loads((pathlib.Path(root)/"Package.resolved").read_text(encoding="utf-8"))
 pins=[p for p in resolved.get("pins",[]) if p.get("identity","").lower()==repository.split("/")[1].lower()]
 if len(pins)!=1 or pins[0].get("location")!=url or pins[0].get("state")!={"revision":expected,"version":version}:raise ValueError("Resolved version/revision/source mismatch")
 return {"version":version,"repository":repository,"revision":expected,"semanticSourceControl":declarations[0],
  "manifestSHA256":hashlib.sha256(manifest).hexdigest(),"resolvedSHA256":hashlib.sha256((root/"Package.resolved").read_bytes()).hexdigest(),
  "swiftPMModelSHA256":hashlib.sha256(json.dumps(model,sort_keys=True).encode()).hexdigest(),"toolchain":toolchain}

def peel(object,lookup):
 seen=set()
 for _ in range(5):
  if object.get("type")=="commit" and re.fullmatch(r"[a-f0-9]{40}",object.get("sha","")):return object["sha"]
  if object.get("type")!="tag" or object.get("sha") in seen:raise ValueError("Invalid/cyclic upstream tag")
  seen.add(object["sha"]);object=lookup(object["sha"])["object"]
 raise ValueError("Upstream annotated tag chain exceeds bound")

def upstream_revision(repository,version):
 def api(path):return json.loads(subprocess.check_output(["gh","api",f"repos/{repository}/{path}"],stderr=subprocess.PIPE))
 return peel(api(f"git/ref/tags/{version}")["object"],lambda sha:api("git/tags/"+sha))

if __name__=="__main__":
 root,version,repository,expected=sys.argv[1:5]
 result=verify_pin(root,version,repository,expected)
 actual=upstream_revision(repository,version)
 if actual!=expected:raise SystemExit("Original upstream tag retarget/source drift: review required")
 print(json.dumps({**result,"upstreamPeeledCommit":actual,"status":"EXECUTED_PASS"}))
