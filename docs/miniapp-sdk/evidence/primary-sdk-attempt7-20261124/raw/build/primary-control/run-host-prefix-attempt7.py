from pathlib import Path
import os,sys,subprocess,json,time,datetime,hashlib,signal
c=Path(__file__).resolve().parent
r=c.parents[1]
receipt=c/'host-prefix-attempt7.json'
source='fd81d602d3b25f09162a659e1e0cf0582e91a93a'
def utc():return datetime.datetime.now(datetime.timezone.utc).isoformat()
def save(d):
 p=receipt.with_suffix('.tmp');p.write_text(json.dumps(d,indent=2)+'\n');p.replace(receipt)
assert not receipt.exists(),'Host prefix already has a retained receipt'
d={'source':source,'through':'split-host-lifecycle','scope':'ORIGINAL_HOST_PREFIX_ONLY','startedAt':utc(),'wrapperPID':os.getpid(),'status':'ADMITTING_LIGHT_PREFIX','nativePreparationStarted':False,'fullAcceptancePass':False}
save(d)
paused=False;admission_pid=None;controller=None;code=None
try:
 assert subprocess.check_output(['git','rev-parse','HEAD'],cwd=r,text=True).strip()==source
 a=json.loads((c/'capacity-admission-attempt7.json').read_text())
 s=json.loads((c/'state.json').read_text())
 assert a['source']==source and s['source']==source and s['attempt']==7
 if s['status']!='READY_FOR_REVIEWED_RESUME' or a['status']!='WAITING_FOR_NATIVE_CAPACITY':
  d.update(status='NOT_STARTED_EXISTING_ADMISSION_ADVANCED',stateStatus=s['status'],admissionStatus=a['status'],finishedAt=utc());save(d);sys.exit(0)
 admission_pid=a['pid']
 command=subprocess.check_output(['ps','-p',str(admission_pid),'-o','command='],text=True).strip()
 assert str(c/'admit_and_run-attempt7.py') in command,command
 d.update(admissionPID=admission_pid,admissionStartedAt=a['startedAt'],maximumWaitSeconds=a['maximumWaitSeconds'],activeElapsedBefore=s['activeElapsedSeconds'],admissionSHA256Before=hashlib.sha256((c/'capacity-admission-attempt7.json').read_bytes()).hexdigest())
 os.kill(admission_pid,signal.SIGSTOP);paused=True
 assert 'T' in subprocess.check_output(['ps','-p',str(admission_pid),'-o','state='],text=True)
 s=json.loads((c/'state.json').read_text());a=json.loads((c/'capacity-admission-attempt7.json').read_text())
 if s['status']!='READY_FOR_REVIEWED_RESUME' or a['status']!='WAITING_FOR_NATIVE_CAPACITY':
  d.update(status='NOT_STARTED_EXISTING_ADMISSION_ADVANCED',stateStatus=s['status'],admissionStatus=a['status'],finishedAt=utc());save(d);sys.exit(0)
 assert 'split-host-lifecycle' not in s['phases']
 argv=['/opt/homebrew/bin/python3.12',str(c/'controller-attempt7.py'),'split-host-lifecycle']
 log=c/'controller-host-prefix-attempt7.log'
 with log.open('xb') as stream:
  controller=subprocess.Popen(argv,cwd=r,env={**os.environ,'DEVELOPER_DIR':'/Applications/Xcode.app/Contents/Developer'},stdin=subprocess.DEVNULL,stdout=stream,stderr=subprocess.STDOUT,start_new_session=True)
  d.update(status='RUNNING',controllerPID=controller.pid,controllerArgv=argv,controllerStartedAt=utc(),log=str(log),admissionTemporarilyPaused=True);save(d)
  code=controller.wait()
 s=json.loads((c/'state.json').read_text())
 d.update(exitCode=code,controllerFinishedAt=utc(),controllerStateStatus=s['status'],phase=s.get('phase'),phaseResult=s.get('phases',{}).get('split-host-lifecycle'),activeElapsedAfter=s['activeElapsedSeconds'],logSHA256=hashlib.sha256(log.read_bytes()).hexdigest())
 if code==0 and s['status']=='PAUSED_AFTER_PHASE' and s['phases']['split-host-lifecycle']['status']=='PASS':
  d.update(status='HOST_PREFIX_PASS_HEAVY_WORK_PENDING',finishedAt=utc())
 else:
  d.update(status='HOST_PREFIX_FAIL',finishedAt=utc(),error=s.get('error'))
  os.kill(admission_pid,signal.SIGTERM)
  a=json.loads((c/'capacity-admission-attempt7.json').read_text())
  a.update(status='STOPPED_AFTER_HOST_PREFIX_FAILURE',finishedAt=utc(),prefixReceipt=str(receipt))
  (c/'capacity-admission-attempt7.json').write_text(json.dumps(a,indent=2)+'\n')
 save(d)
except BaseException as e:
 if not isinstance(e,SystemExit):
  d.update(status='HOST_PREFIX_CONTROLLER_ERROR',error=repr(e),finishedAt=utc());save(d)
  if controller is None and admission_pid and paused:
   pass
  raise
finally:
 if paused and admission_pid:
  try:os.kill(admission_pid,signal.SIGCONT)
  except ProcessLookupError:pass
  d.update(admissionTemporarilyPaused=False,admissionResumedAt=utc());save(d)
print(json.dumps(d),flush=True)
