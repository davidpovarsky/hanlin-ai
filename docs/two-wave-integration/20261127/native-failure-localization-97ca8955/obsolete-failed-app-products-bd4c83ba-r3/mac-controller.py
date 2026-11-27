import pathlib,subprocess,json,os,time,stat,fcntl,hashlib,shutil,datetime
stage=pathlib.Path('/Users/m1/builds/hanlin-two-wave-root-20261126');source=stage/'source';dd=pathlib.Path('/Users/m1/caches/DerivedData/hanlin-two-wave-root-20261126')
e=stage/'cleanup/obsolete-failed-app-products-bd4c83ba-r3'
locks=[]
for path,mode in [('/Users/m1/caches/hanlin-two-wave-native-app.lock',fcntl.LOCK_EX),('/Users/m1/caches/.scaleway-cache-maintenance.lock',fcntl.LOCK_EX)]:
 f=open(path,'a+');fcntl.flock(f,mode|fcntl.LOCK_NB);locks.append(f)
def h(p):
 z=hashlib.sha256()
 with open(p,'rb') as f:
  for b in iter(lambda:f.read(1048576),b''):z.update(b)
 return z.hexdigest()
def git(*a):return subprocess.check_output(['git',*a],cwd=source,text=True).strip()
def free():return int(subprocess.check_output(['/bin/df','-k','/System/Volumes/Data'],text=True).splitlines()[-1].split()[3])*1024
assert git('rev-parse','HEAD')=='bd4c83baff2ed049a5a98aa0e0608f56f5a5cbcb'
assert git('status','--porcelain=v1','--untracked-files=no')==''
beforeLedger=stage/'cleanup/own-obsolete-app-cache-bd4c83ba-r1/before.json'
assert h(beforeLedger)=='c11e40afecb2092171f9fa97e396c7a44d5472539bab9fae822308dca8f4672f'
original=json.loads(beforeLedger.read_text());assert len(original['productsEntries'])==31047
targets=[dd/'Build/Products/Debug-iphonesimulator/AI_Hanlin.app',dd/'Build/Products/Debug-iphonesimulator/HanlinMiniApps.app']
expected=[57136093,57122270]
ps=subprocess.check_output(['/bin/ps','-axo','pid=,ppid=,comm=,args='],text=True)
assert not [x for x in ps.splitlines() if int(x.split()[0])!=os.getpid() and (str(dd) in x or str(stage) in x)], 'Other owned process still active'
ls=subprocess.run(['/usr/sbin/lsof','-nP','-F','pn'],text=True,stdout=subprocess.PIPE,stderr=subprocess.PIPE,timeout=8)
assert ls.returncode==0
opened=[x[1:] for x in ls.stdout.splitlines() if x.startswith('n')]
rows=[]
for p,ino in zip(targets,expected):
 st=p.lstat();assert st.st_uid==501 and st.st_ino==ino and not p.is_symlink()
 assert str(p.resolve())==str(p) and p.parent==dd/'Build/Products/Debug-iphonesimulator'
 assert not [x for x in opened if x==str(p) or x.startswith(str(p)+'/')]
 entries=[];allocated=st.st_blocks*512
 for d,ds,fs in os.walk(p):
  for n in ds+fs:
   q=pathlib.Path(d)/n;t=q.lstat()
   assert not n.endswith(('.dSYM','.ipa','.xcarchive','.xcresult')),str(q)
   assert t.st_uid==501
   entries.append({'path':str(q.relative_to(p)),'mode':t.st_mode,'bytes':t.st_size,'allocatedBytes':t.st_blocks*512,'mtimeNS':t.st_mtime_ns,'inode':t.st_ino})
   allocated+=t.st_blocks*512
 assert max([x['mtimeNS'] for x in entries]+[st.st_mtime_ns])<1795766338173069000,'Products changed since preserved ledger'
 rows.append({'path':str(p),'inode':ino,'allocatedBytes':allocated,'entries':entries})
protected=[source/'Packages/HanlinPlatform/.build',stage/'derived-data/platform-16b4af44/Build/Products']
protectedBefore={str(p):p.stat().st_ino for p in protected}
zipPath=source/'build/runtime-host-f768d634-original-phases-r1/RuntimeHostResources.zip'
zipHash=h(zipPath);assert zipHash=='fae9778f1b6548a069f6bd16bef3e2f22c710445a84d1fb025f4e90a5d1e1718'
before={'at':datetime.datetime.now(datetime.timezone.utc).isoformat(),'source':git('rev-parse','HEAD'),'freeBytes':free(),'originalPreservedLedgerSHA256':h(beforeLedger),'originalPreservedEntries':31047,'offHostPacket':'foundation-bookmark-and-capacity-bd4c83ba','targets':rows,'protectedInodes':protectedBefore,'hostZIP':str(zipPath),'hostZIP_SHA256':zipHash,'lsofCode':ls.returncode}
beforeBytes=(json.dumps(before,indent=2)+'\n').encode()
beforeHash=hashlib.sha256(beforeBytes).hexdigest()
import base64,sys
print(json.dumps({'beforeBase64':base64.b64encode(beforeBytes).decode(),'sha256':beforeHash}),flush=True)
assert sys.stdin.readline().strip()=='DURABLY_RETAINED:'+beforeHash,'Missing durable Oracle retention acknowledgement'
for p in targets:shutil.rmtree(p)
assert all(not p.exists() for p in targets)
e.mkdir(parents=True,exist_ok=False)
(e/'before.json').write_bytes(beforeBytes)
assert all(p.stat().st_ino==protectedBefore[str(p)] for p in protected)
assert h(zipPath)==zipHash and git('status','--porcelain=v1','--untracked-files=no')==''
after={'status':'OBSOLETE_FAILED_APP_BUNDLES_RETIRED','at':datetime.datetime.now(datetime.timezone.utc).isoformat(),'source':git('rev-parse','HEAD'),'removed':[{'path':x['path'],'allocatedBytes':x['allocatedBytes'],'entries':len(x['entries'])} for x in rows],'allocatedBytesRemoved':sum(x['allocatedBytes'] for x in rows),'freeBytesBefore':before['freeBytes'],'freeBytesAfter':free(),'protectedInodesUnchanged':True,'hostZIPUnchanged':True,'sourceClean':True,'beforeSHA256':h(e/'before.json'),'originalPreservedLedgerSHA256':h(beforeLedger),'boundary':'Only two explicitly authorized obsolete failed simulator app bundles removed. Existing source, .build, native79 products, xctestrun, archives, dSYMs, xcresults and signing retained. Observed free-space delta may include concurrent system changes.'}
(e/'result.json').write_text(json.dumps(after,indent=2)+'\n')
print(json.dumps({'receipt':str(e/'result.json'),'sha256':h(e/'result.json'),'result':after}))
