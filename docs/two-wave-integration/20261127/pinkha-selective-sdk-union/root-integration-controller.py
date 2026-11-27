import gzip, hashlib, json, os, pathlib, subprocess, time

ROOT=pathlib.Path('/mnt/development/projects/worktrees/hanlin-pinkha-original-sdk-union-20261127')
MIRROR='/mnt/development/projects/git-mirrors/hanlin-ai.git'
PRE=['sudo','-n','-u','chatgpt-agent']
G=PRE+['git','--no-optional-locks','-c','gc.auto=0','-c','user.name=ChatGPT','-c','user.email=chatgpt@openai.com','-C',str(ROOT)]
P=['sudo','-n','-u','ubuntu','-g','chatgpt-agent','git','--no-optional-locks','-c','gc.auto=0','-C',MIRROR]
BASE='20a1e6fa33ed261ba11e83a0b84a157029822e5e'
DONOR='3657b52ea9e72b8dc42819177dc8e1d865e8a6d3'
REF='refs/heads/codex/pinkha-original-sdk-union-20261127'
PREFIX='docs/two-wave-integration/20261127/pinkha-selective-sdk-union'
PAYLOAD=pathlib.Path('/var/lib/sentinelx/uploads/pinkha-root-hanlin-selective-intake.json.gz')
OUT=pathlib.Path('/tmp/pinkha-root-hanlin-selective-scrolling-integration-20261127.json')

def h(b):return hashlib.sha256(b).hexdigest()
def blob(b):return hashlib.sha1(b'blob '+str(len(b)).encode()+b'\0'+b).hexdigest()
def ident(b):return {'bytes':len(b),'sha256':h(b),'blob':blob(b)}
def b(*args):return subprocess.check_output(G+list(args),stderr=subprocess.PIPE)
def t(*args):return b(*args).decode().strip()
def owned(path,data):
    code="import pathlib,sys;p=pathlib.Path(sys.argv[1]);p.parent.mkdir(parents=True,exist_ok=True);f=p.open('xb');f.write(sys.stdin.buffer.read());f.close()"
    subprocess.run(PRE+['python3','-B','-c',code,str(ROOT/path)],input=data,capture_output=True,check=True)
def inverse(after,row):
    restored=after
    for op in sorted(row['literalInverse'],key=lambda x:x['afterStartByte'],reverse=True):
        lo,hi=op['afterStartByte'],op['afterEndByte']
        assert restored[lo:hi]==op['after'].encode(),row['path']
        restored=restored[:lo]+op['before'].encode()+restored[hi:]
    return restored
def pubrun(*args):return subprocess.check_output(P+['-c','credential.helper=!gh auth git-credential']+list(args),stderr=subprocess.PIPE).decode().strip()

assert not OUT.exists()
payload_bytes=PAYLOAD.read_bytes()
assert h(payload_bytes)=='2e11f070e212930c285434490ea9ef11a0a1052b87d9516e8a46c0e95e8a0434'
payload=gzip.decompress(payload_bytes)
assert h(payload)=='443a6b59de23d18fb484620acf3abb51b47baed64488d3c0dfc51fa59ee7c54c'
rows=json.loads(payload)['files']
data={r['path']:r['content'].encode() for r in rows}
assert len(data)==len(rows)==9
for r in rows:assert len(data[r['path']])==r['bytes'] and h(data[r['path']])==r['sha256']
assert h(data['independent-review.json'])=='2b48d63e9365b8307e56b95cca40340a3b29d8b73815dcd7bafff4e31c9736da'
assert h(data['selective-proposal/selective-source-proof.json'])=='3e0c238aa36f56710e6afb67e35e98f11db08eb330d483e6d485dbd315e15823'
assert h(data['selective-proposal/three-scrolling-one-localization.patch'])=='b3c0dea078f781deb37a3b543ae0c65d447bb1e28b9d85d7b9483bd5feaeb7a7'
assert h(data['selective-proposal/affected-original-tests.json'])=='569caf6f0eea30e2cb8840558e1a4fbebca2acef2e70dac510877124f8948063'
assert h(data['selective-proposal/original-six-regressions.patch'])=='c55072374d2eaf4f1591624e45a0c9a43d085c1390a2e154b62f9b6121742589'
assert h(data['selective-proposal/original-test-patch-replay-proof.json'])=='6f72038be24d665ef19b726f41c5a4baeceaf80a182cdce023c44bde2fc6d347'
production=json.loads(data['selective-proposal/selective-source-proof.json'])
tests=json.loads(data['selective-proposal/affected-original-tests.json'])
assert production['base']==tests['base']==BASE and production['donor']==tests['donor']==DONOR
source_rows=production['sourceFiles']+tests['files']; assert len(source_rows)==6
assert t('rev-parse','HEAD')==BASE and t('symbolic-ref','HEAD')==REF
assert t('rev-parse','HEAD^{tree}')=='14e860ce3f7d2b8623085f16d99d34b8b347a48c'
assert t('status','--porcelain=v1','--untracked-files=all')==''
assert not pathlib.Path(t('rev-parse','--git-path','MERGE_HEAD')).exists()
assert pubrun('ls-remote','--heads','origin',REF).split()==[BASE,REF]
if subprocess.run(G+['cat-file','-e',DONOR+'^{commit}'],capture_output=True).returncode:
    pubrun('fetch','--no-tags','--refmap=','origin',DONOR)
assert t('rev-parse',DONOR+'^{tree}')=='33c806257b89a5150ba071886ccf653125e3d2af'
before={}
for row in source_rows:
    path=row['path']
    if row['before'] is None:
        assert subprocess.run(G+['cat-file','-e',BASE+':'+path],capture_output=True).returncode!=0 and not (ROOT/path).exists()
    else:
        before[path]=b('show',BASE+':'+path);assert ident(before[path])==row['before'],path
        if (ROOT/path).exists():assert (ROOT/path).read_bytes()==before[path],path
for path,row in tests['originalAppAliases'].items():
    assert t('rev-parse',BASE+':'+path)==row['blob']
    assert b('show',BASE+':'+path)==row['source'].encode()
packages=['HanlinAgentSDK','HanlinPlatform','HanlinPresentationSDK','HanlinAppExtensionsSDK','HanlinNativeScriptRuntime','HanlinMiniAppsBridge']
package_before={p:t('rev-parse',BASE+':Packages/'+p) for p in packages}
protected={production['retainedOriginalNativeHandler']['path']:production['retainedOriginalNativeHandler']['blob'],
           production['retainedOriginalExplicitHandlerTest']['path']:production['retainedOriginalExplicitHandlerTest']['blob']}
for path,v in protected.items():assert t('rev-parse',BASE+':'+path)==v
free=os.statvfs(ROOT).f_bavail*os.statvfs(ROOT).f_frsize
assert free>512*1024*1024+4*1024*1024,'bounded source-only allocation4MiB + original512MiB floor'
state={'schema':'hanlin-root-selective-sdk-integration-v1','base':BASE,'donor':DONOR,'startedAt':time.time(),
       'status':'RUNNING','controllerSHA256':h(pathlib.Path(__file__).read_bytes()),'payloadSHA256':h(payload),
       'sourceFiles':source_rows,'packagesBefore':package_before,'startingFreeBytes':free,
       'compiler':'NOT_RUN','nativeRuntime':'NOT_RUN','scope':'Four original selected SDK production files plus six original added regression methods in two App test files; no G19 App overlay call-site activation.'}
f=OUT.open('x');os.chmod(OUT,0o600)
def persist():
    f.seek(0);f.truncate();json.dump(state,f,ensure_ascii=False,indent=2,sort_keys=True);f.write('\n');f.flush();os.fsync(f.fileno())
try:
    persist()
    sparse=t('sparse-checkout','list');state['sparseBefore']=sparse
    additions='\n'.join('/'+r['path'] for r in tests['files'])+'\n/'+PREFIX+'/**\n'
    subprocess.run(G+['sparse-checkout','add','--stdin'],input=additions.encode(),capture_output=True,check=True)
    assert t('status','--porcelain=v1','--untracked-files=all')==''
    for row in source_rows:
        if row['before'] is not None:assert (ROOT/row['path']).read_bytes()==before[row['path']]
    for patch in ['selective-proposal/three-scrolling-one-localization.patch','selective-proposal/original-six-regressions.patch']:
        subprocess.run(G+['apply','--check','-'],input=data[patch],capture_output=True,check=True)
        subprocess.run(G+['apply','-'],input=data[patch],capture_output=True,check=True)
    for row in source_rows:
        path=row['path'];after=(ROOT/path).read_bytes();assert ident(after)==row['after'],path
        if row['before'] is not None:assert inverse(after,row)==before[path],path
        if row.get('afterEqualsOriginalDonor') or row in tests['files']:
            assert after==b('show',DONOR+':'+path),path
    loc=next(r for r in source_rows if r['path'].endswith('Localizable.xcstrings'))
    old=json.loads(before[loc['path']]);new=json.loads((ROOT/loc['path']).read_bytes())
    assert len(old['strings'])==1294 and len(new['strings'])==1295
    assert set(new['strings'])-set(old['strings'])=={loc['onlyAddedKey']}
    assert all(new['strings'][key]==value for key,value in old['strings'].items())
    assert new['strings'][loc['onlyAddedKey']]==loc['addedValue']
    extras=[]
    for r in rows:
        path=PREFIX+'/'+r['path'];owned(path,data[r['path']]);extras.append(path)
    prior=pathlib.Path('/tmp/pinkha-root-hanlin-union-publication-resume-20261127.json').read_bytes()
    assert h(prior)=='69644eeb1deced0568c440390516404c8bbdf8bfb90510d2348d80c73e981845'
    for name,value in [('prior20a-publication-receipt.json',prior),('root-integration-controller.py',pathlib.Path(__file__).read_bytes())]:
        path=PREFIX+'/'+name;owned(path,value);extras.append(path)
    review={'base':BASE,'originalDonor':DONOR,'productionFiles':4,'testFiles':2,'newOriginalRegressionMethods':6,
      'rootReviewed':['Root read full selected production patch, full native scroll handle, all six original regression methods and independent latest-source audit.',
       'Coalesced native layout reads retain original conversation/viewport generation and discard stale work; original invalidation cancels the pending read. Diagnostic peek changes no generation or readiness. Equal near-bottom Boolean samples no longer repeatedly invalidate observed readers.',
       'Original overlay retains live anchor, unique current conversation and revalidates live selection. It does not itself qualify the originating transcript. Existing Anytype SDK host and G19 main App call-site adoption/runtime are separately scoped; no whole divergent main-App file is imported.',
       'Every old locale byte and all1294 original entries survive; only the original Select-a-conversation member is added. The98 original entries absent in donor remain.',
       'All original tests remain by addition-only inverse, including original no-handler/JavaScript-state regression. The six selected added methods are AI_HLYTests with UIKit/App requirements, not a claim of standalone macOS package execution.',
       'Original20a worker/cancellation/Composer/provider/cache/context/widget/native-window/assistant/AX/renderer capability graph is retained. The donor synthetic demo handler is explicitly excluded. Five other package trees and all original locks stay identical.'],
      'sourceOnly':True,'originalHandlerBlobs':protected,'compiler':'NOT_RUN','sixRegressions':'NOT_RUN','explicitHandlerNativeRoute':'NOT_RUN','iPhoneAndIPadConsumerUI':'NOT_RUN'}
    path=PREFIX+'/root-source-review.json';owned(path,(json.dumps(review,ensure_ascii=False,indent=2,sort_keys=True)+'\n').encode());extras.append(path)
    expected=sorted([r['path'] for r in source_rows]+extras)
    b('add','--sparse','--',*[r['path'] for r in source_rows],PREFIX)
    b('diff','--cached','--check','--',*[r['path'] for r in source_rows])
    assert t('diff','--cached','--name-only').splitlines()==expected
    tree=t('write-tree')
    package_after={p:t('rev-parse',tree+':Packages/'+p) for p in packages}
    for p in packages:
        if p!='HanlinPresentationSDK':assert package_after[p]==package_before[p],p
    for path,v in protected.items():assert t('rev-parse',tree+':'+path)==v
    assert t('diff','--name-only',BASE,tree,'--','Packages/HanlinPresentationSDK').splitlines()==sorted(r['path'] for r in production['sourceFiles'])
    state.update({'stagedTree':tree,'files':expected,'packagesAfter':package_after,'sourceInversesPassed':True,'sourceMapChanges':0});persist()
    message='Retain latest original scrolling SDK fixes in the preserved Pinkha union\n\nSelect three original scrolling sources and one locale member from3657 without losing original handler, cancellation, Composer, context, widgets or native-window capabilities. Retain six original added regression methods with every existing test. Compile and runtime acceptance remain pending.\n\nOriginal donor: '+DONOR+'\n'
    subprocess.run(G+['commit','-F','-'],input=message.encode(),capture_output=True,check=True)
    head=t('rev-parse','HEAD');assert t('rev-parse','HEAD^')==BASE
    assert t('status','--porcelain=v1','--untracked-files=all')==''
    state['head']=head;state['tree']=tree;persist()
    assert pubrun('ls-remote','--heads','origin',REF).split()==[BASE,REF]
    push=subprocess.run(P+['-c','remote.origin.mirror=false','-c','credential.helper=!gh auth git-credential','push','origin',head+':'+REF],capture_output=True,text=True,timeout=90)
    state.update({'pushExit':push.returncode,'pushStdout':push.stdout,'pushStderr':push.stderr});persist();assert push.returncode==0
    assert pubrun('ls-remote','--heads','origin',REF).split()==[head,REF]
    state.update({'status':'PASS_SELECTED_SOURCE_PUBLISHED','normalPushReadback':head,'completedAt':time.time()});persist()
except BaseException as exc:
    state['status']='FAILED_PRESERVED_FOR_INSPECTION';state['failure']=str(exc);persist();raise
finally:
    f.close()
    print(json.dumps({'status':state['status'],'head':state.get('head'),'tree':state.get('tree'),'packagesAfter':state.get('packagesAfter'),
      'receipt':str(OUT),'receiptSHA256':h(OUT.read_bytes())}),flush=True)
