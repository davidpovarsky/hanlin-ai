import pathlib, subprocess, os, json, hashlib, datetime, time, signal
ROOT=pathlib.Path('/Users/m1/builds/hanlin-ai-ce49e30d-miniapp-complete')
WORK=ROOT/'build/primary-control/projection-regression-attempt7'
STATE=WORK/'state.json'
def now():return datetime.datetime.now(datetime.timezone.utc).isoformat()
def sha(path):return hashlib.sha256(path.read_bytes()).hexdigest()
state=json.loads((WORK/'prepared.json').read_text())
state.update(status='RUNNING',startedAt=now(),controllerPID=os.getpid(),commands=[])
def save():
 temp=STATE.with_suffix('.tmp');temp.write_text(json.dumps(state,indent=2)+'\n');temp.replace(STATE)
def run(label,expected):
 command=['/usr/bin/xcrun','swift','test','--package-path',str(WORK/'package'),'--jobs','1','--filter','HanlinCanonicalEntrypointProjectionTests']
 log=WORK/(label+'.log');started=time.monotonic()
 event={'label':label,'argv':command,'startedAt':now(),'expectedExitCode':expected}
 env=dict(os.environ,DEVELOPER_DIR='/Applications/Xcode.app/Contents/Developer')
 with log.open('wb') as handle:
  process=subprocess.Popen(command,stdout=handle,stderr=subprocess.STDOUT,env=env,cwd=ROOT,start_new_session=True)
  event['pid']=process.pid;state['commands'].append(event);state['phase']=label;save()
  try:code=process.wait(timeout=300)
  except subprocess.TimeoutExpired:
   os.killpg(process.pid,signal.SIGTERM)
   try:process.wait(timeout=5)
   except subprocess.TimeoutExpired:os.killpg(process.pid,signal.SIGKILL);process.wait()
   code=process.returncode;event['timedOut']=True
 event.update(exitCode=code,finishedAt=now(),elapsedSeconds=time.monotonic()-started,log=str(log),logBytes=log.stat().st_size,logSHA256=sha(log))
 save()
 if event.get('timedOut') or code!=expected:raise RuntimeError(f'{label}: expected exit {expected}, got {code}')
 text=log.read_text(errors='replace')
 if label=='baseline':
  if 'duplicateEntryPoint' not in text or 'storedExpoActionsRemainDiscoverable' not in text:raise RuntimeError('Baseline did not report the expected canonical duplicate-kind failure.')
 else:
  if '✔ Test run with' not in text or 'passed' not in text:raise RuntimeError('Candidate did not report a passed Swift Testing run.')
try:
 save()
 run('baseline',1)
 target=WORK/'package/Sources/HanlinScriptStore/HanlinStoredPackageSnapshot+MiniAppRegistration.swift'
 assert sha(target)==state['baselineSHA256']
 target.write_bytes((WORK/'candidate.swift').read_bytes())
 assert sha(target)==state['candidateSHA256']
 state['candidateAppliedAt']=now();save()
 run('candidate',0)
 state.update(status='PASS',finishedAt=now());save()
except BaseException as error:
 state.update(status='FAIL',error=str(error),finishedAt=now());save();raise
