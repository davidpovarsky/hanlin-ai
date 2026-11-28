from pathlib import Path
import os,subprocess,json,time,datetime,hashlib,re,signal
ROOT=Path('/Users/m1/builds/hanlin-ai-ce49e30d-miniapp-complete');CTRL=ROOT/'build/primary-control';SOURCE='42e34eff615a6d599ddfd01ea9382d920b5f9a5c'
STATE=CTRL/'focused-launch-attempt13.json';OUT=CTRL/'focused-diagnostics-attempt13';WRAPPER=CTRL/'focused-diagnostics-attempt13.py'
assert not STATE.exists() and not OUT.exists()
assert hashlib.sha256(WRAPPER.read_bytes()).hexdigest()=='7438ab010cedebd87a3ac16b10617113b7d4c71a5b4e9d041d071f7897a68797'
assert hashlib.sha256((CTRL/'diagnostic-observer-attempt13.py').read_bytes()).hexdigest()=='d36d818a02c5a9ddba660bf83e4827d96af75b38052f9eaa26bf3c7aab2a97e1'
def utc():return datetime.datetime.now(datetime.timezone.utc).isoformat()
state={'owner':'/root/native_execution','source':SOURCE,'status':'PREPARING_REVIEWED_DIAGNOSTIC','pid':os.getpid(),'startedAt':utc(),'original52':'NOT_RUN','wrapperSHA256':hashlib.sha256(WRAPPER.read_bytes()).hexdigest(),'diagnosticState':str(OUT/'state.json')}
advance_path=CTRL/'source-advance-42e34eff/receipt.json';advance=json.loads(advance_path.read_text())
assert advance['target']==SOURCE and advance['preservedHostArchiveSHA256']=='86733eba5d80156edf52da87f0f371c208122d6e60f618f182990330514984c3'
state['sourceAdvance']={'receipt':str(advance_path),'sha256':hashlib.sha256(advance_path.read_bytes()).hexdigest()}
def save():
 temp=STATE.with_suffix('.tmp');temp.write_text(json.dumps(state,indent=2)+'\n');temp.replace(STATE)
save()
primary=json.loads((CTRL/'state.json').read_text())
assert primary['source']==SOURCE and primary['status']=='PAUSED_AFTER_PHASE' and primary['attempt']==13
assert json.loads((CTRL/'companion-gates-attempt9/state.json').read_text())['status']=='COMPANION_GATES_PASS'
assert subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT,text=True).strip()==SOURCE
df=subprocess.check_output(["df","-k","/System/Volumes/Data"],text=True)
free=int(df.splitlines()[1].split()[3])*1024
# Current measured scope: one original Modular case, existing unchanged SDK/native products,
# exact larger prior device footprint,1GiB changed-test products,0.5GiB evidence and observed-burst allowance.
estimated_incremental=5731033088+512*1024**2+512*1024**2
concurrent_and_os=4*1024**3
state["resourceObservation"]={"observedAt":utc(),"df":df,"freeBytes":free,
 "estimatedIncrementalBytes":estimated_incremental,"concurrentGrowthAndOSAllowanceBytes":concurrent_and_os,
 "basis":"Revised measured scope: current same-Modular device is5,731,033,088B by du; this is a conservative full-directory upper bound, not measured new physical allocation. APFS sharing is not assumed. Only changed UI test/source against reused SDK/native products, with0.5GiB incremental products and0.5GiB one-case evidence. Actual concurrent-growth/OS allowance4GiB remains explicit. Prior12.149GB estimate and all retirement receipts are preserved; no fixed free-space/CPU/load/job-count threshold."}
if free<estimated_incremental+concurrent_and_os:
 state.update(status="MEASURED_STORAGE_REVIEW_REQUIRED",finishedAt=utc());save();raise SystemExit(2)
state["resourceObservation"]["decision"]="ADMITTED";save()
tools=ROOT.parent/(ROOT.name+'-tools')
env={**os.environ,'PATH':str(tools/'bin')+':/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin','DEVELOPER_DIR':'/Applications/Xcode.app/Contents/Developer','GITHUB_WORKSPACE':str(ROOT),'GITHUB_SHA':SOURCE,'GITHUB_RUN_ID':'primary-ce49e30d-20261124','SPLIT_EVIDENCE':str(ROOT/'build/app-split-evidence'),'SPLIT_DERIVED_DATA':'/Users/m1/caches/DerivedData/hanlin-ai-ce49e30d-miniapp-complete','SPLIT_NATIVE_TEST_SCOPE':'baseline','PAIRED_TEST_SCOPE':'miniapp_complete','RUNNER_TEMP':str(ROOT/'build/primary-temp')}
remaining=12600-json.loads((CTRL/'state.json').read_text())['activeElapsedSeconds'];assert remaining>0
argv=['/opt/homebrew/bin/python3.12',str(WRAPPER),'--source',SOURCE,'--output',str(OUT)]
log=CTRL/'focused-diagnostics-attempt13.log';beg=time.monotonic()
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
    state.update(elapsedSeconds=time.monotonic()-beg,logBytes=log.stat().st_size)
    try:
     disk=subprocess.check_output(["df","-k","/System/Volumes/Data"],text=True)
     state.setdefault("diskObservations",[]).append({"observedAt":utc(),"freeBytes":int(disk.splitlines()[-1].split()[3])*1024})
    except Exception as error:state.setdefault("diskObservationErrors",[]).append(str(error))
    save()
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
primary=json.loads((CTRL/'state.json').read_text());assert primary['source']==SOURCE and primary['status']=='PAUSED_AFTER_PHASE' and primary['attempt']==13
record={'name':'focused-native-diagnostic','source':SOURCE,'argv':argv,'startedAt':state['admittedAt'],'finishedAt':utc(),'exitCode':code,'elapsedSeconds':elapsed,'log':str(log),'logBytes':log.stat().st_size,'logSHA256':hashlib.sha256(log.read_bytes()).hexdigest(),'original52':'NOT_RUN'}
primary['activeElapsedSeconds']+=elapsed;primary.setdefault('additionalRequiredProofs',[]).append(record)
temp=CTRL/'state.json.tmp';temp.write_text(json.dumps(primary,indent=2)+'\n');temp.replace(CTRL/'state.json')
state.update(status='DIAGNOSTIC_PROCESS_FINISHED' if code==0 and not finally_error else 'FAIL',exitCode=code,finishedAt=utc(),elapsedSeconds=elapsed,sourceRestored=source.read_bytes()==expected)
if finally_error:state['error']=finally_error
save()
raise SystemExit(0 if code==0 and not finally_error else 1)
