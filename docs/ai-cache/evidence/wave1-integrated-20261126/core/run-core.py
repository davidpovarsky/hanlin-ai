
import pathlib,subprocess,json,datetime,hashlib,traceback,os
c=pathlib.Path('/Users/m1/builds/hanlin-wave1-core-f3b55fdd-20261126');s=c/'source'
bundle=pathlib.Path('/Users/m1/builds/hanlin-two-wave-root-20261126/root-a30c8267.bundle')
wanted='a30c8267c1f5ce2a122889b81dc9fffc0f295758'
r={'started_at':datetime.datetime.now(datetime.timezone.utc).isoformat(),'state':'PREPARING','steps':[],'source_sha':wanted}
def save():(c/'core-dispatch.json').write_text(json.dumps(r,indent=2)+'\n')
def run(cmd):
 p=subprocess.run(cmd,text=True,capture_output=True,timeout=180)
 r['steps'].append({'command':cmd,'exit':p.returncode,'stdout':p.stdout[-1500:],'stderr':p.stderr[-1500:]});save()
 if p.returncode:raise RuntimeError('Command failed '+cmd[0])
 return p.stdout.strip()
def free():
 st=os.statvfs('/Users/m1');return st.f_bavail*st.f_frsize
try:
 r['free_before']=free();save()
 assert hashlib.sha256(bundle.read_bytes()).hexdigest()=='24179c9bb33618cca7a96d48788a1b8da273fa2edb637f6a771fa0af288d0d75'
 assert json.loads((c/'producer-preparation.json').read_text())['state']=='READY'
 assert run(['git','-C',str(s),'status','--porcelain'])==''
 run(['git','-C',str(s),'bundle','verify',str(bundle)])
 heads=run(['git','bundle','list-heads',str(bundle)]).splitlines()
 ref=next(x.split()[1] for x in heads if x.split()[0]==wanted)
 run(['git','-C',str(s),'fetch','--no-tags',str(bundle),ref+':refs/heads/integrated-validation'])
 run(['git','-C',str(s),'checkout','integrated-validation'])
 assert run(['git','-C',str(s),'rev-parse','HEAD'])==wanted
 assert run(['git','-C',str(s),'status','--porcelain'])==''
 lock=json.loads(run(['git','-C',str(s),'show','HEAD:AI_HLY.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved']))
 r['canonical_pins']={x['identity']:x['state'] for x in lock['pins']}
 proof=c/'proof'
 for p in json.loads((proof/'Package.resolved').read_text())['pins']:assert r['canonical_pins'][p['identity']]==p['state']
 script=s/'Scripts/CI/IntegrationValidation/run_cache_native.py'
 r['original_runner_sha256']=hashlib.sha256(script.read_bytes()).hexdigest()
 r['command']=['python3',str(script),'--proof',str(proof),'--scratch','/Users/m1/caches/DerivedData/hanlin-wave1-core-20261126','--producer-tests',str(c/'producer-fixtures')]
 r['state']='RUNNING';r['free_at_dispatch']=free();save()
 with (c/'core-runner.log').open('w') as log:
  p=subprocess.run(r['command'],cwd=s,stdout=log,stderr=subprocess.STDOUT,timeout=2400)
 r['exit_code']=p.returncode;r['state']='COMPLETED'
 native=json.loads((proof/'evidence/receipt.json').read_text())
 r['native_status']=native.get('status');r['pins_match_canonical']=all(r['canonical_pins'].get(x['identity'])==x['state'] for x in native.get('resolved_pins',[]))
 r['source_still_clean']=run(['git','-C',str(s),'status','--porcelain'])==''
except Exception:r['state']='FAILED';r['error']=traceback.format_exc()
r['finished_at']=datetime.datetime.now(datetime.timezone.utc).isoformat();r['free_end']=free();save()
print(json.dumps({k:v for k,v in r.items() if k not in ['steps','canonical_pins']}),flush=True)
