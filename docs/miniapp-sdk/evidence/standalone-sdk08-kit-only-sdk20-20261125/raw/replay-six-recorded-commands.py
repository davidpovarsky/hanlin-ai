#!/usr/bin/env python3
"""Replay the six retained SDK08 CLI commands against frozen SDK20.
No retained runner script existed. Commands/fixtures/assertions are retained;
this operational harness only changes the isolated destination and SDK identity.
"""
from pathlib import Path
import datetime, hashlib, json, os, shutil, stat, subprocess, time, traceback, zipfile

B=Path('/mnt/development/projects/transfers/hanlin-primary-ce49-20261124')
OLD=B/'standalone-sdk08-kit-only'
ROOT=B/'standalone-sdk08-kit-only-sdk20'
KIT=ROOT/'kit'
E=ROOT/'evidence'
PRODUCER=B/'sdk20-dff3b45c'
REPO=Path('/mnt/development/projects/worktrees/hanlin-miniapps-sdk-completion-20261123')
SOURCE='7f5dad540ade7fec6e5ace980eb99d1d6d0c2e8f'
SDK_SOURCE='dff3b45c99a57bf8fe8ec721db3fa1fafce7134b'
SDK_SHA='c1c181182d1e47db1f7977a284cea507397dc47e9170645b019dbdec5ab858ca'
MANIFEST_SHA='6f11ed8da3df18627f05932d47b5b68dec54eb26ac396151a21cbc8c3e65800e'
IDS=['expo-validate','expo-build','nativescript-validate','nativescript-build','negative-type-error-validate','negative-type-error-build']

def now(): return datetime.datetime.now(datetime.timezone.utc).isoformat()
def sha(p):
    with Path(p).open('rb') as f:return hashlib.file_digest(f,'sha256').hexdigest()
def row(p,root=ROOT):
    p=Path(p)
    return {'path':str(p.relative_to(root)),'bytes':p.stat().st_size,'sha256':sha(p),'mode':oct(stat.S_IMODE(p.stat().st_mode))}
def write(p,v):
    p=Path(p);p.parent.mkdir(parents=True,exist_ok=True)
    data=(json.dumps(v,indent=2,ensure_ascii=False)+'\n').encode()
    with p.open('xb') as f:f.write(data)
def state(v):
    p=ROOT/'state.json';tmp=ROOT/'state.json.next'
    tmp.write_text(json.dumps(v,indent=2,ensure_ascii=False)+'\n');os.replace(tmp,p)
def main():
    assert not KIT.exists(), 'Fresh kit already exists; inspect before resuming.'
    E.mkdir(parents=True,exist_ok=True)
    (ROOT/'tmp').mkdir()
    started=now();began=time.monotonic()
    s={'schema':1,'status':'STAGING','startedAt':started,'pid':os.getpid(),'productionSource':SOURCE,'SDKProducerSource':SDK_SOURCE,
       'nativeExecution':'NOT_RUN','upstreamResolution':False,'npmInstallUsed':False,'completed':[]}
    state(s)
    oldreceipt=json.loads((OLD/'evidence/receipt.json').read_text())
    assert sha(OLD/'evidence/verification-summary.json')=='7d1885c948302bc7a4b8151be968105bc41ffbebee715d2d5cdc4800fea9970f'
    assert sha(OLD/'payload/export-standalone-toolchain.py')=='cbedfdda2acdada007e95514ebc54ffe406640c1671eb0968d882cfdc88bb186'
    assert sha(PRODUCER/'verification.json')=='8c33bf22355ab2749f81c8abc5fa0b08ef8fe87fca78077512f35060d789f21d'
    assert sha(PRODUCER/'MiniAppSDK20.zip')==SDK_SHA
    env=os.environ.copy()
    env.update({'GIT_CONFIG_COUNT':'1','GIT_CONFIG_KEY_0':'safe.directory','GIT_CONFIG_VALUE_0':str(REPO)})
    stagecmd=['/usr/bin/python3',str(OLD/'payload/export-standalone-toolchain.py'),
              '--repository',str(REPO),'--source',SOURCE,'--sdk-source',SDK_SOURCE,
              '--sdk-zip',str(PRODUCER/'MiniAppSDK20.zip'),'--expected-sdk-sha256',SDK_SHA,
              '--expected-manifest-sha256',MANIFEST_SHA,'--output',str(KIT)]
    with (E/'staging.stdout').open('xb') as out,(E/'staging.stderr').open('xb') as err:
        r=subprocess.run(stagecmd,stdout=out,stderr=err,env=env,cwd=ROOT)
    assert r.returncode==0, 'Original exporter failed; retained logs.'
    export=json.loads((KIT/'toolchain-export-receipt.json').read_text())
    assert len(export['SDKFiles'])==25682
    assert sha(KIT/'MiniAppSDK/miniapp-sdk.json')==MANIFEST_SHA
    prod=[]
    for expected in oldreceipt['productionFiles']:
        p=KIT/expected['path'];assert sha(p)==expected['sha256'] and p.stat().st_size==expected['bytes']
        prod.append(row(p))
    for name in ['expo-hello-world','nativescript-hello-world']:
        shutil.copytree(KIT/'MiniAppSDK/examples'/name,KIT/'workspace'/name)
    shutil.copytree(KIT/'workspace/nativescript-hello-world',KIT/'workspace/nativescript-type-error')
    shutil.copy2(OLD/'kit/workspace/nativescript-type-error/index.ts',KIT/'workspace/nativescript-type-error/index.ts')
    source_rows=[]
    for expected in oldreceipt['files']:
        if expected['path'].startswith('kit/workspace/'):
            p=ROOT/expected['path'];assert sha(p)==expected['sha256'] and p.stat().st_size==expected['bytes']
            source_rows.append(row(p))
    actual_source=[p for p in (KIT/'workspace').rglob('*') if p.is_file()]
    assert len(source_rows)==22 and len(actual_source)==22
    ancestors=[p/'node_modules' for p in [KIT,*KIT.parents] if (p/'node_modules').exists()]
    assert ancestors==[],str(ancestors)
    (KIT/'artifacts').mkdir()
    sdk_rows=[row(p,KIT) for p in sorted((KIT/'MiniAppSDK').rglob('*')) if p.is_file()]
    assert len(sdk_rows)==25682
    write(E/'sdk-member-inventory-before.json',sdk_rows)
    versions={}
    for name,path in [('node','/usr/local/bin/node'),('python','/usr/bin/python3'),('strace','/usr/bin/strace')]:
        versions[name]={'path':path,'version':subprocess.check_output([path,'--version'],text=True).splitlines()[0],'sha256':sha(path)}
    original_records={}
    for ident in IDS:
        p=OLD/'evidence'/f'{ident}-command.json'
        original_records[ident]={'path':str(p),'bytes':p.stat().st_size,'sha256':sha(p),'record':json.loads(p.read_text())}
    write(E/'replay-contract.json',{'schema':1,'description':__doc__,'oldReceipt':row(OLD/'evidence/receipt.json',OLD),
       'oldVerification':row(OLD/'evidence/verification-summary.json',OLD),
       'originalRecords':original_records,'ids':IDS,'productionFiles':prod,'fixtureFiles':source_rows,
       'sdkArchive':row(PRODUCER/'MiniAppSDK20.zip',PRODUCER),'SDKManifestSHA256':MANIFEST_SHA,
       'SDKInputSHA256':json.loads((KIT/'MiniAppSDK/miniapp-sdk.json').read_text())['inputSHA256'],
       'prerequisites':versions,'ancestorNodeModules':[],
       'operationalWrapper':'New replay of retained argv/environment/strace; no historical runner-script identity is claimed.',
       'networkAndDependencies':'No install/resolver invoked. Complete syscall traces retained for independent network/dependency audit.'})
    write(E/'staging-receipt.json',{'schema':1,'status':'STAGED_AND_HASH_VERIFIED','observedAt':now(),
       'productionSource':SOURCE,'SDKProducerSource':SDK_SOURCE,'command':stagecmd,
       'SDKFileCountIncludingManifest':len(sdk_rows),'productionFiles':prod,'fixtureFiles':source_rows,
       'SDKArchiveSHA256':SDK_SHA,'SDKManifestSHA256':MANIFEST_SHA,'versions':versions,
       'exportReceipt':row(KIT/'toolchain-export-receipt.json'),'sourceOrSDKRegenerated':False})
    s['status']='RUNNING';s['phase']='CLI';state(s)
    for ident in IDS:
        original=original_records[ident]['record']
        cmd=original['command']
        expected=0 if not ident.startswith('negative-') else 1
        env=dict(original['environment']);env['TMPDIR']=str(ROOT/'tmp')
        # Exact retained trace arguments except its fresh output path and TMPDIR.
        tracecmd=original['traceCommand'].copy()
        tracecmd[tracecmd.index('-o')+1]=str(E/f'{ident}.strace')
        assert tracecmd[tracecmd.index('-o')+2:]==cmd
        st=now();t=time.monotonic();s['activeCommand']=ident;s['activeCommandStartedAt']=st;state(s)
        with (E/f'{ident}.stdout').open('xb') as out,(E/f'{ident}.stderr').open('xb') as err:
            proc=subprocess.Popen(tracecmd,cwd=KIT,env=env,stdout=out,stderr=err)
            s['activePID']=proc.pid;state(s)
            rc=proc.wait()
        reportrel=original['report'];report=ROOT/reportrel
        rec={'schema':1,'id':ident,'startedAt':st,'finishedAt':now(),'elapsedSeconds':time.monotonic()-t,
             'cwd':str(KIT),'command':cmd,'traceCommand':tracecmd,'environment':env,
             'returncode':rc,'expectedReturnCode':expected,'expectedOutcomeMatched':rc==expected,
             'report':reportrel,'originalRecord':{k:v for k,v in original_records[ident].items() if k!='record'}}
        write(E/f'{ident}-command.json',rec)
        s['completed'].append({'id':ident,'returncode':rc,'elapsedSeconds':rec['elapsedSeconds']})
        s.pop('activePID',None);state(s)
        assert rc==expected, f'{ident}: unexpected exit {rc}'
        data=json.loads(report.read_text())
        assert data.get('succeeded')==(expected==0), f'{ident}: unexpected succeeded flag'
        assert data['sdk']['manifestSHA256']==MANIFEST_SHA, f'{ident}: wrong SDK identity'
        if expected==0:
            assert data.get('diagnostics')==[], f'{ident}: diagnostics not empty'
        else:
            codes=[d.get('code') for d in data.get('diagnostics',[])]
            assert codes==['TS2322'], f'{ident}: expected one TS2322, got {codes}'
    sdk_after=[row(p,KIT) for p in sorted((KIT/'MiniAppSDK').rglob('*')) if p.is_file()]
    write(E/'sdk-member-inventory-after.json',sdk_after)
    assert sdk_after==sdk_rows,'SDK member bytes/modes changed'
    for r in prod+source_rows:
        p=ROOT/r['path'];assert row(p)==r,'Production/source input changed'
    assert not (KIT/'artifacts/Rejected-Type-Error.hanlinNativeScript').exists()
    assert not (KIT/'workspace/nativescript-type-error/.hanlin-build').exists()
    s.update({'status':'SIX_COMMANDS_EXECUTED_EXPECTED','finishedAt':now(),'elapsedSeconds':time.monotonic()-began,
              'SDKFilesByteAndModeIdenticalAfter':len(sdk_rows),'independentTraceAndArchiveAudit':'PENDING'})
    s.pop('activeCommand',None);s.pop('activeCommandStartedAt',None);state(s)
    print(json.dumps({'status':s['status'],'completed':s['completed'],'SDKFiles':len(sdk_rows)}),flush=True)
if __name__=='__main__':
    try:main()
    except BaseException as exc:
        p=ROOT/'state.json'
        s=json.loads(p.read_text()) if p.exists() else {'schema':1}
        s.update({'status':'FAILED','finishedAt':now(),'error':str(exc),'traceback':traceback.format_exc()})
        state(s);raise
