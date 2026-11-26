from pathlib import Path
import gzip,hashlib,json,shutil,tempfile,zipfile

E=Path(__file__).resolve().parent
OLD=E.parent/'sdk05-current-shipping-20261124'
OUTER=Path('/tmp/hanlin-native-gate-evidence-45389020875/app-split-45389020875.zip')
TEXT=Path('/dev/shm/hanlin-native-gate-evidence-45389020875/app-split-evidence')
EXPECTED='7e228d0676a5addfcdd1e00767769d746b566824b3c201293d370cb9630b7dce'
def sha(data): return hashlib.sha256(data).hexdigest()
def save(path,data):
    path=E/path;path.parent.mkdir(parents=True,exist_ok=True);path.write_bytes(data)
def out(path,data): save(path,(json.dumps(data,indent=2,ensure_ascii=False)+'\n').encode())
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
assert OUTER.stat().st_size==334177257 and outer_sha==EXPECTED
old_manifest_bytes=gzip.decompress((OLD/'raw/miniapp-sdk.json.gz').read_bytes())
assert sha(old_manifest_bytes)=='1b66e9111586a764617a47fafe8f71ac677c14743fc1d0df79290e3ac994cebc'
before=json.loads(old_manifest_bytes)
old_report_bytes=(OLD/'raw/app-split-evidence/miniapp-documentation-snippets.json').read_bytes()
assert sha(old_report_bytes)=='d4af6b636f23f004618da047803a7f73a4897f433d2bd9dfe8e5b72311ebe912'
prior=json.loads(old_report_bytes)
stage=Path(tempfile.mkdtemp(prefix='hanlin-sdk05-main13-reuse-',dir='/tmp'))
cleanup={'ownedPath':str(stage),'removed':False}
try:
    with zipfile.ZipFile(OUTER) as z:
        for name in ['app-split-evidence/miniapp-documentation-snippets.json','app-split-evidence/acceptance.json','app-split-evidence/paired-product/acceptance.json','app-split-evidence/paired-product/source-sha.txt','runtime-host/host-metadata.json','runtime-host/runtime-host.sha256']:
            data=z.read(name);save('raw/'+name,data)
            if name.startswith('app-split-evidence/'):
                local=TEXT/name.removeprefix('app-split-evidence/')
                assert local.read_bytes()==data, name
        info=z.getinfo('runtime-host/RuntimeHostResources.zip')
        nested=stage/'RuntimeHostResources.zip';h=hashlib.sha256()
        with z.open(info) as src,nested.open('wb') as dst:
            while b:=src.read(1024*1024):h.update(b);dst.write(b)
        nested_sha=h.hexdigest()
    hash_text=(E/'raw/runtime-host/runtime-host.sha256').read_text().strip()
    assert hash_text.split()[0]==nested_sha
    host=json.loads((E/'raw/runtime-host/host-metadata.json').read_bytes())
    with zipfile.ZipFile(nested) as sdk:
        mb=sdk.read('MiniAppSDK/miniapp-sdk.json')
    after=json.loads(mb)
    save('raw/miniapp-sdk.json.gz',gzip.compress(mb,mtime=0))
    now_bytes=(E/'raw/app-split-evidence/miniapp-documentation-snippets.json').read_bytes();now=json.loads(now_bytes)
    assert now['status']=='EXECUTED_PASS'
    assert now['sdk']['manifestSHA256']==sha(mb)
    assert now['sdk']['inputSHA256']==after['inputSHA256']
    old_rows={x['path']:x for x in before['files']};new_rows={x['path']:x for x in after['files']}
    row_changes=[{'path':p,'before':old_rows.get(p),'after':new_rows.get(p)} for p in sorted(set(old_rows)|set(new_rows)) if old_rows.get(p)!=new_rows.get(p)]
    source_changes=changes(before['sourceInputs'],after['sourceInputs'])
    doc_paths=[p for p in new_rows if p.startswith('docs/')]
    example_paths=[p for p in new_rows if p.startswith('examples/')]
    declaration_paths=[p for p in new_rows if p.endswith(('.d.ts','.d.mts','.d.cts'))]
    prior_checked=json.loads((OLD/'checked-artifact-files.json').read_bytes())
    summary={'status':'PASS' if not source_changes and not row_changes else 'DIFFERENCES_RECORDED','outerArtifact':{'path':str(OUTER),'bytes':OUTER.stat().st_size,'sha256':outer_sha,'artifactID':14921026306},'nested':{'member':'runtime-host/RuntimeHostResources.zip','bytes':info.file_size,'sha256':nested_sha,'previousSHA256':'3f8369a26f492aa0cb4c7ca63a03d33104993adad81223ba9b3ee7f0e46ada4c'},'sdk':{'manifestSHA256':sha(mb),'previousManifestSHA256':sha(old_manifest_bytes),'manifestBytes':len(mb),'manifestByteIdentical':mb==old_manifest_bytes,'inputSHA256':after['inputSHA256'],'previousInputSHA256':before['inputSHA256'],'sourceInputs':len(after['sourceInputs']),'sourceInputsOrderedIdentical':before['sourceInputs']==after['sourceInputs'],'fileRows':len(after['files']),'fileRowsOrderedIdentical':before['files']==after['files'],'engineMetadataIdentical':before['engines']==after['engines'],'upstreamMetadataIdentical':before['upstream']==after['upstream']},'manifestRowCoverage':{'docs':len(doc_paths),'examplesIncludingIndex':len(example_paths),'declarations':len(declaration_paths),'docsRowsIdentical':all(old_rows.get(p)==new_rows[p] for p in doc_paths),'exampleRowsIdentical':all(old_rows.get(p)==new_rows[p] for p in example_paths),'declarationRowsIdentical':all(old_rows.get(p)==new_rows[p] for p in declaration_paths)},'snippet':{'sha256':sha(now_bytes),'previousSHA256':sha(old_report_bytes),'status':now['status'],'sourceBlocks':now['sourceBlockCount'],'jsonBlocks':now['jsonBlockCount'],'excluded':len(now['excluded']),'projects':len(now['projects']),'documentationIdentityRowsIdentical':prior['documentation']==now['documentation'],'checkerInputsIdentical':prior['checkerInputs']==now['checkerInputs'],'registrationIdentical':prior['registration']==now['registration']},'sourceInputDifferences':source_changes,'manifestFileRowDifferences':row_changes,'otherManifestDifferences':changes({k:v for k,v in before.items() if k not in ('files','sourceInputs')},{k:v for k,v in after.items() if k not in ('files','sourceInputs')}),'snippetDifferences':changes(prior,now),'proofBoundary':'Read the nested manifest only. Reused prior 112-member byte verification by manifest identities; no repeated per-member inspection, compiler, test, build, download or native claim.'}
    out('manifest-and-snippet-comparison.json',summary)
    print(json.dumps({k:v for k,v in summary.items() if k not in ('manifestFileRowDifferences','sourceInputDifferences')},indent=2))
finally:
    cleanup['bytesBeforeRemoval']=sum(p.stat().st_size for p in stage.rglob('*') if p.is_file())
    shutil.rmtree(stage);cleanup['removed']=not stage.exists();out('owned-staging-cleanup.json',cleanup)
