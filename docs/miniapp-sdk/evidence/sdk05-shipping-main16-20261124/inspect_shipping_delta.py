from pathlib import Path
import gzip,hashlib,json,shutil,subprocess,tempfile,zipfile

E=Path(__file__).resolve().parent
OLD=E.parent/'sdk05-shipping-main15-20261124'
OUTER=Path('/tmp/hanlin-native-gate-evidence-45430463243/app-split-45430463243.zip')
TEXT=Path('/dev/shm/hanlin-native-gate-evidence-45430463243/app-split-evidence')
EXPECTED_OUTER='ad546a720f976eef8d7af40c8187a287b56382af6caba614ad9e35aa5491b95f'
EXPECTED_INPUT='307f689d68445cae8cb4f049f015c9bf55904d0de40a96e69fb59fa622d0a863'
SOURCE='7d1efaa6ada43dd80c57133c09e6a8fb327075cf'
BASE='1bc0360cb204796a092c9101df980028f2963459'
OLD_SOURCE='e2227ccdfe0c3111d1c17ef2b4bb1653ac24bb9c'
README='docs/miniapp-sdk/README.md'
EXPECTED_CHANGED={README,'docs/miniapp-sdk/extension-reachability.json','docs/miniapp-sdk/extension-reachability.md'}
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
assert OUTER.stat().st_size==335922163 and outer_sha==EXPECTED_OUTER
old_bytes=gzip.decompress((OLD/'raw/miniapp-sdk.json.gz').read_bytes());before=json.loads(old_bytes)
assert sha(old_bytes)=='ab7900fbb6009606800a7d4beda2bef2cee6ef8492928bea90ad5d0460abff8b'
prior=json.loads((OLD/'raw/app-split-evidence/miniapp-documentation-snippets.json').read_bytes())
with zipfile.ZipFile(OUTER) as z:nested_info=z.getinfo('runtime-host/RuntimeHostResources.zip')
free=shutil.disk_usage('/tmp').free
assert free>nested_info.file_size+64*1024*1024
out('disk-before-staging.json',{'tmpFreeBytes':free,'sharedMemoryFreeBytes':shutil.disk_usage('/dev/shm').free,'nestedBytes':nested_info.file_size,'additionalMarginBytes':64*1024*1024,'sufficient':True})
stage=Path(tempfile.mkdtemp(prefix='hanlin-sdk05-main16-delta-',dir='/tmp'))
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
            assert body==git_bytes(SOURCE,p)==git_bytes(BASE,p)
            old_git=git_bytes(OLD_SOURCE,p);assert sha(old_git)==row['before']['sha256']
            save('raw/changed-sdk/'+p,body)
            content_delta=changes(json.loads(old_git),json.loads(body)) if p.endswith('.json') else [{'before':old_git.decode(),'after':body.decode()}]
            checked.append({'path':p,'member':'MiniAppSDK/'+p,'bytes':len(body),'sha256':sha(body),'matchesExactTestedSource':True,'matchesEvidenceBase':True,'beforeMatchesPriorSource':True,'contentChanges':content_delta})
        out('changed-member-proof.json',checked)
    input_paths=[x['path'] for x in after['sourceInputs']]
    git_changes=git('diff','--name-only',OLD_SOURCE,SOURCE,'--',*input_paths).decode().splitlines()
    later_changes=git('diff','--name-only',SOURCE,BASE,'--',*input_paths).decode().splitlines()
    assert set(git_changes)==EXPECTED_CHANGED and later_changes==[]
    assert [x['path'] for x in before['sourceInputs']]==input_paths
    assert [x['path'] for x in before['files']]==[x['path'] for x in after['files']]
    assert before['engines']==after['engines'] and before['upstream']==after['upstream']
    readme_index=next(i for i,x in enumerate(now['documentation']) if x['path']==README)
    diff=changes(prior,now)
    allowed={'/sdk/manifestSHA256','/sdk/inputSHA256'}|{f'/projects/{i}/validation/'+field for i in range(4) for field in ['sourceRoot','sdk/manifestSHA256']}|{f'/documentation/{readme_index}/sha256',f'/documentation/{readme_index}/stagedSDKSHA256'}
    assert all(x['path'] in allowed for x in diff)
    assert len(now['projects'])==4 and all(p['validation']['succeeded'] and p['validation']['diagnostics']==[] for p in now['projects'])
    new_readme=(E/'raw/changed-sdk'/README).read_bytes();old_readme=git_bytes(OLD_SOURCE,README)
    assert sha(new_readme)=='90068db0d87718cc9f995f9d45c1e2e8a7bd670aa8b8f3b324f0bf4cfc591d95'
    assert len(old_readme.splitlines(keepends=True))==len(new_readme.splitlines(keepends=True))
    changed_lines=[i+1 for i,(a,b) in enumerate(zip(old_readme.splitlines(keepends=True),new_readme.splitlines(keepends=True))) if a!=b]
    assert changed_lines==[109]
    assert now['documentation'][readme_index]['sha256']==now['documentation'][readme_index]['stagedSDKSHA256']==sha(new_readme)
    assert now['documentation'][readme_index]['stagedSDKMatches']
    out('readme-shipping-binding.json',{'source':SOURCE,'path':README,'actualSHA256':sha(new_readme),'previousSHA256':sha(old_readme),'changedLines':changed_lines,'allOtherLinesByteIdentical':True,'actualExecutedSnippetDocument':now['documentation'][readme_index],'scope':'Previously post-MAIN15 scope clarification is now actually shipped in MAIN16. The one prose line does not change the inventoried descriptor or any executable snippet.'})
    inventory_path='docs/miniapp-sdk/source-inventory.json'
    assert old_rows[inventory_path]==new_rows[inventory_path]
    assert sha(git_bytes(SOURCE,inventory_path))==new_rows[inventory_path]['sha256']==sha(git_bytes(OLD_SOURCE,inventory_path))
    reach=json.loads((E/'raw/changed-sdk/docs/miniapp-sdk/extension-reachability.json').read_bytes())
    project='AI_HLY.xcodeproj/project.pbxproj';project_sha=sha(git_bytes(SOURCE,project))
    assert reach['sourceRefs']['projectTargets']['sha256']==project_sha
    assert reach['sourceRefs']['currentScope']['sha256']==sha(new_readme)
    out('reachability-provenance-binding.json',{'source':SOURCE,'project':{'path':project,'sha256':project_sha,'actualReference':reach['sourceRefs']['projectTargets']},'READMEReference':reach['sourceRefs']['currentScope'],'unchangedSourceInventorySHA256':new_rows[inventory_path]['sha256'],'generatorExecuted':False})
    doc_paths=[p for p in new_rows if p.startswith('docs/')];example_paths=[p for p in new_rows if p.startswith('examples/')];declaration_paths=[p for p in new_rows if p.endswith(('.d.ts','.d.mts','.d.cts'))]
    summary={'status':'PASS_EXPECTED_README_AND_REACHABILITY_DELTA','outerArtifact':{'path':str(OUTER),'artifactID':14942495736,'bytes':OUTER.stat().st_size,'sha256':outer_sha},'nested':{'member':'runtime-host/RuntimeHostResources.zip','bytes':nested_info.file_size,'sha256':nested_sha},'sdk':{'manifestSHA256':sha(mb),'previousManifestSHA256':sha(old_bytes),'manifestBytes':len(mb),'manifestByteIdentical':mb==old_bytes,'inputSHA256':after['inputSHA256'],'computedInputSHA256':computed_input,'previousInputSHA256':before['inputSHA256'],'sourceInputs':len(after['sourceInputs']),'unchangedInputCount':len(after['sourceInputs'])-len(input_delta),'changedInputs':len(input_delta),'fileRows':len(after['files']),'unchangedFileRows':len(after['files'])-len(file_delta),'changedFileRows':len(file_delta),'sameOrderedPaths':True,'engineMetadataIdentical':before['engines']==after['engines'],'upstreamMetadataIdentical':before['upstream']==after['upstream']},'sourceApplicability':{'priorSource':OLD_SOURCE,'testedSource':SOURCE,'evidenceBase':BASE,'gitChangedInputPaths':git_changes,'gitChangedInputPathsAfterTestedSource':later_changes},'reusedManifestRowCoverage':{'docs':len(doc_paths),'unchangedDocs':len(doc_paths)-len(file_delta),'changedDocsFreshlyRead':len(checked),'examplesIncludingIndex':len(example_paths),'exampleRowsIdentical':all(old_rows.get(p)==new_rows[p] for p in example_paths),'declarations':len(declaration_paths),'declarationRowsIdentical':all(old_rows.get(p)==new_rows[p] for p in declaration_paths),'sourceInventoryRowIdentical':old_rows[inventory_path]==new_rows[inventory_path]},'snippet':{'sha256':sha(report_bytes),'status':now['status'],'sourceBlocks':now['sourceBlockCount'],'jsonBlocks':now['jsonBlockCount'],'excluded':len(now['excluded']),'projects':len(now['projects']),'diagnostics':0,'changedDocumentationRows':[x['path'] for i,x in enumerate(now['documentation']) if x!=prior['documentation'][i]],'checkerInputsIdentical':prior['checkerInputs']==now['checkerInputs'],'registrationIdentical':prior['registration']==now['registration']},'snippetDifferences':diff,'boundary':'Only nested manifest plus exactly three changed documentation bodies were opened. Prior unchanged member/type/example proof is reused by identical records. Native MiniApps build success, AI build failure and unexecuted application cases are separate facts from SDK preparation/typecheck success. No repeated112-member inspection/compiler/tests/build/download/generator.'}
    out('shipping-reconciliation.json',summary)
    print(json.dumps({k:v for k,v in summary.items() if k!='snippetDifferences'},indent=2))
finally:
    cleanup['bytesBeforeRemoval']=sum(p.stat().st_size for p in stage.rglob('*') if p.is_file())
    shutil.rmtree(stage);cleanup['removed']=not stage.exists();cleanup['tmpFreeBytesAfterRemoval']=shutil.disk_usage('/tmp').free;out('owned-staging-cleanup.json',cleanup)
