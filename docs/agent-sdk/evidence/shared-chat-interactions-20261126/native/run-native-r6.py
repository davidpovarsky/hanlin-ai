import pathlib,subprocess,json,hashlib,datetime,time,os,tarfile
BASE=pathlib.Path('/Users/m1/builds/hanlin-shared-chat-a84ecd6d-20261126');SRC=BASE/'source';RESULTS=BASE/'results'
def now():return datetime.datetime.now(datetime.timezone.utc).isoformat()
def free():
 s=os.statvfs('/System/Volumes/Data');return s.f_bavail*s.f_frsize
original=json.loads((BASE/'native-receipt.json').read_text())
previous=json.loads((BASE/'native-receipt-r5.json').read_text())
assert previous['status']=='FAILED'
cumulative={}
for number in range(2,6):cumulative.update(json.loads((BASE/('source-r'+str(number)+'-transfer.json')).read_text())['files'])
transfer=json.loads((BASE/'source-r6-transfer.json').read_text())
cumulative.update(transfer['files'])
assert previous['source_sha']==transfer['parent']
receipt={'source_sha':transfer['source_sha'],'parent':transfer['parent'],'started_at':now(),'status':'RUNNING','source_delta':transfer,'reused_setup':'native-receipt.json: canonical six-target source profile, exact pins, original XcodeGen target, own dependency cache and products','steps':[],'free_bytes_start':free(),'simulator':original['simulator']}
def save():(BASE/'native-receipt-r6.json').write_text(json.dumps(receipt,indent=2)+'\n')
save()
try:
 assert original['status']=='FAILED'
 assert hashlib.sha256((BASE/'source-r6.tar.gz').read_bytes()).hexdigest()==transfer['archive_sha256']
 for path,value in transfer['files'].items():assert hashlib.sha256((SRC/path).read_bytes()).hexdigest()==value['before_sha256'],path
 subprocess.run(['tar','-xzf',str(BASE/'source-r6.tar.gz'),'-C',str(SRC)],check=True)
 for path,value in transfer['files'].items():assert hashlib.sha256((SRC/path).read_bytes()).hexdigest()==value['after_sha256'],path
 assert hashlib.sha256((SRC/'Package.swift').read_bytes()).hexdigest()==original['selected_manifest_sha256']
 mismatches=[];checked=0
 with tarfile.open(BASE/'source.tar.gz','r:gz') as archive:
  for item in archive:
   if not item.isfile() or item.name=='Package.swift':continue
   expected=cumulative.get(item.name,{}).get('after_sha256')
   if expected is None:expected=hashlib.sha256(archive.extractfile(item).read()).hexdigest()
   if hashlib.sha256((SRC/item.name).read_bytes()).hexdigest()!=expected:mismatches.append(item.name)
   checked+=1
 receipt['source_validation']={'checked_archived_files':checked,'mismatches':mismatches,'selected_manifest_unchanged':True};save()
 if mismatches:raise RuntimeError('Source validation mismatches')
 def setup_step(name,cmd,cwd=SRC):
  log=RESULTS/(name+'.log')
  item={'name':name,'command':cmd,'started_at':now()};receipt['steps'].append(item);save()
  with log.open('w') as output:q=subprocess.run(cmd,cwd=cwd,stdout=output,stderr=subprocess.STDOUT,timeout=300)
  item.update(exit=q.returncode,finished_at=now(),log_sha256=hashlib.sha256(log.read_bytes()).hexdigest());save()
  if q.returncode:raise RuntimeError(name+' failed')
 example=SRC/'Examples/HanlinLauncherLab'
 setup_step('xcodegen-r6',['/opt/homebrew/bin/xcodegen','generate','--spec','project.yml'],example)
 command=next(x['command'] for x in original['steps'] if x['name']=='native-interactions').copy()
 resolve=command[:command.index('test')]+['-resolvePackageDependencies','-onlyUsePackageVersionsFromResolvedFile']
 setup_step('resolve-r6',resolve)
 canonical={p['identity']:p['state'] for p in json.loads((SRC/'AI_HLY.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved').read_text())['pins']}
 actual={p['identity']:p['state'] for p in json.loads((example/'HanlinLauncherLab.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved').read_text())['pins']}
 mismatch={k:{'expected':canonical.get(k),'actual':v} for k,v in actual.items() if canonical.get(k)!=v}
 receipt['pin_validation']={'actual':actual,'mismatches':mismatch};save()
 if mismatch:raise RuntimeError('Resolved pins differ from canonical source')

 bundle=RESULTS/'interaction-r6.xcresult';command[command.index('-resultBundlePath')+1]=str(bundle)
 log=RESULTS/'native-interactions-r6.log';start=time.monotonic()
 step={'name':'native-interactions-r6','command':command,'started_at':now(),'free_bytes_before':free()};receipt['steps'].append(step);save()
 with log.open('w') as out:
  try:q=subprocess.run(command,cwd=SRC,stdout=out,stderr=subprocess.STDOUT,timeout=1800);rc=q.returncode
  except subprocess.TimeoutExpired:rc=124
 step.update({'exit':rc,'finished_at':now(),'seconds':round(time.monotonic()-start,3),'log_sha256':hashlib.sha256(log.read_bytes()).hexdigest()});save()
 if (bundle/'Info.plist').exists():
  summary=RESULTS/'test-summary-r6.json'
  with summary.open('w') as out:q=subprocess.run(['xcrun','xcresulttool','get','test-results','summary','--path',str(bundle)],stdout=out,stderr=subprocess.STDOUT,timeout=45)
  receipt['summary']={'exit':q.returncode,'path':str(summary),'sha256':hashlib.sha256(summary.read_bytes()).hexdigest()}
 receipt['status']='NATIVE_COMMAND_PASSED_PENDING_COUNT_REVIEW' if rc==0 else 'FAILED'
except BaseException as e:
 receipt['status']='FAILED';receipt['error']=str(e)
finally:
 receipt['finished_at']=now();receipt['free_bytes_end']=free();save()
 print(json.dumps({'status':receipt['status'],'receipt':str(BASE/'native-receipt-r6.json')}),flush=True)
