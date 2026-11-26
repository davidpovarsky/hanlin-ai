
import pathlib,subprocess,json,datetime,hashlib,shutil,traceback,os
c=pathlib.Path('/Users/m1/builds/hanlin-wave1-core-f3b55fdd-20261126')
sdk=c/'producer-sdk'; wanted='abf0921c6e89e6521cc2b510ff11016b45a0ef08'
r={'started':datetime.datetime.now(datetime.timezone.utc).isoformat(),'steps':[],'state':'RUNNING'}
def save():(c/'producer-preparation.json').write_text(json.dumps(r,indent=2)+'\n')
def run(cmd,check=True):
 p=subprocess.run(cmd,text=True,capture_output=True,env=dict(os.environ,GIT_TERMINAL_PROMPT='0'),timeout=180)
 r['steps'].append({'command':cmd,'exit':p.returncode,'stdout':p.stdout[-1800:],'stderr':p.stderr[-1800:]});save()
 if check and p.returncode:raise RuntimeError('Command failed '+cmd[0])
 return p
try:
 save()
 if not sdk.exists():run(['git','clone','--shared','--no-checkout','/Users/m1/builds/hanlin-testflight-149101-20261125/SourcePackages/checkouts/swift-ai-sdk',str(sdk)])
 if run(['git','-C',str(sdk),'cat-file','-e',wanted+'^{commit}'],False).returncode:
  run(['git','-C',str(sdk),'fetch','--no-tags','https://github.com/davidpovarsky/swift-ai-sdk.git',wanted])
 run(['git','-C',str(sdk),'sparse-checkout','init','--cone'])
 run(['git','-C',str(sdk),'sparse-checkout','set','Tests'])
 run(['git','-C',str(sdk),'checkout','--detach',wanted])
 r['producer_sha']=run(['git','-C',str(sdk),'rev-parse','HEAD']).stdout.strip()
 assert r['producer_sha']==wanted
 fixtures=c/'producer-fixtures';fixtures.mkdir(exist_ok=True); r['fixtures']={}
 for name in ['OpenAIPromptCacheControlTests.swift','MockTracer.swift']:
  files=list((sdk/'Tests').rglob(name));assert len(files)==1,(name,files)
  dest=fixtures/name;shutil.copyfile(files[0],dest)
  r['fixtures'][name]={'source':str(files[0]),'sha256':hashlib.sha256(dest.read_bytes()).hexdigest()}
 historical=c/'source/docs/ai-cache/evidence/native-core-20261125/final-pin/receipt.json'
 old=json.loads(historical.read_text())
 r['historical_fixture_hashes']=old.get('producer_test_sha256')
 assert {name:value['sha256'] for name,value in r['fixtures'].items()}==old['producer_test_sha256']
 proof=c/'proof';proof.mkdir(exist_ok=True)
 shutil.copyfile(c/'source/docs/ai-cache/evidence/native-core-20261125/final-pin/proof-Package.resolved',proof/'Package.resolved')
 r['state']='READY'
except Exception:r['state']='FAILED';r['error']=traceback.format_exc()
r['finished']=datetime.datetime.now(datetime.timezone.utc).isoformat();save()
print(json.dumps({k:v for k,v in r.items() if k!='steps'}),flush=True)
