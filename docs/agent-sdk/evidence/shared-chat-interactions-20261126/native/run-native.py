import pathlib,subprocess,json,hashlib,time,datetime,os,shutil,traceback
BASE=pathlib.Path('/Users/m1/builds/hanlin-shared-chat-a84ecd6d-20261126')
SRC=BASE/'source'
RESULTS=BASE/'results';RESULTS.mkdir(exist_ok=True)
DD=pathlib.Path('/Users/m1/caches/DerivedData/hanlin-shared-chat-a84ecd6d-20261126')
SP=BASE/'SourcePackages'
SHA='a84ecd6db0dfa77e2241cb9481b9f9d43a7a13c6'
def now():return datetime.datetime.now(datetime.timezone.utc).isoformat()
def free():
 s=os.statvfs('/System/Volumes/Data');return s.f_bavail*s.f_frsize
receipt={'source_sha':SHA,'started_at':now(),'status':'RUNNING','scope':'Focused original LauncherLab consumer and five new shared interaction methods','steps':[],'free_bytes_start':free(),'derived_data':str(DD),'result_bundle':str(RESULTS/'interaction-r1.xcresult'),'policy_tests':'NOT_RUN: unchanged original policy evidence reused separately'}
def save(): (BASE/'native-receipt.json').write_text(json.dumps(receipt,indent=2)+'\n')
def step(name,cmd,cwd=BASE,timeout=1800,check=True):
 log=RESULTS/(name+'.log');start=time.monotonic();item={'name':name,'command':cmd,'cwd':str(cwd),'started_at':now(),'free_bytes_before':free()};receipt['steps'].append(item);save()
 with log.open('w') as out:
  try:p=subprocess.run(cmd,cwd=cwd,text=True,stdout=out,stderr=subprocess.STDOUT,timeout=timeout);rc=p.returncode
  except subprocess.TimeoutExpired:rc=124
 item.update({'exit':rc,'finished_at':now(),'seconds':round(time.monotonic()-start,3),'log':str(log),'log_sha256':hashlib.sha256(log.read_bytes()).hexdigest(),'free_bytes_after':free()});save()
 if check and rc:raise RuntimeError(name+' exit '+str(rc))
 return rc
try:
 transfer=json.loads((BASE/'source-transfer.json').read_text())
 assert transfer['source_sha']==SHA
 assert hashlib.sha256((BASE/'source.tar.gz').read_bytes()).hexdigest()==transfer['archive_sha256']
 receipt['transfer']=transfer;save()
 SRC.mkdir(exist_ok=True)
 step('extract',['tar','-xzf',str(BASE/'source.tar.gz'),'-C',str(SRC)],timeout=120)
 shutil.copy2(SRC/'Package.swift',BASE/'canonical-Package.swift')
 step('toolchain',['xcodebuild','-version'],timeout=30)
 for name in ['repositories','checkouts']:
  donor=pathlib.Path('/Users/m1/builds/hanlin-testflight-149101-20261125/SourcePackages')/name
  dest=SP/name;SP.mkdir(exist_ok=True)
  if dest.exists():raise RuntimeError('Unexpected existing cache '+str(dest))
  step('clone-'+name,['/bin/cp','-cR',str(donor),str(dest)],timeout=300)
 step('selected-products',['python3','Scripts/SDK/generate_manifest.py','--products','HanlinChatPresentation','HanlinPresentationKit','HanlinChatUI'],cwd=SRC,timeout=180)
 receipt['profile']=json.loads((SRC/'docs/agent-sdk/unified-package-manifest.json').read_text())
 receipt['selected_manifest_sha256']=hashlib.sha256((SRC/'Package.swift').read_bytes()).hexdigest()
 shutil.copy2(SRC/'Package.swift',BASE/'selected-Package.swift');save()
 EXAMPLE=SRC/'Examples/HanlinLauncherLab'
 step('xcodegen',['/opt/homebrew/bin/xcodegen','generate','--spec','project.yml'],cwd=EXAMPLE,timeout=60)
 PROJECT=EXAMPLE/'HanlinLauncherLab.xcodeproj'
 canonical_lock=SRC/'AI_HLY.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved'
 own_lock=PROJECT/'project.xcworkspace/xcshareddata/swiftpm/Package.resolved'
 own_lock.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(canonical_lock,own_lock)
 receipt['canonical_lock_sha256']=hashlib.sha256(canonical_lock.read_bytes()).hexdigest();save()
 baseargs=['xcodebuild','-project',str(PROJECT),'-scheme','HanlinLauncherLab','-clonedSourcePackagesDirPath',str(SP),'-skipPackagePluginValidation','-skipMacroValidation']
 step('resolve',baseargs+['-resolvePackageDependencies','-onlyUsePackageVersionsFromResolvedFile'],cwd=SRC,timeout=600)
 original={p['identity']:p['state'] for p in json.loads(canonical_lock.read_text())['pins']}
 actual={p['identity']:p['state'] for p in json.loads(own_lock.read_text())['pins']}
 mismatch={k:{'expected':original.get(k),'actual':v} for k,v in actual.items() if original.get(k)!=v}
 receipt['pin_validation']={'actual':actual,'mismatches':mismatch};save()
 if mismatch:raise RuntimeError('Resolved dependency pins differ from integrated canonical source')
 devices=json.loads(subprocess.check_output(['xcrun','simctl','list','devices','available','-j'],text=True))
 name='HanlinSharedUI-a84ecd6d-20261126'
 existing=[x['udid'] for val in devices['devices'].values() for x in val if x['name']==name]
 if len(existing)>1:raise RuntimeError('Duplicate owned simulator name')
 udid=existing[0] if existing else subprocess.check_output(['xcrun','simctl','create',name,'com.apple.CoreSimulator.SimDeviceType.iPad-Pro-11-inch-M5-12GB','com.apple.CoreSimulator.SimRuntime.iOS-27-0'],text=True).strip()
 receipt['simulator']={'udid':udid,'name':name,'runtime':'iOS 27.0 24A434','device_type':'iPad Pro 11-inch M5 12GB'};save()
 args=baseargs+['test','-configuration','Debug','-destination','platform=iOS Simulator,id='+udid,'-derivedDataPath',str(DD),'-resultBundlePath',str(RESULTS/'interaction-r1.xcresult'),'-disableAutomaticPackageResolution','-onlyUsePackageVersionsFromResolvedFile','-parallel-testing-enabled','NO','-only-testing:HanlinLauncherLabTests/HanlinMessagePreviewMetricsTests','-only-testing:HanlinLauncherLabTests/HanlinMessageActionTests','CODE_SIGNING_ALLOWED=NO','COMPILER_INDEX_STORE_ENABLE=NO']
 rc=step('native-interactions',args,cwd=SRC,timeout=1800,check=False)
 if (RESULTS/'interaction-r1.xcresult/Info.plist').exists():
  step('test-summary',['xcrun','xcresulttool','get','test-results','summary','--path',str(RESULTS/'interaction-r1.xcresult')],timeout=45,check=False)
 receipt['status']='NATIVE_COMMAND_PASSED_PENDING_COUNT_REVIEW' if rc==0 else 'FAILED'
except BaseException as e:
 receipt['status']='FAILED';receipt['error']=str(e)
 (RESULTS/'runner-error.log').write_text(traceback.format_exc())
finally:
 receipt['finished_at']=now();receipt['free_bytes_end']=free();save()
 print(json.dumps({'status':receipt['status'],'receipt':str(BASE/'native-receipt.json')}),flush=True)
