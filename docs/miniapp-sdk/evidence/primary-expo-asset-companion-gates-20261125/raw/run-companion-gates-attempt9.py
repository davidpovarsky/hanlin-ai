from pathlib import Path
import os,subprocess,json,time,datetime,hashlib,re,signal
ROOT=Path('/Users/m1/builds/hanlin-ai-ce49e30d-miniapp-complete');CTRL=ROOT/'build/primary-control';OUT=CTRL/'companion-gates-attempt9'
SOURCE='1812bff50571c9907d15cd8b4bfbe4874be24756'
OUT.mkdir(exist_ok=False)
def utc():return datetime.datetime.now(datetime.timezone.utc).isoformat()
def digest(p):return hashlib.sha256(p.read_bytes()).hexdigest()
state={'owner':'/root/native_execution','source':SOURCE,'status':'WAITING_FOR_NATIVE_CAPACITY','pid':os.getpid(),'startedAt':utc(),'commands':[],'original52':'NOT_RUN','focusedDiagnostic':'NOT_RUN'}
def save():
 temp=OUT/'state.json.tmp';temp.write_text(json.dumps(state,indent=2)+'\n');temp.replace(OUT/'state.json')
save()
assert subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT,text=True).strip()==SOURCE
primary=json.loads((CTRL/'state.json').read_text());assert primary['status']=='PAUSED_AFTER_PHASE' and primary['source']==SOURCE
env={**os.environ,'DEVELOPER_DIR':'/Applications/Xcode.app/Contents/Developer','PATH':str(ROOT.parent/(ROOT.name+'-tools')/'bin')+':/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin'}
def blockers():
 rows=[]
 for line in subprocess.check_output(['/bin/ps','-axo','pid=,ppid=,stat=,%cpu=,etime=,comm='],text=True).splitlines():
  fields=line.split(None,5)
  if len(fields)!=6 or fields[2].startswith('Z'):continue
  name=Path(fields[5]).name
  if name in ['xcodebuild','swift','swiftc','swift-frontend','swift-build','clang','clang++','cmake','ninja','make'] or name.startswith('clang-') or name.endswith('-Runner'):
   rows.append({'pid':int(fields[0]),'ppid':int(fields[1]),'state':fields[2],'cpu':fields[3],'elapsed':fields[4],'name':fields[5]})
 return rows
wait_start=time.monotonic()
while True:
 current=blockers();state.update(observedAt=utc(),capacityElapsedSeconds=time.monotonic()-wait_start,blockers=current);save()
 with (OUT/'capacity-observations.jsonl').open('a') as f:f.write(json.dumps({'utc':state['observedAt'],'blockers':current})+'\n')
 if not current:
  top=subprocess.check_output(['/usr/bin/top','-l','1','-n','0'],text=True)
  idle=float(re.search(r'([\d.]+)% idle',top).group(1));m=re.search(r'([\d.]+)([MGT]) unused',top);unused=float(m.group(1))*{'M':1,'G':1024,'T':1048576}[m.group(2)] if m else 0
  disk=os.statvfs(ROOT).f_bavail*os.statvfs(ROOT).f_frsize
  state['headroom']={'observedAt':utc(),'top':top,'cpuIdlePercent':idle,'physicalUnusedMiB':unused,'diskFreeBytes':disk};save()
  if idle>=20 and unused>=2048 and disk>15000000000 and not blockers():break
 if time.monotonic()-wait_start>=3500:state.update(status='CAPACITY_WAIT_EXPIRED',finishedAt=utc());save();raise SystemExit(2)
 time.sleep(30)
state.update(status='RUNNING',admittedAt=utc(),phase=None);save()
tasks=[
 ('node-manifest-upstream',['node','--test','Scripts/Audit/Tests/manifest-contracts.test.mjs','Scripts/MiniApps/Tests/upstream-resolution.test.mjs'],90),
 ('swift-expo-asset-analyzer',['xcrun','swift','test','--package-path','Packages/HanlinPlatform','--jobs','1','--filter','HanlinScriptAnalyzerTests/expoAssetPluginRequiresItsActualEmbeddedVersion'],1200)
]
try:
 for name,argv,timeout in tasks:
  pstate=json.loads((CTRL/'state.json').read_text());assert pstate['status']=='PAUSED_AFTER_PHASE' and pstate['source']==SOURCE
  remaining=12600-pstate['activeElapsedSeconds'];assert remaining>0
  log=OUT/(name+'.log');row={'name':name,'argv':argv,'startedAt':utc(),'status':'RUNNING','log':str(log),'timeout':min(timeout,remaining)}
  state['commands'].append(row);state['phase']=name;save();beg=time.monotonic()
  with log.open('wb') as stream:
   process=subprocess.Popen(argv,cwd=ROOT,env=env,stdout=stream,stderr=subprocess.STDOUT,start_new_session=True)
   row['pid']=process.pid;save()
   try:
    while True:
     elapsed=time.monotonic()-beg
     try:code=process.wait(timeout=min(30,max(.01,row['timeout']-elapsed)));break
     except subprocess.TimeoutExpired:
      row.update(elapsedSeconds=time.monotonic()-beg,logBytes=log.stat().st_size);save()
      if row['elapsedSeconds']>=row['timeout']:
       os.killpg(process.pid,signal.SIGTERM)
       try:process.wait(timeout=20)
       except subprocess.TimeoutExpired:os.killpg(process.pid,signal.SIGKILL);process.wait()
       code=-1;break
   except BaseException:
    if process.poll() is None:
     os.killpg(process.pid,signal.SIGTERM)
     try:process.wait(timeout=20)
     except subprocess.TimeoutExpired:os.killpg(process.pid,signal.SIGKILL);process.wait()
    raise
  row.update(status='PASS' if code==0 else 'FAIL',exitCode=code,finishedAt=utc(),elapsedSeconds=time.monotonic()-beg,logBytes=log.stat().st_size,logSHA256=digest(log))
  pstate=json.loads((CTRL/'state.json').read_text());assert pstate['status']=='PAUSED_AFTER_PHASE' and pstate['source']==SOURCE
  pstate['activeElapsedSeconds']+=row['elapsedSeconds'];pstate.setdefault('additionalRequiredProofs',[]).append({**row,'source':SOURCE})
  temp=CTRL/'state.json.tmp';temp.write_text(json.dumps(pstate,indent=2)+'\n');temp.replace(CTRL/'state.json');save()
  if code:raise RuntimeError(name+' failed, inspect '+str(log))
  text=log.read_text(errors='replace')
  if name=='node-manifest-upstream':
   assert re.search(r'pass\s+14\b',text) and re.search(r'fail\s+0\b',text) and re.search(r'skipped\s+0\b',text),'Expected14 original Node tests,0fail,0skip'
  else:
   assert 'Prepared Expo packages preserve the embedded original asset version contract' in text and 'Test run with 1 test passed' in text,'Expected actual one Swift test with all3 version cases'
 state.update(status='COMPANION_GATES_PASS',phase=None,finishedAt=utc());save()
except BaseException as error:
 state.update(status='FAIL',error=str(error),finishedAt=utc());save();raise
