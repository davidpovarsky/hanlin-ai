from pathlib import Path
import subprocess,json,datetime,time,hashlib
root=Path(__file__).resolve().parent
cache=Path.home()/'caches'/'DerivedData'/'hanlin-ai-ce2eceeb-expo-widget-props-20261124'
cache.mkdir(parents=True,exist_ok=True)
results=[]
commands=[('contracts',['xcrun','swiftc','-swift-version','6','-emit-module','-emit-library','-module-name','HanlinPlatformContracts','-module-cache-path',str(cache),'HanlinValue.swift','HanlinContractError.swift','HanlinManifestIssue.swift','-o',str(root/'libHanlinPlatformContracts.dylib')]),('probe',['xcrun','swiftc','-swift-version','6','-module-cache-path',str(cache),'-I',str(root),'-L',str(root),'-lHanlinPlatformContracts','-Xlinker','-rpath','-Xlinker',str(root),'Probe.swift','-o',str(root/'Probe')]),('run',[str(root/'Probe')])]
for name,argv in commands:
 started=datetime.datetime.now(datetime.timezone.utc).isoformat(); t=time.monotonic()
 r=subprocess.run(argv,cwd=root,text=True,capture_output=True,timeout=90)
 (root/(name+'.stdout.log')).write_text(r.stdout); (root/(name+'.stderr.log')).write_text(r.stderr)
 results.append({'name':name,'argv':argv,'startedAt':started,'elapsedSeconds':time.monotonic()-t,'exit':r.returncode,'stdout':r.stdout,'stderr':r.stderr})
 (root/'results.json').write_text(json.dumps(results,indent=2)+'\n')
 if r.returncode: break
print(json.dumps({'cwd':str(root),'moduleCache':str(cache),'results':results},indent=2))
