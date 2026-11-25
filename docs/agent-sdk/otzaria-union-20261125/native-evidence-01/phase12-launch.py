import pathlib,hashlib,json,tarfile,os,shutil,subprocess,sys,time,datetime
base=pathlib.Path('/Users/m1/builds')
archive=base/'hanlin-c92c3f-manifest-source.tar.gz'
runner=base/'otzaria-core7-union-20261125.py'
root=base/'hanlin-c92c3f-manifest-check-20261125'
free=shutil.disk_usage(base).free
print('FRESH_PHASE_ADMISSION',json.dumps({'free_bytes':free,'required_bytes':12*1024**3,'own_remaining_gib':1,'anytype_remaining_gib':1,'external_growth_gib':8,'os_margin_gib':2,'prior_blocked_job':'job_5911ae8b89ea'}),flush=True)
assert free>12*1024**3,('joint storage admission',free,12*1024**3)
assert hashlib.sha256(archive.read_bytes()).hexdigest()=='a459fe8b3b1da2c17c78a63894c140f7f6b8d6d867dcd853fc6340a7ea43ac0f'
assert hashlib.sha256(runner.read_bytes()).hexdigest()=='a28aecadd9a30e58fe0a99bbea230e0e362f70bf4c3d3e2c6b90e6bf2e6de3b2'
assert not root.exists()
root.mkdir()
with tarfile.open(archive,'r:gz') as t:
    members=t.getmembers()
    assert len({m.name for m in members})==len(members)
    for m in members:
        p=pathlib.PurePosixPath(m.name)
        assert not p.is_absolute() and '..' not in p.parts
        assert (m.isfile() or m.issym()) and not m.islnk()
        if m.issym():
            assert not pathlib.PurePosixPath(m.linkname).is_absolute()
            assert str((root/m.name).parent.joinpath(m.linkname).resolve()).startswith(str(root.resolve())+'/')
    t.extractall(root)
manifest=root/'manifest-source.json'
assert hashlib.sha256(manifest.read_bytes()).hexdigest()=='04f5f9d9a703ae8c94baea9047b6b750478ecf0c2586ec6fed5d11653c1d1e88'
doc=json.loads(manifest.read_text())
assert doc['source']=='c92c3f904872b37287861dfafa9cc668d5dc44c3' and len(doc['files'])==754
def verify():
    for f in doc['files']:
        p=root/f['path']
        raw=os.fsencode(os.readlink(p)) if f['mode']=='120000' else p.read_bytes()
        assert len(raw)==f['bytes'] and hashlib.sha256(raw).hexdigest()==f['sha256'],f['path']
        assert hashlib.sha1(b'blob '+str(len(raw)).encode()+b'\0'+raw).hexdigest()==f['git_blob'],f['path']
    return len(doc['files'])
evidence=root/'evidence'
evidence.mkdir()
result={'status':'NOT_RUN','source':doc['source'],'source_archive':'EXACT_COMMITTED_SOURCE_CLOSURE_NOT_GIT_CHECKOUT','verified_before':verify(),'admission':{'free_bytes':free,'my_incremental_gib':1,'anytype_remaining_incremental_gib':1,'other_growth_gib':8,'os_margin_gib':2,'joint_required_gib':12},'runner_source':'0df4152bb7cecb79f9f0c87ee328d63ef59d2a84'}
started=time.monotonic()
cmd=[sys.executable,str(root/'Scripts/SDK/generate_manifest.py'),'--check']
with (evidence/'canonical-manifest.stdout.log').open('wb') as out,(evidence/'canonical-manifest.stderr.log').open('wb') as err:
    proc=subprocess.run(cmd,cwd=root,stdout=out,stderr=err,timeout=300)
result.update(command=cmd,exit=proc.returncode,seconds=time.monotonic()-started,verified_after=verify())
if proc.returncode==0:
    observed=json.loads((evidence/'canonical-manifest.stdout.log').read_text())
    expected=json.loads((root/'docs/agent-sdk/unified-package-manifest.json').read_text())
    assert observed==expected,('Canonical graph receipt differs',observed,expected)
    result.update(status='EXECUTED_PASS',manifest=observed)
else:
    result.update(status='FAILED')
(evidence/'RESULT.json').write_text(json.dumps(result,indent=2,sort_keys=True)+'\n')
print('MANIFEST',json.dumps(result),flush=True)
assert proc.returncode==0,'Canonical manifest --check failed; original logs retained'
assert shutil.disk_usage(base).free>12*1024**3,'Fresh Core7 joint admission failed'
cmd=[sys.executable,str(runner),'--hanlin-source','c92c3f904872b37287861dfafa9cc668d5dc44c3','--core-checkout','/Users/m1/caches/DerivedData/hanlin-ai-cache-20261125/core-proof/checkouts/swift-ai-sdk','--warm-cache','/Users/m1/caches/DerivedData/hanlin-ai-cache-20261125/core-proof','--proof-root','/Users/m1/builds/otzaria-core7-abf-union-20261125','--scratch','/Users/m1/caches/DerivedData/otzaria-core7-abf-union-20261125','--anticipated-concurrent-growth-gib','9','--os-margin-gib','2']
print('CORE7_START',json.dumps({'argv':cmd,'free':shutil.disk_usage(base).free}),flush=True)
p=subprocess.run(cmd,timeout=3000)
print('CORE7_FINISHED',p.returncode,flush=True)
sys.exit(p.returncode)
