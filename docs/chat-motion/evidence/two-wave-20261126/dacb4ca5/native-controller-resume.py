from __future__ import annotations
from pathlib import Path
import subprocess,json,os,time,hashlib,shutil,sys,traceback,datetime

STAGE=Path('/Users/m1/builds/hanlin-motion-dacb4ca5-20261126')
SOURCE=STAGE/'source';PROOF=STAGE/'proof'
DD=Path('/Users/m1/caches/DerivedData/hanlin-motion-dacb4ca5-20261126')
DONOR_DD=Path('/Users/m1/caches/DerivedData/hanlin-shared-chat-a84ecd6d-20261126')
DONOR_SP=Path('/Users/m1/builds/hanlin-shared-chat-a84ecd6d-20261126/SourcePackages')
EVIDENCE=STAGE/'evidence';EVIDENCE.mkdir(exist_ok=True)
SHA='dacb4ca5c809e7b0355a95e53d137ef3bb58f7fb'
PY='/opt/homebrew/bin/python3.12'
RUN='motion-dacb4ca5-20261126';ATTEMPT='1'
RUNTIME='com.apple.CoreSimulator.SimRuntime.iOS-27-2'
METHODS=[
 ('B','reversal-b','testBRapidReversalPresetSwitchAndPersistence'),
 ('A','cycles','testAAllFivePresetsTwentyCompleteCyclesEach'),
 ('C','visual-c','testCReadableLongContentRTLTypeOrientationAndCompletion')]
ENV=dict(os.environ);ENV['PATH']='/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin'
ENV['HANLIN_LOCAL_RUN_ID']=RUN;ENV['HANLIN_LOCAL_RUN_ATTEMPT']=ATTEMPT
STATE={'schemaVersion':1,'sourceSHA':SHA,'run':RUN,'attempt':ATTEMPT,'pid':os.getpid(),
       'startedUTC':datetime.datetime.now(datetime.timezone.utc).isoformat(),'steps':[],
       'cases':{letter:{'method':name,'status':'NOT_RUN'} for letter,scope,name in METHODS},
       'productionOwnership':'Original selected-product SDK checkout; no copied production bodies',
       'assertions':'Original A/B/C method bodies and thresholds unchanged',
       'controllerSHA256':hashlib.sha256(Path(__file__).read_bytes()).hexdigest()}
def free_bytes():
 s=os.statvfs('/System/Volumes/Data');return s.f_bavail*s.f_frsize
def save():
 (STAGE/'status.json').write_text(json.dumps(STATE,indent=2)+'\n')
def digest(path):return hashlib.sha256(Path(path).read_bytes()).hexdigest()
def read(args,cwd=None):
 return subprocess.check_output(args,cwd=cwd,env=ENV,text=True,timeout=30).strip()
def phase(name,own_remaining=0):
 free=free_bytes();STATE['phase']=name
 STATE.setdefault('resourceObservations',[]).append({'phase':name,'freeBytes':free,'at':time.time()})
 save()
 # This is the measured budget admitted for the concurrently active Host phase.
 if own_remaining and free < own_remaining+1800000000+1073741824:
  raise RuntimeError('BLOCKED_DISK_PHASE: '+name+' free='+str(free)+' current combined phase budget='+str(own_remaining+1800000000+1073741824))
def run(name,args,cwd=PROOF,timeout=1800,check=True,logdir=EVIDENCE):
 phase(name);logdir.mkdir(parents=True,exist_ok=True)
 log=logdir/(name+'.log')
 item={'name':name,'command':args,'cwd':str(cwd),'startedUTC':datetime.datetime.now(datetime.timezone.utc).isoformat(),'log':str(log)}
 STATE['steps'].append(item);save()
 started=time.monotonic()
 with log.open('w') as stream:
  try:
   result=subprocess.run(args,cwd=cwd,env=ENV,stdout=stream,stderr=subprocess.STDOUT,timeout=timeout)
   code=result.returncode
  except subprocess.TimeoutExpired:
   item.update(exitCode=124,timedOut=True,seconds=time.monotonic()-started,logSHA256=digest(log));save()
   raise
 item.update(exitCode=code,seconds=time.monotonic()-started,logSHA256=digest(log))
 save()
 if check and code:raise RuntimeError(name+' failed with exit '+str(code))
 return code
def copy_receipt(name):shutil.copyfile(PROOF/name,EVIDENCE/Path(name).name)


try:
 prior=json.loads((STAGE/'status.json').read_text())
 assert prior['status']=='FAILED' and prior['phase']=='record-original-resolved-inputs'
 assert any(s['name']=='build' and s.get('exitCode')==0 for s in prior['steps'])
 try:
  os.kill(prior['pid'],0)
  raise RuntimeError('Prior controller is still alive')
 except ProcessLookupError: pass
 first=EVIDENCE/'attempt1';first.mkdir(exist_ok=False)
 for folder,names in [(STAGE,['status.json','launch.json','controller.log','dependency-staging-proposal.json']), (EVIDENCE,[p.name for p in EVIDENCE.iterdir() if p.is_file()])]:
  for name in names:
   if (folder/name).exists():shutil.copyfile(folder/name,first/name)
 for name in ['sourceFingerprint','sourceFileCount','developerDir','xcodeVersion','swiftVersion','compilerSDK','device','runtime','deviceModel']:
  STATE[name]=prior[name]
 STATE['resumption']='Correct overly broad dependency staging to actual selected graph; original recorder and test bodies unchanged'
 STATE['priorAttemptStatus']=str(first/'status.json')
 STATE['priorBuildStatus']='EXECUTED_PASS'
 assert read(['git','-C',str(SOURCE),'rev-parse','HEAD'])==SHA
 assert not read(['git','-C',str(SOURCE),'status','--porcelain'])
 for path in ['App/App.swift','UITests/MotionUITests.swift']:
  assert digest(PROOF/path)==digest(SOURCE/('docs/chat-motion/MotionUI/'+Path(path).name))
 ENV['DEVELOPER_DIR']=read(['xcode-select','-p'])
 assert read(['xcodebuild','-version'])==STATE['xcodeVersion']
 assert read(['xcrun','--sdk','iphonesimulator','--show-sdk-version'])==STATE['compilerSDK']
 phase('selected-closure-staging-admission',600000000)
 proposal=json.loads((STAGE/'dependency-staging-proposal.json').read_text())
 wanted=set(proposal['selected']);assert len(wanted)==8
 lock=PROOF/'ChatMotionProof.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved'
 original_lock=json.loads(lock.read_text())
 canonical=json.loads((SOURCE/'AI_HLY.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved').read_text())
 canonical_pins={p['identity']:p for p in canonical['pins']}
 selected_pins=[p for p in original_lock['pins'] if p['identity'] in wanted]
 assert len(selected_pins)==8
 for pin in selected_pins:assert pin==canonical_pins[pin['identity']]
 retained=STAGE/'dependency-staging-retained';retained.mkdir(exist_ok=False)
 relocated=[]
 for item in proposal['checkouts']:
  if item['selected']:continue
  source=DD/'SourcePackages/checkouts'/item['directory']
  assert read(['git','-C',str(source),'rev-parse','HEAD'])==item['revision']
  assert not read(['git','-C',str(source),'status','--porcelain'])
  destination=retained/item['directory'];source.rename(destination)
  relocated.append({**item,'retainedPath':str(destination)})
 original_lock['pins']=selected_pins
 lock.write_text(json.dumps(original_lock,indent=2)+'\n')
 receipt={'selectionBasis':'Actual Xcode resolved source packages in unchanged original resolve.log; no product source or dependency revision changed','sourceSHA':SHA,'pins':selected_pins,'retainedUnusedCheckouts':relocated,'generatedLockSHA256':digest(lock),'sourceRecorderSHA256':digest(SOURCE/'docs/chat-motion/record_sdk_inputs.py')}
 (EVIDENCE/'dependency-staging-correction.json').write_text(json.dumps(receipt,indent=2)+'\n')
 common=['-project','ChatMotionProof.xcodeproj','-scheme','ChatMotionProof','-derivedDataPath',str(DD)]
 run('resolve-selected',['xcodebuild','-resolvePackageDependencies',*common,'-onlyUsePackageVersionsFromResolvedFile'],timeout=900)
 resolved=json.loads(lock.read_text())['pins']
 assert {p['identity'] for p in resolved}==wanted
 for pin in resolved:assert pin==canonical_pins[pin['identity']]
 actual_directories={p.name for p in (DD/'SourcePackages/checkouts').iterdir()}
 assert actual_directories=={p['directory'] for p in proposal['checkouts'] if p['selected']}
 STATE['resolvedPins']=resolved;save()
 run('admit-original-macro-selected',[PY,str(SOURCE/'docs/chat-motion/record_sdk_inputs.py'),'--proof',str(PROOF),'--derived-data',str(DD),'--evidence',str(EVIDENCE),'--admit-macro'],timeout=120,cwd=SOURCE)
 selection=EVIDENCE/'verified-environment.json';selected=json.loads(selection.read_text())
 device=selected['device']['udid'];assert device==prior['device']
 assert selected['runtime']['identifier']==RUNTIME and selected['runtime']['buildversion']=='24B8117'
 run('boot-original-owned-simulator-selected',[PY,str(SOURCE/'Scripts/CI/boot_motion_simulator.py'),'--device',device,'--selection',str(selection),'--strategy','fresh'],cwd=SOURCE,timeout=680)
 phase('incremental-build-admission',600000000)
 destination=['-destination','platform=iOS Simulator,id='+device,'-destination-timeout','90']
 build=['xcodebuild','build-for-testing',*common,*destination,'-disableAutomaticPackageResolution','-skipMacroValidation','CODE_SIGNING_ALLOWED=NO']
 run('build-selected',build,timeout=900)
 run('record-original-resolved-inputs-selected',[PY,str(SOURCE/'docs/chat-motion/record_sdk_inputs.py'),'--proof',str(PROOF),'--derived-data',str(DD),'--evidence',str(EVIDENCE)],cwd=SOURCE,timeout=240)
 STATE['buildStatus']='EXECUTED_PASS';save()
 for letter,scope,name in METHODS:
  phase('case-'+letter+'-admission',400000000)
  out=EVIDENCE/letter;out.mkdir(exist_ok=True)
  shutil.copyfile(selection,out/'verified-environment.json')
  (out/'selected-scope.txt').write_text(scope+'\n')
  (out/'source-sha.txt').write_text(SHA+'\n')
  bundle=out/'Motion.xcresult'
  command=['xcodebuild','test-without-building',*common,'-destination','platform=iOS Simulator,id='+device,'-destination-timeout','60','-resultBundlePath',str(bundle),'-disableAutomaticPackageResolution','-skipMacroValidation','-parallel-testing-enabled','NO','-test-timeouts-enabled','YES','-default-test-execution-time-allowance','600','-maximum-test-execution-time-allowance','720','CODE_SIGNING_ALLOWED=NO','-only-testing:ChatMotionProofUITests/MotionUITests/'+name]
  STATE['cases'][letter].update(status='RUNNING',evidence=str(out));save()
  code=run('test-'+letter,[PY,str(SOURCE/'docs/chat-motion/record_ui_run.py'),'--device',device,'--evidence',str(out),'--',*command],check=False,logdir=out,timeout=1800)
  run('collect-'+letter,[PY,str(SOURCE/'docs/chat-motion/collect_motion_result.py'),str(bundle),device,str(out),str(code)],cwd=SOURCE,timeout=300,logdir=out)
  export=run('export-'+letter,['xcrun','xcresulttool','export','attachments','--path',str(bundle),'--output-path',str(out/'attachments'),'--test-id','MotionUITests/'+name+'()'],check=False,logdir=out,timeout=120)
  nodes=[]
  def visit(node):
   if isinstance(node,dict):
    if node.get('nodeType')=='Test Case':nodes.append(node)
    for child in node.values():visit(child)
   elif isinstance(node,list):
    for child in node:visit(child)
  if (out/'tests.json').exists():visit(json.loads((out/'tests.json').read_text()))
  STATE['cases'][letter].update(testExit=code,attachmentExportExit=export,caseNodes=[{k:n.get(k) for k in ['nodeIdentifier','result','duration']} for n in nodes])
  raw=json.loads((out/'raw-result-status.json').read_text())
  video=json.loads((out/'video-status.json').read_text())
  okay=code==0 and raw['status']=='FINALIZED_READABLE_ARCHIVED' and len(nodes)==1 and nodes[0]['nodeIdentifier']=='MotionUITests/'+name+'()' and nodes[0]['result']=='Passed'
  okay=okay and video['exit_code']==0 and (out/'motion-first120s.mp4').stat().st_size>1024
  if letter=='A' and okay:
   timeline=json.loads((out/'motion-geometry-timeline.json').read_text())
   okay={n['preset'] for n in timeline}=={'v1.relaxed','v1.height-reveal','v1.gentle-squeeze','v1.quiet-fade','v1.none'}
  STATE['cases'][letter]['status']='EXECUTED_PASS' if okay else 'FAILED'
  STATE['cases'][letter]['rawResult']=raw;STATE['cases'][letter]['video']=video
  (out/'result-validation.json').write_text(json.dumps(STATE['cases'][letter],indent=2)+'\n')
  save()
  if not okay:raise RuntimeError('Original Motion '+letter+' acceptance failed; original results retained; later cases remain NOT_RUN')
 STATE['status']='EXECUTED_PASS'
 STATE['acceptanceScope']='Three original Motion component cases; C full-screen attachment still requires visual review; no physical-device or full-app acceptance claimed'
 phase('complete')
except BaseException as error:
 STATE['status']='BLOCKED_DISK' if 'BLOCKED_DISK_PHASE' in str(error) else 'FAILED'
 STATE['error']=str(error);STATE['traceback']=traceback.format_exc()
 save()
 raise
finally:
 STATE['finishedUTC']=datetime.datetime.now(datetime.timezone.utc).isoformat()
 STATE['freeBytesAtFinish']=free_bytes();save()
