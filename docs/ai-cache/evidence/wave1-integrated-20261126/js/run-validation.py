import pathlib,subprocess,json,hashlib,datetime,os,tarfile,io,traceback,re
r=pathlib.Path('/mnt/development/projects/worktrees/hanlin-wave1-shared-chat-actions-20261126')
base=r/'build/wave1-shared-ui/js-a30c8267';base.mkdir(exist_ok=True)
src=base/'source';deps=base/'dependencies'
git=['git','--git-dir','/mnt/development/projects/git-mirrors/hanlin-ai.git']
sha='a30c8267c1f5ce2a122889b81dc9fffc0f295758'
receipt={'source_sha':sha,'started_at':datetime.datetime.now(datetime.timezone.utc).isoformat(),'status':'PREPARING','steps':[]}
def save():(base/'receipt.json').write_text(json.dumps(receipt,indent=2)+'\n')
def run(name,command,cwd,timeout=180):
 log=base/(name+'.log')
 with log.open('w') as out:p=subprocess.run(command,cwd=cwd,stdout=out,stderr=subprocess.STDOUT,timeout=timeout)
 item={'name':name,'command':command,'cwd':str(cwd),'exit':p.returncode,'log_sha256':hashlib.sha256(log.read_bytes()).hexdigest()}
 receipt['steps'].append(item);save()
 return p.returncode,log
def read(path):return subprocess.check_output(git+['show',sha+':'+path])
try:
 save()
 paths=['Packages/HanlinExpoUI','Scripts/NativeScript','Scripts/Expo','Packages/HanlinNativeScriptRuntime/Sources/HanlinNativeScriptRuntime/Resources/NativeScriptSharedRuntime/@hanlin/host-services']
 data=subprocess.check_output(git+['archive',sha]+paths)
 src.mkdir(exist_ok=True)
 with tarfile.open(fileobj=io.BytesIO(data)) as tar:tar.extractall(src,filter='data')
 files={str(p.relative_to(src)):hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(src.rglob('*')) if p.is_file()}
 receipt['source_archive_sha256']=hashlib.sha256(data).hexdigest();receipt['source_inputs']=files
 receipt['node']=subprocess.check_output(['node','--version'],text=True).strip();assert receipt['node']=='v24.22.0'
 receipt['dependency_locks']={}
 specs=[
  ('native','Scripts/NativeScript/package-lock.json',{'typescript':'5.9.3'},['node_modules/typescript']),
  ('expo','Scripts/Expo/package-lock.json',{'typescript':'npm:@typescript/typescript6@6.0.2','@typescript/old':'npm:typescript@6.0.3','base64-js':'1.5.1'},['node_modules/typescript','node_modules/@typescript/old','node_modules/base64-js'])
 ]
 for name,path,requirements,keys in specs:
  original=json.loads(read(path));entries={key:original['packages'][key] for key in keys}
  receipt['dependency_locks'][name]={'original_path':path,'original_sha256':hashlib.sha256(read(path)).hexdigest(),'consumed_entries':entries}
  folder=deps/name;folder.mkdir(parents=True,exist_ok=True)
  package={'name':'hanlin-wave1-'+name+'-validation','private':True,'version':'0.0.0','dependencies':requirements}
  lock={'name':package['name'],'version':'0.0.0','lockfileVersion':3,'requires':True,'packages':{'':{k:v for k,v in package.items() if k!='private'},**entries}}
  (folder/'package.json').write_text(json.dumps(package,indent=2)+'\n')
  (folder/'package-lock.json').write_text(json.dumps(lock,indent=2)+'\n')
  rc,_=run('npm-'+name,['npm','ci','--ignore-scripts','--no-audit','--no-fund','--prefer-offline','--include=dev','--include=optional'],folder)
  if rc:raise RuntimeError('Dependency preparation failed: '+name)
  receipt['dependency_locks'][name]['installed']={}
  for key in keys:
   p=folder/key/'package.json';j=json.loads(p.read_text())
   receipt['dependency_locks'][name]['installed'][key]={'name':j['name'],'version':j['version'],'package_json_sha256':hashlib.sha256(p.read_bytes()).hexdigest()}
 link=src/'Scripts/Expo/node_modules';link.symlink_to(deps/'expo/node_modules',target_is_directory=True)
 compiler=deps/'native/node_modules/typescript/lib/typescript.js'
 receipt['compiler_sha256']={'native':hashlib.sha256(compiler.read_bytes()).hexdigest(),'expo':hashlib.sha256((deps/'expo/node_modules/typescript/lib/typescript.js').read_bytes()).hexdigest()}
 receipt['status']='RUNNING';save()
 commands=[
  ('nativescript-generated-check',['node','Scripts/NativeScript/build-host-services.mjs','--typescript-module',str(compiler),'--check']),
  ('expo-assistant-tests',['node','--test','Packages/HanlinExpoUI/tests/miniapp-assistant.test.mjs','Packages/HanlinExpoUI/tests/host-services-publication.test.mjs']),
  ('host-facade-tests',['node','--test','Scripts/NativeScript/Tests/assistant.test.mjs','Scripts/NativeScript/Tests/miniapps-sharing.test.mjs','Scripts/NativeScript/Tests/live-activities.test.mjs','Scripts/Expo/Tests/host-services.test.mjs'])
 ]
 for name,cmd in commands:
  rc,log=run(name,cmd,src)
  if '--test' in cmd:
   counts={key:int(value) for key,value in re.findall(r'(?m)^(?:#|ℹ)\s+(tests|pass|fail|cancelled|skipped|todo)\s+(\d+)',log.read_text())}
   receipt['steps'][-1]['counts']=counts;save()
 receipt['source_unchanged']=all(hashlib.sha256((src/name).read_bytes()).hexdigest()==expected for name,expected in files.items())
 teststeps=[x for x in receipt['steps'] if 'counts' in x]
 receipt['all_actual_invocations_passed']=len(teststeps)==2 and all(x['counts'].get('tests',0)>0 and x['counts'].get('pass')==x['counts']['tests'] and all(x['counts'].get(k)==0 for k in ['fail','cancelled','skipped','todo']) for x in teststeps)
 receipt['status']='PASS' if all(x['exit']==0 for x in receipt['steps']) and receipt['source_unchanged'] and receipt['all_actual_invocations_passed'] else 'FAILED'
except Exception:receipt['status']='FAILED';receipt['error']=traceback.format_exc()
receipt['finished_at']=datetime.datetime.now(datetime.timezone.utc).isoformat();save()
print(json.dumps({k:v for k,v in receipt.items() if k not in ['source_inputs','dependency_locks']}),flush=True)
