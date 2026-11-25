"""Bounded evidence collection for the exact owned native diagnostic; no source mutation."""
from pathlib import Path
import datetime,hashlib,json,plistlib,struct,subprocess,threading,time,shutil
def utc():return datetime.datetime.now(datetime.timezone.utc).isoformat()
def sha(data):return hashlib.sha256(data).hexdigest()
def append(path,value):
 with path.open("a") as f:f.write(json.dumps(value)+"\n");f.flush()
def metadata_sections(binary):
 rows=[]
 with binary.open("rb") as stream:
  header=stream.read(32)
  if len(header)!=32 or struct.unpack("<I",header[:4])[0]!=0xfeedfacf:return rows
  commands=struct.unpack("<IiiIIIII",header)[4];offset=32
  for _ in range(commands):
   stream.seek(offset);cmd,size=struct.unpack("<II",stream.read(8))
   if size<8:raise RuntimeError("Invalid Mach-O load command")
   if cmd==0x19:
    stream.seek(offset);data=stream.read(size);count=struct.unpack_from("<I",data,64)[0]
    for i in range(count):
     section=72+i*80;name=data[section:section+16].split(b"\0")[0]
     if name==b"__TNSMetadata":
      length=struct.unpack_from("<Q",data,section+40)[0];position=struct.unpack_from("<I",data,section+48)[0]
      stream.seek(position);raw=stream.read(length)
      if len(raw)!=length:raise RuntimeError("Truncated installed metadata section")
      rows.append({"binary":str(binary),"offset":position,"bytes":length,"sha256":sha(raw),
       "requiredNames":{name:(name.encode()+b"\0") in raw for name in ["TNSLabel","NSCCrypto","UIView","HanlinNativeServicesBridge"]}})
   offset+=size
 return rows
def bind_metadata(root,out,derived,simulator,source):
 report={"observedAt":utc(),"source":source,"products":[]}
 for bundle,filename in [("com.itorah.hanlinminiapps","HanlinMiniApps.app"),("com.itorah.chavrusachat","AI_Hanlin.app")]:
  probe=subprocess.run(["xcrun","simctl","get_app_container",simulator,bundle,"app"],capture_output=True,text=True,timeout=10,check=True)
  installed=Path(probe.stdout.strip())
  if not installed.is_relative_to(Path.home()/"Library/Developer/CoreSimulator/Devices"/simulator):
   raise RuntimeError("Installed metadata proof escaped owned simulator")
  product={"bundle":bundle,"built":str(derived/filename),"installed":str(installed),"binaries":[]}
  info=plistlib.loads((installed/"Info.plist").read_bytes());executable=info["CFBundleExecutable"]
  for name in [executable,executable+".debug.dylib"]:
   current=installed/name;built=derived/filename/name
   if not current.is_file():continue
   with current.open("rb") as f:current_sha=hashlib.file_digest(f,"sha256").hexdigest()
   with built.open("rb") as f:built_sha=hashlib.file_digest(f,"sha256").hexdigest()
   if current_sha!=built_sha:raise RuntimeError("Installed native binary differs from completed build: "+bundle+"/"+name)
   product["binaries"].append({"name":name,"bytes":current.stat().st_size,"sha256":current_sha,"metadata":metadata_sections(current)})
  found=[item for binary in product["binaries"] for item in binary["metadata"]]
  if not found or not all(all(item["requiredNames"].values()) for item in found):
   raise RuntimeError("Original Core metadata classes absent in actual installed product: "+bundle)
  report["products"].append(product)
 destination=out/"installed-metadata-binding.json";destination.write_text(json.dumps(report,indent=2)+"\n")
 return {"path":destination.name,"sha256":sha(destination.read_bytes()),"requiredNamesPresent":True}
class Observer:
 def __init__(self,root,out,simulator,container,host_digest,current_case):
  self.root=root;self.out=out;self.simulator=simulator;self.container=container;self.host_digest=host_digest;self.current_case=current_case
  self.stop_event=threading.Event();self.sample_taken=False;self.process=None;self.thread=None
 def start(self):
  predicate='process == "HanlinMiniApps" AND (eventMessage CONTAINS "HANLIN_" OR eventMessage CONTAINS "NativeScript" OR eventMessage CONTAINS "runtime_paths" OR eventMessage CONTAINS "host_ready")'
  with (self.out/"runtime-logstream.jsonl").open("wb") as stdout,(self.out/"runtime-logstream.stderr").open("wb") as stderr:
   self.process=subprocess.Popen(["xcrun","simctl","spawn",self.simulator,"log","stream","--style","ndjson","--level","debug","--predicate",predicate],
    stdout=stdout,stderr=stderr,stdin=subprocess.DEVNULL,start_new_session=True)
  self.receipt={"pid":self.process.pid,"predicate":predicate,"startedAt":utc(),"sampleLimit":1,"sampleDurationSeconds":3,"persistentBeginBeforeSampleSeconds":2,"terminalMarkers":["HANLIN_NS_RUN_MAIN_OK","HANLIN_NS_RUN_MAIN_DONE","HANLIN_NS_SHUTDOWN"]}
  self.thread=threading.Thread(target=self.run,daemon=True);self.thread.start()
  return self.receipt.copy()
 def stop(self):
  self.stop_event.set()
  if self.thread:self.thread.join(timeout=18)
  if self.process:
   if self.process.poll() is None:
    self.process.terminate()
    try:self.process.wait(timeout=10)
    except subprocess.TimeoutExpired:self.process.kill();self.process.wait()
   self.receipt.update(exitCode=self.process.returncode,reaped=True,finishedAt=utc(),observerStopped=not self.thread.is_alive(),sampleTaken=self.sample_taken)
  return self.receipt.copy()
 def sample(self,pid,event):
  if self.sample_taken:return
  result=subprocess.run(["ps","-p",str(pid),"-o","command="],capture_output=True,text=True,timeout=5)
  command=result.stdout.strip()
  if "/Devices/"+self.simulator+"/" not in command or "/HanlinMiniApps.app/" not in command:return
  self.sample_taken=True;dest=self.out/"parity-run-main-owned-app-sample.txt"
  record={"observedAt":utc(),"pid":pid,"command":command,"trigger":event,"durationSeconds":3,"activeCase":self.current_case()}
  (self.out/"parity-sample-start.json").write_text(json.dumps(record,indent=2)+"\n")
  try:
   result=subprocess.run(["sample",str(pid),"3","1","-file",str(dest)],capture_output=True,text=True,timeout=12)
   record.update(exitCode=result.returncode,finishedAt=utc(),stderr=result.stderr[-2000:])
   if dest.exists():record.update(bytes=dest.stat().st_size,sha256=sha(dest.read_bytes()))
  except Exception as error:record.update(error=str(error),finishedAt=utc())
  (self.out/"parity-sample-result.json").write_text(json.dumps(record,indent=2)+"\n")
 def run(self):
  seen={};ready_seen={};current=self.container;last_refresh=0;log_offset=0;partial=b"";run_main={}
  while not self.stop_event.is_set():
   try:
    if time.monotonic()-last_refresh>=5:
     last_refresh=time.monotonic()
     probe=subprocess.run(["xcrun","simctl","get_app_container",self.simulator,"com.itorah.hanlinminiapps","data"],capture_output=True,text=True,timeout=5)
     if probe.returncode==0:
      actual=Path(probe.stdout.strip()).resolve()
      boundary=Path.home()/"Library/Developer/CoreSimulator/Devices"/self.simulator/"data/Containers/Data/Application"
      if not actual.is_relative_to(boundary):raise RuntimeError("Observed data container escaped owned simulator")
      if actual!=current:
       append(self.out/"container-observations.jsonl",{"observedAt":utc(),"old":str(current),"actual":str(actual),"simulator":self.simulator,"activeCase":self.current_case()})
       current=actual
    ready=current/"Library/Application Support/HanlinRuntime/v1/runtime/node"/("host-"+self.host_digest)/".ready"
    readiness={"exists":ready.is_file(),"hostSHA256":self.host_digest}
    if ready.is_file():
     stat=ready.stat();readiness.update(bytes=stat.st_size,mtimeNs=stat.st_mtime_ns,birthtime=getattr(stat,"st_birthtime",None),sha256=sha(ready.read_bytes()))
    signature=json.dumps(readiness,sort_keys=True);key=(str(current),self.current_case())
    if ready_seen.get(key)!=signature:
     ready_seen[key]=signature
     append(self.out/"host-ready-observations.jsonl",{"observedAt":utc(),"container":str(current),"path":str(ready),"activeCase":self.current_case(),**readiness})
    jobs=current/"Library/Application Support/HanlinRuntime/v1/jobs"
    for path in sorted(jobs.glob("*/*/job.json")):
     raw=path.read_bytes();digest=sha(raw);key=str(path)
     if seen.get(key)==digest:continue
     seen[key]=digest;doc=json.loads(raw)
     append(self.out/"node-job-observations.jsonl",{"observedAt":utc(),"container":str(current),"path":key,"sha256":digest,"bytes":len(raw),"activeCase":self.current_case(),"job":doc})
     destination=self.out/"observed-jobs"/current.name/path.parent.parent.name/path.parent.name
     destination.mkdir(parents=True,exist_ok=True);(destination/"job.json").write_bytes(raw)
     for source in path.parent.iterdir():
      if source.is_file() and source.name!="job.json" and source.stat().st_size<=2000000:shutil.copy2(source,destination/source.name)
    log=self.out/"runtime-logstream.jsonl"
    if log.exists():
     with log.open("rb") as stream:stream.seek(log_offset);data=stream.read(2*1024*1024);log_offset=stream.tell()
     chunks=(partial+data).split(b"\n");partial=chunks.pop()
     for line in chunks:
      try:event=json.loads(line)
      except ValueError:continue
      message=str(event.get("eventMessage",""));pid=event.get("processID")
      if not isinstance(pid,int):continue
      if "HANLIN_NS_RUN_MAIN_BEGIN" in message:run_main[pid]={"status":"BEGIN","observedMonotonic":time.monotonic(),"event":event}
      if any(token in message for token in ["HANLIN_NS_RUN_MAIN_OK","HANLIN_NS_RUN_MAIN_DONE","HANLIN_NS_SHUTDOWN"]):run_main[pid]={"status":"DONE"}
     # Inspect the whole available batch before considering a sample. Fast successful
     # module startup must not trigger a sample merely because BEGIN precedes OK.
     if self.current_case()=="ParityStartupDiagnostic" and not self.sample_taken:
      for pid,entry in run_main.items():
       if entry["status"]=="BEGIN" and time.monotonic()-entry["observedMonotonic"]>=2:
        self.sample(pid,entry["event"]);break
   except Exception as error:append(self.out/"job-observation-errors.jsonl",{"observedAt":utc(),"error":str(error)})
   self.stop_event.wait(1)
