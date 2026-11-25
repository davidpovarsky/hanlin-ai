#!/usr/bin/env python3
"""Reconcile retained actual attempt7 output bytes; never execute product tooling."""
from pathlib import Path
from datetime import datetime, timezone
import subprocess,json,hashlib,gzip,zipfile,difflib,re,time
W=Path('/mnt/development/projects/worktrees/hanlin-primary-sdk-preparation-20261124')
S=Path('/mnt/development/projects/transfers/hanlin-primary-ce49-20261124/prepared-snapshot-attempt7')
P6=S.parent/'prepared-snapshot-attempt6'
BASE='fd81d602d3b25f09162a659e1e0cf0582e91a93a'
PRIOR_SOURCE='bd6da170da7936fe3c5353ddaf8b25c97477a380'
OUT=W/'docs/miniapp-sdk/evidence/primary-sdk-attempt7-20261124'
HOST='AI_HLY/Downstream/RuntimeCore/Node/Host/miniapp-authoring.mjs'
TEST='AI_HLY/Downstream/RuntimeCore/Node/Host/Tests/miniapp-sdk-resolution.test.mjs'
HOST_SHA='aecc8c0ba732396a637a7d7eda8864f7bdc5b3acbe0894a640c5e9c2e8ac1cb9'
TEST_SHA='958d0e0a71f47fa7677e412cd1a0ed40da43feb898b182df84e63256a05e5865'
def sha(b):return hashlib.sha256(b).hexdigest()
def canonical(v):return json.dumps(v,ensure_ascii=False,separators=(',',':')).encode()
def emit(name,value):
 p=OUT/name;p.parent.mkdir(parents=True,exist_ok=True);p.write_bytes((json.dumps(value,ensure_ascii=False,indent=2)+'\n').encode())
def raw(name,body):
 p=OUT/'raw'/name;p.parent.mkdir(parents=True,exist_ok=True);p.write_bytes(body)
 return {'path':'raw/'+name,'bytes':len(body),'sha256':sha(body)}
cache={}
def git(path):
 if path not in cache:cache[path]=subprocess.check_output(['git','-C',str(W),'show',BASE+':'+path])
 return cache[path]
def jsondiff(a,b,p=''):
 if type(a)!=type(b):return [{'pointer':p,'before':a,'after':b}]
 if isinstance(a,dict):
  rows=[]
  for k in sorted(a.keys()|b.keys()):
   if k not in a or k not in b:rows.append({'pointer':p+'/'+k,'before':a.get(k),'after':b.get(k)})
   else:rows.extend(jsondiff(a[k],b[k],p+'/'+k))
  return rows
 if isinstance(a,list):
  if len(a)!=len(b):return [{'pointer':p,'beforeLength':len(a),'afterLength':len(b)}]
  rows=[]
  for i,(x,y) in enumerate(zip(a,b)):rows.extend(jsondiff(x,y,p+'/'+str(i)))
  return rows
 return [] if a==b else [{'pointer':p,'before':a,'after':b}]
started=datetime.now(timezone.utc).isoformat();clock=time.monotonic()
receiptBytes=(S/'receipt.json').read_bytes()
assert sha(receiptBytes)=='84ecaace9bd43f9e275047e28ba5755f7a2551ec5decc726940293cd1bd296aa'
r=json.loads(receiptBytes);assert r['sourceHEAD']==BASE
assert r['sourceTree']==subprocess.check_output(['git','-C',str(W),'rev-parse',BASE+'^{tree}'],text=True).strip()
assert sha(git(HOST))==HOST_SHA and sha(git(TEST))==TEST_SHA
handoff=[]
for row in r['files']:
 p=S/row['snapshotPath'];h=hashlib.sha256()
 with p.open('rb') as stream:
  for chunk in iter(lambda:stream.read(1024*1024),b''):h.update(chunk)
 assert p.stat().st_size==row['bytes'] and h.hexdigest()==row['sha256'],row['path']
 handoff.append({**row,'actualSHA256':h.hexdigest(),'verified':True})
assert len(handoff)==20
deltaBytes=(S/r['trackedDeltaPath']).read_bytes()
assert sha(deltaBytes)==r['trackedDeltaSHA256']
delta=json.loads(deltaBytes);assert len(delta)==r['trackedDeltaCount']==4
overlay={x['path']:(S/x['contentFrom']).read_bytes() for x in delta}
def current(path):return overlay[path] if path in overlay else git(path)
deltaRows=[];diffs=[]
for row in delta:
 path=row['path'];before=git(path);after=overlay[path]
 assert sha(before)==row['headSHA256'] and sha(after)==row['sha256'] and len(after)==row['bytes']
 mode=subprocess.check_output(['git','-C',str(W),'ls-tree',BASE,'--',path],text=True).split()[0]
 assert mode==row['headMode']=='100644' and row['mode']=='0o644'
 if path.endswith('.json'):
  a=json.loads(before);b=json.loads(after);semantic=jsondiff(a,b)
  assert b['sourceCommit']==BASE and a['sourceCommit']=='340018ddc9ea2395ffabedbf179369b5bdb791af'
  if path.endswith('source-inventory.json'):
   assert len(semantic)==74
   assert sum(x['pointer'].endswith('/line') for x in semantic)==36
   assert sum(x['pointer'].endswith('/sha256') for x in semantic)==37
   for x in semantic:
    assert x['pointer']=='/sourceCommit' or x['pointer'].endswith(('/line','/sha256')),x
    if x['pointer'].endswith('/sha256'):assert x['after']==HOST_SHA
   classification='sourceCommit, authoring source hash, and 36 existing manifest source anchors/hashes; contract fields and values unchanged'
  else:
   assert len(semantic)==2 and {x['pointer'] for x in semantic}=={'/sourceCommit','/sdkSources/9/sha256'}
   classification='sourceCommit and exact authoring source hash; reachability/API matrix unchanged'
 elif path.endswith('MANIFEST_REFERENCE.md'):
  pattern=rb'miniapp-authoring\.mjs:\d+'
  assert re.sub(pattern,b'miniapp-authoring.mjs:#',before)==re.sub(pattern,b'miniapp-authoring.mjs:#',after)
  oldAnchors=re.findall(pattern,before);newAnchors=re.findall(pattern,after)
  semantic=[{'occurrence':i+1,'before':a.decode(),'after':b.decode()} for i,(a,b) in enumerate(zip(oldAnchors,newAnchors)) if a!=b]
  assert len(oldAnchors)==len(newAnchors)==len(semantic)==36
  classification='Only 36 authoring source line anchors changed; manifest field descriptions and contracts unchanged'
 else:
  assert before.replace(b'340018ddc9ea2395ffabedbf179369b5bdb791af',BASE.encode())==after
  semantic=[{'field':'rendered source commit','before':'340018ddc9ea2395ffabedbf179369b5bdb791af','after':BASE}]
  classification='Only sourceCommit substitution'
 deltaRows.append({'path':path,'beforeSHA256':sha(before),'afterSHA256':sha(after),'bytes':len(after),'beforeMode':mode,'afterMode':'100644','contentFrom':row['contentFrom'],'classification':classification,'semanticDelta':semantic})
 diffs.extend(difflib.unified_diff(before.decode().splitlines(True),after.decode().splitlines(True),fromfile=BASE+'/'+path,tofile='actual-prepared/'+path))
 raw(path,after)
bindingRows=[{k:x[k] for k in ['path','beforeSHA256','afterSHA256','bytes','contentFrom']} for x in sorted(deltaRows,key=lambda v:v['path'])]
deltaBinding=sha(canonical(bindingRows))
emit('prepared-source-delta.json',{'executionSource':BASE,'snapshotRoot':str(S),'ledgerSHA256':sha(deltaBytes),'paths':4,'payloadBytes':sum(x['bytes'] for x in deltaRows),'contentChanges':4,'modeChanges':0,'canonicalBinding':{'algorithm':'SHA256 of compact UTF-8 JSON rows sorted by path; keys path,beforeSHA256,afterSHA256,bytes,contentFrom','sha256':deltaBinding},'rows':deltaRows,'materializedByThisLane':False})
(OUT/'prepared-provenance.diff').write_text(''.join(diffs))
mb=(S/r['sdkManifest']['snapshotPath']).read_bytes()
assert len(mb)==r['sdkManifest']['bytes'] and sha(mb)==r['sdkManifest']['sha256']
m=json.loads(mb);priorBytes=(P6/'extracted-sdk/miniapp-sdk.json').read_bytes()
assert sha(priorBytes)=='c9491455251124a82a7ca5721cc2fcd78e424670eeac53fdf8b1fc07abd4c325'
prior=json.loads(priorBytes)
assert sha(canonical(m['sourceInputs']))==m['inputSHA256']==r['sdkIdentity']['inputSHA256']
inputs={x['path']:x for x in m['sourceInputs']};oldInputs={x['path']:x for x in prior['sourceInputs']}
files={x['path']:x for x in m['files']};oldFiles={x['path']:x for x in prior['files']}
assert len(inputs)==len(m['sourceInputs'])==222 and len(files)==len(m['files'])==25661
assert inputs.keys()==oldInputs.keys() and files.keys()==oldFiles.keys()
changedInputs=[{'path':p,'before':oldInputs[p],'after':inputs[p]} for p in inputs if inputs[p]!=oldInputs[p]]
changedFiles=[{'path':p,'before':oldFiles[p],'after':files[p]} for p in files if files[p]!=oldFiles[p]]
assert {x['path'] for x in changedInputs}=={x['path'] for x in changedFiles}==set(overlay)
sourceRows=[]
for path,row in inputs.items():
 actual=sha(current(path));assert actual==row['sha256'],path
 sourceRows.append({'path':path,'sha256':actual,'authority':'Actual prepared provenance delta' if path in overlay else BASE,'matches':True})
assert {k:v for k,v in m.items() if k not in ['sourceInputs','files','inputSHA256']}=={k:v for k,v in prior.items() if k not in ['sourceInputs','files','inputSHA256']}
zipRef=next(x for x in handoff if x['path']=='build/runtime-host/RuntimeHostResources.zip')
archive=S/zipRef['snapshotPath']
aliasPath='docs/miniapp-sdk/evidence/primary-typescript-alias-identity-20261124/receipt.json'
aliasBytes=subprocess.check_output(['git','-C',str(W),'show','1fb9d62ae048ff895d5b3d26f71c62163ace4bf6:'+aliasPath])
assert sha(aliasBytes)=='20a4f5c5abf3c294e3a6f522ca3e840b73d869755b26f3935f04b27079eb9043'
alias=json.loads(aliasBytes)
with zipfile.ZipFile(archive) as z,zipfile.ZipFile(P6/'files/build/runtime-host/RuntimeHostResources.zip') as oldz:
 assert z.read(r['sdkManifest']['archiveMember'])==mb
 names=z.namelist();assert len(names)==len(set(names))
 actualSDKNames={p[len('MiniAppSDK/'):] for p in names if p.startswith('MiniAppSDK/') and not p.endswith('/') and p!='MiniAppSDK/miniapp-sdk.json'}
 assert actualSDKNames==set(files)
 for row in changedFiles:
  p=row['path'];body=z.read('MiniAppSDK/'+p);assert body==overlay[p] and sha(body)==row['after']['sha256'] and len(body)==row['after']['bytes']
 assert z.read('miniapp-authoring.mjs')==git(HOST)
 assert r['hostModule']=={'archiveMember':'miniapp-authoring.mjs','bytes':len(git(HOST)),'sha256':HOST_SHA,'appSourceArchiveSHA256':zipRef['sha256']}
 outer={x.filename:x for x in z.infolist() if not x.filename.startswith('MiniAppSDK/') and not x.is_dir()}
 oldOuter={x.filename:x for x in oldz.infolist() if not x.filename.startswith('MiniAppSDK/') and not x.is_dir()}
 assert outer.keys()==oldOuter.keys() and len(outer)==3102
 hostRows=[]
 for name in sorted(outer):
  actual=sha(z.read(name));previous=sha(oldz.read(name))
  hostRows.append({'path':name,'bytes':outer[name].file_size,'sha256':actual,'priorBytes':oldOuter[name].file_size,'priorSHA256':previous,'unchanged':actual==previous})
 hostChanged=[x for x in hostRows if not x['unchanged']]
 assert [x['path'] for x in hostChanged]==['miniapp-authoring.mjs']
 assert not any(p.startswith('Tests/') for p in names)
 hostMemberBytes=(json.dumps(hostRows,ensure_ascii=False,indent=2)+'\n').encode()
 emit('host-member-comparison.json',hostRows)
 compilerRows=[]
 for row in alias['members']:
  body=z.read('MiniAppSDK/'+row['path'])
  assert len(body)==row['bytes'] and sha(body)==row['sha256']
  assert files[row['path']]==oldFiles[row['path']]
  compilerRows.append({'path':row['path'],'bytes':len(body),'sha256':sha(body),'matchesAliasEvidence':True,'sameAsAttempt6':True})
 for key in ['package','lock']:
  row=alias['sourceBinding'][key]
  assert sha(current(row['path']))==row['sha256']==inputs[row['path']]['sha256']
 assert m['engines']['expo']['typescript']==alias['manifestCompilerIdentity']
 docBytes=(S/'files/build/app-split-evidence/miniapp-documentation-snippets.json').read_bytes()
 doc=json.loads(docBytes);oldDoc=json.loads((P6/'files/build/app-split-evidence/miniapp-documentation-snippets.json').read_bytes())
 assert doc['status']=='EXECUTED_PASS' and doc['sdk']=={'manifestSHA256':sha(mb),'inputSHA256':m['inputSHA256']}
 assert doc['sourceBlockCount']==14 and doc['jsonBlockCount']==7 and len(doc['excluded'])==8
 guides=[]
 for row in doc['documentation']:
  path=row['path'];body=z.read('MiniAppSDK/'+path)
  assert sha(body)==row['sha256']==row['stagedSDKSHA256']==sha(current(path)) and row['stagedSDKMatches']
  assert files[path]==oldFiles[path]
  guides.append({**row,'actualMemberSHA256':sha(body),'sourceMatches':True,'sameAsAttempt6':True})
 checker=[]
 for row in doc['checkerInputs']:
  assert sha(current(row['path']))==row['sha256'];checker.append({**row,'sourceMatches':True})
 assert next(x for x in checker if x['path']==HOST)['sha256']==HOST_SHA
 projects=[];oldProjects={x['name']:x for x in oldDoc['projects']}
 for p in doc['projects']:
  v=p['validation'];o=oldProjects[p['name']]
  assert v['succeeded'] and v['diagnostics']==[] and v['sdk']['manifestSHA256']==sha(mb)
  same={'snippets':p['snippets']==o['snippets'],'context':p['context']==o['context'],'typecheck':v['typecheck']==o['validation']['typecheck'],'compilerVersion':v['sdk']['compilerVersion']==o['validation']['sdk']['compilerVersion'],'packageVersions':v['sdk']['packageVersions']==o['validation']['sdk']['packageVersions']}
  assert all(same.values())
  projects.append({'name':p['name'],'engine':p['engine'],'succeeded':True,'diagnostics':[],'compilerVersion':v['sdk']['compilerVersion'],'typecheck':v['typecheck'],'sameContractAsAttempt6':same})
 assert len(projects)==4 and doc['registration']==oldDoc['registration']
 assert sha(current(doc['registration']['nativePath']))==doc['registration']['nativeSessionSHA256']
emit('compiler-identity-binding.json',{'aliasEvidence':{'path':aliasPath,'sha256':sha(aliasBytes)},'actualManifestIdentity':m['engines']['expo']['typescript'],'members':compilerRows,'sourceAndLockMatch':True,'boundary':'Read four actual original compiler identity-chain members. No compiler invocation or package download.'})
emit('documentation-execution-binding.json',{'actualReportSHA256':sha(docBytes),'status':'EXECUTED_PASS','projectCount':4,'diagnosticCount':0,'sourceFences':14,'jsonFences':7,'nonAuthoringExclusions':8,'totalFences':29,'projects':projects,'guides':guides,'checkerInputs':checker,'registration':doc['registration'],'boundary':doc['boundary'],'origin':'Actual original attempt7 native preparation; checker source is final aecc and SDK identity is the new manifest. No checker/compiler rerun in this inspection.'})
emit('sdk-source-binding.json',{'executionSource':BASE,'preparedDeltaLedgerSHA256':sha(deltaBytes),'count':222,'sourceInputsAtBase':218,'sourceInputsFromPreparedProvenance':4,'allMatch':True,'rows':sourceRows})
inv=json.loads(overlay['docs/miniapp-sdk/source-inventory.json']);reach=json.loads(overlay['docs/miniapp-sdk/extension-reachability.json'])
assert inv['sourceCommit']==reach['sourceCommit']==BASE
provenance=[]
for group,rows in [('inventory.sources',inv['sources']),('reachability.sdkSources',reach['sdkSources'])]:
 for row in rows:
  assert sha(current(row['path']))==row['sha256'],row['path'];provenance.append({'group':group,**row})
refs=[]
def collect(v,context):
 if isinstance(v,dict):
  p=v.get('file') or v.get('path')
  if isinstance(p,str) and isinstance(v.get('sha256'),str):
   body=current(p);assert sha(body)==v['sha256'],(context,p)
   row={'context':context,'path':p,'sha256':sha(body)}
   if isinstance(v.get('line'),int):
    assert 1<=v['line']<=len(body.splitlines()),(context,p,v['line']);row['line']=v['line']
   refs.append(row)
  for k,x in v.items():
   if isinstance(x,(dict,list)):collect(x,context+'.'+k)
 elif isinstance(v,list):
  for i,x in enumerate(v):collect(x,context+'.'+str(i))
collect(reach['sourceRefs'],'reachability.sourceRefs');collect(inv['manifests'],'inventory.manifests')
emit('shipped-provenance-binding.json',{'executionSource':BASE,'inventorySourceCount':len(inv['sources']),'reachabilitySDKSourceCount':len(reach['sdkSources']),'boundSourceRefCount':len(refs),'allBoundHashesMatch':True,'sourceRows':provenance,'sourceRefs':refs,'inventoryUncommittedSourcePaths':inv['uncommittedSourcePaths'],'reachabilityUncommittedSourcePaths':reach['uncommittedSourcePaths'],'boundary':'Hashes and source-line bounds are checked against the exact source. Source reachability remains distinct from native E2E or OS semantics.'})
catalogBytes=(S/'files/build/app-split-evidence/prepared-native/native-artifacts.json').read_bytes();catalog=json.loads(catalogBytes)
oldCatalog=json.loads((P6/'files/build/app-split-evidence/prepared-native/native-artifacts.json').read_bytes())
nativeInputs=[]
for path,expected in catalog['inputSHA256'].items():
 assert sha(current(path))==expected;nativeInputs.append({'path':path,'sha256':expected,'sameAsAttempt6':expected==oldCatalog['inputSHA256'].get(path)})
assert len(nativeInputs)==16 and all(x['sameAsAttempt6'] for x in nativeInputs)
assert catalog['state']=='prepared' and catalog['sourceCommit']==BASE and catalog['missingTargets']==[] and len(catalog['requiredTargets'])==14
artifactComparison={}
for key in ['artifacts','supportArtifacts']:
 a={x['target']:x for x in oldCatalog[key]};b={x['target']:x for x in catalog[key]};assert a.keys()==b.keys()
 rows=[]
 for target in b:
  before={k:v for k,v in a[target].items() if k!='url'};after={k:v for k,v in b[target].items() if k!='url'}
  rows.append({'target':target,'sameContentMetadata':before==after,'changesExcludingReleaseURL':jsondiff(before,after)})
 artifactComparison[key]=rows
assert all(x['sameContentMetadata'] for x in artifactComparison['artifacts'])
assert [x['target'] for x in artifactComparison['supportArtifacts'] if not x['sameContentMetadata']]==['HanlinNodeHostSupport']
emit('native-catalog-binding.json',{'catalogSHA256':sha(catalogBytes),'state':catalog['state'],'sourceCommit':catalog['sourceCommit'],'contentSHA256':catalog['contentSHA256'],'inputBindings':nativeInputs,'requiredTargets':catalog['requiredTargets'],'missingTargets':catalog['missingTargets'],'acceptance':catalog['acceptance'],'priorCatalogContentSHA256':oldCatalog['contentSHA256'],'comparison':artifactComparison,'currentNodeHostSupport':next(x for x in catalog['supportArtifacts'] if x['target']=='HanlinNodeHostSupport'),'boundary':'The actual producer catalog and all direct source inputs are bound. All artifact metadata except release URL is compared, without downloading or re-extracting the full native export. Catalog state alone does not prove application cases.'})
stateBytes=(S/'controller-state-at-capture.json').read_bytes();state=json.loads(stateBytes)
assert state['source']==BASE and state['attempt']==7 and state['status']=='RUNNING' and state['phase']=='split-paired-acceptance'
for key,value in r['phaseReceipts'].items():assert value['status']=='PASS' and value['exitCode']==0 and state['phases'][key]==value
first=json.loads((S/'files/build/primary-control/observation-attempt7/first-controller-state.json').read_bytes())
prefix=json.loads((S/'files/build/primary-control/host-prefix-attempt7.json').read_bytes())
admission=json.loads((S/'files/build/primary-control/capacity-admission-attempt7.json').read_bytes())
advance=json.loads((S/'files/build/primary-control/source-advance-fd81d602/receipt.json').read_bytes())
assert first['state']['source']==BASE and first['state']['attempt']==7 and first['state']['phase']=='split-host-lifecycle'
assert prefix['source']==BASE and prefix['status']=='HOST_PREFIX_PASS_HEAVY_WORK_PENDING'
assert admission['source']==BASE and admission['status']=='ADMITTED_CONTROLLER_STARTED'
assert advance['target']==BASE and advance['targetTree']==r['sourceTree'] and advance['nativeStarted'] is False
for path,digest in advance['sourceHashes'].items():assert sha(git(path))==digest
emit('execution-checkpoint.json',{'capturedAtUTC':r['capturedAt'],'executionSource':BASE,'sourceTree':r['sourceTree'],'attempt':7,'sourceAdvanceAtUTC':advance['utc'],'firstControllerObservationAtUTC':first['observedAt'],'firstControllerPhase':first['state']['phase'],'firstPrefixControllerStartUTC':first['state']['resumedAt'],'prefix':prefix,'capacityAdmission':admission,'heavyContinuationStartedAtUTC':r['phaseReceipts']['split-native-preparation']['startedAt'],'heavyControllerResumedAtUTC':state['resumedAt'],'controllerPID':state['controllerPID'],'controllerStatusAtCapture':state['status'],'controllerPhaseAtCapture':state['phase'],'phaseReceipts':r['phaseReceipts'],'pairedPhase':state['phases']['split-paired-acceptance'],'applicationAcceptance':'Not established by prepared snapshot; paired phase running at capture. Later built-resource proof is retained separately; selected52 outcomes remain separate.','boundary':'Distinct source advance, bounded Host prefix and heavy continuation are preserved. Later observations supersede this immutable running checkpoint without rewriting raw proof.'})
metadataBytes=(S/'files/build/runtime-host/host-metadata.json').read_bytes();metadata=json.loads(metadataBytes)
assert metadata['archiveSha256']==zipRef['sha256'] and metadata['tests']=='passed' and metadata['jitlessArchiveSmoke']=='passed'
prepLog=(S/'files/build/primary-control/logs-attempt7/split-native-preparation.log').read_text()
hostTestCounts={}
for key in ['tests','pass','fail','skipped']:
 match=re.search(r'ℹ '+key+r' (\d+)',prepLog);assert match
 hostTestCounts[key]=int(match.group(1))
assert hostTestCounts=={'tests':169,'pass':168,'fail':0,'skipped':1}
resolverLines=[line for line in prepLog.splitlines() if any(x in line for x in ['canonical module and type references use the supplied SDK','NativeScript emission and copied bodies agree','missing canonical exports, configs and SDK dependencies'])]
assert len(resolverLines)==3 and all(line.startswith('✔') for line in resolverLines)
skipLines=[line for line in prepLog.splitlines() if '# SKIP' in line]
assert len(skipLines)==1 and 'actual Node job crosses 300 seconds' in skipLines[0]
producerPath='Scripts/Runtime/runtime_host_archive.py';producer=git(producerPath).decode().splitlines()
assert 'for directory, subdirectories, names in os.walk(source)' in producer[142]
emit('host-archive-binding.json',{'archive':zipRef,'embeddedAuthoringModule':r['hostModule'],'sourceAuthoringSHA256':sha(git(HOST)),'sourceRegression':{'path':TEST,'sha256':sha(git(TEST)),'includedInProducerSourceFingerprint':True,'shippedInArchive':False},'producerSource':{'path':producerPath,'sha256':sha(git(producerPath)),'inputHashSourceWalkLines':[143,148],'sourceWalk':'Original producer walks all Host source paths except node_modules/.git; Tests are included in fingerprint but excluded from shipped archive.'},'hostMetadata':metadata,'hostMetadataSHA256':sha(metadataBytes),'outsideSDKMembers':{'count':len(hostRows),'unchanged':len(hostRows)-len(hostChanged),'changed':hostChanged,'fullRows':'host-member-comparison.json','fullRowsSHA256':sha(hostMemberBytes),'method':'Hash actual uncompressed bytes of all 3102 outside-SDK members in both immutable archives; no extraction or product execution.'},'actualHostTestLog':{'path':'raw/build/primary-control/logs-attempt7/split-native-preparation.log','sha256':r['phaseReceipts']['split-native-preparation']['logSHA256'],'counts':hostTestCounts,'newResolverCases':resolverLines,'skipLines':skipLines,'boundary':'Host verification contains one existing long-duration test skip. The three new resolver cases actually passed. These Host counts are distinct from the selected52 application acceptance cases.'},'boundary':'Actual top-level Host module equals final published source. App-source ZIP identity comes from producer capture; actual built resources are separately bound below.'})
embeddedBytes=(S.parent/'embedded-host-binding-attempt7.json').read_bytes()
assert sha(embeddedBytes)=='ab377226d4312c5cccbdaa20bf9dc6bc236250df35868ad98878729e67fb8067'
embedded=json.loads(embeddedBytes)
assert embedded['source']==BASE and embedded['attempt']==7 and embedded['archiveSHA256']==zipRef['sha256'] and embedded['moduleSHA256']==HOST_SHA
assert embedded['status']=='BOTH_BUILT_PRODUCTS_BOUND'
assert set(embedded['products'])=={'HanlinMiniApps.app','AI_Hanlin.app'}
builtRows=[]
for product,observation in embedded['products'].items():
 assert observation['buildCommand']['status']=='completed' and observation['buildCommand']['exit']==0
 for row in observation['archives']:
  assert row['bytes']==zipRef['bytes'] and row['sha256']==zipRef['sha256'] and row['moduleSHA256']==HOST_SHA
  builtRows.append({'product':product,'observedAt':observation['observedAt'],**row})
assert len(builtRows)==5
raw('embedded-host-binding-attempt7.json',embeddedBytes)
emit('built-resource-binding.json',{'actualReceiptSHA256':sha(embeddedBytes),'capturedAtUTC':embedded['capturedAt'],'source':BASE,'attempt':7,'status':'BOTH_BUILT_PRODUCTS_BOUND','builtCopies':builtRows,'products':{k:v['buildCommand'] for k,v in embedded['products'].items()},'preparedArchiveSHA256':zipRef['sha256'],'preparedModuleSHA256':HOST_SHA,'boundary':'Actual owner-observed built app/test/framework resource bytes and completed build commands are retained and compared to this exact prepared archive. This inspector did not query or rerun native builds. Five resource copies are not five application test passes; selected52/physical/screenshots remain separate.'})
reuse={}
for group,predicate in [('declarations',lambda p:p.endswith(('.d.ts','.d.mts','.d.cts'))),('examples',lambda p:p.startswith('examples/')),('public-docs',lambda p:p.startswith('docs/')),('original-compiler-entrypoints',lambda p:p in ['expo/node_modules/typescript/lib/typescript.js','nativescript/node_modules/typescript/lib/typescript.js'])]:
 paths=[p for p in files if predicate(p)]
 reuse[group]={'members':len(paths),'unchanged':sum(files[p]==oldFiles[p] for p in paths),'changed':[p for p in paths if files[p]!=oldFiles[p]]}
rawRefs=[raw('snapshot-receipt.json',receiptBytes),raw('tracked-delta.json',deltaBytes),raw('miniapp-sdk.json.gz',gzip.compress(mb,mtime=0)),raw('controller-state-at-capture.json',stateBytes)]
rawRefs[2].update({'uncompressedBytes':len(mb),'uncompressedSHA256':sha(mb)})
knownSource=[]
for row in handoff:
 rel=row['path']
 if rel.startswith('build/') and rel!='build/runtime-host/RuntimeHostResources.zip':
  rawRefs.append(raw(rel,(S/row['snapshotPath']).read_bytes()))
 elif rel!='build/runtime-host/RuntimeHostResources.zip':
  assert sha(git(rel))==row['sha256'];knownSource.append({'path':rel,'sha256':row['sha256'],'matchesExecutionSource':True})
emit('retained-raw-files.json',rawRefs)
emit('transfer-verification.json',{'snapshotReceiptSHA256':sha(receiptBytes),'memberCount':20,'allVerified':True,'members':handoff,'manifestVerified':r['sdkManifest'],'deltaLedgerSHA256':sha(deltaBytes),'deltaPayloadsVerified':4,'controllerStateAtCaptureSHA256':sha(stateBytes),'sourceInputFilesVerifiedWithoutDuplicating':knownSource,'separateBuiltResourceReceiptSHA256':sha(embeddedBytes),'boundary':'Archive inspected in place; no duplicated archive, full SDK extraction or full native export.'})
recon={'executionSource':BASE,'sourceTree':r['sourceTree'],'archivePath':str(archive),'archiveBytes':zipRef['bytes'],'archiveSHA256':zipRef['sha256'],'manifestSHA256':sha(mb),'manifestBytes':len(mb),'inputSHA256':m['inputSHA256'],'sourceInputCount':222,'fileCount':25661,'prior':{'executionSource':PRIOR_SOURCE,'receiptPath':'docs/miniapp-sdk/evidence/primary-sdk-attempt6-20261124/receipt.json','receiptSHA256':'2ce330eafec2788a46d184ed4c40bb1dcd281fbc54a7a570da65abc437ca9f4b','manifestSHA256':sha(priorBytes),'inputSHA256':prior['inputSHA256']},'sourceInputs':{'changed':changedInputs,'unchanged':218,'added':[],'removed':[]},'members':{'changed':changedFiles,'unchanged':25657,'added':[],'removed':[]},'reuseGroups':reuse,'engineAndUpstreamMetadataUnchanged':True,'sourceDeltaCanonicalSHA256':deltaBinding,'hostOutsideSDKChanged':['miniapp-authoring.mjs'],'scope':'Recomputed actual input identity, bound all222 source inputs and compared all25661 SDK manifest file records; reread changed SDK docs and exact original compiler identity-chain members, while reusing unaffected evidence. Separately hashed outside-SDK Host member bytes. No repeated112-member audit or product compiler/generator/native execution.'}
emit('sdk-reconciliation.json',recon)
summary={'status':'PASS','recordedAtUTC':datetime.now(timezone.utc).isoformat(),'inspectionStartedAtUTC':started,'elapsedSeconds':time.monotonic()-clock,'executionSource':BASE,'archiveSHA256':zipRef['sha256'],'manifestSHA256':sha(mb),'inputSHA256':m['inputSHA256'],'changedInputs':4,'unchangedInputs':218,'changedMembers':4,'unchangedMembers':25657,'hostMembersChanged':1,'hostMembersUnchanged':3101,'documentProjects':4,'diagnostics':0,'preparedSourcePaths':4,'preparedSourceBytes':sum(x['bytes'] for x in deltaRows),'sourceDeltaCanonicalSHA256':deltaBinding,'nativePreparation':'EXECUTED_PASS','nativeExport':'EXECUTED_PASS','bothBuiltProductResources':'OWNER_OBSERVED_AND_EXACT_IDENTITY_BOUND','applicationAcceptance':'NOT_ESTABLISHED; paired phase RUNNING at prepared capture, separate later build/resource evidence retained','reuseGroups':reuse}
emit('inspection-summary.json',summary)
print(json.dumps(summary,ensure_ascii=False,indent=2))
