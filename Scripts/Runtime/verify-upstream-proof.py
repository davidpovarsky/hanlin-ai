"""Read bounded known proof members from a digest-authenticated GitHub artifact; never extract."""
import io,json,sys,zipfile
archive=sys.stdin.buffer.read(16_777_217)
if len(archive)>16_777_216:raise SystemExit("Proof archive exceeds16MiB")
with zipfile.ZipFile(io.BytesIO(archive)) as bundle:
 def read(name,limit,optional=False):
  items=[item for item in bundle.infolist() if item.filename==name]
  if optional and not items:return None
  if len(items)!=1 or items[0].file_size>limit:raise SystemExit("Missing/duplicate/oversized proof member: "+name)
  value=bundle.read(items[0])
  if len(value)>limit:raise SystemExit("Proof member exceeds limit")
  return value.decode("utf-8")
 receipt=json.loads(read("candidate-receipt.json",65_536))
 if receipt.get("schemaVersion") not in (1,2):raise SystemExit("Unsupported receipt")
 entries=[]
 for stage in ["native-origin","host"]:
  capture=read(stage+"-context.json",65_536,True)
  entries.append({"stage":stage,"log":read(stage+".log",262_144,True),"capture":json.loads(capture) if capture else None})
 print(json.dumps({"receipt":receipt,"hostEntries":entries}))
