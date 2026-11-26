#!/usr/bin/env python3
"""Audit the six actual SDK20 command results using the retained SDK08 conditions."""
from pathlib import Path
import ast, datetime, hashlib, json, os, re, stat, zipfile
B=Path('/mnt/development/projects/transfers/hanlin-primary-ce49-20261124')
ROOT=B/'standalone-sdk08-kit-only-sdk20';KIT=ROOT/'kit';E=ROOT/'evidence'
OLD=B/'standalone-sdk08-kit-only'
M='6f11ed8da3df18627f05932d47b5b68dec54eb26ac396151a21cbc8c3e65800e'
IDS=['expo-validate','expo-build','nativescript-validate','nativescript-build','negative-type-error-validate','negative-type-error-build']
def sha(p):
    with Path(p).open('rb') as f:return hashlib.file_digest(f,'sha256').hexdigest()
def row(p,root=ROOT):
    p=Path(p);return {'path':str(p.relative_to(root)),'bytes':p.stat().st_size,'sha256':sha(p)}
def write(p,v):
    with Path(p).open('x') as f:json.dump(v,f,indent=2,ensure_ascii=False);f.write('\n')
def qstrings(t):return re.findall(r'"(?:\\.|[^"\\])*"',t)
def decode(t):return ast.literal_eval(t)
def trace_audit(ident):
    p=E/f'{ident}.strace';pending={};unmatched=[];calls=[];mentioned=False
    for line in p.read_text().splitlines():
        m=re.match(r'^\s*(\d+)\s+(.*)$',line)
        if not m:continue
        pid,t=m.groups()
        if '/mnt/development/projects/worktrees/' in t or '/sdk20-dff3b45c/source/' in t:mentioned=True
        if '<unfinished ...>' in t:
            assert pid not in pending,('second pending',pid)
            pending[pid]=t.split('<unfinished ...>',1)[0];continue
        m=re.match(r'^<\.\.\. (\w+) resumed>(.*)$',t)
        if m:
            if pid not in pending:unmatched.append({'pid':pid,'text':t});continue
            t=pending.pop(pid)+m.group(2)
        if re.match(r'^\w+\(',t):calls.append((pid,t))
    cwd={};fds={};external=[];dependency=[];project=[];probes=[];net=[];unresolved=[]
    def resolve(pid,path,fd='AT_FDCWD'):
        if path.startswith('/'):return os.path.normpath(path)
        if fd=='AT_FDCWD':base=cwd.get(pid,str(KIT))
        else:base=fds.get(pid,{}).get(fd)
        if base is None:return None
        return os.path.normpath(os.path.join(base,path))
    for pid,t in calls:
        cwd.setdefault(pid,str(KIT));fds.setdefault(pid,{})
        name=t.split('(',1)[0]
        ret=re.search(r'\)\s+=\s+(-?\d+)',t)
        rv=int(ret.group(1)) if ret else None
        qs=qstrings(t)
        if name in ('clone','clone3','fork','vfork') and rv and rv>0:
            child=str(rv);cwd.setdefault(child,cwd[pid]);fds.setdefault(child,dict(fds[pid]))
        if name=='chdir' and rv==0 and qs:
            val=resolve(pid,decode(qs[0]));assert val is not None;cwd[pid]=val
        if name=='getcwd' and rv is not None and rv>=0 and qs:cwd[pid]=decode(qs[0])
        if name in ('socket','socketpair','connect','bind','listen','accept','accept4','sendto','sendmsg','recvfrom','recvmsg','getsockname','getpeername','setsockopt','getsockopt','shutdown'):
            net.append({'pid':pid,'text':t})
        dep_paths=[decode(x) for x in qs if '/node_modules' in x]
        if any(not x.startswith(str(KIT)+'/') for x in dep_paths):probes.append({'pid':pid,'text':t})
        if name not in ('open','openat','openat2') or rv is None or rv<0 or not qs:continue
        path=decode(qs[0]);fd='AT_FDCWD'
        if name in ('openat','openat2'):
            fd=t.split('(',1)[1].split(',',1)[0].strip()
        resolved=resolve(pid,path,fd)
        if resolved is None:
            unresolved.append({'pid':pid,'path':path,'dirfd':fd,'call':t});continue
        fds[pid][str(rv)]=resolved
        if not (resolved==str(KIT) or resolved.startswith(str(KIT)+'/')):
            item={'path':resolved,'call':t};external.append(item)
            if '/node_modules/' in resolved or resolved.endswith('/node_modules'):dependency.append(item)
            if resolved.startswith('/mnt/development/projects/') and not resolved.startswith(str(ROOT/'tmp')+'/'):
                project.append(item)
    internet=[v for v in net if 'AF_INET' in v['text']]
    result={'id':ident,'traceBytes':p.stat().st_size,'traceSHA256':sha(p),'reassembledCalls':len(calls),
            'unmatchedResumed':unmatched,'pendingAtEnd':pending,'unresolvedSuccessfulRelativeOpens':unresolved,
            'successfulExternalDependencyOpens':dependency,'successfulExternalProjectOpens':project,
            'successfulExternalOpens':external,'externalDependencyProbes':probes,'networkCalls':net,
            'internetNetworkCalls':internet,'repositoryPathMentioned':mentioned,
            'observedNoRepositoryFallback':not dependency and not project and not mentioned and not unresolved}
    return result

s=json.loads((ROOT/'state.json').read_text())
assert s['status']=='SIX_COMMANDS_EXECUTED_EXPECTED',s
contract=json.loads((E/'replay-contract.json').read_text())
traces=[trace_audit(i) for i in IDS]
write(E/'trace-audit.json',{'schema':1,'method':'Reassemble strace unfinished/resumed calls by PID; distinguish failed ancestor package probes from actual opens; track process cwd and known directory descriptors. System executables/Python standard library/OS libraries remain prerequisites.','traces':traces})
assert all(not x['unmatchedResumed'] and not x['pendingAtEnd'] and not x['unresolvedSuccessfulRelativeOpens'] for x in traces),'Trace reconstruction requires review'
assert all(x['observedNoRepositoryFallback'] and not x['internetNetworkCalls'] for x in traces),'External dependency/network observation requires review'
before=json.loads((E/'sdk-member-inventory-before.json').read_text());after=json.loads((E/'sdk-member-inventory-after.json').read_text())
assert before==after and len(before)==25682
for x in before:
    p=KIT/x['path'];assert p.stat().st_size==x['bytes'] and sha(p)==x['sha256'] and oct(stat.S_IMODE(p.stat().st_mode))==x['mode']
commands=[]
for ident in IDS:
    r=json.loads((E/f'{ident}-command.json').read_text());original=contract['originalRecords'][ident]['record']
    assert r['command']==original['command']
    assert r['environment']=={**original['environment'],'TMPDIR':str(ROOT/'tmp')}
    expected=1 if ident.startswith('negative-') else 0
    assert r['returncode']==expected
    p=ROOT/r['report'];report=json.loads(p.read_text());assert report['sdk']['manifestSHA256']==M
    assert report['succeeded']==(expected==0)
    tc=report['typecheck'];assert tc['strict'] is True
    assert tc['skipLibCheck']==(report['engine']=='nativescript')
    if expected:
        assert len(report['diagnostics'])==1
        d=report['diagnostics'][0]
        assert d['code']=='TS2322' and d['file']=='index.ts' and d['line']==36 and d['column']==14
    else:assert report['diagnostics']==[]
    commands.append({'id':ident,'returncode':r['returncode'],'succeeded':report['succeeded'],
                     'expectedOutcomeMatched':True,'elapsedSeconds':r['elapsedSeconds'],'command':r['command'],
                     'record':row(E/f'{ident}-command.json'),'report':row(p),
                     'compilerVersion':report['sdk']['compilerVersion'],'typecheck':tc,'diagnostics':report['diagnostics']})
archives=[]
for name,engine,project,expected_count in [
    ('Expo-Hello-World.hanlinExpo','expo','expo-hello-world',14),
    ('NativeScript-Hello-World.hanlinNativeScript','nativescript','nativescript-hello-world',16)]:
    p=KIT/'artifacts'/name
    with zipfile.ZipFile(p) as z:
        assert z.testzip() is None
        names=z.namelist();assert len(names)==len(set(names))==expected_count
        manifest=json.loads(z.read('script.json'));assert manifest['runInApp'] is True
        assert manifest['hanlinRuntime']=='hanlin-'+engine
        entry=manifest['entry'];assert z.read(entry)
        valid=json.loads(z.read('hanlin.validation.json'));assert valid['succeeded'] and valid['diagnostics']==[] and valid['sdk']['manifestSHA256']==M
        source_rows={}
        for q in sorted((KIT/'workspace'/project).iterdir()):
            if q.is_file():
                h=hashlib.sha256(z.read('source/'+q.name)).hexdigest();assert h==sha(q);source_rows[q.name]=h
        members=[{'path':i.filename,'bytes':i.file_size,'sha256':hashlib.sha256(z.read(i)).hexdigest()} for i in z.infolist()]
        archives.append({**row(p),'engine':engine,'CRC':'PASS','memberCount':len(names),'entry':entry,
                         'manifest':manifest,'retainedSourceRows':source_rows,'validation':valid,'members':members})
write(E/'archive-audit.json',{'schema':1,'archives':archives})
assert not (KIT/'artifacts/Rejected-Type-Error.hanlinNativeScript').exists()
assert not (KIT/'workspace/nativescript-type-error/.hanlin-build').exists()
summary={'schema':1,'status':'PASS','verifiedAt':datetime.datetime.now(datetime.timezone.utc).isoformat(),
 'scope':'Standalone SDK08 authoring replay only: exact retained six production CLI invocations, SDK20, original two representative projects and intentional TypeScript rejection. No native execution.',
 'productionSource':contract['originalRecords']['expo-validate']['record'].get('productionSource','7f5dad540ade7fec6e5ace980eb99d1d6d0c2e8f'),
 'SDKProducerSource':'dff3b45c99a57bf8fe8ec721db3fa1fafce7134b',
 'SDKArchive':contract['sdkArchive'],'SDKManifest':{'path':'MiniAppSDK/miniapp-sdk.json','sha256':M},
 'SDKInputSHA256':contract['SDKInputSHA256'],'productionFiles':contract['productionFiles'],'prerequisites':contract['prerequisites'],
 'checks':{'expectedInvocations':6,'matchedInvocations':6,'positiveValidateAndBuild':4,'negativeRejects':2,
           'SDKFilesByteAndModeIdenticalAfter':25682,'SDKFileSetUnchanged':True,'productionFilesByteIdentical':True,
           'originalFixtureFilesByteIdentical':22,'repositoryDependencyFallbackObserved':False,
           'externalSuccessfulNodeModuleOpens':0,'internetNetworkCallsObserved':0,'ancestorNodeModules':[],
           'negativeArchiveCreated':False,'negativeBuildStageCreated':False,'sourceOrSDKRegenerated':False,
           'npmInstallUsed':False,'nativeExecution':'NOT_RUN'},
 'diagnosticBoundary':{'expo':{'strict':True,'skipLibCheck':False,'dependencyDeclarationsChecked':True},
                      'nativescript':{'strict':True,'skipLibCheck':True,'dependencyDeclarationsChecked':False},
                      'explanation':'Original NativeScript consumer config skips dependency declaration internals; authored source remains strict, and TS2322 was rejected by validate/build.'},
 'commands':commands,'archives':[{k:v for k,v in a.items() if k in ('path','bytes','sha256','engine','memberCount','CRC')} for a in archives],
 'traceAudit':row(E/'trace-audit.json'),'archiveAudit':row(E/'archive-audit.json'),
 'SDKInventoryBefore':row(E/'sdk-member-inventory-before.json'),'SDKInventoryAfter':row(E/'sdk-member-inventory-after.json'),
 'historicalSDK19Proof':{'path':str(OLD/'evidence/verification-summary.json'),'sha256':sha(OLD/'evidence/verification-summary.json')},
 'operationalHarness':row(ROOT/'replay-six-recorded-commands.py'),
 'traceNote':'Optional ancestor dependency probes failed. All successful compiler/dependency opens remained within this SDK20 kit; system Node, Python and OS libraries are prerequisites. Complete traces retained.',
 'runnerIdentityBoundary':'No original runner script was retained; this new wrapper replays the unchanged original six recorded commands and assertions. It does not fabricate a historical script identity.'}
write(E/'verification-summary.json',summary)
print(json.dumps({'status':'PASS','summary':row(E/'verification-summary.json'),'commands':[(c['id'],c['returncode'],c['elapsedSeconds']) for c in commands],'SDKFiles':25682,'traceAudit':row(E/'trace-audit.json'),'archives':summary['archives']}))
