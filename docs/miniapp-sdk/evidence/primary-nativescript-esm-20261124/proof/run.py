import pathlib, subprocess, os, json, hashlib, datetime, time, signal, re
ROOT=pathlib.Path('/Users/m1/builds/hanlin-ai-ce49e30d-miniapp-complete')
WORK=ROOT/'build/primary-control/ns-esm-regression-attempt7'
REPO=WORK/'repository'
HOST=REPO/'AI_HLY/Downstream/RuntimeCore/Node/Host'
NODE='/Users/m1/builds/hanlin-ai-ce49e30d-miniapp-complete-tools/node-v24.5.0-darwin-arm64/bin/node'
STATE=WORK/'state.json'
def now():return datetime.datetime.now(datetime.timezone.utc).isoformat()
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
state=json.loads((WORK/'prepared.json').read_text())
state.update(status='RUNNING',startedAt=now(),controllerPID=os.getpid(),commands=[])
def save():
 p=STATE.with_suffix('.tmp');p.write_text(json.dumps(state,indent=2)+'\n');p.replace(STATE)
def run(label,pattern,expected,files):
 env=dict(os.environ)
 env['PATH']=str(pathlib.Path(NODE).parent)+':/opt/homebrew/bin:/usr/bin:/bin'
 env['HANLIN_AUTHORING_TYPESCRIPT']=(ROOT/'Scripts/NativeScript/node_modules/typescript/lib/typescript.js').as_uri()
 env['HANLIN_MINIAPP_REPOSITORY_ROOT']=str(REPO)
 env['HANLIN_AUTHORING_TMP']=str(WORK/'tmp')
 command=[NODE,'--test','--test-reporter=tap','--test-concurrency=1','--test-name-pattern='+pattern,*[str(HOST/'Tests'/p) for p in files]]
 event={'label':label,'argv':command,'startedAt':now(),'expectedExitCode':expected}
 log=WORK/(label+'.log');started=time.monotonic()
 with log.open('wb') as output:
  process=subprocess.Popen(command,stdout=output,stderr=subprocess.STDOUT,env=env,cwd=REPO,start_new_session=True)
  event['pid']=process.pid;state['commands'].append(event);state['phase']=label;save()
  try:code=process.wait(timeout=300)
  except subprocess.TimeoutExpired:
   os.killpg(process.pid,signal.SIGTERM)
   try:process.wait(timeout=5)
   except subprocess.TimeoutExpired:os.killpg(process.pid,signal.SIGKILL);process.wait()
   code=process.returncode;event['timedOut']=True
 event.update(exitCode=code,finishedAt=now(),elapsedSeconds=time.monotonic()-started,log=str(log),logBytes=log.stat().st_size,logSHA256=sha(log))
 text=log.read_text(errors='replace')
 event['tapCounts']={key:int(value) for key,value in re.findall(r'^# (tests|pass|fail|skipped) (\d+)$',text,re.M)}
 save()
 if event.get('timedOut') or code!=expected:raise RuntimeError(f'{label}: expected {expected}, got {code}')
 if label=='baseline' and (event['tapCounts'].get('fail')!=1 or event['tapCounts'].get('pass')!=1):
  raise RuntimeError('Baseline must isolate one ESM failure while authored CommonJS passes.')
try:
 save()
 run('baseline',r'^NativeScript package emits a runnable ESM graph|^NativeScript preserves authored CommonJS JavaScript',1,['miniapp-authoring.test.mjs'])
 target=HOST/'miniapp-authoring.mjs';assert sha(target)==state['baselineSHA256']
 target.write_bytes((WORK/'candidate.mjs').read_bytes());assert sha(target)==state['candidateSHA256']
 run('candidate',r'^NativeScript package emits a runnable ESM graph|^NativeScript preserves authored CommonJS JavaScript|^NativeScript preserves the original npm runtime package|^NativeScript emission and copied bodies agree|^the real CLI archives and revalidates retained source',0,['miniapp-authoring.test.mjs','miniapp-sdk-resolution.test.mjs'])
 state.update(status='PASS',finishedAt=now());save()
except BaseException as error:
 state.update(status='FAIL',error=str(error),finishedAt=now());save();raise
