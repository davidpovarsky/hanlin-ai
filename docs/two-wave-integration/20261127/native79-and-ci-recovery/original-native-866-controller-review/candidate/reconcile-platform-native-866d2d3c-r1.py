import pathlib,json,hashlib,collections,datetime
stage=pathlib.Path('/Users/m1/builds/hanlin-two-wave-root-20261126');proof=stage/'validation/platform-866d2d3c/test-r1'
out=proof/'required-scope-reconciliation.json';assert not out.exists()
def sha(p):
 with p.open('rb') as f:return hashlib.file_digest(f,'sha256').hexdigest()
invPath=stage/'platform-test-inventory-866d2d3c.json';inv=json.loads(invPath.read_text());runPath=stage/'platform-native-test-866d2d3c-r1.json';run=json.loads(runPath.read_text())
assert run['source']==inv['sourceCommit']=='866d2d3c60525e32eae27564869e6dba024e625c' and run['nativeExitCode'] in [0,65] and run['sourceProductsAndFixturesUnchanged']
currentReviewPath=stage/'platform-final-controller-review-866d2d3c.json'
currentReview=json.loads(currentReviewPath.read_text())
assert currentReview['source']=='866d2d3c60525e32eae27564869e6dba024e625c' and currentReview['decision']=='APPROVED_ORIGINAL_NATIVE_AND_HOST_SOURCE_BINDINGS'
assert currentReview['inventorySHA256']=='a5530408269f296d1cbb743fd52624f74755509623ee68b2bfd0f7e351b78822'
assert currentReview['controllerSHA256'][pathlib.Path(__file__).name]==sha(pathlib.Path(__file__))
assert sha(invPath)=='a5530408269f296d1cbb743fd52624f74755509623ee68b2bfd0f7e351b78822'
expected={t['sourceDerivedIdentifier']:t for t in inv['prior59']}
for name in inv['queue19']['methods']:
 ident=inv['queue19']['selector']+'/'+name+'()';assert ident not in expected;expected[ident]={'sourceDerivedIdentifier':ident,'expectedInvocations':1,'parameterValues':None}
assert len(expected)==57 and sum(x['expectedInvocations'] for x in expected.values())==78
new=inv['compatibilityRegression'];assert new['sourceDerivedIdentifier'] not in expected
expected[new['sourceDerivedIdentifier']]=new
assert len(expected)==58 and sum(x['expectedInvocations'] for x in expected.values())==79
summaryPath=proof/'native-result-summary.log';nodesPath=proof/'native-result-tests.log';summary=json.loads(summaryPath.read_text());tree=json.loads(nodesPath.read_text());actual={}
def walk(n,target=None):
 if n.get('nodeType')=='Unit test bundle':target=n['name']
 if n.get('nodeType')=='Test Case':
  ident=target+'/'+n['nodeIdentifier'];assert ident not in actual;actual[ident]=n
 for x in n.get('children',[]):walk(x,target)
for n in tree['testNodes']:walk(n)
assert set(actual)==set(expected),(sorted(set(expected)-set(actual)),sorted(set(actual)-set(expected)))
methodCounts=collections.Counter();caseCounts=collections.Counter();rows=[];allArgumentURLs=[]
for ident,e in sorted(expected.items()):
 n=actual[ident];assert n['result'] in ['Passed','Failed','Skipped','Expected Failure'];methodCounts[n['result']]+=1
 args=[x for x in n.get('children',[]) if x.get('nodeType')=='Arguments']
 row={'identifier':ident,'result':n['result'],'durationInSeconds':n.get('durationInSeconds'),'expectedInvocations':e['expectedInvocations'],'actualInvocations':len(args) if args else 1,'nodeIdentifierURL':n['nodeIdentifierURL']}
 assert row['actualInvocations']==e['expectedInvocations'],row
 if e.get('parameterValues') is not None:
  assert args and len(args)==len(e['parameterValues'])
  if ident.endswith('(engine:)') or ident.endswith('(invalidation:)'):
   displays=['.'+str(x) for x in e['parameterValues']]
  elif all(isinstance(x,(int,float)) and not isinstance(x,bool) for x in e['parameterValues']):
   displays=[str(float(x)) for x in e['parameterValues']]
  else:
   assert all(isinstance(x,str) for x in e['parameterValues']);displays=['"'+x+'"' for x in e['parameterValues']]
  assert collections.Counter(x['name'] for x in args)==collections.Counter(displays),(ident,[x['name'] for x in args],displays)
  row['expectedParameterValues']=e['parameterValues'];row['arguments']=[]
  for arg in args:
   assert arg['result'] in ['Passed','Failed','Skipped','Expected Failure'];url=arg['nodeIdentifierURL']
   assert url.startswith(n['nodeIdentifierURL']+'?args=') and url.split('?args=',1)[1]
   allArgumentURLs.append(url);caseCounts[arg['result']]+=1;row['arguments'].append({'display':arg['name'],'result':arg['result'],'nodeIdentifierURL':url,'durationInSeconds':arg.get('durationInSeconds')})
 else:
  assert not args;caseCounts[n['result']]+=1
 rows.append(row)
assert len(allArgumentURLs)==28 and len(set(allArgumentURLs))==28
assert sum(methodCounts.values())==58 and sum(caseCounts.values())==79
assert summary['totalTestCount']==58 and summary['passedTests']==methodCounts['Passed'] and summary['failedTests']==methodCounts['Failed'] and summary['skippedTests']==methodCounts['Skipped'] and summary['expectedFailures']==methodCounts['Expected Failure']
assert len(summary['devicesAndConfigurations'])==1
device=summary['devicesAndConfigurations'][0];assert device['device']['deviceId']=='233DB080-C913-4EE6-BF3D-99659F5CD475' and device['device']['osVersion']=='27.2' and device['device']['osBuildNumber']=='24B8117'
assert device['passedTests']==caseCounts['Passed'] and device['failedTests']==caseCounts['Failed'] and device['skippedTests']==caseCounts['Skipped'] and device['expectedFailures']==caseCounts['Expected Failure']
nativePhases=[p for p in run['phases'] if p['name']=='original-native-test-without-building'];assert len(nativePhases)==1
nativeFinishedCleanly=run['status']=='TEST_COMMAND_FINISHED_AWAITING_EXACT_CASE_RECONCILIATION' and nativePhases[0]['status']=='PASSED' and not nativePhases[0].get('stopReason')
passed=nativeFinishedCleanly and run['nativeExitCode']==0 and methodCounts['Passed']==58 and caseCounts['Passed']==79 and not any(caseCounts[k] for k in ['Failed','Skipped','Expected Failure'])
reviewPath=stage/'platform-independent-61-scope-6975e769.json';review=json.loads(reviewPath.read_text());collateral={x['identifier'] for x in review['exactExpectedCohort'] if x['classification']!='REQUIRED'}
assert len(collateral)==4 and not(collateral&set(actual))
data={'source':run['source'],'recordedAtUTC':datetime.datetime.now(datetime.timezone.utc).isoformat(),'status':'EXACT_REQUIRED_NATIVE_SCOPE_PASSED' if passed else 'EXACT_REQUIRED_NATIVE_SCOPE_EXECUTED_WITH_FAILURES','acceptancePassed':passed,'buildSDK':'27.0','device':device['device'],'actualDefinitions':58,'actualInvocations':79,'originalDefinitions':57,'originalInvocations':78,'newRegressionDefinitions':1,'newRegressionInvocations':1,'methodResults':dict(methodCounts),'invocationResults':dict(caseCounts),'skipped':caseCounts['Skipped'],'expectedFailures':caseCounts['Expected Failure'],'missingRequiredIdentifiers':[],'unexpectedExecutedIdentifiers':[],'parameterizedDefinitions':7,'parameterInvocations':28,'parameterValuesExactlyReconciled':True,'nativeExitCode':run['nativeExitCode'],'selectionQualification':{'historical6975EnumerationReportedDefinitions':61,'proposedCollateralDefinitions':4,'proposedCollateralInvocations':16,'actualCollateralDefinitions':0,'actualCollateralInvocations':0,'absentCollateralIdentifiers':sorted(collateral),'observation':'Previous6975 enumeration overreported four excluded parameterized definitions; its actual execution honored exclusions. The current original includes/exclusions execute exactly58 required definitions/79 cases, comprising all unchanged57/78 plus one reviewed regression. All four collateral definitions remain absent from actual execution. Historical planning and failed execution receipts are unchanged.','independentEnumerationReviewSHA256':sha(reviewPath)},'inputProofs':{'inventorySHA256':sha(invPath),'runReceiptSHA256':sha(runPath),'summarySHA256':sha(summaryPath),'testNodesSHA256':sha(nodesPath)},'failedIdentifiers':sorted(k for k,n in actual.items() if n['result']=='Failed'),'tests':rows,'originalResultBundle':run['resultBundle']}
out.write_text(json.dumps(data,indent=2)+'\n');print(json.dumps({'path':str(out),'sha256':sha(out),**{k:data[k] for k in ['source','status','actualDefinitions','actualInvocations','methodResults','invocationResults','failedIdentifiers']}}))

if not passed:raise SystemExit(1)
