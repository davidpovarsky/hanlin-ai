from pathlib import Path
import subprocess,json,datetime,os,hashlib
w=Path('/mnt/development/projects/worktrees/hanlin-ai-cache-final-sync-20261125')
e=Path('/mnt/development/projects/artifacts/hanlin-ai-cache-final-sync-20261125')
env=dict(os.environ);env['PYTHONDONTWRITEBYTECODE']='1'
ts='/mnt/development/projects/worktrees/hanlin-ai-cache-bridge-20261125/Scripts/Expo/node_modules/typescript/lib/typescript.js'
assert Path(ts).is_file()
commands=[
 ('app-intents-check',['python3','-B','Scripts/SDK/generate_app_intents_resources.py','--check']),
 ('manifest-check',['python3','-B','Scripts/SDK/generate_manifest.py','--check']),
 ('project-check',['python3','-B','Scripts/SDK/update_project.py','--check']),
 ('miniapp-sdk-audit-check',['node','Scripts/Audit/audit-miniapp-sdk.mjs','--check','--typescript-module',ts]),
 ('miniapp-reachability-check',['python3','-B','Scripts/Audit/audit_miniapp_reachability.py','--check'])
]
def now():return datetime.datetime.now(datetime.timezone.utc).isoformat()
def git(*args):return subprocess.run(['git','-c','safe.directory='+str(w),'-C',str(w),*args],text=True,capture_output=True,check=True).stdout.strip()
r={'sourceSHA':git('rev-parse','HEAD'),'sourceTree':git('rev-parse','HEAD^{tree}'),'startedAtUTC':now(),'status':'RUNNING','pid':os.getpid(),'mode':'Original source/graph/audit CHECKS only; no tests/native build/generator rewrite','typescriptModule':{'path':ts,'sha256':hashlib.sha256(Path(ts).read_bytes()).hexdigest()},'commands':[]}
receipt=e/'checks-receipt.json'
def save():receipt.write_text(json.dumps(r,indent=2)+'\n')
save()
for i,(name,argv) in enumerate(commands,1):
 out=e/(str(i).zfill(2)+'-'+name+'.stdout.log');err=e/(str(i).zfill(2)+'-'+name+'.stderr.log')
item=None
for i,(name,argv) in enumerate(commands,1):
 out=e/(str(i).zfill(2)+'-'+name+'.stdout.log');err=e/(str(i).zfill(2)+'-'+name+'.stderr.log')
 item={'name':name,'argv':argv,'startedAtUTC':now(),'stdout':out.name,'stderr':err.name,'exitCode':None}
 r['commands'].append(item);save()
 with out.open('w') as o,err.open('w') as q:
  try:
   p=subprocess.run(argv,cwd=w,env=env,stdout=o,stderr=q,text=True,timeout=180)
   item['exitCode']=p.returncode
  except subprocess.TimeoutExpired:
   item['exitCode']=124;item['failure']='Original check command exceeded180 seconds'
 item['finishedAtUTC']=now()
 for label,path in [('stdout',out),('stderr',err)]:item[label+'SHA256']=hashlib.sha256(path.read_bytes()).hexdigest()
 save()
r['finishedAtUTC']=now();r['sourceAfter']=git('rev-parse','HEAD');r['workingTreeStatusAfter']=git('status','--porcelain')
r['status']='PASS' if all(x['exitCode']==0 for x in r['commands']) and r['sourceAfter']==r['sourceSHA'] and not r['workingTreeStatusAfter'] else 'CHECK_FAILURE'
save()
