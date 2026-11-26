from pathlib import Path
import subprocess,json,hashlib,datetime,fcntl,os,sys,time,base64
R=Path('/Users/m1/builds/hanlin-ai-ce49e30d-miniapp-complete');C=R/'build/primary-control'
def sha(p):
 with Path(p).open('rb')as f:return hashlib.file_digest(f,'sha256').hexdigest()
def utc():return datetime.datetime.now(datetime.timezone.utc).isoformat()
name='notification-os-v2'
sealer=C/'seal-notification-os-decision-v5.py';assert sha(sealer)=='5420df7554987731262440fa7fef022a03ce42b3fb4081b1010c8609c8f534f7'
decision=C/(name+'-decision.json');out=C/name
assert not decision.exists()and not out.exists()
node=Path('/Users/m1/builds/hanlin-ai-ce49e30d-miniapp-complete-tools/node-v24.5.0-darwin-arm64/bin/node')
env=dict(os.environ);env['PATH']=str(node.parent)+':/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin';env['DEVELOPER_DIR']='/Applications/Xcode.app/Contents/Developer'
started=utc();a=time.monotonic();cmd=[sys.executable,str(sealer)]
q=subprocess.run(cmd,cwd=R,env=env,text=True,capture_output=True,timeout=45)
sc={'argv':cmd,'startedAt':started,'finishedAt':utc(),'seconds':time.monotonic()-a,'exitCode':q.returncode,'stdout':q.stdout,'stderr':q.stderr}
sp=C/(name+'-seal-command.json');assert not sp.exists();sp.write_text(json.dumps(sc,indent=2)+'\n')
files=[sp]
if q.returncode==0:
 d=json.loads(decision.read_text());receipt=C/(name+'-decision-receipt.json');sr=json.loads(receipt.read_text())
 assert sha(decision)==sr['decision']['sha256']
 assert d['source']=='d4a0b115b106d4250ea40ad66153d5156847a07c'and d['sourceTree']=='f7a6596a1ef53d8d962ceb9f619460ffa19ee91e'
 controller=C/'notification-os-v7.py';assert sha(controller)==sr['controller']['sha256']=='a18a542aa525ead25d50f870f63a252aeef5328678e895e7f3d2f6d1c0961d5f'
 assert d['allowanceSeconds']==900 and d['expectedTests']==1
 assert d['osContinuation']['priorChargedSeconds']==353.58866224999656
 assert d['osContinuation']['remainingAllowanceSeconds']==900-353.58866224999656
 assert d['selector']=='HanlinMiniAppsUITests/MiniAppsProductionRuntimeUITests/testOriginalNotificationAuthorizationAndOSDeliveryToBothEngines'
 launch=C/(name+'-launch.json');log=C/(name+'-launch.log')
 assert not out.exists()and not launch.exists()and not log.exists()
 lock=(C/'native-continuation-owner.lock').open('a');fcntl.flock(lock.fileno(),fcntl.LOCK_EX|fcntl.LOCK_NB)
 assert sha(C/'state.json')==d['primaryStateSHA256']
 primary=json.loads((C/'state.json').read_text());assert primary['status']in('COMPLETED','FAIL','PAUSED_AFTER_PHASE')and primary.get('controllerPID')is None and primary['activeElapsedSeconds']==d['activeBaselineSeconds']
 df=subprocess.check_output(['df','-k','/System/Volumes/Data'],text=True);free=int(df.splitlines()[-1].split()[3])*1024
 assert free>=d['resourceAssessment']['estimatedIncrementalBytes']+d['resourceAssessment']['concurrentAndOSAllowanceBytes']
 fcntl.flock(lock.fileno(),fcntl.LOCK_UN);lock.close()
 argv=[sys.executable,str(controller),'--decision',str(decision)]
 with log.open('xb')as output:
  process=subprocess.Popen(argv,cwd=R,env=env,stdin=subprocess.DEVNULL,stdout=output,stderr=subprocess.STDOUT,start_new_session=True)
 lr={'schema':1,'source':d['source'],'observedAt':utc(),'pid':process.pid,'argv':argv,'decision':str(decision),'decisionSHA256':sha(decision),'controllerSHA256':sha(controller),'activeBaselineSeconds':d['activeBaselineSeconds'],'allowanceSeconds':d['osContinuation']['remainingAllowanceSeconds'],'originalAllowanceSeconds':d['allowanceSeconds'],'priorChargedSeconds':d['osContinuation']['priorChargedSeconds'],'freshFreeBytes':free,'selector':d['selector'],'expectedTests':1,'phaseStatus':'NOT_RUN_AT_DISPATCH'}
 launch.write_text(json.dumps(lr,indent=2)+'\n')
 files += [decision,receipt,C/(name+'-seal-inputs.json'),launch]
 time.sleep(2)
 if(out/'state.json').is_file():files.append(out/'state.json')
 status={'status':'DISPATCHED_ONCE','launch':lr,'controllerExit':process.poll(),'state':json.loads((out/'state.json').read_text())if(out/'state.json').exists()else None,'logTail':log.read_text()[-2000:]}
else:status={'status':'SEAL_REJECTED_NO_LAUNCH','command':sc}
print(json.dumps({'result':status,'files':[{'sourcePath':str(p),'name':(name+'-first-state.json'if p==out/'state.json'else p.name),'bytes':p.stat().st_size,'sha256':sha(p),'base64':base64.b64encode(p.read_bytes()).decode()}for p in files]}))