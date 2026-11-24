from pathlib import Path
import gzip,hashlib,json,shutil,subprocess,tempfile,zipfile

E=Path(__file__).resolve().parent
OLD=E.parent/'sdk05-shipping-main14-20261124'
OUTER=Path('/tmp/hanlin-native-gate-evidence-45412939674/app-split-45412939674.zip')
TEXT=Path('/dev/shm/hanlin-native-gate-evidence-45412939674/app-split-evidence')
EXPECTED_OUTER='1c7b453087a1bb7d2e1a07fa2ec94898afc0e0b2dbee6f3ac2dc5d691c80d574'
EXPECTED_INPUT='91128b0831f2d90374bc7889acb9cbbd695d49187520ee23a7a75e3c2bcef6fc'
SOURCE='e2227ccdfe0c3111d1c17ef2b4bb1653ac24bb9c'
BASE='788354f8e9e863eb5e4c9007a8b58ea71d028b19'
OLD_SOURCE='cf9c18903c03264265557efb446207efa7226912'
EXPECTED_CHANGED={'docs/miniapp-sdk/source-inventory.json','docs/miniapp-sdk/extension-reachability.json','docs/miniapp-sdk/extension-reachability.md'}
POST_SDK={'docs/miniapp-sdk/README.md','docs/miniapp-sdk/extension-reachability.json','docs/miniapp-sdk/extension-reachability.md'}
POST_TEST='AI_HLYTests/HanlinExpoHostServicesAcceptanceTests.swift'
def sha(data):return hashlib.sha256(data).hexdigest()
def save(path,data):
    path=E/path;path.parent.mkdir(parents=True,exist_ok=True);path.write_bytes(data)
def out(path,data):save(path,(json.dumps(data,indent=2,ensure_ascii=False)+'\n').encode())
def git(*args):return subprocess.run(['git',*args],capture_output=True,check=True).stdout
def git_bytes(commit,path):return git('show',commit+':'+path)
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
assert OUTER.stat().st_size==333459051 and outer_sha==EXPECTED_OUTER
old_bytes=gzip.decompress((OLD/'raw/miniapp-sdk.json.gz').read_bytes());before=json.loads(old_bytes)
assert sha(old_bytes)=='17df84a3ea5121d8b6362a03d095114ff3ce7702ad605a97b91f21666480a7e6'
prior=json.loads((OLD/'raw/app-split-evidence/miniapp-documentation-snippets.json').read_bytes())
with zipfile.ZipFile(OUTER) as z: nested_info=z.getinfo('runtime-host/RuntimeHostResources.zip')
free=shutil.disk_usage('/tmp').free
assert free>nested_info.file_size+64*1024*1024
out('disk-before-staging.json',{'tmpFreeBytes':free,'sharedMemoryFreeBytes':shutil.disk_usage('/dev/shm').free,'requiredNestedBytes':nested_info.file_size,'additionalMarginBytes':64*1024*1024,'sufficient':True})
stage=Path(tempfile.mkdtemp(prefix='hanlin-sdk05-main15-delta-',dir='/tmp'))
cleanup={'ownedPath':str(stage),'removed':False}
try:
    with zipfile.ZipFile(OUTER) as z:
        for name in ['app-split-evidence/miniapp-documentation-snippets.json','app-split-evidence/acceptance.json','app-split-evidence/paired-product/acceptance.json','app-split-evidence/paired-product/source-sha.txt','runtime-host/host-metadata.json','runtime-host/runtime-host.sha256']:
            data=z.read(name);save('raw/'+name,data)
            if name.startswith('app-split-evidence/'):
                assert (TEXT/name.removeprefix('app-split-evidence/')).read_bytes()==data,name
        nested=stage/'RuntimeHostResources.zip';h=hashlib.sha256()
        with z.open(nested_info) as src,nested.open('wb') as dst:
            while b:=src.read(1024*1024):h.update(b);dst.write(b)
        nested_sha=h.hexdigest()
    assert (E/'raw/runtime-host/runtime-host.sha256').read_text().split()[0]==nested_sha
    report_bytes=(E/'raw/app-split-evidence/miniapp-documentation-snippets.json').read_bytes();now=json.loads(report_bytes)
    assert now['status']=='EXECUTED_PASS'
    assert (E/'raw/app-split-evidence/paired-product/source-sha.txt').read_text().strip()==SOURCE
    with zipfile.ZipFile(nested) as sdk:
        mb=sdk.read('MiniAppSDK/miniapp-sdk.json');after=json.loads(mb)
        assert sha(mb)==now['sdk']['manifestSHA256']
        assert after['inputSHA256']==now['sdk']['inputSHA256']==EXPECTED_INPUT
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
            p=row['path'];body=sdk.read('MiniAppSDK/'+p)
            assert sha(body)==row['after']['sha256'] and len(body)==row['after']['bytes']
            assert body==git_bytes(SOURCE,p)
            old_git=git_bytes(OLD_SOURCE,p);assert sha(old_git)==row['before']['sha256']
            save('raw/changed-sdk/'+p,body)
            content_delta=changes(json.loads(old_git),json.loads(body)) if p.endswith('.json') else [{'before':old_git.decode(),'after':body.decode()}]
            checked.append({'path':p,'member':'MiniAppSDK/'+p,'bytes':len(body),'sha256':sha(body),'matchesTestedSource':True,'matchesLaterEvidenceBase':body==git_bytes(BASE,p),'beforeMatchesPriorSource':True,'contentChanges':content_delta})
        out('changed-member-proof.json',checked)
    input_paths=[x['path'] for x in after['sourceInputs']]
    git_changes=git('diff','--name-only',OLD_SOURCE,SOURCE,'--',*input_paths).decode().splitlines()
    post_changes=git('diff','--name-only',SOURCE,BASE,'--',*input_paths).decode().splitlines()
    assert set(git_changes)==EXPECTED_CHANGED and set(post_changes)==POST_SDK
    assert [x['path'] for x in before['sourceInputs']]==input_paths
    assert [x['path'] for x in before['files']]==[x['path'] for x in after['files']]
    assert before['engines']==after['engines'] and before['upstream']==after['upstream']
    diff=changes(prior,now)
    allowed={'/sdk/manifestSHA256','/sdk/inputSHA256'}|{f'/projects/{i}/validation/'+field for i in range(4) for field in ['sourceRoot','sdk/manifestSHA256']}
    assert all(x['path'] in allowed for x in diff)
    assert len(now['projects'])==4 and all(p['validation']['succeeded'] and p['validation']['diagnostics']==[] for p in now['projects'])
    README='docs/miniapp-sdk/README.md'
    actual_readme_report=next(x for x in now['documentation'] if x['path']==README)
    assert new_rows[README]==old_rows[README]
    assert actual_readme_report['sha256']==new_rows[README]['sha256']==sha(git_bytes(SOURCE,README))=='4427f49e5b729658d95d98eb6cdbb84ea08f2e4d2e33d7b7c480192914346637'
    assert actual_readme_report['stagedSDKMatches'] and actual_readme_report['stagedSDKSHA256']==new_rows[README]['sha256']
    assert sha(git_bytes(BASE,README))=='90068db0d87718cc9f995f9d45c1e2e8a7bd670aa8b8f3b324f0bf4cfc591d95'
    post_rows=[{'path':p,'testedSourceSHA256':sha(git_bytes(SOURCE,p)),'laterBaseSHA256':sha(git_bytes(BASE,p)),'sdkInput':p in input_paths} for p in sorted(POST_SDK|{POST_TEST})]
    assert all(x['testedSourceSHA256']!=x['laterBaseSHA256'] for x in post_rows)
    out('post-dispatch-boundary.json',{'testedSource':SOURCE,'laterEvidenceBase':BASE,'postDispatchSDKInputPaths':post_changes,'laterChangesNotInArtifact':post_rows,'readmeProof':{'actualManifestRow':new_rows[README],'actualExecutedSnippetDocument':actual_readme_report,'priorBodyVerificationReused':True,'bodyReopened':False},'nativeTestBoundary':'The later checked HanlinObject test conversion belongs to a later test source; MAIN15 did not execute its application test cases. It is not a direct SDK input.'})
    adapter='AI_HLY/Downstream/HostServices/Adapters/ExpoHostServicesAdapter.swift';adapter_sha=sha(git_bytes(SOURCE,adapter))
    inventory=json.loads((E/'raw/changed-sdk/docs/miniapp-sdk/source-inventory.json').read_bytes());reach=json.loads((E/'raw/changed-sdk/docs/miniapp-sdk/extension-reachability.json').read_bytes())
    assert next(x['sha256'] for x in inventory['sources'] if x['path']==adapter)==adapter_sha
    assert next(x['sha256'] for x in reach['sdkSources'] if x['path']==adapter)==adapter_sha
    assert reach['sourceRefs']['expoAdapter']['sha256']==reach['sourceRefs']['expoRuntimeDispatch']['sha256']==adapter_sha
    out('adapter-provenance-binding.json',{'source':SOURCE,'path':adapter,'sha256':adapter_sha,'inventoryMatches':True,'reachabilitySourceAndBothRefsMatch':True,'generatorExecuted':False})
    doc_paths=[p for p in new_rows if p.startswith('docs/')];example_paths=[p for p in new_rows if p.startswith('examples/')];declaration_paths=[p for p in new_rows if p.endswith(('.d.ts','.d.mts','.d.cts'))]
    summary={'status':'PASS_EXPECTED_PROVENANCE_DELTA','outerArtifact':{'path':str(OUTER),'artifactID':14933389929,'bytes':OUTER.stat().st_size,'sha256':outer_sha},'nested':{'member':'runtime-host/RuntimeHostResources.zip','bytes':nested_info.file_size,'sha256':nested_sha},'sdk':{'manifestSHA256':sha(mb),'previousManifestSHA256':sha(old_bytes),'manifestBytes':len(mb),'manifestByteIdentical':mb==old_bytes,'inputSHA256':after['inputSHA256'],'computedInputSHA256':computed_input,'previousInputSHA256':before['inputSHA256'],'sourceInputs':len(after['sourceInputs']),'unchangedInputCount':len(after['sourceInputs'])-len(input_delta),'changedInputs':len(input_delta),'fileRows':len(after['files']),'unchangedFileRows':len(after['files'])-len(file_delta),'changedFileRows':len(file_delta),'sameOrderedPaths':True,'engineMetadataIdentical':before['engines']==after['engines'],'upstreamMetadataIdentical':before['upstream']==after['upstream']},'sourceApplicability':{'priorSource':OLD_SOURCE,'testedSource':SOURCE,'laterEvidenceBase':BASE,'gitChangedInputPaths':git_changes,'postDispatchSDKInputPaths':post_changes},'reusedManifestRowCoverage':{'docs':len(doc_paths),'unchangedDocs':len(doc_paths)-len(file_delta),'changedDocsFreshlyRead':len(checked),'examplesIncludingIndex':len(example_paths),'exampleRowsIdentical':all(old_rows.get(p)==new_rows[p] for p in example_paths),'declarations':len(declaration_paths),'declarationRowsIdentical':all(old_rows.get(p)==new_rows[p] for p in declaration_paths)},'snippet':{'sha256':sha(report_bytes),'status':now['status'],'sourceBlocks':now['sourceBlockCount'],'jsonBlocks':now['jsonBlockCount'],'excluded':len(now['excluded']),'projects':len(now['projects']),'diagnostics':0,'documentationIdentityRowsIdentical':prior['documentation']==now['documentation'],'checkerInputsIdentical':prior['checkerInputs']==now['checkerInputs'],'registrationIdentical':prior['registration']==now['registration']},'snippetDifferences':diff,'boundary':'Only the nested manifest and exactly three changed documentation members were opened. Unchanged original member/type/example proof is reused by identical manifest records. Compare artifact to exact e222 source, not later README/reachability/test edits. No repeated 112-member inspection, compiler, tests, build, download, generator or native acceptance claim.'}
    out('shipping-reconciliation.json',summary)
    print(json.dumps({k:v for k,v in summary.items() if k!='snippetDifferences'},indent=2))
finally:
    cleanup['bytesBeforeRemoval']=sum(p.stat().st_size for p in stage.rglob('*') if p.is_file())
    shutil.rmtree(stage);cleanup['removed']=not stage.exists();cleanup['tmpFreeBytesAfterRemoval']=shutil.disk_usage('/tmp').free;out('owned-staging-cleanup.json',cleanup)
