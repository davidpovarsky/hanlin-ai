from pathlib import Path
import subprocess,json,datetime,time,hashlib
root=Path(__file__).resolve().parent
prior=Path('/Users/m1/builds/hanlin-ai-ce2eceeb-expo-widget-props-20261124')
metadata=json.loads((root/'contract-module-reuse.json').read_text())
for item in metadata['files']:
 actual=hashlib.sha256((prior/item['previousMacFile']).read_bytes()).hexdigest()
 assert actual==item['sha256'],item['source']
artifacts={f.name:hashlib.sha256(f.read_bytes()).hexdigest() for f in prior.iterdir() if f.suffix in ('.swiftmodule','.swiftdoc','.swiftsourceinfo','.dylib')}
cache=Path.home()/'caches'/'DerivedData'/'hanlin-ai-dc518aa3-widget-options-20261124'
cache.mkdir(parents=True,exist_ok=True)
results=[]
commands=[('compile',['xcrun','swiftc','-swift-version','6','-cxx-interoperability-mode=default','-parse-as-library','-module-cache-path',str(cache),'-I',str(prior),'-L',str(prior),'-lHanlinPlatformContracts','-Xlinker','-rpath','-Xlinker',str(prior),'ProductionProjection.swift','Probe.swift','-o',str(root/'Probe')]),('run',[str(root/'Probe')])]
for name,argv in commands:
 started=datetime.datetime.now(datetime.timezone.utc).isoformat(); t=time.monotonic()
 r=subprocess.run(argv,cwd=root,text=True,capture_output=True,timeout=90)
 (root/(name+'.stdout.log')).write_text(r.stdout); (root/(name+'.stderr.log')).write_text(r.stderr)
 results.append({'name':name,'argv':argv,'startedAt':started,'elapsedSeconds':time.monotonic()-t,'exit':r.returncode,'stdout':r.stdout,'stderr':r.stderr})
 if r.returncode: break
out={'cwd':str(root),'moduleCache':str(cache),'reusedContractArtifacts':artifacts,'results':results}
(root/'results.json').write_text(json.dumps(out,indent=2)+'\n')
print(json.dumps(out,indent=2))
