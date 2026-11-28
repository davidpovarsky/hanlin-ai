import pathlib,subprocess,os,json,hashlib,datetime,time,fcntl,signal,traceback,plistlib,copy
stage=pathlib.Path('/Users/m1/builds/hanlin-two-wave-root-20261126');root=stage/'source';package=root/'Packages/HanlinPlatform'
source='866d2d3c60525e32eae27564869e6dba024e625c';dd=pathlib.Path('/Users/m1/builds/hanlin-two-wave-root-20261126/derived-data/platform-16b4af44')
proof=stage/'validation/platform-866d2d3c/test-r1';receipt=stage/'platform-native-test-866d2d3c-r1.json';uuid='233DB080-C913-4EE6-BF3D-99659F5CD475'
now=lambda:datetime.datetime.now(datetime.timezone.utc).isoformat()
def digest(p):
 with p.open('rb') as f:return hashlib.file_digest(f,'sha256').hexdigest()
def free():s=os.statvfs('/System/Volumes/Data');return s.f_bavail*s.f_frsize
data={'source':source,'status':'PREPARING','startedAt':now(),'controllerPID':os.getpid(),'route':'Original HanlinPlatform-Package generated xctestrun, same built products, supported test-without-building and exact enumerated selectors; only the original optional raster evidence directory is supplied. No source, test assertion, timeout, diagnostic policy or dependency change. Actual required58 definitions/79 invocations comprise the unchanged original57/78 plus one reviewed V1 regression. Prior actual execution honored all original exclusions; collateral acceptance remains0.','expectedDefinitions':58,'expectedInvocations':79,'originalRequiredDefinitions':57,'originalRequiredInvocations':78,'newRegressionDefinitions':1,'newRegressionInvocations':1,'collateralAcceptance':0,'phases':[],'requiredFreeBytes':4073741824,'phaseBudget':{'ownedNativeExecutionAndResultsAllowance':1000000000,'observedSharedGrowthAllowance':2000000000,'OSMargin':1073741824}}
env=os.environ.copy();env['PATH']=str(stage/'tool-bin')+':/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin';env['NSUnbufferedIO']='YES'
def save():
 t=receipt.with_suffix('.tmp');t.write_text(json.dumps(data,indent=2)+'\n');t.replace(receipt)
def phase(name,args,timeout=600,allow_failure=False):
 pth=proof/(name+'.log');row={'name':name,'command':args,'cwd':str(package),'startedAt':now(),'log':str(pth)};data['phases'].append(row);save()
 with pth.open('wb') as f:
  p=subprocess.Popen(args,cwd=package,env=env,stdout=f,stderr=subprocess.STDOUT,start_new_session=True);row.update(pid=p.pid,status='RUNNING');save();start=time.monotonic()
  while True:
   try:rc=p.wait(timeout=10);break
   except subprocess.TimeoutExpired:
    row['lastObservation']={'at':now(),'freeBytes':free(),'logBytes':pth.stat().st_size};save()
    if free()<750000000 or time.monotonic()-start>timeout:
     row['stopReason']='ACTUAL_DISK_FLOOR' if free()<750000000 else 'BOUNDED_CONTROLLER_TIMEOUT';save();os.killpg(p.pid,signal.SIGINT)
     try:rc=p.wait(timeout=30)
     except subprocess.TimeoutExpired:
      os.killpg(p.pid,signal.SIGTERM)
      try:rc=p.wait(timeout=10)
      except subprocess.TimeoutExpired:os.killpg(p.pid,signal.SIGKILL);rc=p.wait()
     break
 row.update(exitCode=rc,status='PASSED' if rc==0 and not row.get('stopReason') else 'FAILED',finishedAt=now(),logSHA256=digest(pth));save()
 if row['status']!='PASSED' and not allow_failure:raise RuntimeError({'phase':name,'exitCode':rc,'stopReason':row.get('stopReason'),'log':str(pth)})
 return row
lock=open('/Users/m1/caches/hanlin-two-wave-native-app.lock','a+')
maintenance=open('/Users/m1/caches/.scaleway-cache-maintenance.lock','a+')
try:
 fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB);fcntl.flock(maintenance,fcntl.LOCK_SH|fcntl.LOCK_NB)
 assert not proof.exists() and not receipt.exists();proof.mkdir(parents=True)
 data['coordinationLocks']={'native':'exclusive','existingMaintenance':'shared'}
 data['freeAtAdmission']=free();assert data['freeAtAdmission']>=data['requiredFreeBytes'];save()
 assert subprocess.check_output(['/usr/bin/git','-C',str(root),'rev-parse','HEAD'],text=True).strip()==source
 assert subprocess.check_output(['/usr/bin/git','-C',str(root),'rev-parse','HEAD:Packages/HanlinPlatform/Sources'],text=True).strip()=='1586a7e95b6a3245bf0bb0ea60600c9b5086bc63'
 assert not subprocess.check_output(['/usr/bin/git','-C',str(root),'diff','--name-only','HEAD','--','Packages/HanlinPlatform','Fixtures/Widgets'],text=True).strip()
 builtPath=stage/'platform-native-build-866d2d3c-r2.json';built=json.loads(builtPath.read_text());assert built['status']=='BUILT_FOR_TESTING_AWAITING_ORIGINAL_TEST_EXECUTION' and built['source']==source
 invPath=stage/'platform-test-inventory-866d2d3c.json';inv=json.loads(invPath.read_text());assert inv['sourceCommit']==source
 assert digest(invPath)=='a5530408269f296d1cbb743fd52624f74755509623ee68b2bfd0f7e351b78822'
 for rel,sha in inv['sourceSHA256'].items():assert digest(root/rel)==sha,rel
 expected={t['sourceDerivedIdentifier']:t for t in inv['prior59']}
 for name in inv['queue19']['methods']:
  ident=inv['queue19']['selector']+'/'+name+'()';assert ident not in expected
  expected[ident]={'sourceDerivedIdentifier':ident,'expectedInvocations':1,'parameterValues':None}
 assert len(expected)==57 and sum(t['expectedInvocations'] for t in expected.values())==78
 previousExecutionPath=stage/'validation/platform-6975e769/test-r2/required-scope-reconciliation.json'
 assert digest(previousExecutionPath)=='be476c5a6739385b129ba5cf428157cef08de8b5714ecd5987d1b19bad584c98'
 previousExecution=json.loads(previousExecutionPath.read_text())
 assert {x['identifier'] for x in previousExecution['tests']}==set(expected)
 new=inv['compatibilityRegression'];assert new['sourceDerivedIdentifier']=='HanlinScriptExtensionsTests/HanlinDualWidgetEnginesTests/v1ShadowProjectsHistoricalFieldsWithoutLosingCurrentMetadata()' and new['expectedInvocations']==1 and new['parameterValues'] is None
 expected[new['sourceDerivedIdentifier']]=new
 assert len(expected)==58 and sum(t['expectedInvocations'] for t in expected.values())==79
 reviewPath=stage/'platform-independent-compatibility-review-16b4af44.json';assert digest(reviewPath)=='6474b813c1a524d1261219c8f3a0ff8b5e1883ad65ba9c66637f739b30fd05fb'
 review=json.loads(reviewPath.read_text());assert review['source']=='16b4af4490d96c41cb76ed185a1e6d4e828899e7' and review['decision']=='APPROVED_BOUNDED_SOURCE_CORRECTION_NATIVE_ACCEPTANCE_PENDING'
 currentReviewPath=stage/'platform-final-controller-review-866d2d3c-r2.json'
 currentReview=json.loads(currentReviewPath.read_text())
 assert currentReview['source']=='866d2d3c60525e32eae27564869e6dba024e625c' and currentReview['decision']=='APPROVED_ORIGINAL_NATIVE_AND_HOST_SOURCE_BINDINGS'
 assert currentReview['inventorySHA256']=='a5530408269f296d1cbb743fd52624f74755509623ee68b2bfd0f7e351b78822'
 assert currentReview['controllerSHA256'][pathlib.Path(__file__).name]==digest(pathlib.Path(__file__))
 data['currentControllerReview']={'path':str(currentReviewPath),'sha256':digest(currentReviewPath)}
 oldReviewPath=stage/'platform-independent-61-scope-6975e769.json';oldReview=json.loads(oldReviewPath.read_text())
 collateral={x['identifier'] for x in oldReview['exactExpectedCohort'] if x['classification']!='REQUIRED'}
 assert len(collateral)==4 and not(set(expected)&collateral)
 data['originalFixtureParity']=[]
 for rel in oldReview['fixtureSourceFiles']:
  p=root/rel;assert p.is_file() and not p.is_symlink()
  tracked=subprocess.check_output(['/usr/bin/git','-C',str(root),'show',source+':'+rel])
  assert hashlib.sha256(tracked).hexdigest()==digest(p),rel
  data['originalFixtureParity'].append({'path':str(p),'bytes':p.stat().st_size,'sha256':digest(p)})
 enumReceiptPath=stage/'platform-native-enumeration-6975e769-r4.json';enumReceipt=json.loads(enumReceiptPath.read_text())
 selectors=built['selectors'];assert selectors==enumReceipt['selectors'] and all(x.startswith(('-only-testing:','-skip-testing:')) for x in selectors)
 assert '-only-testing:HanlinScriptExtensionsTests/HanlinDualWidgetEnginesTests' in selectors
 assert not any(new['function'] in s for s in selectors if s.startswith('-skip-testing:'))
 data['selection']={'inventory':str(invPath),'inventorySHA256':digest(invPath),'expectedDefinitions':58,'expectedInvocations':79,'parameterInvocations':28,'collateralAcceptance':0,'expectedTests':list(expected.values()),'excludedCollateralIdentifiers':sorted(collateral),'observedPriorExecution':{'path':str(previousExecutionPath),'sha256':digest(previousExecutionPath),'actualDefinitions':57,'actualInvocations':78},'historicalIndependentCorrectionReview':{'path':str(reviewPath),'sha256':digest(reviewPath)},'route':'Retain exactly the documented includes/exclusions whose previous actual execution matched57/78; only one new test was added inside the already included suite. Require actual58/79, all28 unchanged parameter invocations and zero collateral.'}
 data['selectors']=selectors;data['buildReceipt']={'path':str(builtPath),'sha256':digest(builtPath)}
 pinpath=package/'Package.resolved';assert digest(pinpath)==built['originalLockSHA256'];data['packagePinSHA256']=digest(pinpath)
 data['resolvedPins']=[]
 for pin in built['originalPins']['pins']:
  candidates=[p for p in (dd/'SourcePackages/checkouts').iterdir() if p.is_dir() and p.name.lower()==pin['identity'].lower()];assert len(candidates)==1,pin['identity']
  revision=subprocess.check_output(['/usr/bin/git','-C',str(candidates[0]),'rev-parse','HEAD'],text=True).strip();assert revision==pin['state']['revision']
  data['resolvedPins'].append({'identity':pin['identity'],'revision':revision})
 fixture=root/'Fixtures/Widgets/Hanlin-Expo-Widget-Counter.hanlinExpo'
 assert digest(fixture)=='a52c828cdb87f115c668b7cba544781ce89c023b14a65551844ee7985faa3d9d'
 data['originalCompatibilityFixture']={'path':str(fixture),'sha256':digest(fixture),'bytes':fixture.stat().st_size}
 run=dd/'Build/Products/HanlinPlatform-Package_HanlinPlatform-Package_iphonesimulator27.0-arm64.xctestrun'
 observed=[x for x in built['xctestruns'] if x['path']==str(run)];assert len(observed)==1 and digest(run)==observed[0]['sha256']
 original=plistlib.loads(run.read_bytes());assert original['__xctestrun_metadata__']['FormatVersion']==2
 targets=[t for c in original['TestConfigurations'] for t in c['TestTargets']]
 selected={ident.split('/')[0] for ident in expected};assert selected<={t['BlueprintName'] for t in targets}
 data['originalXctestrun']={'path':str(run),'sha256':digest(run),'formatVersion':2,'selectedTargets':sorted(selected)}
 data['selectedProducts']=[]
 for t in targets:
  if t['BlueprintName'] not in selected:continue
  p=pathlib.Path(t['TestBundlePath'].replace('__TESTROOT__',str(run.parent)));binary=p/t['BlueprintName'];assert binary.is_file()
  data['selectedProducts'].append({'target':t['BlueprintName'],'path':str(binary),'bytes':binary.stat().st_size,'sha256':digest(binary),'originalTestHostPath':t['TestHostPath']})
 assert len(data['selectedProducts'])==len(selected)
 modified=copy.deepcopy(original);matches=[t for c in modified['TestConfigurations'] for t in c['TestTargets'] if t['BlueprintName']=='HanlinScriptExtensionsTests'];assert len(matches)==1
 evidenceDirectory=proof/'raster-evidence';evidenceDirectory.mkdir()
 target=matches[0];assert 'HANLIN_WIDGET_EVIDENCE_DIR' not in target.get('EnvironmentVariables',{})
 target.setdefault('EnvironmentVariables',{})['HANLIN_WIDGET_EVIDENCE_DIR']=str(evidenceDirectory)
 derived=run.parent/'HanlinPlatform-866d2d3c-native-evidence-r1.xctestrun';assert not derived.exists();derived.write_bytes(plistlib.dumps(modified,fmt=plistlib.FMT_XML))
 check=plistlib.loads(derived.read_bytes());changed=[t for c in check['TestConfigurations'] for t in c['TestTargets'] if t['BlueprintName']=='HanlinScriptExtensionsTests'];assert len(changed)==1
 assert changed[0]['EnvironmentVariables'].pop('HANLIN_WIDGET_EVIDENCE_DIR')==str(evidenceDirectory) and check==original
 data['executionXctestrun']={'path':str(derived),'sha256':digest(derived),'onlySemanticDifference':{'target':'HanlinScriptExtensionsTests','EnvironmentVariables.HANLIN_WIDGET_EVIDENCE_DIR':str(evidenceDirectory)},'sameTestRoot':derived.parent==run.parent,'originalDeepEqualityAfterRemovingOutputVariable':True}
 deviceRow=phase('owned-device-readback',['xcrun','simctl','list','devices','available','-j'],90)
 devices=json.loads(pathlib.Path(deviceRow['log']).read_text())['devices'];observed=[dict(d,runtime=r) for r,ds in devices.items() for d in ds if d.get('udid')==uuid]
 assert len(observed)==1 and observed[0]['runtime']=='com.apple.CoreSimulator.SimRuntime.iOS-27-2' and observed[0]['isAvailable']
 ownerPath=stage/'validation/08ed647b-mini-build-r1/original-mini-build/owned-simulator.json';owner=json.loads(ownerPath.read_text());assert owner['udid']==uuid and owner['createdByThisController']
 data['simulator']={'udid':uuid,'runtime':observed[0]['runtime'],'stateBefore':observed[0]['state'],'ownershipReceiptSHA256':digest(ownerPath)}
 if observed[0]['state']=='Shutdown':phase('owned-simulator-boot',['xcrun','simctl','boot',uuid],120)
 else:assert observed[0]['state']=='Booted'
 phase('owned-simulator-ready',['xcrun','simctl','bootstatus',uuid,'-b'],300)
 data['freeBeforeTest']=free();assert data['freeBeforeTest']>=data['requiredFreeBytes']
 result=proof/'PlatformTests.xcresult';command=['xcodebuild','test-without-building','-xctestrun',str(derived),'-destination','platform=iOS Simulator,id='+uuid,'-parallel-testing-enabled','NO','-resultBundlePath',str(result),*selectors]
 data['status']='RUNNING_ORIGINAL_NATIVE_TESTS';save();native=phase('original-native-test-without-building',command,1800,True);data['nativeExitCode']=native['exitCode'];data['resultBundle']=str(result);save()
 if (result/'Info.plist').is_file():
  for name,command in [('native-result-summary',['xcrun','xcresulttool','get','test-results','summary','--path',str(result),'--format','json']),('native-result-tests',['xcrun','xcresulttool','get','test-results','tests','--path',str(result),'--format','json'])]:phase(name,command,300,True)
  data['resultInfoSHA256']=digest(result/'Info.plist')
 else:data['resultIncomplete']=True
 data['rasterEvidence']=[{'path':str(p),'bytes':p.stat().st_size,'sha256':digest(p)} for p in sorted(evidenceDirectory.glob('*.png'))]
 assert digest(run)==data['originalXctestrun']['sha256'] and digest(derived)==data['executionXctestrun']['sha256']
 for item in data['selectedProducts']:assert digest(pathlib.Path(item['path']))==item['sha256']
 for rel,sha in inv['sourceSHA256'].items():assert digest(root/rel)==sha,rel
 for item in data['originalFixtureParity']:assert digest(pathlib.Path(item['path']))==item['sha256']
 assert digest(pinpath)==data['packagePinSHA256'] and digest(fixture)==data['originalCompatibilityFixture']['sha256']
 assert subprocess.check_output(['/usr/bin/git','-C',str(root),'rev-parse','HEAD'],text=True).strip()==source
 data['sourceProductsAndFixturesUnchanged']=True
 data['status']='TEST_COMMAND_FINISHED_AWAITING_EXACT_CASE_RECONCILIATION' if native['status']=='PASSED' else 'TEST_COMMAND_FAILED_WITH_RETAINED_RESULTS'
except Exception as e:data.update(status='FAILED',error=repr(e),traceback=traceback.format_exc())
finally:
 data['finishedAt']=now();data['freeAfter']=free();save();print(json.dumps({k:data.get(k) for k in ['source','status','error','nativeExitCode','finishedAt','freeAfter','resultBundle','resultIncomplete','rasterEvidence']}),flush=True)
if data['status']!='TEST_COMMAND_FINISHED_AWAITING_EXACT_CASE_RECONCILIATION':raise SystemExit(1)
