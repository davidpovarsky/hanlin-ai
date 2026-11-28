import pathlib,subprocess,os,json,hashlib,datetime,time,fcntl,signal,traceback,plistlib
stage=pathlib.Path('/Users/m1/builds/hanlin-two-wave-root-20261126');root=stage/'source';package=root/'Packages/HanlinPlatform'
source='16b4af4490d96c41cb76ed185a1e6d4e828899e7';dd=pathlib.Path('/Users/m1/builds/hanlin-two-wave-root-20261126/derived-data/platform-16b4af44')
proof=stage/'validation/platform-16b4af44/build-r2';receipt=stage/'platform-native-build-16b4af44-r2.json';uuid='233DB080-C913-4EE6-BF3D-99659F5CD475'
now=lambda:datetime.datetime.now(datetime.timezone.utc).isoformat()
def digest(p):
 with p.open('rb') as f:return hashlib.file_digest(f,'sha256').hexdigest()
def free():s=os.statvfs('/System/Volumes/Data');return s.f_bavail*s.f_frsize
data={'source':source,'status':'PREPARING','startedAt':now(),'controllerPID':os.getpid(),'route':'Original generated HanlinPlatform package scheme, actual iOS destination, exact original source/fixtures/pins. Build-for-testing phase; native test acceptance remains separate.','derivedData':str(dd),'expectedTestDefinitions':58,'expectedTestInvocations':79,'phases':[],'requiredFreeBytes':8073741824,'phaseBudget':{'freshCompileCheckoutsAndProductsAllowance':5000000000,'observedSharedGrowthAllowance':2000000000,'OSMargin':1073741824},'buildJobs':2}
env=os.environ.copy();env['PATH']=str(stage/'tool-bin')+':/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin';env['NSUnbufferedIO']='YES'
lock=open('/Users/m1/caches/hanlin-two-wave-native-app.lock','a+')
maintenance=open('/Users/m1/caches/.scaleway-cache-maintenance.lock','a+')
def save():
 t=receipt.with_suffix('.tmp');t.write_text(json.dumps(data,indent=2)+'\n');t.replace(receipt)
def phase(name,args,timeout=600,separate=False):
 path=proof/(name+'.log');err=proof/(name+'.stderr.log');row={'name':name,'command':args,'cwd':str(package),'startedAt':now(),'log':str(path)}
 data['phases'].append(row);save()
 with path.open('wb') as f,err.open('wb') as e:
  p=subprocess.Popen(args,cwd=package,env=env,stdout=f,stderr=e if separate else subprocess.STDOUT,start_new_session=True)
  row.update(pid=p.pid,status='RUNNING');save();start=time.monotonic()
  while True:
   try:rc=p.wait(timeout=15);break
   except subprocess.TimeoutExpired:
    row['lastObservation']={'at':now(),'freeBytes':free(),'elapsedSeconds':time.monotonic()-start,'logBytes':path.stat().st_size};save()
    if free()<750000000 or time.monotonic()-start>timeout:
     row['stopReason']='ACTUAL_DISK_FLOOR' if free()<750000000 else 'BOUNDED_PHASE_TIMEOUT';save()
     os.killpg(p.pid,signal.SIGINT)
     try:rc=p.wait(timeout=30)
     except subprocess.TimeoutExpired:
      os.killpg(p.pid,signal.SIGTERM)
      try:rc=p.wait(timeout=10)
      except subprocess.TimeoutExpired:os.killpg(p.pid,signal.SIGKILL);rc=p.wait()
     break
 row.update(status='PASSED' if rc==0 and not row.get('stopReason') else 'FAILED',exitCode=rc,finishedAt=now(),logSHA256=digest(path))
 if separate:row.update(stderr=str(err),stderrSHA256=digest(err))
 save()
 if row['status']!='PASSED':raise RuntimeError({'phase':name,'exitCode':rc,'stopReason':row.get('stopReason'),'log':str(path)})
 return path.read_text(errors='replace')
try:
 fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB)
 fcntl.flock(maintenance,fcntl.LOCK_SH|fcntl.LOCK_NB)
 data['coordinationLocks']={'native':'exclusive','existingMaintenance':'shared'}
 assert not proof.exists() and not receipt.exists()
 proof.mkdir(parents=True)
 data['freshBuildBudgetBasis']={'previousOwnedCacheObservedAbsent':True,'presenceReceipt':str(stage/'platform-cache-presence-16b4af44-readback.json'),'initialWarmAdmissionReceipt':str(stage/'platform-native-build-16b4af44-r1.json'),'freshOwnedAllowanceBytes':5000000000,'scope':'Conservative allowance for the original13 native test products, module caches and six resolved checkouts. This is a phase budget estimate; actual free-space observations are retained separately. No warm-product reuse is claimed.'}
 assert dd.is_dir() and (dd/'SourcePackages/repositories').is_dir() and not (dd/'Build').exists()
 data['freeAtAdmission']=free();assert data['freeAtAdmission']>data['requiredFreeBytes'];save()
 assert subprocess.check_output(['/usr/bin/git','-C',str(root),'rev-parse','HEAD'],text=True).strip()==source
 host=json.loads((stage/'host-preparation-9819697c-original-phases-r1.json').read_text());assert host['status']=='FRESH_HOST_AND_SDK_VERIFIED' and host['source']=='9819697c1792119a6a93b492d12abad7b3330c93'
 data['hostReceiptSHA256']=digest(stage/'host-preparation-9819697c-original-phases-r1.json')
 data['hostProofScope']='Completed981 Host evidence retained; this native package gate does not execute the Host and does not claim final-source Host reuse.'
 change=json.loads((stage/'source-update-16b4af44-package.json').read_text());assert change['status']=='REVIEWED_PACKAGE_CANDIDATE_STAGED'
 data['sourceChangeQualification']={'sourceUpdateReceipt':str(stage/'source-update-16b4af44-package.json'),'sha256':digest(stage/'source-update-16b4af44-package.json'),'source':source,'scope':'Reviewed provisional package-only correction; V1 projection and exact current pinned widget fixtures address the two measured failures. Original57/78 plus one nonparameterized regression yield58/79. Final integrated-source and Host qualification remain separate.'}
 data['canonicalHostStatus']='Final Host preparation is separate and pending; this original package gate does not execute the Host and cannot discharge its acceptance.'
 prep=json.loads((stage/'platform-native-preparation-16b4af44-fresh.json').read_text());assert prep['status']=='ORIGINAL_PACKAGE_DEPENDENCIES_PREPARED_NATIVE_NOT_RUN'
 inv=json.loads((stage/'platform-test-inventory-16b4af44-provisional.json').read_text());assert inv['sourceCommit']==source and inv['combinedPackage']['expectedInvocations']==79 and inv['combinedPackage']['definitions']==58
 for rel,sha in inv['sourceSHA256'].items():assert digest(root/rel)==sha,rel
 data['inventorySHA256']=digest(stage/'platform-test-inventory-16b4af44-provisional.json')
 priorSelection=json.loads((stage/'platform-native-enumeration-6975e769-r4.json').read_text())
 priorExecution=json.loads((stage/'validation/platform-6975e769/test-r2/required-scope-reconciliation.json').read_text())
 assert priorExecution['actualDefinitions']==57 and priorExecution['actualInvocations']==78 and priorExecution['unexpectedExecutedIdentifiers']==[]
 assert inv['compatibilityRegression']['sourceDerivedIdentifier']=='HanlinScriptExtensionsTests/HanlinDualWidgetEnginesTests/v1ShadowProjectsHistoricalFieldsWithoutLosingCurrentMetadata()'
 data['selectors']=priorSelection['selectors']
 assert '-only-testing:HanlinScriptExtensionsTests/HanlinDualWidgetEnginesTests' in data['selectors']
 assert not any(inv['compatibilityRegression']['function'] in s for s in data['selectors'] if s.startswith('-skip-testing:'))
 data['selectionQualification']={'originalObservedRoute':'Same documented target/suite includes and explicit exclusions as the completed6975 actual57/78 execution; the single new method is inside the included DualWidget suite.','expectedDefinitions':58,'expectedInvocations':79,'parameterInvocations':28,'collateralAcceptance':0,'priorExecutionSHA256':digest(stage/'validation/platform-6975e769/test-r2/required-scope-reconciliation.json')}
 oldRun=dd/'Build/Products/HanlinPlatform-Package_HanlinPlatform-Package_iphonesimulator27.0-arm64.xctestrun'
 if oldRun.exists():
  saved=proof/'previous-generated-xctestrun.plist';saved.write_bytes(oldRun.read_bytes());data['preservedPreviousXctestrun']={'path':str(saved),'sha256':digest(saved)}
 assert change['qualification']['packageSourcesTree']==subprocess.check_output(['/usr/bin/git','-C',str(root),'rev-parse','HEAD:Packages/HanlinPlatform/Sources'],text=True).strip()
 originalPins=json.loads((package/'Package.resolved').read_text());data['originalPins']=originalPins;data['originalLockSHA256']=digest(package/'Package.resolved')
 assert data['originalLockSHA256']==prep['packageLockSHA256']
 data['toolchain']=phase('toolchain',['xcodebuild','-version'],60).strip()
 data['buildSDK']=phase('sdk',['xcrun','--sdk','iphonesimulator','--show-sdk-version'],60).strip();assert data['buildSDK']=='27.0'
 devices=json.loads(phase('owned-device-inventory',['xcrun','simctl','list','devices','available','-j'],90))['devices']
 rows=[dict(d,runtime=r) for r,ds in devices.items() for d in ds if d['udid']==uuid]
 assert len(rows)==1 and rows[0]['runtime']=='com.apple.CoreSimulator.SimRuntime.iOS-27-2'
 data['simulator']={'udid':uuid,'runtime':rows[0]['runtime'],'state':rows[0]['state'],'creationReceipt':str(stage/'validation/08ed647b-mini-build-r1/original-mini-build/owned-simulator.json'),'bootedForBuild':False}
 listing=json.loads(phase('original-package-scheme-discovery',['xcodebuild','-list','-json','-clonedSourcePackagesDirPath',str(dd/'SourcePackages'),'-skipPackagePluginValidation','-skipMacroValidation'],900,separate=True))
 container=listing.get('workspace') or listing.get('project') or {};schemes=container.get('schemes') or []
 if 'HanlinPlatform-Package' in schemes:scheme='HanlinPlatform-Package'
 elif len(schemes)==1:scheme=schemes[0]
 else:raise RuntimeError({'ambiguousOriginalGeneratedScheme':schemes})
 data['observedScheme']=scheme;data['observedSchemes']=schemes
 assert digest(package/'Package.resolved')==data['originalLockSHA256'],'Original package lock changed'
 checkouts=dd/'SourcePackages/checkouts';actual=[]
 for pin in originalPins['pins']:
  candidates=[p for p in checkouts.iterdir() if p.is_dir() and p.name.lower()==pin['identity'].lower()]
  assert len(candidates)==1,('checkout identity',pin['identity'],[p.name for p in checkouts.iterdir()])
  p=candidates[0];rev=subprocess.check_output(['/usr/bin/git','-C',str(p),'rev-parse','HEAD'],text=True).strip()
  assert rev==pin['state']['revision'],pin['identity']
  subprocess.run(['/usr/bin/git','-C',str(p),'diff','--exit-code','--quiet'],check=True)
  actual.append({'identity':pin['identity'],'revision':rev})
 data['actualResolvedPins']=actual;data['freeBeforeBuild']=free();assert data['freeBeforeBuild']>data['requiredFreeBytes'],'Resource budget changed before compilation';data['status']='BUILDING_ORIGINAL_PACKAGE';save()
 result=proof/'PlatformBuild.xcresult'
 args=['xcodebuild','-scheme',scheme,'-configuration','Debug','-sdk','iphonesimulator','-destination','platform=iOS Simulator,id='+uuid,'-derivedDataPath',str(dd),'-clonedSourcePackagesDirPath',str(dd/'SourcePackages'),'-skipPackagePluginValidation','-skipMacroValidation','-parallel-testing-enabled','NO','-jobs','2','-resultBundlePath',str(result),'CODE_SIGNING_ALLOWED=NO','SWIFT_STRICT_CONCURRENCY=complete',*data['selectors'],'build-for-testing']
 phase('original-package-build-for-testing',args,3300)
 assert subprocess.check_output(['/usr/bin/git','-C',str(root),'rev-parse','HEAD'],text=True).strip()==source
 for rel,sha in inv['sourceSHA256'].items():assert digest(root/rel)==sha,rel
 runs=sorted((dd/'Build/Products').glob('*.xctestrun'));assert runs,'No original generated xctestrun'
 data['xctestruns']=[{'path':str(p),'sha256':digest(p),'topLevelKeys':list(plistlib.loads(p.read_bytes()))} for p in runs]
 data['status']='BUILT_FOR_TESTING_AWAITING_ORIGINAL_TEST_EXECUTION'
except Exception as e:data.update(status='FAILED',error=repr(e),traceback=traceback.format_exc())
finally:
 data['finishedAt']=now();data['freeAfter']=free();save();print(json.dumps({k:data.get(k) for k in ['source','status','error','finishedAt','freeAfter','observedScheme','xctestruns']}),flush=True)
if data['status']!='BUILT_FOR_TESTING_AWAITING_ORIGINAL_TEST_EXECUTION':raise SystemExit(1)
