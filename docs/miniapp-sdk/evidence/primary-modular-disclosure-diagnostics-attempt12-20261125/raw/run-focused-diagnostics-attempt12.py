from pathlib import Path
import os,subprocess,json,time,datetime,hashlib,re,signal
ROOT=Path('/Users/m1/builds/hanlin-ai-ce49e30d-miniapp-complete');CTRL=ROOT/'build/primary-control';SOURCE='1a611764779b0a57cc57d71b26d2cd6449895d8d'
STATE=CTRL/'focused-launch-attempt12.json';OUT=CTRL/'focused-diagnostics-attempt12';WRAPPER=CTRL/'focused-diagnostics-attempt12.py'
assert not STATE.exists() and not OUT.exists()
assert hashlib.sha256(WRAPPER.read_bytes()).hexdigest()=='b8122500556429a554a1a63286e19e5af119c0f6b60d6b8c5f1ace64d54d3e8a'
assert hashlib.sha256((CTRL/'diagnostic-observer-attempt12.py').read_bytes()).hexdigest()=='d36d818a02c5a9ddba660bf83e4827d96af75b38052f9eaa26bf3c7aab2a97e1'
def utc():return datetime.datetime.now(datetime.timezone.utc).isoformat()
state={'owner':'/root/native_execution','source':SOURCE,'status':'PREPARING_REVIEWED_DIAGNOSTIC','pid':os.getpid(),'startedAt':utc(),'original52':'NOT_RUN','wrapperSHA256':hashlib.sha256(WRAPPER.read_bytes()).hexdigest(),'diagnosticState':str(OUT/'state.json')}
def save():
 temp=STATE.with_suffix('.tmp');temp.write_text(json.dumps(state,indent=2)+'\n');temp.replace(STATE)
save()
primary=json.loads((CTRL/'state.json').read_text())
assert primary['source']==SOURCE and primary['status']=='PAUSED_AFTER_PHASE' and primary['attempt']==12
assert json.loads((CTRL/'companion-gates-attempt9/state.json').read_text())['status']=='COMPANION_GATES_PASS'
assert subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT,text=True).strip()==SOURCE
df=subprocess.check_output(["df","-k","/System/Volumes/Data"],text=True)
free=int(df.splitlines()[1].split()[3])*1024
# Based on retained actual6.2GB dedicated simulator +0.6GB prior focused evidence,
# existing compatible DerivedData, up to4GB incremental products and4GB concurrent/OS allowance.
estimated_incremental=11*1024**3
concurrent_and_os=4*1024**3
state["resourceObservation"]={"observedAt":utc(),"df":df,"freeBytes":free,
 "estimatedIncrementalBytes":estimated_incremental,"concurrentGrowthAndOSAllowanceBytes":concurrent_and_os,
 "basis":"One fresh dedicated simulator; retained measured6.2GB data footprint,0.6GB evidence, existing compatible product cache and <=4GB incremental compilation. No CPU-idle/load/job-count gate."}
if free<estimated_incremental+concurrent_and_os:
 state.update(status="MEASURED_STORAGE_REVIEW_REQUIRED",finishedAt=utc());save();raise SystemExit(2)
state["resourceObservation"]["decision"]="ADMITTED";save()
tools=ROOT.parent/(ROOT.name+'-tools')
env={**os.environ,'PATH':str(tools/'bin')+':/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin','DEVELOPER_DIR':'/Applications/Xcode.app/Contents/Developer','GITHUB_WORKSPACE':str(ROOT),'GITHUB_SHA':SOURCE,'GITHUB_RUN_ID':'primary-ce49e30d-20261124','SPLIT_EVIDENCE':str(ROOT/'build/app-split-evidence'),'SPLIT_DERIVED_DATA':'/Users/m1/caches/DerivedData/hanlin-ai-ce49e30d-miniapp-complete','SPLIT_NATIVE_TEST_SCOPE':'baseline','PAIRED_TEST_SCOPE':'miniapp_complete','RUNNER_TEMP':str(ROOT/'build/primary-temp')}
remaining=12600-json.loads((CTRL/'state.json').read_text())['activeElapsedSeconds'];assert remaining>0
argv=['/opt/homebrew/bin/python3.12',str(WRAPPER),'--source',SOURCE,'--output',str(OUT)]
log=CTRL/'focused-diagnostics-attempt12.log';beg=time.monotonic()
state.update(status='RUNNING',admittedAt=utc(),argv=argv,maximumActiveSeconds=remaining,log=str(log));save()
code=None
with log.open('xb') as stream:
 p=subprocess.Popen(argv,cwd=ROOT,env=env,stdout=stream,stderr=subprocess.STDOUT,start_new_session=True)
 state['wrapperPID']=p.pid;save()
 try:
  while True:
   elapsed=time.monotonic()-beg
   try:code=p.wait(timeout=min(30,max(.01,remaining-elapsed)));break
   except subprocess.TimeoutExpired:
    state.update(elapsedSeconds=time.monotonic()-beg,logBytes=log.stat().st_size);save()
    if state['elapsedSeconds']>=remaining:
     os.killpg(p.pid,signal.SIGTERM)
     try:p.wait(timeout=20)
     except subprocess.TimeoutExpired:os.killpg(p.pid,signal.SIGKILL);p.wait()
     code=-1;break
 except BaseException:
  if p.poll() is None:
   os.killpg(p.pid,signal.SIGTERM)
   try:p.wait(timeout=20)
   except subprocess.TimeoutExpired:os.killpg(p.pid,signal.SIGKILL);p.wait()
  raise
finally_error=None
source=ROOT/'HanlinMiniAppsUITests/HanlinMiniAppsUITests.swift'
expected=subprocess.check_output(['git','show',SOURCE+':HanlinMiniAppsUITests/HanlinMiniAppsUITests.swift'],cwd=ROOT)
if source.read_bytes()!=expected:
 finally_error="Unexpected UI source drift; preserve bytes and diagnose. This wrapper never writes source."
elapsed=time.monotonic()-beg
primary=json.loads((CTRL/'state.json').read_text());assert primary['source']==SOURCE and primary['status']=='PAUSED_AFTER_PHASE' and primary['attempt']==12
record={'name':'focused-native-diagnostic','source':SOURCE,'argv':argv,'startedAt':state['admittedAt'],'finishedAt':utc(),'exitCode':code,'elapsedSeconds':elapsed,'log':str(log),'logBytes':log.stat().st_size,'logSHA256':hashlib.sha256(log.read_bytes()).hexdigest(),'original52':'NOT_RUN'}
primary['activeElapsedSeconds']+=elapsed;primary.setdefault('additionalRequiredProofs',[]).append(record)
temp=CTRL/'state.json.tmp';temp.write_text(json.dumps(primary,indent=2)+'\n');temp.replace(CTRL/'state.json')
state.update(status='DIAGNOSTIC_PROCESS_FINISHED' if code==0 and not finally_error else 'FAIL',exitCode=code,finishedAt=utc(),elapsedSeconds=elapsed,sourceRestored=source.read_bytes()==expected)
if finally_error:state['error']=finally_error
save()
raise SystemExit(0 if code==0 and not finally_error else 1)
