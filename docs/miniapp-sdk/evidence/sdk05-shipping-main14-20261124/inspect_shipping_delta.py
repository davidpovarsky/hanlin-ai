from pathlib import Path
import gzip,hashlib,json,shutil,subprocess,tempfile,zipfile

E=Path(__file__).resolve().parent
OLD=E.parent/'sdk05-shipping-reuse-main13-20261124'
OUTER=Path('/tmp/hanlin-native-gate-evidence-45398772829/app-split-45398772829.zip')
TEXT=Path('/dev/shm/hanlin-native-gate-evidence-45398772829/app-split-evidence')
EXPECTED='1ff663b205d35ce9d6f6eaadbb6e0690c40d4f96fdee9ab2f19d3bdd083ce33e'
SOURCE='cf9c18903c03264265557efb446207efa7226912'
BASE='dc518aa35d123b611c02b10ad75e11477a7eb131'
OLD_SOURCE='2cb851067c4339125ab6fb515522796bceb80c35'
EXPECTED_CHANGED={'docs/miniapp-sdk/source-inventory.json','docs/miniapp-sdk/extension-reachability.json','docs/miniapp-sdk/extension-reachability.md'}
def sha(data):return hashlib.sha256(data).hexdigest()
def save(path,data):
    path=E/path;path.parent.mkdir(parents=True,exist_ok=True);path.write_bytes(data)
def out(path,data):save(path,(json.dumps(data,indent=2,ensure_ascii=False)+'\n').encode())
def git(*args):return subprocess.run(['git',*args],capture_output=True,check=True).stdout
def file_hash(path):
    h=hashlib.sha256()
    with path.open('rb') as f:
        while b:=f.read(1024*1024):h.update(b)
    return h.hexdigest()
def changes(before,after,p=''):
    if type(before)!=type(after):return [{'path':p,'before':before,'after':after}]
    if isinstance(before,dict):
        rows=[]
        for k in sorted(set(before)|set(after)):
            if k not in before or k not in after:rows.append({'path':p+'/'+k,'before':before.get(k),'after':after.get(k)})
            else:rows.extend(changes(before[k],after[k],p+'/'+k))
        return rows
    if isinstance(before,list):
        if len(before)!=len(after):return [{'path':p,'beforeCount':len(before),'afterCount':len(after)}]
        return [r for i,(a,b) in enumerate(zip(before,after)) for r in changes(a,b,p+'/'+str(i))]
    return [] if before==after else [{'path':p,'before':before,'after':after}]

outer_sha=file_hash(OUTER)
assert OUTER.stat().st_size==334245460 and outer_sha==EXPECTED
old_bytes=gzip.decompress((OLD/'raw/miniapp-sdk.json.gz').read_bytes());before=json.loads(old_bytes)
assert sha(old_bytes)=='1b66e9111586a764617a47fafe8f71ac677c14743fc1d0df79290e3ac994cebc'
prior=json.loads((OLD/'raw/app-split-evidence/miniapp-documentation-snippets.json').read_bytes())
stage=Path(tempfile.mkdtemp(prefix='hanlin-sdk05-main14-delta-',dir='/tmp'))
cleanup={'ownedPath':str(stage),'removed':False}
try:
    with zipfile.ZipFile(OUTER) as z:
        for name in ['app-split-evidence/miniapp-documentation-snippets.json','app-split-evidence/acceptance.json','app-split-evidence/paired-product/acceptance.json','app-split-evidence/paired-product/source-sha.txt','runtime-host/host-metadata.json','runtime-host/runtime-host.sha256']:
            data=z.read(name);save('raw/'+name,data)
            if name.startswith('app-split-evidence/'):
                local=TEXT/name.removeprefix('app-split-evidence/')
                assert local.read_bytes()==data,name
        info=z.getinfo('runtime-host/RuntimeHostResources.zip');nested=stage/'RuntimeHostResources.zip';h=hashlib.sha256()
        with z.open(info) as src,nested.open('wb') as dst:
            while b:=src.read(1024*1024):h.update(b);dst.write(b)
        nested_sha=h.hexdigest()
    assert (E/'raw/runtime-host/runtime-host.sha256').read_text().split()[0]==nested_sha
    report_bytes=(E/'raw/app-split-evidence/miniapp-documentation-snippets.json').read_bytes();now=json.loads(report_bytes)
    assert now['status']=='EXECUTED_PASS'
    assert (E/'raw/app-split-evidence/paired-product/source-sha.txt').read_text().strip()==SOURCE
    with zipfile.ZipFile(nested) as sdk:
        mb=sdk.read('MiniAppSDK/miniapp-sdk.json');after=json.loads(mb)
        assert sha(mb)==now['sdk']['manifestSHA256']
        assert after['inputSHA256']==now['sdk']['inputSHA256']
        computed_input=sha(json.dumps(after['sourceInputs'],ensure_ascii=False,separators=(',',':')).encode())
        assert computed_input==after['inputSHA256']
        save('raw/miniapp-sdk.json.gz',gzip.compress(mb,mtime=0))
        old_rows={x['path']:x for x in before['files']};new_rows={x['path']:x for x in after['files']}
        old_inputs={x['path']:x for x in before['sourceInputs']};new_inputs={x['path']:x for x in after['sourceInputs']}
        file_delta=[{'path':p,'before':old_rows.get(p),'after':new_rows.get(p)} for p in sorted(set(old_rows)|set(new_rows)) if old_rows.get(p)!=new_rows.get(p)]
        input_delta=[{'path':p,'before':old_inputs.get(p),'after':new_inputs.get(p)} for p in sorted(set(old_inputs)|set(new_inputs)) if old_inputs.get(p)!=new_inputs.get(p)]
        out('declared-delta.json',{'sourceInputs':input_delta,'files':file_delta})
        assert {x['path'] for x in file_delta}==EXPECTED_CHANGED
        assert {x['path'] for x in input_delta}==EXPECTED_CHANGED
        checked=[]
        for row in file_delta:
            p=row['path'];b=sdk.read('MiniAppSDK/'+p)
            assert sha(b)==row['after']['sha256'] and len(b)==row['after']['bytes']
            assert b==git('show',SOURCE+':'+p)==git('show',BASE+':'+p)
            before_git=git('show',OLD_SOURCE+':'+p);assert sha(before_git)==row['before']['sha256']
            save('raw/changed-sdk/'+p,b)
            delta=changes(json.loads(before_git),json.loads(b)) if p.endswith('.json') else [{'before':before_git.decode(),'after':b.decode()}]
            checked.append({'path':p,'member':'MiniAppSDK/'+p,'bytes':len(b),'sha256':sha(b),'matchesTestedSource':True,'matchesEvidenceBase':True,'beforeMatchesPriorSource':True,'contentChanges':delta})
        out('changed-member-proof.json',checked)
    input_paths=[x['path'] for x in after['sourceInputs']]
    git_changes=git('diff','--name-only',OLD_SOURCE,SOURCE,'--',*input_paths).decode().splitlines()
    base_changes=git('diff','--name-only',SOURCE,BASE,'--',*input_paths).decode().splitlines()
    assert set(git_changes)==EXPECTED_CHANGED and not base_changes
    assert [x['path'] for x in before['sourceInputs']]==input_paths
    assert [x['path'] for x in before['files']]==[x['path'] for x in after['files']]
    assert before['engines']==after['engines'] and before['upstream']==after['upstream']
    diff=changes(prior,now)
    allowed={'/sdk/manifestSHA256','/sdk/inputSHA256'}|{f'/projects/{i}/validation/'+field for i in range(4) for field in ['sourceRoot','sdk/manifestSHA256']}
    assert all(x['path'] in allowed for x in diff)
    assert len(now['projects'])==4 and all(p['validation']['succeeded'] and p['validation']['diagnostics']==[] for p in now['projects'])
    doc_paths=[p for p in new_rows if p.startswith('docs/')];example_paths=[p for p in new_rows if p.startswith('examples/')];declaration_paths=[p for p in new_rows if p.endswith(('.d.ts','.d.mts','.d.cts'))]
    summary={'status':'PASS_EXPECTED_PROVENANCE_DELTA','outerArtifact':{'path':str(OUTER),'bytes':OUTER.stat().st_size,'sha256':outer_sha},'nested':{'member':'runtime-host/RuntimeHostResources.zip','bytes':info.file_size,'sha256':nested_sha},'sdk':{'manifestSHA256':sha(mb),'previousManifestSHA256':sha(old_bytes),'manifestBytes':len(mb),'manifestByteIdentical':mb==old_bytes,'inputSHA256':after['inputSHA256'],'computedInputSHA256':computed_input,'previousInputSHA256':before['inputSHA256'],'sourceInputs':len(after['sourceInputs']),'unchangedInputCount':len(after['sourceInputs'])-len(input_delta),'changedInputs':len(input_delta),'fileRows':len(after['files']),'unchangedFileRows':len(after['files'])-len(file_delta),'changedFileRows':len(file_delta),'sameOrderedPaths':True,'engineMetadataIdentical':before['engines']==after['engines'],'upstreamMetadataIdentical':before['upstream']==after['upstream']},'sourceApplicability':{'priorSource':OLD_SOURCE,'testedSource':SOURCE,'evidenceBase':BASE,'gitChangedInputPaths':git_changes,'gitChangedInputPathsAfterTestedSource':base_changes},'reusedManifestRowCoverage':{'docs':len(doc_paths),'unchangedDocs':len(doc_paths)-len(file_delta),'changedDocsFreshlyRead':len(checked),'examplesIncludingIndex':len(example_paths),'exampleRowsIdentical':all(old_rows.get(p)==new_rows[p] for p in example_paths),'declarations':len(declaration_paths),'declarationRowsIdentical':all(old_rows.get(p)==new_rows[p] for p in declaration_paths)},'snippet':{'sha256':sha(report_bytes),'status':now['status'],'sourceBlocks':now['sourceBlockCount'],'jsonBlocks':now['jsonBlockCount'],'excluded':len(now['excluded']),'projects':len(now['projects']),'diagnostics':0,'documentationIdentityRowsIdentical':prior['documentation']==now['documentation'],'checkerInputsIdentical':prior['checkerInputs']==now['checkerInputs'],'registrationIdentical':prior['registration']==now['registration']},'snippetDifferences':diff,'boundary':'Only the nested manifest and exactly three changed documentation members were opened. Unchanged original member/type/example proof is reused by identical manifest records. No repeated 112-member inspection, compiler, tests, build, download, generator or native acceptance claim.'}
    out('shipping-reconciliation.json',summary)
    print(json.dumps({k:v for k,v in summary.items() if k!='snippetDifferences'},indent=2))
finally:
    cleanup['bytesBeforeRemoval']=sum(p.stat().st_size for p in stage.rglob('*') if p.is_file())
    shutil.rmtree(stage);cleanup['removed']=not stage.exists();out('owned-staging-cleanup.json',cleanup)
