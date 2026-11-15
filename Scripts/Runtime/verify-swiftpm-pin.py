#!/usr/bin/env python3
"""Verify an exact original SwiftPM release and its resolved Git commit; never resolve/build."""
import json,pathlib,re,subprocess,sys

def verify_pin(root,version,repository,expected):
 if not re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+",version) or not re.fullmatch(r"[\w.-]+/[\w.-]+",repository) or not re.fullmatch(r"[a-f0-9]{40}",expected):raise ValueError("Invalid stable source pin")
 manifest=(pathlib.Path(root)/"Package.swift").read_text(encoding="utf-8")
 url="https://github.com/"+repository+".git"
 pattern=r'\.package\(\s*url:\s*"'+re.escape(url)+r'"\s*,\s*exact:\s*"'+re.escape(version)+r'"\s*\)'
 if not re.search(pattern,manifest):raise ValueError("Exact original release manifest mismatch")
 resolved=json.loads((pathlib.Path(root)/"Package.resolved").read_text(encoding="utf-8"))
 pins=[p for p in resolved.get("pins",[]) if p.get("identity","").lower()==repository.split("/")[1].lower()]
 if len(pins)!=1 or pins[0].get("location")!=url or pins[0].get("state")!={"revision":expected,"version":version}:raise ValueError("Resolved version/revision/source mismatch")
 return {"version":version,"repository":repository,"revision":expected}

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
