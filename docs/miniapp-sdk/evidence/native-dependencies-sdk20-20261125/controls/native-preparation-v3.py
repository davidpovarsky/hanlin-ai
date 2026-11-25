#!/usr/bin/env python3
"""Run only the original pinned native dependency producers in the new owned root."""
import argparse, datetime, fcntl, hashlib, importlib.util, json, math, os, pathlib, signal, stat, subprocess, sys, time, traceback
P=pathlib.Path
def utc(): return datetime.datetime.now(datetime.timezone.utc).isoformat()
def sha(p): return hashlib.file_digest(P(p).open('rb'),'sha256').hexdigest()
def write(p,obj):
    tmp=P(str(p)+'.tmp');tmp.write_text(json.dumps(obj,ensure_ascii=False,indent=2)+'\n');os.replace(tmp,p)
def row(p):
    p=P(p);return {'path':str(p),'bytes':p.stat().st_size,'sha256':sha(p),'mode':stat.S_IMODE(p.stat().st_mode)}
def read_bound(x):
    p=P(x['path']);assert p.is_file() and not p.is_symlink(),str(p)
    assert p.stat().st_size==x['bytes'] and sha(p)==x['sha256'],str(p)
    return p
def run_small(argv,cwd=None,env=None,timeout=15):
    return subprocess.run(argv,cwd=cwd,env=env,text=True,capture_output=True,check=True,timeout=timeout)
def live_group(pgid):
    try: os.killpg(pgid,0)
    except ProcessLookupError:return []
    r=subprocess.run(['/usr/bin/pgrep','-g',str(pgid)],text=True,capture_output=True,timeout=5)
    if r.returncode==1 and not r.stdout.strip() and not r.stderr.strip():return []
    assert r.returncode==0,(r.returncode,r.stderr)
    pids=[int(x) for x in r.stdout.split()]
    if not pids:return []
    r=subprocess.run(['/bin/ps','-p',','.join(map(str,pids)),'-o','pid=,pgid=,state='],text=True,capture_output=True,timeout=5)
    if r.returncode==1 and not r.stdout.strip() and not r.stderr.strip():return []
    assert r.returncode==0,(r.returncode,r.stderr)
    return [list(x.split()) for x in r.stdout.splitlines() if len(x.split())==3 and int(x.split()[1])==pgid and not x.split()[2].startswith('Z')]
def cleanup_group(proc):
    found=live_group(proc.pid)
    if found:
        os.killpg(proc.pid,signal.SIGTERM)
        deadline=time.monotonic()+8
        while time.monotonic()<deadline and live_group(proc.pid):time.sleep(.2)
        if live_group(proc.pid):os.killpg(proc.pid,signal.SIGKILL)
    try:proc.wait(timeout=10)
    except subprocess.TimeoutExpired:raise RuntimeError('Owned command did not reap')
    deadline=time.monotonic()+5
    while time.monotonic()<deadline and live_group(proc.pid):time.sleep(.2)
    assert not live_group(proc.pid),'Owned native producer group remains alive'
def main():
    ap=argparse.ArgumentParser();ap.add_argument('--plan',required=True);args=ap.parse_args()
    plan_path=P(args.plan);plan=json.loads(plan_path.read_text());root=P(plan['root']);out=P(plan['output'])
    assert plan['id']=='notification-native-preparation-v3' and plan['allowanceSeconds']==1800
    assert root==P('/Users/m1/builds/hanlin-notification-wire-fix-20261125') and root.resolve()==root
    assert out==root/'validation/notification-native-preparation-v3' and not out.exists()
    assert sha(__file__)==plan['controllerSHA256']
    for x in plan['requiredFiles']:read_bound(x)
    assert run_small(['/usr/bin/git','rev-parse','HEAD'],cwd=root).stdout.strip()==plan['source']
    assert run_small(['/usr/bin/git','rev-parse','HEAD^{tree}'],cwd=root).stdout.strip()==plan['sourceTree']
    prior=plan['priorPreparation']
    prior_state=json.loads(read_bound(prior['state']).read_text())
    prior_ledger=json.loads(read_bound(prior['ledger']).read_text())
    prior_plan=json.loads(read_bound(prior['plan']).read_text())
    assert prior_state['status']=='FAILED' and prior_state['source']==plan['source']
    assert not prior_state['sourceErrors'] and not prior_state['cleanupErrors']
    assert prior_ledger['allowanceSeconds']==1800 and prior_ledger['totalChargedSeconds']==188.837976625
    assert prior_ledger['totalChargedSeconds']==prior_state['actualElapsedSeconds']
    assert plan['commands']==prior_plan['commands'][4:] and plan['requiredSourceFiles']==prior_plan['requiredSourceFiles']
    assert [x['id'] for x in prior_state['commands'][:4]]==[x['id'] for x in prior_plan['commands'][:4]]
    for completed in prior_state['commands'][:4]:
        assert completed['status']=='PASS' and completed['exitCode']==0
        read_bound(completed['logIdentity'])
    continuation=plan['priorContinuation']
    continuation_state=json.loads(read_bound(continuation['state']).read_text())
    continuation_ledger=json.loads(read_bound(continuation['ledger']).read_text())
    continuation_plan=json.loads(read_bound(continuation['plan']).read_text())
    assert continuation_state['id']=='notification-native-preparation-v2' and continuation_state['status']=='FAILED'
    assert continuation_state['source']==continuation_state['sourceAfter']==plan['source']
    assert not continuation_state['sourceErrors'] and not continuation_state['cleanupErrors']
    assert continuation_plan['priorPreparation']==prior and continuation_plan['commands']==plan['commands']
    assert continuation_plan['python']==plan['python']
    assert continuation_ledger['allowanceSeconds']==1800
    assert continuation_ledger['charges'][:-1]==prior_ledger['charges']
    assert continuation_ledger['charges'][-1]['seconds']==continuation_state['actualElapsedSeconds']
    assert continuation_ledger['totalChargedSeconds']==continuation_state['totalChargedSeconds']==math.fsum(x['seconds'] for x in continuation_ledger['charges'])
    for completed in continuation_state['commands']:read_bound(completed['logIdentity'])
    toolchain=plan['toolchainPreparation'];installed=json.loads(read_bound(toolchain['state']).read_text())
    assert installed['status']=='INSTALLED' and installed['exitCode']==0 and installed['source']==plan['source']
    assert not installed['sourceErrors'] and not installed['cleanupErrors']
    read_bound(installed['log'])
    install_charge={'startedAt':installed['startedAt'],'finishedAt':installed['finishedAt'],
                    'seconds':installed['actualElapsedSeconds'],'status':'INSTALLED','phase':'notification-metadata-toolchain-v1'}
    assert toolchain['charge']==install_charge and plan['cmake']==installed['cmake']
    prior_charges=continuation_ledger['charges']+[install_charge]
    prior_total=math.fsum(x['seconds'] for x in prior_charges)
    assert plan['remainingAllowanceSeconds']==1800-prior_total and plan['remainingAllowanceSeconds']>30
    before_diff=subprocess.run(['/usr/bin/git','diff','--binary','HEAD'],cwd=root,capture_output=True,check=True,timeout=30).stdout
    assert hashlib.sha256(before_diff).hexdigest()==plan['preparedTrackedDiffSHA256']
    restoration=json.loads(P(plan['restoration']['path']).read_text())
    assert restoration['status']=='RESTORED_INPUTS' and restoration['source']==plan['source']
    sdk=json.loads(P(plan['sdkManifest']['path']).read_text());assert len(sdk['sourceInputs'])==235
    def verify_sdk():
        errors=[]
        for x in sdk['sourceInputs']:
            p=root/x['path']
            if not p.is_file() or sha(p)!=x['sha256']:errors.append(x['path'])
        for x in plan['hostArchives']:
            if sha(x['path'])!=x['sha256']:errors.append(x['path'])
        return errors
    assert not verify_sdk(),'SDK20 source/resource mismatch before preparation'
    node=P(plan['node']['path']);assert node.resolve()==node and sha(node)==plan['node']['sha256']
    python=plan['python']
    assert P(python['aliasPath']).resolve()==P(python['resolvedPath'])
    assert sha(python['resolvedPath'])==python['sha256']
    env=os.environ.copy()
    env.update({'PATH':str(node.parent)+':'+str(P(python['aliasPath']).parent)+':/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin',
                'DEVELOPER_DIR':'/Applications/Xcode.app/Contents/Developer',
                'CI':'1','GITHUB_SHA':plan['source'],'PYTHONUNBUFFERED':'1'})
    ident=json.loads(run_small([str(node),'-e','console.log(JSON.stringify({version:process.versions.node,platform:process.platform,arch:process.arch,execPath:process.execPath}))'],env=env).stdout)
    assert ident=={'version':'24.5.0','platform':'darwin','arch':'arm64','execPath':str(node)},ident
    python_ident=json.loads(run_small(['python3','-c','import sys,tarfile,inspect,json;print(json.dumps({"version":sys.version.split()[0],"executable":sys.executable,"supportsFilter":"filter" in inspect.signature(tarfile.TarFile.extractall).parameters}))'],env=env).stdout)
    assert python_ident['version']=='3.12.16' and python_ident['supportsFilter'] is True
    assert P(python_ident['executable']).resolve()==P(python['resolvedPath'])
    cmake=plan['cmake'];cmake_path=P(cmake['resolvedPath'])
    assert P(cmake['path']).resolve()==cmake_path and cmake_path.stat().st_size==cmake['bytes']
    assert sha(cmake_path)==cmake['sha256']
    assert P(run_small(['/usr/bin/which','cmake'],env=env).stdout.strip()).resolve()==cmake_path
    assert run_small([cmake['path'],'--version'],env=env).stdout==cmake['version']
    st=os.statvfs(root);free=st.f_bavail*st.f_frsize
    assert free>=plan['resourceAssessment']['requiredFreeBytes'],('Insufficient measured preparation capacity',free)
    lock=(root/'validation/native-owner.lock').open('a+');fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB)
    started=time.monotonic();out.mkdir()
    state={'schema':1,'id':plan['id'],'source':plan['source'],'sourceTree':plan['sourceTree'],
           'status':'RUNNING','startedAt':utc(),'pid':os.getpid(),'commands':[],'errors':[],
           'sourceErrors':[],'cleanupErrors':[],'freeBytesAtStart':free,'nodeIdentity':ident,
           'allowanceSeconds':1800,'priorLedgersModified':False,'oldDerivedDataModified':False,
           'plan':row(plan_path),'controller':row(__file__),'restoration':plan['restoration'],
           'priorPreparation':prior,'priorContinuation':continuation,'toolchainPreparation':toolchain,
           'reusedCommands':prior_state['commands'][:4],'pythonIdentity':python_ident,'cmakeIdentity':cmake,
           'sdkManifest':plan['sdkManifest'],'hostArchives':plan['hostArchives']}
    proc=None;current=None
    def checkpoint():
        state['observedAt']=utc();state['elapsedSeconds']=time.monotonic()-started;write(out/'state.json',state)
    def interrupt(sig,frame):raise KeyboardInterrupt('Controller signal '+str(sig))
    signal.signal(signal.SIGTERM,interrupt);signal.signal(signal.SIGINT,interrupt)
    checkpoint()
    try:
        for cmd in plan['commands']:
            remaining=plan['remainingAllowanceSeconds']-(time.monotonic()-started)
            if remaining<=30:raise TimeoutError('Native preparation allowance exhausted before next original command')
            log=out/(cmd['id']+'.log')
            current={'id':cmd['id'],'argv':cmd['argv'],'cwd':str(root),'startedAt':utc(),'status':'RUNNING','log':str(log)}
            state['commands'].append(current);checkpoint()
            t=time.monotonic()
            with log.open('xb') as output:
                proc=subprocess.Popen(cmd['argv'],cwd=root,env=env,stdout=output,stderr=subprocess.STDOUT,start_new_session=True)
                current['pid']=proc.pid;current['pgid']=proc.pid;checkpoint()
                code=proc.wait(timeout=remaining-30)
            cleanup_group(proc);proc=None
            current.update({'status':'PASS' if code==0 else 'FAILED','exitCode':code,'finishedAt':utc(),
                            'actualElapsedSeconds':time.monotonic()-t,'logIdentity':row(log)})
            checkpoint()
            if code:raise RuntimeError('Original producer failed: '+cmd['id'])
        state['sourceErrors']=verify_sdk()
        for x in plan['requiredSourceFiles']:
            if sha(x['path'])!=x['sha256']:state['sourceErrors'].append(x['path'])
        if state['sourceErrors']:raise RuntimeError('Declared source/resource bytes changed; SDK20 is not relabeled')
        spec=importlib.util.spec_from_file_location('native_artifacts',root/'Scripts/SDK/native_artifacts.py')
        mod=importlib.util.module_from_spec(spec);sys.modules[spec.name]=mod;spec.loader.exec_module(mod)
        frameworks=[]
        for target,path in mod.TARGETS.items():
            frameworks.append({'target':target,'path':path,'libraries':mod.framework_libraries(root/path,target)})
        assert len(frameworks)==15
        write(out/'prepared-frameworks.json',{'schema':1,'source':plan['source'],'frameworks':frameworks})
        state['frameworkReceipt']=row(out/'prepared-frameworks.json')
        metadata=root/'build/nativescript-metadata-tool/provenance.json'
        proof=json.loads(metadata.read_text())
        state['metadataProvenance']=row(metadata);state['metadataTool']=row(root/'build/nativescript-metadata-tool/bin/objc-metadata-generator')
        assert proof['generatorSHA256']==state['metadataTool']['sha256']
        assert proof['xcode']==run_small(['/usr/bin/xcodebuild','-version'],env=env).stdout.strip()
        tracked=run_small(['/usr/bin/git','status','--porcelain','--untracked-files=no'],cwd=root).stdout
        (out/'tracked-status.txt').write_text(tracked)
        diff=run_small(['/usr/bin/git','diff','--binary','HEAD'],cwd=root,timeout=30).stdout
        (out/'prepared-source.diff').write_text(diff)
        paths=run_small(['/usr/bin/git','diff','--name-only','-z','HEAD'],cwd=root).stdout.split('\0')
        changes=[]
        for p in filter(None,paths):
            actual=root/p
            prior=subprocess.run(['/usr/bin/git','show','HEAD:'+p],cwd=root,capture_output=True,check=True).stdout
            changes.append({'path':p,'beforeGitSHA256':hashlib.sha256(prior).hexdigest(),'after':row(actual) if actual.is_file() else None})
        state['preparedChanges']=changes;state['trackedStatus']=row(out/'tracked-status.txt');state['preparedDiff']=row(out/'prepared-source.diff')
        state['sdkSourceInputsVerified']=235;state['status']='PREPARED'
    except BaseException as error:
        state['status']='FAILED';state['errors'].append(repr(error));state['traceback']=traceback.format_exc()
    finally:
        if proc is not None:
            try:cleanup_group(proc)
            except BaseException as error:state['cleanupErrors'].append(repr(error))
        if current and current['status']=='RUNNING':
            current.update({'status':'FAILED','finishedAt':utc(),'exitCode':proc.returncode if proc else None,
                            'actualElapsedSeconds':time.monotonic()-t})
            if P(current['log']).is_file():current['logIdentity']=row(current['log'])
        try:
            after=verify_sdk()
            state['sourceErrors']=sorted(set(state['sourceErrors']+after))
            state['sourceAfter']=run_small(['/usr/bin/git','rev-parse','HEAD'],cwd=root).stdout.strip()
            if state['sourceAfter']!=plan['source']:state['sourceErrors'].append('Git HEAD changed')
        except BaseException as error:state['sourceErrors'].append(repr(error))
        if state['cleanupErrors'] or state['sourceErrors']:state['status']='FAILED'
        state['finishedAt']=utc();state['actualElapsedSeconds']=time.monotonic()-started
        charges=prior_charges+[{'startedAt':state['startedAt'],'finishedAt':state['finishedAt'],'seconds':state['actualElapsedSeconds'],'status':state['status']}]
        state['totalChargedSeconds']=math.fsum(x['seconds'] for x in charges)
        state['remainingAllowanceSeconds']=max(0,1800-state['totalChargedSeconds'])
        write(out/'ledger.json',{'schema':1,'id':plan['id'],'allowanceSeconds':1800,
            'charges':charges,
            'totalChargedSeconds':state['totalChargedSeconds'],'remainingAllowanceSeconds':state['remainingAllowanceSeconds'],'priorLedger':continuation['ledger'],
            'toolchainPreparation':toolchain,
            'priorLedgersModified':False,'restorationChargeRecordedSeparately':54.375687207997544})
        state['ledger']=row(out/'ledger.json');checkpoint();fcntl.flock(lock,fcntl.LOCK_UN);lock.close()
    print(json.dumps({'status':state['status'],'state':row(out/'state.json'),'actualElapsedSeconds':state['actualElapsedSeconds']}),flush=True)
    return 0 if state['status']=='PREPARED' else 1
if __name__=='__main__':sys.exit(main())
