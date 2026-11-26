"""Additional evidence for the real compiled MiniApps bootstrap and UI processes.
The original native runner, selected methods and result verifiers remain unchanged.
"""
from pathlib import Path
import ast, hashlib, json, os, plistlib, re, subprocess, threading, time, datetime
def digest(path):
    h=hashlib.sha256()
    with Path(path).open("rb") as f:
        for b in iter(lambda:f.read(1024*1024),b""): h.update(b)
    return h.hexdigest()
class ImageAudit:
    def __init__(self,root,evidence,app):
        self.root=Path(root);self.e=Path(evidence);self.app=Path(app)
        self.out=self.e/"actual-image-origin";self.out.mkdir()
        export=self.root/"Scripts/ProductSplit/export_cross_app_simulator.py"
        defs=[n for n in ast.parse(export.read_text()).body if isinstance(n,ast.FunctionDef) and n.name in("digest","inventory")]
        ns={"hashlib":hashlib,"os":os,"Path":Path,"stat":__import__("stat")}
        assert len(defs)==2
        exec(compile(ast.Module(body=defs,type_ignores=[]),str(export),"exec"),ns)
        self.inventory=ns["inventory"];self.files=self.inventory(self.app)
        self.save("built-app-inventory.json",self.files)
        self.sim=None;self.stop=threading.Event();self.thread=None
        self.rows=[];self.errors=[];self.verified=set();self.cache={}
    def save(self,name,value):
        (self.e/name).write_text(json.dumps(value,indent=2)+"\n")
    def observe(self,pid,installed,raw,name,phase):
        installed=Path(installed);paths=set()
        for line in raw.splitlines():
            if line.startswith("__TEXT "):
                m=re.search(r"\s(/.*)$",line)
                if m:paths.add(m.group(1))
        assert paths,("No actual vmmap images",pid)
        private=[];foreign=[]
        for text in sorted(paths):
            p=Path(text);relative=None;location=None
            if p.is_relative_to(self.app):
                relative=p.relative_to(self.app).as_posix();location="CURRENT_VERIFIED_BUILT_APP"
            elif p.is_relative_to(installed):
                relative=p.relative_to(installed).as_posix();location="ACTUAL_INSTALLED_APP"
            if relative is not None:
                expected=self.files.get(relative)
                assert expected and expected.get("kind")=="file",("Unqualified private image",text)
                s=p.stat();key=(text,s.st_ino,s.st_mtime_ns,s.st_size)
                if key not in self.cache:self.cache[key]=digest(p)
                assert self.cache[key]==expected["sha256"],("Private image differs",text)
                private.append({"path":text,"manifest_relative_path":relative,"sha256":self.cache[key],"origin":location})
            elif text.startswith(("/System/","/usr/","/Library/Apple/","/Applications/Xcode.app/","/private/var/run/com.apple.security.cryptexd/","/var/run/com.apple.security.cryptexd/","/Library/Developer/CoreSimulator/Volumes/")):
                continue
            else:foreign.append(text)
        assert not foreign,("Foreign loaded image",foreign)
        assert any(x["manifest_relative_path"]=="HanlinMiniApps" for x in private)
        debug=[x for x in private if x["manifest_relative_path"]=="HanlinMiniApps.debug.dylib"]
        assert not debug or all(x["origin"]=="ACTUAL_INSTALLED_APP" for x in debug),("Debug metadata image outside installed main bundle",debug)
        full=bool(debug) and any(x["manifest_relative_path"]=="Frameworks/NativeScript.framework/NativeScript" for x in private)
        row={"utc":datetime.datetime.now(datetime.timezone.utc).isoformat(),"pid":pid,"phase":phase,"vmmap_file":name,"vmmap_sha256":digest(self.out/name),"full_original_runtime_presence":full,"private_images":private,"unqualified_images":foreign}
        self.rows.append(row)
        if full:self.verified.add(pid)
        with(self.out/"observations.jsonl").open("a") as f:f.write(json.dumps(row)+"\n")
        return full
    def launchctl_snapshot(self, argv, reason):
        # A failed transport query is not an image-integrity error. Retry only
        # a known interruption, retaining both attempts; fail closed if the
        # second call cannot establish a live snapshot of this same simulator.
        for attempt in (1, 2):
            try:
                result = subprocess.run(argv, capture_output=True, text=True, timeout=5)
                stdout = result.stdout
                raw = stdout + result.stderr
                returncode = result.returncode
                timed_out = False
            except subprocess.TimeoutExpired as failure:
                raw = (failure.stdout or b"") + (failure.stderr or b"")
                raw = raw.decode("utf-8", errors="replace")
                stdout, returncode, timed_out = "", None, True
            raw_sha = hashlib.sha256(raw.encode()).hexdigest()
            name = f"owned-launchctl-{raw_sha}.txt"
            raw_path = self.out / name
            if raw_path.exists():
                assert raw_path.read_text() == raw
            else:
                raw_path.write_text(raw)
            with (self.out / "owned-launchctl-attempts.jsonl").open("a") as stream:
                stream.write(json.dumps({
                    "reason": reason, "simulator_udid": self.sim, "attempt": attempt,
                    "returncode": returncode, "timed_out": timed_out,
                    "raw_file": name, "raw_sha256": raw_sha,
                }) + "\n")
            if returncode == 0:
                return stdout, name, raw_sha
            if attempt == 1 and (timed_out or returncode in (124, 143, -15)):
                self.stop.wait(0.25)
                continue
            raise RuntimeError(("Owned simulator process observation failed", returncode, name))
        raise AssertionError("Owned simulator process observation did not execute")

    def scoped_processes(self,reason):
        argv=["/usr/bin/xcrun","simctl","spawn",self.sim,"launchctl","list"]
        stdout, name, raw_sha = self.launchctl_snapshot(argv, reason)
        lines=stdout.splitlines()
        assert lines and lines[0].split()==["PID","Status","Label"],("Unexpected launchctl format",name)
        roles={"app":[],"ui_runner":[]}
        all_pids=set()
        for line in lines[1:]:
            if not line.strip():continue
            fields=line.split(None,2)
            assert len(fields)==3,("Malformed scoped process row",name,line)
            pid_text,status,label=fields
            assert pid_text=="-" or pid_text.isdigit(),("Malformed scoped PID",name,line)
            if pid_text=="-":continue
            pid=int(pid_text);all_pids.add(pid)
            if re.match(r"^UIKitApplication:com\.itorah\.hanlinminiapps(?:\[|$)",label):role="app"
            elif re.match(r"^UIKitApplication:com\.itorah\.hanlinminiapps\.integration\.uitests\.xctrunner(?:\[|$)",label):role="ui_runner"
            else:continue
            roles[role].append({"pid":pid,"label":label})
        row={"utc":datetime.datetime.now(datetime.timezone.utc).isoformat(),"reason":reason,"simulator_udid":self.sim,"argv":argv,"raw_file":name,"raw_sha256":raw_sha,"roles":roles}
        with(self.out/"owned-process-scopes.jsonl").open("a") as f:f.write(json.dumps(row)+"\n")
        return roles,all_pids
    def installed_app(self,pid):
        argv=["/usr/bin/xcrun","simctl","get_app_container",self.sim,"com.itorah.hanlinminiapps","app"]
        p=subprocess.run(argv,capture_output=True,text=True,timeout=5)
        name=f"installed-app-pid-{pid}.txt"
        (self.out/name).write_text(p.stdout+p.stderr)
        assert p.returncode==0,("Owned installed app query failed",pid,name)
        path=Path(p.stdout.strip())
        prefix=f"/CoreSimulator/Devices/{self.sim}/data/Containers/Bundle/Application/"
        assert prefix in str(path) and path.name=="HanlinMiniApps.app" and path.is_dir(),("Unexpected owned installed bundle",str(path))
        info=plistlib.loads((path/"Info.plist").read_bytes())
        assert info["CFBundleIdentifier"]=="com.itorah.hanlinminiapps"
        return path
    def capture(self,pid,installed,phase):
        name=f"pid-{pid}-{time.time_ns()}.vmmap.txt"
        p=subprocess.run(["/usr/bin/vmmap","-wide",str(pid)],capture_output=True,text=True,timeout=20)
        (self.out/name).write_text(p.stdout+p.stderr)
        if p.returncode:
            _,live=self.scoped_processes("vmmap_failure_liveness")
            if pid not in live:
                with(self.out/"terminated-before-capture.jsonl").open("a") as f:f.write(json.dumps({"pid":pid,"file":name,"exit":p.returncode})+"\n")
                return False
            raise RuntimeError(("Live own process vmmap failed",pid,p.returncode,name))
        return self.observe(pid,installed,p.stdout,name,phase)
    def bootstrap(self,sim,pid,installed):
        self.sim=sim
        roles,_=self.scoped_processes("bootstrap_admission")
        assert pid in {x["pid"] for x in roles["app"]},"Bootstrap PID absent from owned simulator launchd"
        assert self.installed_app(pid)==Path(installed),"Bootstrap installed bundle identity changed"
        for _ in range(10):
            if self.capture(pid,installed,"ORIGINAL_BOOTSTRAP"):return
            time.sleep(1)
        raise RuntimeError("Bootstrap never produced complete original runtime image proof")
    def loop(self):
        seen={};installed={}
        while not self.stop.wait(1):
            try:
                roles,_=self.scoped_processes("actual_ui_process_observation")
                # These are the actual owned simulator launchd records, not a host-wide
                # process scan. Native unit methods retain original instrumentation.
                if not roles["ui_runner"]:continue
                for process in roles["app"]:
                    pid=process["pid"]
                    if time.monotonic()-seen.get(pid,0)<(20 if pid in self.verified else 1):continue
                    seen[pid]=time.monotonic()
                    if pid not in installed:installed[pid]=self.installed_app(pid)
                    self.capture(pid,installed[pid],"ACTUAL_ORIGINAL_APP_UI")
            except Exception as ex:
                row={"utc":datetime.datetime.now(datetime.timezone.utc).isoformat(),"error":str(ex)}
                self.errors.append(row)
                with(self.out/"errors.jsonl").open("a") as f:f.write(json.dumps(row)+"\n")
    def start(self):
        self.thread=threading.Thread(target=self.loop,daemon=True);self.thread.start()
    def finish(self):
        self.stop.set()
        if self.thread:
            self.thread.join(30)
            assert not self.thread.is_alive(),"Image observer did not complete"
        assert self.inventory(self.app)==self.files,"Qualified built app changed during test-without-building"
        text=(self.e/"xcodebuild.log").read_text(errors="replace") if (self.e/"xcodebuild.log").exists() else ""
        pids=set(map(int,re.findall(r"com\.itorah\.hanlinminiapps:(\d+)",text)))
        for p in (self.e/"ui-attachments").glob("*.txt"):
            pids.update(map(int,re.findall(r"Application,\s*(?:0x[0-9a-fA-F]+,\s*)?pid:\s*(\d+),\s*label:\s*'Hanlin MiniApps'",p.read_text(errors="replace"))))
        ui_verified={row["pid"] for row in self.rows if row["phase"]=="ACTUAL_ORIGINAL_APP_UI" and row["full_original_runtime_presence"]}
        missing=sorted(pids-ui_verified)
        status="PASS" if pids and ui_verified and not self.errors and not missing else "IMAGE_ORIGIN_INCOMPLETE"
        result={"status":status,"scope":"Authentic shipping bootstrap and actual original-app UI processes; native unit methods retain original Apple test instrumentation and are classified separately.","referenced_ui_pids":sorted(pids),"complete_observed_pids":sorted(self.verified),"complete_observed_ui_pids":sorted(ui_verified),"missing_referenced_ui_pids":missing,"nonempty_ui_pid_sets_required":True,"observations":len(self.rows),"errors":self.errors,"all_built_app_entries_unchanged":True}
        self.save("actual-image-origin-result.json",result)
        return result
def create_bundled_ui_configuration(root,e,app,derived):
    products=Path(derived)/"Build/Products"
    originals=list(products.glob("HanlinMiniApps_*.xctestrun"));assert len(originals)==1,originals
    original=originals[0];raw=original.read_bytes();data=plistlib.loads(raw)
    assert {"HanlinMiniAppsTests","HanlinMiniAppsUITests","HanlinMiniAppsBootstrapTests"}.issubset(data)
    def resolve(v):
        if isinstance(v,str):return v.replace("__TESTROOT__",str(products))
        if isinstance(v,list):return [resolve(x) for x in v]
        if isinstance(v,dict):return {k:resolve(x) for k,x in v.items()}
        return v
    data=resolve(data)
    target=data["HanlinMiniAppsUITests"]
    assert Path(target["UITargetAppPath"])==Path(app)
    before=dict(target["UITargetAppEnvironmentVariables"]);after=dict(before)
    after["DYLD_FRAMEWORK_PATH"]=str(Path(app)/"Frameworks")
    after["__XPC_DYLD_FRAMEWORK_PATH"]=str(Path(app)/"Frameworks")
    after.pop("DYLD_LIBRARY_PATH",None);after.pop("__XPC_DYLD_LIBRARY_PATH",None)
    target["UITargetAppEnvironmentVariables"]=after
    e=Path(e);(e/"original-built.xctestrun").write_bytes(raw)
    output=e/"ActualBundledFull25.xctestrun";output.write_bytes(plistlib.dumps(data))
    changes={"source_configuration":str(original),"source_sha256":hashlib.sha256(raw).hexdigest(),"effective_configuration":str(output),"effective_sha256":digest(output),"change":"Resolve TESTROOT because the copy has a different directory; constrain only actual UI application framework lookup to its own verified bundled frameworks and remove target debug-library relocation overrides.","ui_environment_before":before,"ui_environment_after":after,"all_original_targets_retained":True,"native_unit_and_runner_environments_unchanged_after_path_resolution":True}
    (e/"actual-bundled-xctestrun-admission.json").write_text(json.dumps(changes,indent=2)+"\n")
    return output
