from pathlib import Path
import os,json,time,datetime,subprocess,hashlib,signal,re
base=Path(__file__).resolve().parent
statePath=base/'state.json'
state=json.loads(statePath.read_text())
def now():return datetime.datetime.now(datetime.timezone.utc).isoformat()
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def save():
 tmp=statePath.with_suffix('.tmp');tmp.write_text(json.dumps(state,indent=2)+'\n');tmp.replace(statePath)
def run(label,argv,expected):
 log=base/(label+'.log')
 record={'label':label,'argv':argv,'startedAt':now(),'expectedExitCode':expected,'log':str(log)}
 state['commands'].append(record);state['phase']=label;save()
 start=time.monotonic()
 with log.open('wb') as out:
  proc=subprocess.Popen(argv,cwd=base,stdout=out,stderr=subprocess.STDOUT,start_new_session=True,env={**os.environ,'DEVELOPER_DIR':'/Applications/Xcode.app/Contents/Developer'})
  record['pid']=proc.pid;save();print(json.dumps({'event':'started',**record}),flush=True)
  try:code=proc.wait(timeout=300)
  except subprocess.TimeoutExpired:
   os.killpg(proc.pid,signal.SIGTERM)
   try:proc.wait(timeout=15)
   except subprocess.TimeoutExpired:os.killpg(proc.pid,signal.SIGKILL);proc.wait()
   code=-1
 record.update(exitCode=code,finishedAt=now(),elapsedSeconds=time.monotonic()-start,logBytes=log.stat().st_size,logSHA256=sha(log))
 save();print(json.dumps({'event':'terminal',**record}),flush=True)
 text=log.read_text(errors='replace')
 if code!=expected:raise RuntimeError(label+' actual exit '+str(code)+', expected '+str(expected))
 if label=='baseline':
  if 'Execution timed out after 20s' not in text or 'Executed 1 test, with 2 failures' not in text:raise RuntimeError('Baseline did not reproduce the exact original timeout/assertions; inspect retained raw log')
 else:
  if 'Executed 3 tests, with 0 failures' not in text:raise RuntimeError('Candidate did not execute all three original-bridge regressions')
state.update(status='RUNNING',startedAt=now(),controllerPID=os.getpid(),commands=[]);save()
try:
 common=['/usr/bin/swift','test','--package-path',str(base/'package'),'--scratch-path',str(base/'build'),'--jobs','1']
 production=base/'package/Sources/HanlinNativeScriptCoreSupport/HanlinNativeServicesBridge.m'
 production.write_bytes((base/'baseline.m').read_bytes())
 run('baseline',common+['--filter','NativeScriptMainRunLoopCallbackTests.testBackgroundCompletionReentersRunLoopInsideMainQueueSynchronousCall'],1)
 production.write_bytes((base/'candidate.m').read_bytes())
 run('candidate',common+['--filter','NativeScriptMainRunLoopCallbackTests'],0)
 state.update(status='PASS',finishedAt=now())
except BaseException as error:
 state.update(status='FAIL',error=str(error),finishedAt=now());raise
finally:save();print(json.dumps({'status':state['status'],'finishedAt':state['finishedAt'],'state':str(statePath)}),flush=True)
