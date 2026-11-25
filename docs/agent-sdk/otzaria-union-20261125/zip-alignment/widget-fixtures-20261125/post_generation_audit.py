import pathlib,tarfile,zipfile,io,json,hashlib,copy,re,datetime
B=pathlib.Path("/Users/m1/builds/hanlin-widget-fixtures-3f622f78-20261125");S=B/"source";E=B/"evidence"
def sha(p):return hashlib.sha256(pathlib.Path(p).read_bytes()).hexdigest()
failed=E/"RESULT.json";assert sha(failed)=="3d7a964b2c413589777381712cc8c5a035ae10f1ce13e04c6812346f69fd86b5"
first=json.loads(failed.read_text());assert first["status"]=="FAILED" and all(x["exit"]==0 for x in first["commands"])
log=(E/"source-controls.log").read_text()
for v in ["# tests 8","# pass 8","# fail 0","# cancelled 0","# skipped 0","# todo 0"]:assert v in log
assert len(re.findall(r"^ok [0-9]+ - ",log,re.M))==8 and not re.search(r"^not ok ",log,re.M)
M=json.loads((S/"SOURCE_MANIFEST.json").read_text());expected={r["path"]:r for r in M["files"]}
versions=json.loads((S/"Scripts/Expo/dependency-lock.json").read_text())["expo"]
dirs=["Fixtures/Widgets","AI_HLYUITests/Fixtures","AI_HLYTests/Fixtures/WidgetEngineFixtures.bundle"]
changed=[];members=[];outputs=[]
with tarfile.open(str(B)+"-source.tar.gz","r:gz") as t:
 for row in M["files"]:
  p=S/row["path"]
  if sha(p)!=row["sha256"]:changed.append(row["path"])
  if not row["path"].startswith("Fixtures/Widgets/") or p.suffix not in (".scripting",".hanlinExpo"):continue
  old=t.extractfile(row["path"]).read();new=p.read_bytes()
  record={"archive":p.name,"before_sha256":hashlib.sha256(old).hexdigest(),"after_sha256":sha(p),"members":[]}
  with zipfile.ZipFile(io.BytesIO(old)) as a,zipfile.ZipFile(io.BytesIO(new)) as z:
   assert a.namelist()==z.namelist()
   for n in a.namelist():
    x,y=a.read(n),z.read(n);ai,zi=a.getinfo(n),z.getinfo(n)
    for prop in ["compress_type","flag_bits","date_time","external_attr","internal_attr","create_system","create_version","extract_version","extra","comment"]:
     assert getattr(ai,prop)==getattr(zi,prop),(p.name,n,prop)
    if n=="package.json":
     before=json.loads(x);after=json.loads(y);wanted=copy.deepcopy(before)
     wanted["hanlinExpo"]["runtimeVersion"]=versions["uiVersion"];wanted["hanlinExpo"]["plugins"]["@expo/ui"]=versions["uiVersion"]
     wanted["dependencies"]["@expo/ui"]=versions["uiVersion"];wanted["dependencies"]["expo-widgets"]=versions["widgetsVersion"];wanted["dependencies"]["react"]=versions["reactVersion"]
     assert after==wanted and before!=after
    else:assert x==y,(p.name,n,"unexpected payload change")
    record["members"].append({"path":n,"before_sha256":hashlib.sha256(x).hexdigest(),"after_sha256":hashlib.sha256(y).hexdigest(),"old_compressed_bytes":ai.compress_size,"new_compressed_bytes":zi.compress_size,"payload_changed":x!=y})
  for d in dirs:
   fp=S/d/p.name;assert sha(fp)==sha(p);outputs.append({"path":str(fp.relative_to(S)),"size":fp.stat().st_size,"sha256":sha(fp)})
  members.append(record)
assert len(members)==7 and sum(x["payload_changed"] for a in members for x in a["members"])==4
expected_changed={d+"/"+m["archive"] for m in members for d in dirs}|{"Fixtures/Widgets/SHA256.json"}
assert set(changed)==expected_changed
index=json.loads((S/"Fixtures/Widgets/SHA256.json").read_text())
assert len(index)==7
for item in index:
 p=S/"Fixtures/Widgets"/item["archive"];assert sha(p)==item["sha256"] and p.stat().st_size==item["bytes"]
 with zipfile.ZipFile(p) as z:
  assert set(z.namelist())==set(item["sources"])
  for n in z.namelist():assert hashlib.sha256(z.read(n)).hexdigest()==item["sources"][n]
outputs.append({"path":"Fixtures/Widgets/SHA256.json","size":(S/"Fixtures/Widgets/SHA256.json").stat().st_size,"sha256":sha(S/"Fixtures/Widgets/SHA256.json")})
out={"status":"PASS","scope":"Post-generation source and archive-member validation; eight original Node controls reused from actual same-run logs; zero native widget tests","source_sha":M["source_sha"],"retained_failed_validation_sha256":sha(failed),"node_tests_passed":8,"native_tests_executed":0,"node_log_sha256":sha(E/"source-controls.log"),"generator_log_sha256":sha(E/"generate.log"),"node_version":first["node_version"],"changed_fixture_files":22,"unchanged_original_script_resource_inputs":9,"changed_uncompressed_members":4,"reason_extra_zip_bytes_changed":"Original deterministicZip uses this Node runtime compressor. Uncompressed members and all ZIP metadata are independently equal except four expected Expo package.json version contracts; compressed sizes differ.","member_validation":members,"outputs":outputs,"validated_at":datetime.datetime.now(datetime.timezone.utc).isoformat()}
(E/"POST_GENERATION_AUDIT.json").write_text(json.dumps(out,indent=2)+"\n")
with tarfile.open(B/"generated-evidence.tar.gz","w:gz",compresslevel=6) as t:
 for row in outputs:t.add(S/row["path"],arcname="generated/"+row["path"])
 for p in sorted(E.iterdir()):
  if p.is_file():t.add(p,arcname="evidence/"+p.name)
print(json.dumps({"status":"PASS","audit":str(E/"POST_GENERATION_AUDIT.json"),"audit_sha256":sha(E/"POST_GENERATION_AUDIT.json"),"output_archive":str(B/"generated-evidence.tar.gz"),"output_archive_sha256":sha(B/"generated-evidence.tar.gz"),"output_archive_bytes":(B/"generated-evidence.tar.gz").stat().st_size,"node_tests_passed":8,"changed_fixture_files":22,"changed_payload_members":4}))
