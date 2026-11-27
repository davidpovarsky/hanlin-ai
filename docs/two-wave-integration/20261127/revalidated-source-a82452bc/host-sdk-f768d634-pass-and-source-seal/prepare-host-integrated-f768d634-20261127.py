import os,sys,pathlib,json,hashlib,subprocess,time,datetime,signal,traceback,re,shutil,zipfile,stat
stage=pathlib.Path('/Users/m1/builds/hanlin-two-wave-root-20261126')
root=stage/'source';source=sys.argv[1];assert source=='f768d634bfa8a102cf63b32c7ab9d129cafc671d';tag=source[:8]+'-original-phases-r1'
work=stage/('runtime-work-'+tag)/'hanlin-runtime-host'
grammar=pathlib.Path(str(work)+'-grammar-tools')
proof=stage/('host-resume-'+tag);assert not proof.exists();proof.mkdir()
output=root/('build/runtime-host-'+tag)
receipt=stage/('host-preparation-'+tag+'.json')
now=lambda:datetime.datetime.now(datetime.timezone.utc).isoformat()
def digest(p):
 with p.open('rb') as f:return hashlib.file_digest(f,'sha256').hexdigest()
def free():s=os.statvfs('/System/Volumes/Data');return s.f_bavail*s.f_frsize
env=os.environ.copy();env['PATH']=str(stage/'tool-bin')+':/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin'
assert not env.get('NODE_OPTIONS'),'No unsupported NODE_OPTIONS adjustment'
env['HANLIN_RUN_LONG_JOBS']='1'
env['RUNNER_TEMP']=str(work.parent)
work.parent.mkdir(exist_ok=False)
env['HANLIN_HOST_GRAMMAR_COMPILER_ROOT']=str(grammar)
env['HANLIN_MINIAPP_REPOSITORY_ROOT']=str(root)
env['HANLIN_RUNTIME_TEST_FIXTURES']=str(root/'AI_HLYTests/Fixtures/RuntimeNetworkFixtures.bundle')
data={'status':'RUNNING','route':'ORIGINAL_PHASES_WITH_BOUNDED_TEST_CONCURRENCY','source':source,'startedAt':now(),'freeStart':free(),'phaseEstimatedIncrementalBytes':1796093793,'testScheduling':'Supported Node CLI --test-concurrency=2; original complete test set, assertions, deadlines, isolated Worker behavior and Node24.5 unchanged. Original HANLIN_RUN_LONG_JOBS=1 opt-in enables the actual305-second case.','historicalSchedulingEvidence':str(stage/'host-preparation-a35694f7-final.json'),'phases':[],'boundary':'Every original preparation, test, packing, validation and JITless phase executes with explicit bounded scheduling and unique output binding. Not one untouched-producer invocation and not iOS native acceptance.'}
def save():
 t=receipt.with_suffix('.json.pending')
 try:t.write_text(json.dumps(data,indent=2)+'\n');os.replace(t,receipt);return True
 except OSError as e:data.setdefault('receiptWriteErrors',[]).append({'at':now(),'error':repr(e)});return False
def phase(name,args,cwd=root,timeout=600,phaseEnv=None):
 log=proof/(name+'.log')
 pdat={'name':name,'command':args,'cwd':str(cwd),'startedAt':now(),'log':str(log)}
 data['phases'].append(pdat);save()
 with log.open('w') as logf:
  proc=subprocess.Popen(args,cwd=cwd,env=phaseEnv or env,stdout=logf,stderr=subprocess.STDOUT,start_new_session=True)
  pdat['pid']=proc.pid;save();start=time.monotonic()
  try:
   while True:
    try:rc=proc.wait(timeout=10);break
    except subprocess.TimeoutExpired:
     current=free()
     pdat['lastObservation']={'at':now(),'freeBytes':current,'logBytes':log.stat().st_size}
     persisted=save()
     if current<750000000 or not persisted or time.monotonic()-start>timeout:
      pdat['outerStop']={'freeBytes':current,'receiptPersisted':persisted,'elapsedSeconds':time.monotonic()-start}
      os.killpg(proc.pid,signal.SIGTERM)
      try:rc=proc.wait(timeout=8)
      except subprocess.TimeoutExpired:os.killpg(proc.pid,signal.SIGKILL);rc=proc.wait()
      break
  except BaseException:
   if proc.poll() is None:
    os.killpg(proc.pid,signal.SIGTERM)
    try:proc.wait(timeout=8)
    except subprocess.TimeoutExpired:os.killpg(proc.pid,signal.SIGKILL);proc.wait()
   raise
 pdat.update({'exitCode':rc,'finishedAt':now(),'logSHA256':digest(log)})
 save()
 if rc or pdat.get('outerStop'):raise RuntimeError({'phase':name,'exitCode':rc,'stop':pdat.get('outerStop')})
 return log.read_text(errors='replace')
def closure(base):
 rows=[]
 for current,dirs,files in os.walk(base,followlinks=False):
  dirs.sort();files.sort()
  for n in list(dirs):
   p=pathlib.Path(current,n)
   if p.is_symlink():
    rows.append({'path':str(p.relative_to(base)),'kind':'symlink','target':os.readlink(p)});dirs.remove(n)
  for n in files:
   p=pathlib.Path(current,n);s=p.lstat()
   if stat.S_ISLNK(s.st_mode):rows.append({'path':str(p.relative_to(base)),'kind':'symlink','target':os.readlink(p)})
   elif stat.S_ISREG(s.st_mode):rows.append({'path':str(p.relative_to(base)),'kind':'file','bytes':s.st_size,'sha256':digest(p)})
   else:raise RuntimeError('Nonregular closure input '+str(p))
 rows.sort(key=lambda x:x['path'])
 raw=json.dumps(rows,sort_keys=True,separators=(',',':')).encode()
 return {'sha256':hashlib.sha256(raw).hexdigest(),'fileCount':len(rows),'files':rows}
try:
 assert (root/'.git/HEAD').read_text().strip()==source
 assert free()>2500000000,{'free':free(),'requiredCurrentPhase':2500000000}
 producer=root/'Scripts/Runtime/prepare-runtime-host.sh'
 producerText=producer.read_text();data['originalProducerSHA256']=digest(producer)
 import fcntl,shlex
 nativeLock=open('/Users/m1/caches/hanlin-two-wave-native-app.lock','a+')
 fcntl.flock(nativeLock,fcntl.LOCK_EX|fcntl.LOCK_NB)
 maintenanceLock=open('/Users/m1/caches/.scaleway-cache-maintenance.lock','a+')
 fcntl.flock(maintenanceLock,fcntl.LOCK_SH|fcntl.LOCK_NB)
 currentReviewPath=stage/'host-final-controller-review-f768d634.json'
 currentReview=json.loads(currentReviewPath.read_text())
 assert currentReview['source']==source and currentReview['decision']=='APPROVED_ORIGINAL_HOST_PHASES_WITH_QUALIFIED_NATIVE79_REUSE'
 assert currentReview['native79QualificationSHA256']=='da8f54f596b6e9e7bbda8d55679d49c50953b3a5339a9e7846298b7d9fad4e34'
 assert currentReview['sourceStageSHA256']=='819968e2453efeb7fb72deed1482d53f31f9acc540140adfdc70bb958634b4c8'
 assert currentReview['controllerSHA256'][pathlib.Path(__file__).name]==digest(pathlib.Path(__file__))
 data['currentControllerReview']={'path':str(currentReviewPath),'sha256':digest(currentReviewPath)}
 reusePath=stage/'native79-reuse-qualification-f768d634.json'
 assert digest(reusePath)==currentReview['native79QualificationSHA256']
 reuse=json.loads(reusePath.read_text())
 assert reuse['decision']=='QUALIFIED_ORIGINAL_NATIVE_PACKAGE_79_REUSE_ONLY' and reuse['qualifiedSource']==source
 assert reuse['actualExecutionSource']=='866d2d3c60525e32eae27564869e6dba024e625c'
 assert reuse['freshOriginalHost188Required'] is True and reuse['originalHostArchive866Reusable'] is False
 nativeProof=stage/'validation/platform-866d2d3c/test-r1/required-scope-reconciliation.json'
 assert digest(nativeProof)==reuse['exact79ReconciliationSHA256']=='e99daf1bb7bb98c14d98d33b153d88531e7e016c7e295bc964a1e4f10af2bf64'
 native=json.loads(nativeProof.read_text())
 assert native['status']=='EXACT_REQUIRED_NATIVE_SCOPE_PASSED' and native['acceptancePassed'] and native['source']==reuse['actualExecutionSource']
 assert native['actualDefinitions']==58 and native['actualInvocations']==79 and native['missingRequiredIdentifiers']==native['unexpectedExecutedIdentifiers']==[]
 assert native['parameterInvocations']==28 and native['parameterValuesExactlyReconciled'] and native['skipped']==native['expectedFailures']==native['nativeExitCode']==0 and native['failedIdentifiers']==[]
 runPath=stage/'platform-native-test-866d2d3c-r1.json';run=json.loads(runPath.read_text())
 assert digest(runPath)==native['inputProofs']['runReceiptSHA256']==reuse['nativeReceiptSHA256']=='a8743f6401561b7f54b05c2f2cb4f78ed2fcb2b2c90554c0c8d7a7669e507224'
 assert run['status']=='TEST_COMMAND_FINISHED_AWAITING_EXACT_CASE_RECONCILIATION'
 phases=[p for p in run['phases'] if p['name']=='original-native-test-without-building'];assert len(phases)==1 and phases[0]['status']=='PASSED' and not phases[0].get('stopReason')
 invPath=stage/'platform-test-inventory-866d2d3c.json';inv=json.loads(invPath.read_text())
 assert digest(invPath)==native['inputProofs']['inventorySHA256']==reuse['nativeInventorySHA256']=='a5530408269f296d1cbb743fd52624f74755509623ee68b2bfd0f7e351b78822'
 currentBroadInputs=[];changedBroadInputs=[]
 for rel,sha in inv['sourceSHA256'].items():
  actual=digest(root/rel);row={'path':rel,'recorded866SHA256':sha,'currentSHA256':actual};currentBroadInputs.append(row)
  if actual!=sha:changedBroadInputs.append(row)
 assert len(currentBroadInputs)==33 and len(currentBroadInputs)-len(changedBroadInputs)==reuse['matchedBroadInputCount']==32
 assert changedBroadInputs==reuse['changedBroadInputs']==[{'path':'Scripts/ProductSplit/run_paired_acceptance.py','recorded866SHA256':'872a7f6e7f786e2d578a54e3107bbe00e42a8dd2238e23f10fd656a63d9ab3f7','currentSHA256':'efb9738edeafd21868ce232343a2db4634e370d47d267d160c86f927847a8836'}]
 expectedTrees={'Packages/HanlinPlatform/Sources':'1586a7e95b6a3245bf0bb0ea60600c9b5086bc63','Packages/HanlinPlatform/Tests':'c4683795c1a192855ca2de769546ee2ccf4f948d','Packages/HanlinPlatform':'ee3dceff23aa4298982869933382bbed06ff6124','Fixtures/Widgets':'a0b7b0b1cb9e1ce756ccff40593a325ffffa73d6'}
 assert reuse['unchangedActualPackageTrees']==expectedTrees
 for rel,sha in expectedTrees.items():assert subprocess.check_output(['git','rev-parse','HEAD:'+rel],cwd=root,text=True).strip()==sha,rel
 sourceQualificationPath=stage/'source-stage-f768d634.json';sourceQualification=json.loads(sourceQualificationPath.read_text())
 assert digest(sourceQualificationPath)==currentReview['sourceStageSHA256'] and sourceQualification['status']=='REVIEWED_INTEGRATED_SOURCE_STAGED_NATIVE79_REUSE_QUALIFIED_FRESH_HOST_REQUIRED' and sourceQualification['sourceAfter']==source
 assert not subprocess.check_output(['git','status','--porcelain=v1'],cwd=root,text=True).strip(),'Current source must remain clean before original producer refresh'
 data['native79ReuseQualification']={'path':str(reusePath),'sha256':digest(reusePath),'status':'REUSED_VERIFIED_PASS','actualExecutionSource':native['source'],'qualifiedSource':source,'totalBroadInputs':33,'matchedBroadInputCount':32,'changedBroadInputs':changedBroadInputs,'currentPackageTrees':expectedTrees,'nativeTestsExecutedByThisController':False}
 data['sourceQualification']={'path':str(sourceQualificationPath),'sha256':digest(sourceQualificationPath),'actualNativeSource':native['source'],'nativeProof':str(nativeProof),'nativeProofSHA256':digest(nativeProof)}
 data['integrationQualification']='Current source reuses exact original58/79 package acceptance executed on866 after independent full package-tree and32/33 broad-input qualification; the sole named changed runner is not consumed by that direct xcodebuild gate. The reviewed App Intents source change invalidates SDK392/archive identity. This controller freshly executes the unchanged original complete188 Host acceptance and all original phases. App/OS acceptance remains separate.'
 data['coordinationLocks']={'native':'exclusive','existingMaintenance':'shared'}
 assert not work.exists() and not grammar.exists() and not output.exists()
 pretestEnd=producerText.index('  npm test\n')
 prefix=producerText[:pretestEnd]
 scriptDirLine=next(x for x in prefix.splitlines() if x.startswith('readonly SCRIPT_DIR='))
 outputLine='readonly OUTPUT_ROOT="'+chr(36)+'{REPOSITORY_ROOT}/build/runtime-host"'
 assert prefix.count(scriptDirLine)==1 and prefix.count(outputLine)==1
 prefix=prefix.replace(scriptDirLine,'readonly SCRIPT_DIR='+shlex.quote(str(root/'Scripts/Runtime')),1)
 prefix=prefix.replace(outputLine,'readonly OUTPUT_ROOT='+shlex.quote(str(output)),1)
 prefix+=')\n'
 prefixScript=proof/'original-pretest-phases.sh';prefixScript.write_text(prefix)
 data['pretestExtract']={'path':str(prefixScript),'sha256':digest(prefixScript),'boundary':'Exact original commands before npm test. Only SCRIPT_DIR binds the real original script directory and OUTPUT_ROOT binds this unique evidence output; the original open subshell is closed at the phase boundary.','longJobOptIn':'HANLIN_RUN_LONG_JOBS=1'}
 save()
 phase('original-pretest-phases',['/bin/bash',str(prefixScript)],timeout=1800)
 assert work.is_dir() and grammar.is_dir() and output.is_dir()

 sourceHost=root/'AI_HLY/Downstream/RuntimeCore/Node/Host'
 assert json.loads((sourceHost/'package.json').read_text())['scripts']['test']=='node --test Tests/*.test.mjs'
 originals=list(sourceHost.glob('*.mjs'))+[sourceHost/x for x in ['package.json','package-lock.json','runtime-dependency-overrides.json','host-dependency-patches.json','UNICODE-LICENSE.txt','PEGJS-LICENSE.txt']]
 for original in originals:assert digest(original)==digest(work/original.name),str(original)
 sourceTests=closure(sourceHost/'Tests');stagedTests=closure(work/'Tests')
 assert sourceTests==stagedTests,'Staged original test closure changed'
 (proof/'original-test-source-manifest.json').write_text(json.dumps(sourceTests,indent=2)+'\n')
 data['originalTestsSHA256']=sourceTests['sha256']
 historical=json.loads((stage/'host-preparation-9819697c-original-phases-r1.json').read_text())
 assert historical['status']=='FRESH_HOST_AND_SDK_VERIFIED' and historical['originalTestSummary']['tests']==188
 assert historical['originalTestsSHA256']==sourceTests['sha256'], 'Original Host test source closure changed; inventory it rather than weakening the expected188 gate'
 data['expectedOriginalTestInvocations']=188
 data['unchangedOriginalHostTestsSHA256']=sourceTests['sha256']
 data['nodeVersion']=phase('node-version',[str(stage/'tool-bin/node'),'--version'],timeout=30).strip()
 assert data['nodeVersion']=='v24.5.0'
 data['nodeBinarySHA256']=digest((stage/'tool-bin/node').resolve())
 phase('current-sdk-audit',[str(stage/'tool-bin/node'),'Scripts/Audit/audit-miniapp-sdk.mjs','--check'],timeout=120)
 phase('current-reachability-audit',[str(stage/'tool-bin/python3'),'Scripts/Audit/audit_miniapp_reachability.py','--check'],timeout=120)
 fingerprint=json.loads(phase('current-sdk-fingerprint',[str(stage/'tool-bin/node'),'Scripts/MiniApps/stage-sdk.mjs','--fingerprint','--repository',str(root)],timeout=150))
 sdkManifest=json.loads((work/'MiniAppSDK/miniapp-sdk.json').read_text())
 assert fingerprint['sha256']==sdkManifest['inputSHA256'],'Staged SDK is not current exact source'
 nodeFingerprint=phase('node-fingerprint',[str(stage/'tool-bin/node'),'-p','JSON.stringify({ versions: process.versions, platform: process.platform, arch: process.arch })'],timeout=30).strip()
 sourceInputsHash=phase('host-input-fingerprint-before',[str(stage/'tool-bin/python3'),'Scripts/Runtime/runtime_host_archive.py','fingerprint','--source-root',str(sourceHost),'--node-fingerprint',nodeFingerprint],timeout=150).strip()
 before=closure(work);(proof/'staged-complete-closure-before.json').write_text(json.dumps(before,indent=2)+'\n')
 data['stagedClosureBefore']={'sha256':before['sha256'],'files':before['fileCount']}
 grammarBefore=closure(grammar);(proof/'grammar-closure-before.json').write_text(json.dumps(grammarBefore,indent=2)+'\n')
 data['grammarClosureBefore']={'sha256':grammarBefore['sha256'],'files':grammarBefore['fileCount']}
 data['sourceInputsHash']=sourceInputsHash;data['sdkInputHash']=fingerprint['sha256'];save()
 testFiles=sorted('Tests/'+p.name for p in (work/'Tests').glob('*.test.mjs'))
 data['originalTestFileCount']=len(testFiles)
 data['testInvocationEnvironment']={'HANLIN_RUN_LONG_JOBS':env['HANLIN_RUN_LONG_JOBS'],'NODE_OPTIONS':'UNSET'}
 command=[str(stage/'tool-bin/node'),'--test','--test-concurrency=2']+testFiles
 text=phase('complete-original-test-set',command,cwd=work,timeout=1800)
 summary={k:int(v) for k,v in re.findall(r'^(?:ℹ|#)\s+(tests|pass|fail|cancelled|skipped)\s+(\d+)\s*$',text,re.M)}
 assert set(summary)=={'tests','pass','fail','cancelled','skipped'} and summary['tests']==188 and summary['pass']==summary['tests'] and summary['fail']==0 and summary['cancelled']==0 and summary['skipped']==0,summary
 data['originalTestSummary']=summary
 longProof=[]
 for line in text.splitlines():
  if 'actual-node-job-over-300-seconds' in line and '{' in line:
   item=json.loads(line[line.index('{'):])
   if item.get('proof')=='actual-node-job-over-300-seconds':longProof.append(item)
 assert len(longProof)==1 and longProof[0]['elapsedMilliseconds']>300000,longProof
 data['actualLongJobProof']=longProof[0]

 after=closure(work);(proof/'staged-complete-closure-after.json').write_text(json.dumps(after,indent=2)+'\n')
 assert before==after,'Actual staged source/dependency/tool files changed during original tests'
 assert grammarBefore==closure(grammar),'Grammar tool closure changed'
 assert data['nodeBinarySHA256']==digest((stage/'tool-bin/node').resolve())
 assert digest(producer)==data['originalProducerSHA256']
 assert sourceTests==closure(sourceHost/'Tests')
 assert (root/'.git/HEAD').read_text().strip()==source
 currentSourceInputsHash=phase('host-input-fingerprint-after',[str(stage/'tool-bin/python3'),'Scripts/Runtime/runtime_host_archive.py','fingerprint','--source-root',str(sourceHost),'--node-fingerprint',nodeFingerprint],timeout=150).strip()
 assert currentSourceInputsHash==sourceInputsHash
 data['stagedClosureAfter']={'sha256':after['sha256'],'files':after['fileCount'],'status':'EXACT_MATCH'}
 # Exact original post-test commands, extracted from the canonical producer.
 packStart=producerText.index('  rm -rf Tests\n')
 packEnd=producerText.index('\n)\n\n# Validate',packStart)
 packing=producerText[packStart:packEnd]
 tail=producerText[producerText.index('# Validate the actual packed payload'):]
 env2=env.copy()
 env2.update({'SCRIPT_DIR':str(root/'Scripts/Runtime'),'REPOSITORY_ROOT':str(root),'HOST_SOURCE':str(sourceHost),'WORK_ROOT':str(work),'OUTPUT_ROOT':str(output),'GRAMMAR_TOOL_ROOT':str(grammar),'SOURCE_INPUTS_HASH':sourceInputsHash})
 assert output.is_dir()
 packScript=proof/'original-post-test-packing.sh';packScript.write_text('set -euo pipefail\n'+packing+'\n')
 tailScript=proof/'original-packed-verification-and-seal.sh';tailScript.write_text('set -euo pipefail\n'+tail)
 data['postTestPackingExtractSHA256']=digest(packScript);data['packedVerificationExtractSHA256']=digest(tailScript);save()
 phase('original-post-test-packing',['/bin/bash',str(packScript)],cwd=work,timeout=600,phaseEnv=env2)
 phase('original-packed-validation-jitless-and-seal',['/bin/bash',str(tailScript)],timeout=600,phaseEnv=env2)
 archive=output/'RuntimeHostResources.zip';metadata=json.loads((output/'host-metadata.json').read_text())
 assert metadata['tests']=='passed' and metadata['jitlessArchiveSmoke']=='passed'
 assert metadata['sourceInputsHash']==sourceInputsHash and metadata['archiveSha256']==digest(archive)
 phase('original-archive-reuse-validation',[str(stage/'tool-bin/python3'),'Scripts/Runtime/runtime_host_archive.py','reuse',str(output),'--source-root',str(sourceHost),'--node-fingerprint',nodeFingerprint],timeout=180)
 canonical=root/'build/runtime-host';canonical.mkdir(exist_ok=True)
 for name in ['RuntimeHostResources.zip','host-metadata.json','runtime-host.sha256']:
  tmp=canonical/(name+'.resumed-pending');shutil.copyfile(output/name,tmp);os.replace(tmp,canonical/name)
 destination=root/'AI_HLY/RuntimeHostResources.zip';tmp=destination.with_suffix('.zip.resumed-pending');shutil.copyfile(archive,tmp);os.replace(tmp,destination)
 sdkRoot=stage/('fresh-sdk-'+tag);assert not sdkRoot.exists();sdkRoot.mkdir()
 with zipfile.ZipFile(archive) as z:
  for member in z.infolist():
   parts=pathlib.PurePosixPath(member.filename).parts
   if not parts or parts[0]!='MiniAppSDK':continue
   assert '..' not in parts and not member.filename.startswith('/')
   z.extract(member,sdkRoot)
 sdk=sdkRoot/'MiniAppSDK';manifest=json.loads((sdk/'miniapp-sdk.json').read_text())
 assert manifest['inputSHA256']==fingerprint['sha256']
 data['archive']={'path':str(archive),'canonicalPath':str(canonical/'RuntimeHostResources.zip'),'bytes':archive.stat().st_size,'sha256':digest(archive)}
 data['sdk']={'path':str(sdk),'manifestSHA256':digest(sdk/'miniapp-sdk.json'),'sourceInputHash':manifest['inputSHA256'],'sourceInputsCount':len(manifest.get('sourceInputs',[]))}
 data['sdkInputCheck']={'status':'CURRENT_SOURCE_MATCHES_PACKAGED_SDK','sha256':fingerprint['sha256'],'filesCount':len(fingerprint['files'])}
 data['hostMetadata']=metadata;data['status']='FRESH_HOST_AND_SDK_VERIFIED'
except BaseException as e:
 data['status']='FAILED';data['error']=repr(e);data['traceback']=traceback.format_exc()
finally:
 data['finishedAt']=now();data['freeEnd']=free();save();print(json.dumps({k:data.get(k) for k in ['source','status','error','finishedAt','freeEnd','originalTestSummary','actualLongJobProof','archive','sdk','sourceInputsHash','sdkInputHash']}),flush=True)
if data['status']!='FRESH_HOST_AND_SDK_VERIFIED':raise SystemExit(1)
