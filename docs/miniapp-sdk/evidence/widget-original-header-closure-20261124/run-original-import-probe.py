from pathlib import Path
import subprocess,json,datetime,time,hashlib,os,signal
root=Path(__file__).resolve().parent
attributes={'sourceLogLine': 3761, 'sourceCommandSHA256': '102709ee415beb39b8dafb79750f02ce43cc8a10b59c0fbc75c69af979d5695a', 'target': 'arm64-apple-ios27.0-simulator', 'swiftVersion': '6', 'extension': True, 'cxxMode': '-cxx-interoperability-mode=default', 'extraClangDefines': ['-D_LIBCPP_HARDENING_MODE=_LIBCPP_HARDENING_MODE_DEBUG', '-DDEBUG=1']}
inputs=json.loads((root/'input-manifest.json').read_text())
for item in inputs:
 f=root/item['path']; assert f.stat().st_size==item['bytes'] and hashlib.sha256(f.read_bytes()).hexdigest()==item['sha256'],str(f)
sdk=subprocess.check_output(['xcrun','--sdk','iphonesimulator','--show-sdk-path'],text=True).strip()
flags=[f.replace('/Users/runner/work/hanlin-ai/hanlin-ai',str(root)) for f in json.loads((root/'original-xcc-flags.json').read_text())]
for define in attributes['extraClangDefines']: flags.extend(['-Xcc',define])
common=['xcrun','swiftc','-swift-version',attributes['swiftVersion'],'-target',attributes['target'],'-sdk',sdk,attributes['cxxMode'],'-application-extension','-I',str(root/'Frameworks'),'-F',str(root/'Frameworks'),'-module-name','HanlinOriginalHeaderProbe','-Xfrontend','-Rmodule-loading',*flags,'-typecheck',str(root/'Probe.swift')]
results=[]
for mode in ['implicit','explicit']:
 cache=Path.home()/'caches'/'DerivedData'/('hanlin-ai-788354f8-headers-'+mode+'-20261124')
 cache.mkdir(parents=True,exist_ok=False)
 argv=[*common,'-module-cache-path',str(cache)]
 if mode=='explicit': argv.append('-explicit-module-build')
 started=datetime.datetime.now(datetime.timezone.utc).isoformat(); t=time.monotonic()
 print('START '+mode+' '+started,flush=True)
 with (root/(mode+'.stdout.log')).open('w') as out,(root/(mode+'.stderr.log')).open('w') as err:
  process=subprocess.Popen(argv,cwd=root,stdout=out,stderr=err,start_new_session=True)
  timedOut=False
  try: code=process.wait(timeout=180)
  except subprocess.TimeoutExpired:
   timedOut=True; os.killpg(process.pid,signal.SIGKILL); code=process.wait()
 result={'mode':mode,'argv':argv,'startedAt':started,'elapsedSeconds':time.monotonic()-t,'exit':code,'timedOut':timedOut,'freshModuleCache':str(cache),'stdoutBytes':(root/(mode+'.stdout.log')).stat().st_size,'stderrBytes':(root/(mode+'.stderr.log')).stat().st_size}
 results.append(result); (root/'comparison-results.json').write_text(json.dumps(results,indent=2)+'\n')
 print(json.dumps(result),flush=True)
