#!/usr/bin/env python3
"""Read-only inspection of actual attempt6 outputs. Never runs product tools."""
from pathlib import Path
from datetime import datetime,timezone
import subprocess,json,hashlib,gzip,zipfile,copy,difflib,os,time
W=Path('/mnt/development/projects/worktrees/hanlin-primary-sdk-preparation-20261124')
S=Path('/mnt/development/projects/transfers/hanlin-primary-ce49-20261124/prepared-snapshot-attempt6')
P5=Path('/mnt/development/projects/transfers/hanlin-primary-ce49-20261124/prepared-snapshot-attempt5')
BASE='bd6da170da7936fe3c5353ddaf8b25c97477a380'
OLD_SOURCE='340018ddc9ea2395ffabedbf179369b5bdb791af'
OUT=W/'docs/miniapp-sdk/evidence/primary-sdk-attempt6-20261124'
def sha(b):return hashlib.sha256(b).hexdigest()
def canonical(v):return json.dumps(v,ensure_ascii=False,separators=(',',':')).encode()
def emit(name,v):
 p=OUT/name;p.parent.mkdir(parents=True,exist_ok=True);p.write_bytes((json.dumps(v,ensure_ascii=False,indent=2)+'\n').encode())
def raw(name,b):
 p=OUT/'raw'/name;p.parent.mkdir(parents=True,exist_ok=True);p.write_bytes(b)
 return {'path':'raw/'+name,'bytes':len(b),'sha256':sha(b)}
cache={}
def git(path):
 if path not in cache:cache[path]=subprocess.check_output(['git','-C',str(W),'show',BASE+':'+path])
 return cache[path]
started=datetime.now(timezone.utc).isoformat();clock=time.monotonic()
assert subprocess.check_output(['git','-C',str(W),'rev-parse','HEAD'],text=True).strip()==BASE
receiptBytes=(S/'receipt.json').read_bytes()
assert sha(receiptBytes)=='9c6e12bb89ac97c09419279eedb09add44267f57fdfd169b4ea374b000d340d3'
r=json.loads(receiptBytes);assert r['sourceHEAD']==BASE
assert r['sourceTree']==subprocess.check_output(['git','-C',str(W),'rev-parse',BASE+'^{tree}'],text=True).strip()
handoff=[]
for f in r['files']:
 p=S/f['snapshotPath'];h=hashlib.sha256()
 with p.open('rb') as stream:
  for chunk in iter(lambda:stream.read(1024*1024),b''):h.update(chunk)
 actual=h.hexdigest()
 assert p.stat().st_size==f['bytes'] and actual==f['sha256'],f['path']
 handoff.append({**f,'actualSHA256':actual,'verified':True})
assert len(handoff)==17
deltaBytes=(S/r['trackedDeltaPath']).read_bytes();assert sha(deltaBytes)==r['trackedDeltaSHA256']
delta=json.loads(deltaBytes);assert len(delta)==r['trackedDeltaCount']==3
overlay={row['path']:(S/row['contentFrom']).read_bytes() for row in delta}
def current(path):return overlay[path] if path in overlay else git(path)
deltaRows=[];diffs=[]
for row in delta:
 path=row['path'];before=git(path);after=overlay[path]
 assert sha(before)==row['headSHA256'] and sha(after)==row['sha256'] and len(after)==row['bytes']
 mode=subprocess.check_output(['git','-C',str(W),'ls-tree',BASE,'--',path],text=True).split()[0]
 assert mode==row['headMode']=='100644' and row['mode']=='0o644'
 if path.endswith('.json'):
  a=json.loads(before);b=json.loads(after);assert a['sourceCommit']==OLD_SOURCE and b['sourceCommit']==BASE
  a['sourceCommit']=BASE;assert a==b
  semanticDelta=[{'jsonPointer':'/sourceCommit','before':OLD_SOURCE,'after':BASE}]
 else:
  assert before.replace(OLD_SOURCE.encode(),BASE.encode())==after
  semanticDelta=[{'field':'rendered source commit','before':OLD_SOURCE,'after':BASE,'occurrences':before.count(OLD_SOURCE.encode())}]
 deltaRows.append({'path':path,'beforeSHA256':sha(before),'afterSHA256':sha(after),'bytes':len(after),'beforeMode':mode,'afterMode':'100644','contentFrom':row['contentFrom'],'semanticDelta':semanticDelta})
 diffs.extend(difflib.unified_diff(before.decode().splitlines(True),after.decode().splitlines(True),fromfile=BASE+'/'+path,tofile='actual-prepared/'+path))
 raw(path,after)
bindingRows=[{k:x[k] for k in ['path','beforeSHA256','afterSHA256','bytes','contentFrom']} for x in sorted(deltaRows,key=lambda v:v['path'])]
deltaBinding=sha(canonical(bindingRows))
emit('prepared-source-delta.json',{'executionSource':BASE,'snapshotRoot':str(S),'ledgerSHA256':sha(deltaBytes),'paths':3,'payloadBytes':sum(x['bytes'] for x in deltaRows),'contentChanges':3,'modeChanges':0,'canonicalBinding':{'algorithm':'SHA256 of compact UTF-8 JSON rows sorted by path, keys in order path,beforeSHA256,afterSHA256,bytes,contentFrom','sha256':deltaBinding},'rows':deltaRows,'classification':'Only provenance sourceCommit changes; no implementation/API/source inventory rows changed. Not materialized by this inspection.'})
(OUT/'prepared-provenance.diff').write_text(''.join(diffs))
mb=(S/r['sdkManifest']['snapshotPath']).read_bytes()
assert len(mb)==r['sdkManifest']['bytes'] and sha(mb)==r['sdkManifest']['sha256']
m=json.loads(mb)
priorBytes=(P5/'extracted-sdk/miniapp-sdk.json').read_bytes()
assert sha(priorBytes)=='1d51c86e55ca79792b6b31176de6363008e5874dec4f919e5ef96c789a6d53f9'
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
 sourceRows.append({'path':path,'sha256':actual,'authority':'actual prepared provenance delta' if path in overlay else BASE,'matches':True})
assert {k:v for k,v in m.items() if k not in ['sourceInputs','files','inputSHA256']}=={k:v for k,v in prior.items() if k not in ['sourceInputs','files','inputSHA256']}
archive=S/'files/build/runtime-host/RuntimeHostResources.zip'
zipRef=next(x for x in handoff if x['path']=='build/runtime-host/RuntimeHostResources.zip')
with zipfile.ZipFile(archive) as z:
 assert z.read(r['sdkManifest']['archiveMember'])==mb
 names=z.namelist();assert len(names)==len(set(names))
 actualSDKNames={p[len('MiniAppSDK/'):] for p in names if p.startswith('MiniAppSDK/') and not p.endswith('/') and p!='MiniAppSDK/miniapp-sdk.json'}
 assert actualSDKNames==set(files)
 for row in changedFiles:
  p=row['path'];body=z.read('MiniAppSDK/'+p);assert body==overlay[p] and sha(body)==row['after']['sha256'] and len(body)==row['after']['bytes']
 docBytes=(S/'files/build/app-split-evidence/miniapp-documentation-snippets.json').read_bytes()
 doc=json.loads(docBytes);oldDoc=json.loads((P5/'files/build/app-split-evidence/miniapp-documentation-snippets.json').read_bytes())
 assert doc['status']=='EXECUTED_PASS' and doc['sdk']=={'manifestSHA256':sha(mb),'inputSHA256':m['inputSHA256']}
 assert doc['sourceBlockCount']==14 and doc['jsonBlockCount']==7 and len(doc['excluded'])==8
 guideRows=[]
 for row in doc['documentation']:
  path=row['path'];body=z.read('MiniAppSDK/'+path);actual=sha(body)
  assert actual==row['sha256']==row['stagedSDKSHA256']==sha(current(path)) and row['stagedSDKMatches'] is True
  assert files[path]==oldFiles[path]
  guideRows.append({**row,'actualMemberSHA256':actual,'sourceMatches':True,'sameAsAttempt5Member':True})
 checkerRows=[]
 for row in doc['checkerInputs']:
  assert sha(current(row['path']))==row['sha256'];checkerRows.append({**row,'sourceMatches':True})
 projects=[];oldProjects={x['name']:x for x in oldDoc['projects']}
 for p in doc['projects']:
  v=p['validation'];o=oldProjects[p['name']]
  assert v['succeeded'] and v['diagnostics']==[] and v['sdk']['manifestSHA256']==sha(mb)
  matches={'snippets':p['snippets']==o['snippets'],'context':p['context']==o['context'],'typecheck':v['typecheck']==o['validation']['typecheck'],'compilerVersion':v['sdk']['compilerVersion']==o['validation']['sdk']['compilerVersion'],'packageVersions':v['sdk']['packageVersions']==o['validation']['sdk']['packageVersions']}
  assert all(matches.values())
  projects.append({'name':p['name'],'engine':p['engine'],'succeeded':True,'diagnostics':[],'compilerVersion':v['sdk']['compilerVersion'],'typecheck':v['typecheck'],'sameContractAsAttempt5':matches})
 assert len(projects)==4 and doc['registration']==oldDoc['registration']
 assert sha(current(doc['registration']['nativePath']))==doc['registration']['nativeSessionSHA256']
emit('documentation-execution-binding.json',{'actualReportSHA256':sha(docBytes),'status':'EXECUTED_PASS','projectCount':4,'diagnosticCount':0,'sourceFences':14,'jsonFences':7,'nonAuthoringExclusions':8,'totalFences':29,'projects':projects,'guides':guideRows,'checkerInputs':checkerRows,'registration':doc['registration'],'boundary':doc['boundary'],'origin':'Actual original native preparation attempt6; inspection does not run compilers/checkers.'})
emit('sdk-source-binding.json',{'executionSource':BASE,'preparedDeltaLedgerSHA256':sha(deltaBytes),'count':222,'sourceInputsAtBase':219,'sourceInputsFromPreparedProvenance':3,'allMatch':True,'rows':sourceRows})
inv=json.loads(overlay['docs/miniapp-sdk/source-inventory.json'])
reach=json.loads(overlay['docs/miniapp-sdk/extension-reachability.json'])
assert inv['sourceCommit']==reach['sourceCommit']==BASE
provenanceRows=[]
for group,rows in [('inventory.sources',inv['sources']),('reachability.sdkSources',reach['sdkSources'])]:
 for row in rows:
  actual=sha(current(row['path']));assert actual==row['sha256'],row['path']
  provenanceRows.append({'group':group,'path':row['path'],'sha256':actual})
refs=[]
def collect(v,context='sourceRefs'):
 if isinstance(v,dict):
  if isinstance(v.get('file'),str) and isinstance(v.get('sha256'),str):
   actual=sha(current(v['file']));assert actual==v['sha256'],(context,v['file'])
   refs.append({'context':context,'path':v['file'],'sha256':actual})
  for k,x in v.items():
   if isinstance(x,(dict,list)):collect(x,context+'.'+k)
 elif isinstance(v,list):
  for i,x in enumerate(v):collect(x,context+'.'+str(i))
collect(reach['sourceRefs'])
emit('shipped-provenance-binding.json',{'executionSource':BASE,'inventorySourceCount':len(inv['sources']),'reachabilitySDKSourceCount':len(reach['sdkSources']),'sourceRefCount':len(refs),'allBoundHashesMatch':True,'sourceRows':provenanceRows,'sourceRefs':refs,'inventoryUncommittedSourcePaths':inv['uncommittedSourcePaths'],'reachabilityUncommittedSourcePaths':reach['uncommittedSourcePaths'],'boundary':'Only each audit source set is covered; source reachability is not native E2E evidence.'})
catalogBytes=(S/'files/build/app-split-evidence/prepared-native/native-artifacts.json').read_bytes()
catalog=json.loads(catalogBytes);oldCatalog=json.loads((P5/'files/build/app-split-evidence/prepared-native/native-artifacts.json').read_bytes())
nativeInputs=[]
for path,expected in catalog['inputSHA256'].items():
 actual=sha(current(path));assert actual==expected,path
 nativeInputs.append({'path':path,'sha256':actual,'previousSHA256':oldCatalog['inputSHA256'].get(path),'changed':expected!=oldCatalog['inputSHA256'].get(path)})
assert catalog['state']=='prepared' and catalog['sourceCommit']==BASE and catalog['missingTargets']==[]
assert {x['path'] for x in nativeInputs if x['changed']}=={'Scripts/Expo/prepare-ios-dependencies.mjs'}
emit('native-catalog-binding.json',{'catalogSHA256':sha(catalogBytes),'state':catalog['state'],'sourceCommit':catalog['sourceCommit'],'contentSHA256':catalog['contentSHA256'],'inputBindings':nativeInputs,'requiredTargets':catalog['requiredTargets'],'missingTargets':catalog['missingTargets'],'acceptance':catalog['acceptance'],'priorCatalogContentSHA256':oldCatalog['contentSHA256'],'boundary':'Actual producer catalog and source inputs bound; no full native export downloaded and no application pass inferred.'})
reuse={}
for group,predicate in [('declarations',lambda p:p.endswith(('.d.ts','.d.mts','.d.cts'))),('examples',lambda p:p.startswith('examples/')),('public-docs',lambda p:p.startswith('docs/')),('original-compilers',lambda p:p in ['expo/node_modules/typescript/lib/typescript.js','nativescript/node_modules/typescript/lib/typescript.js'])]:
 paths=[p for p in files if predicate(p)]
 reuse[group]={'members':len(paths),'unchanged':sum(files[p]==oldFiles[p] for p in paths),'changed':[p for p in paths if files[p]!=oldFiles[p]]}
stateBytes=(S/'controller-state-at-capture.json').read_bytes();state=json.loads(stateBytes)
assert state['source']==BASE and state['attempt']==6 and state['status']=='RUNNING' and state['phase']=='split-paired-acceptance'
for key,v in r['phaseReceipts'].items():assert v['status']=='PASS' and v['exitCode']==0 and state['phases'][key]==v
first=json.loads((S/'files/build/primary-control/observation-attempt6/first-controller-state.json').read_bytes())
assert first['state']['source']==BASE and first['state']['attempt']==6
emit('execution-checkpoint.json',{'capturedAtUTC':r['capturedAt'],'executionSource':BASE,'sourceTree':r['sourceTree'],'attempt':6,'firstControllerObservationAtUTC':first['observedAt'],'startedAtUTC':state['resumedAt'],'controllerPID':state['controllerPID'],'controllerStatusAtCapture':state['status'],'controllerPhaseAtCapture':state['phase'],'phaseReceipts':r['phaseReceipts'],'pairedPhase':state['phases']['split-paired-acceptance'],'applicationAcceptance':'Not established by this prepared SDK snapshot; paired phase running. Actual application terminal/result evidence is owned separately.','boundary':'Snapshot is immutable; later terminal outcomes supersede running status without changing raw proof.'})
rawRefs=[raw('snapshot-receipt.json',receiptBytes),raw('tracked-delta.json',deltaBytes),raw('miniapp-sdk.json.gz',gzip.compress(mb,mtime=0)),raw('controller-state-at-capture.json',stateBytes)]
rawRefs[2].update({'uncompressedBytes':len(mb),'uncompressedSHA256':sha(mb)})
for rel in ['build/app-split-evidence/miniapp-documentation-snippets.json','build/app-split-evidence/prepared-native/native-artifacts.json','build/primary-control/logs-attempt6/split-native-preparation.log','build/primary-control/logs-attempt6/split-native-artifacts.log','build/runtime-host/host-metadata.json','build/primary-control/plan.json','build/primary-control/reuse-closure-attempt6.json','build/primary-control/source-advance-bd6da170/receipt.json','build/primary-control/observation-attempt6/first-controller-state.json','build/primary-control/capacity-admission-attempt6.json']:
 rawRefs.append(raw(rel,(S/'files'/rel).read_bytes()))
emit('retained-raw-files.json',rawRefs)
emit('transfer-verification.json',{'snapshotReceiptSHA256':sha(receiptBytes),'memberCount':17,'allVerified':True,'members':handoff,'manifestVerified':r['sdkManifest'],'deltaLedgerSHA256':sha(deltaBytes),'deltaPayloadsVerified':3,'controllerStateAtCaptureSHA256':sha(stateBytes),'boundary':'Archive inspected in place; no duplicate SDK or native export created.'})
recon={'executionSource':BASE,'sourceTree':r['sourceTree'],'archivePath':str(archive),'archiveBytes':zipRef['bytes'],'archiveSHA256':zipRef['sha256'],'manifestSHA256':sha(mb),'manifestBytes':len(mb),'inputSHA256':m['inputSHA256'],'sourceInputCount':222,'fileCount':25661,'prior':{'executionSource':OLD_SOURCE,'receiptPath':'docs/miniapp-sdk/evidence/primary-sdk-preparation-20261124/receipt.json','receiptSHA256':'53de9094b708b6b338f23c033982bc972b37babe071d47689a0dbfe0752d1e1f','manifestSHA256':sha(priorBytes),'inputSHA256':prior['inputSHA256']},'sourceInputs':{'changed':changedInputs,'unchanged':219,'added':[],'removed':[]},'members':{'changed':changedFiles,'unchanged':25658,'added':[],'removed':[]},'reuseGroups':reuse,'engineAndUpstreamMetadataUnchanged':True,'sourceDeltaCanonicalSHA256':deltaBinding,'scope':'Recomputed actual input identity and bound222 inputs; compared all25661 manifest rows to prior actual SDK, read only changed members/six guide bodies and preserved exact unaffected proof. No repeated112-member audit, no generator/compiler/native execution.'}
emit('sdk-reconciliation.json',recon)
summary={'status':'PASS','recordedAtUTC':datetime.now(timezone.utc).isoformat(),'inspectionStartedAtUTC':started,'elapsedSeconds':time.monotonic()-clock,'executionSource':BASE,'archiveSHA256':recon['archiveSHA256'],'manifestSHA256':sha(mb),'inputSHA256':m['inputSHA256'],'changedInputs':3,'unchangedInputs':219,'changedMembers':3,'unchangedMembers':25658,'documentProjects':4,'diagnostics':0,'preparedSourcePaths':3,'preparedSourceBytes':sum(x['bytes'] for x in deltaRows),'sourceDeltaCanonicalSHA256':deltaBinding,'nativePreparation':'EXECUTED_PASS','nativeExport':'EXECUTED_PASS','applicationAcceptance':'NOT_ESTABLISHED; actual paired phase RUNNING at capture','reuseGroups':reuse}
emit('inspection-summary.json',summary);print(json.dumps(summary,ensure_ascii=False,indent=2))
