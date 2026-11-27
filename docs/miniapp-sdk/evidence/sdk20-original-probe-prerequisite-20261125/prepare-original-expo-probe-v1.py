#!/usr/bin/env python3
"""Run only the original missing Metro probe producer; no native build or test."""
from pathlib import Path
import argparse,datetime,fcntl,hashlib,importlib.util,json,math,os,signal,subprocess,sys,time
ID = "probe-fixture-sdk20-preparation-v1"
ROOT = Path("/Users/m1/builds/hanlin-notification-wire-fix-20261125")
SOURCE = "7f5dad540ade7fec6e5ace980eb99d1d6d0c2e8f"
TOTAL = 14400.0
PRIOR_SECONDS = 2501.629630375013
CAP = 600.0
PAIRED_CONTROLLER_SHA = "cef56339f3bc5f2491b4b941c50f3577a71ff84ba270627c354b159c8668646d"
PAIRED_DECISION_SHA = "f726a6f5053fa7d8743845cce7b1cea22e2b511864cd5916d5f7272733a5f944"
NODE = ROOT / "Tools/node-v24.5.0-darwin-arm64/bin/node"
NODE_SHA = "336b5b3ebc5deb86df842102b20b6e4761605b7a667823e68dda7761b91a161b"
PYTHON = Path("/opt/homebrew/opt/python@3.12/libexec/bin/python3")
PYTHON_SHA = "ab825fde913c394f6fb8dc57da39108ad98e1827a5404119993de3d3bc6d8fb7"
HOSTED = "AI_HLYTests/Fixtures/HostServicesProbe.bundle/ExpoSwiftUIProbeA.hanlinExpo"
OUTPUTS = (
    "Fixtures/ExpoWidgetsProbe/ExpoWidgetsProbeA.hanlinExpo",
    "Fixtures/ExpoWidgetsProbe/ExpoWidgetsProbeB.hanlinExpo",
    "AI_HLYUITests/Fixtures/ExpoWidgetsProbeA.hanlinExpo",
    "AI_HLYUITests/Fixtures/ExpoWidgetsProbeB.hanlinExpo",
    "Fixtures/ExpoSwiftUIProbe/ExpoSwiftUIProbeA.hanlinExpo",
    "Fixtures/ExpoSwiftUIProbe/ExpoSwiftUIProbeB.hanlinExpo",
    "Fixtures/ExpoSwiftUIProbe/ExpoSwiftUIProbe.hanlinExpo",
    "Fixtures/ExpoSwiftUIProbe/ExpoSwiftUIMalformed.hanlinExpo",
    "AI_HLYUITests/Fixtures/ExpoSwiftUIProbeA.hanlinExpo",
    "AI_HLYUITests/Fixtures/ExpoSwiftUIProbeB.hanlinExpo",
    "AI_HLYUITests/Fixtures/ExpoSwiftUIProbe.hanlinExpo",
    "AI_HLYUITests/Fixtures/ExpoSwiftUIMalformed.hanlinExpo",
    HOSTED,
)
def digest(path):
    h=hashlib.sha256()
    with Path(path).open("rb") as f:
        for chunk in iter(lambda:f.read(1024*1024),b""):h.update(chunk)
    return h.hexdigest()
def ref(path):
    path=Path(path)
    return {"path":str(path),"bytes":path.stat().st_size,"sha256":digest(path)}
def verified(row):
    p=Path(row["path"])
    assert p.is_file() and p.stat().st_size==row["bytes"] and digest(p)==row["sha256"],str(p)
    return p
def now():return datetime.datetime.now(datetime.timezone.utc).isoformat()
def write(path,value):
    tmp=path.with_name(path.name+".tmp")
    with tmp.open("w") as f:
        json.dump(value,f,indent=2);f.write("\n");f.flush();os.fsync(f.fileno())
    os.replace(tmp,path)
def git(*args):
    return subprocess.run(["git","-C",str(ROOT),*args],check=True,capture_output=True,timeout=15).stdout
def snapshots():
    rows=[]
    for name in OUTPUTS:
        p=ROOT/name
        assert not p.is_symlink() and p.resolve().is_relative_to(ROOT.resolve()),name
        rows.append({"relativePath":name,"exists":p.exists(),**(ref(p) if p.is_file() else {})})
    return rows
def main():
    parser=argparse.ArgumentParser();parser.add_argument("--decision",type=Path,required=True)
    args=parser.parse_args();raw=args.decision.read_bytes();d=json.loads(raw)
    assert d["schema"]==1 and d["status"]=="SEALED" and d["id"]==ID
    assert d["source"]==SOURCE and d["root"]==str(ROOT) and d["owner"]=="/root/native_execution"
    assert d["authorization"]["by"]=="/root"
    assert d["operationalCapSeconds"]==CAP and d["combinedAllowanceSeconds"]==TOTAL
    assert d["priorChargedSeconds"]==PRIOR_SECONDS and d["remainingBeforePreparationSeconds"]==TOTAL-PRIOR_SECONDS
    assert d["originalCommand"]==[str(NODE),"Scripts/Expo/build-probe.mjs"]
    assert d["expectedOutputPaths"]==list(OUTPUTS)
    assert verified(d["controller"])==Path(__file__).resolve()
    pc=verified(d["pairedController"]);assert digest(pc)==PAIRED_CONTROLLER_SHA
    pd=verified(d["pairedDecision"]);assert digest(pd)==PAIRED_DECISION_SHA
    previous=json.loads(verified(d["priorTerminal"]).read_text())
    previous_ledger=json.loads(verified(d["priorLedger"]).read_text())
    assert previous["id"]==previous_ledger["id"]=="paired52-sdk20-v1"
    assert previous["status"]==previous_ledger["status"]=="FAILED"
    assert previous["source"]==SOURCE and not previous["sourceErrors"] and not previous["cleanupErrors"]
    assert previous["remainingOwnedProcessGroup"]==[]
    assert previous["chargedSeconds"]==previous_ledger["chargedSeconds"]==PRIOR_SECONDS
    assert previous_ledger["allowanceSeconds"]==TOTAL and previous_ledger["decision"]["sha256"]==PAIRED_DECISION_SHA
    spec=importlib.util.spec_from_file_location("original_paired_sdk20_guards",pc)
    paired=importlib.util.module_from_spec(spec);spec.loader.exec_module(paired)
    parent_decision=json.loads(pd.read_text())
    for row in d["requiredFiles"]:verified(row)
    assert digest(NODE)==NODE_SHA and os.access(NODE,os.X_OK)
    assert digest(PYTHON)==PYTHON_SHA and Path(sys.executable).resolve()==PYTHON.resolve()
    assert str(PYTHON.resolve())==parent_decision["python"]["resolvedPath"]
    out=ROOT/"validation"/ID
    assert d["output"]==str(out) and not out.exists(),"One-shot output already exists; reconcile instead of replay"
    lock=(ROOT/"validation/.paired52-sdk20-owner.lock").open("a+")
    fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB)
    env=dict(os.environ);env.update(parent_decision["environment"])
    env["PATH"]=str(NODE.parent)+os.pathsep+str(PYTHON.parent)+os.pathsep+env["PATH"]
    out.mkdir();(out/"decision.json").write_bytes(raw)
    start=time.monotonic();proc=None
    state={"schema":1,"id":ID,"source":SOURCE,"status":"RUNNING","startedAt":now(),
           "controllerPID":os.getpid(),"childPID":None,"operationalCapSeconds":CAP,
           "combinedAllowanceSeconds":TOTAL,"priorChargedSeconds":PRIOR_SECONDS,
           "priorTerminal":d["priorTerminal"],"priorLedger":d["priorLedger"],
           "sourceErrors":[],"cleanupErrors":[],"remainingOwnedProcessGroup":[],
           "originalCommand":d["originalCommand"],"nativeBuildOrTestInvoked":False}
    def checkpoint():
        state["observedAt"]=now();state["observedActiveSeconds"]=time.monotonic()-start
        write(out/"state.json",state)
    def interrupted(signum,frame):raise InterruptedError("Probe preparation signal "+str(signum))
    signal.signal(signal.SIGINT,interrupted);signal.signal(signal.SIGTERM,interrupted)
    checkpoint()
    try:
        state["initialSource"]=paired.source_closure(parent_decision)
        assert state["initialSource"]==previous["finalSource"]==previous["initialSource"]
        state["outputsBefore"]=snapshots()
        state["node"]=json.loads(subprocess.check_output([str(NODE),"-p","JSON.stringify({version:process.version,platform:process.platform,arch:process.arch})"],env=env,text=True,timeout=10))
        assert state["node"]=={"version":"v24.5.0","platform":"darwin","arch":"arm64"}
        with (out/"original-build-probe.log").open("xb") as log:
            proc=subprocess.Popen(d["originalCommand"],cwd=ROOT,env=env,stdout=log,stderr=subprocess.STDOUT,start_new_session=True)
            state["childPID"]=proc.pid;checkpoint()
            while proc.poll() is None:
                remaining=min(CAP,TOTAL-PRIOR_SECONDS)-(time.monotonic()-start)
                if remaining<=0:raise TimeoutError("Original producer operational preparation cap exhausted")
                try:proc.wait(timeout=min(15.0,remaining))
                except subprocess.TimeoutExpired:checkpoint()
        state["exitCode"]=proc.returncode
        assert proc.returncode==0,"Original Metro probe producer failed"
        state["status"]="PREPARED"
    except BaseException as error:
        state["status"]="FAILED";state["error"]={"type":type(error).__name__,"message":str(error)}
    finally:
        signal.signal(signal.SIGINT,signal.SIG_IGN);signal.signal(signal.SIGTERM,signal.SIG_IGN)
        if proc is not None:
            try:
                for sig,seconds in [(signal.SIGINT,30),(signal.SIGTERM,20),(signal.SIGKILL,10)]:
                    if not paired.live_group(proc.pid):break
                    try:os.killpg(proc.pid,sig)
                    except ProcessLookupError:pass
                    until=time.monotonic()+seconds
                    while time.monotonic()<until:
                        if proc.poll() is None:
                            try:proc.wait(timeout=.5)
                            except subprocess.TimeoutExpired:pass
                        if not paired.live_group(proc.pid):break
                        time.sleep(.25)
                try:proc.wait(timeout=1)
                except subprocess.TimeoutExpired:pass
                state["exitCode"]=proc.poll();state["remainingOwnedProcessGroup"]=paired.live_group(proc.pid)
                assert not state["remainingOwnedProcessGroup"],"Owned producer process group remains"
            except BaseException as error:state["cleanupErrors"].append(repr(error))
        try:
            changes=git("diff","--name-only","HEAD","--").decode().splitlines()
            assert set(changes).issubset(set(OUTPUTS)-{HOSTED}),changes
            diff=git("diff","--binary","HEAD","--")
            (out/"prepared-tracked.patch").write_bytes(diff)
            state["preparedChanges"]=changes;state["preparedDiff"]=ref(out/"prepared-tracked.patch")
            adjusted=dict(parent_decision,preparedTrackedDiffSHA256=hashlib.sha256(diff).hexdigest())
            state["finalSource"]=paired.source_closure(adjusted)
            state["sourceClosureBoundary"]="Only the exact original producer archive paths above may change. All235 SDK inputs,15 consumer source files, native binaries, Host archive and index retain the original guard."
            state["outputsAfter"]=snapshots()
            if state["status"]=="PREPARED":
                assert all(row["exists"] for row in state["outputsAfter"]),"Original producer output missing"
                rows={row["relativePath"]:row for row in state["outputsAfter"]}
                assert rows[HOSTED]["sha256"]==rows["AI_HLYUITests/Fixtures/ExpoSwiftUIProbeA.hanlinExpo"]["sha256"]==rows["Fixtures/ExpoSwiftUIProbe/ExpoSwiftUIProbeA.hanlinExpo"]["sha256"]
                assert subprocess.run(["git","-C",str(ROOT),"check-ignore","-q",HOSTED],timeout=15).returncode==0
                assert subprocess.run(["git","-C",str(ROOT),"ls-files","--error-unmatch",HOSTED],capture_output=True,timeout=15).returncode==1
                state["hostedResource"]={k:rows[HOSTED][k] for k in ("path","bytes","sha256")}
                state["hostedResourceIgnoredUntracked"]=True
            for row in d["requiredFiles"]:verified(row)
            verified(d["controller"]);verified(d["priorTerminal"]);verified(d["priorLedger"])
        except BaseException as error:state["sourceErrors"].append(repr(error))
        if state["cleanupErrors"]:state["status"]="CLEANUP_INCOMPLETE"
        elif state["sourceErrors"]:state["status"]="SOURCE_CHANGED"
        elapsed=time.monotonic()-start;total=math.fsum([PRIOR_SECONDS,elapsed])
        state.update(finishedAt=now(),actualElapsedSeconds=elapsed,totalChargedSeconds=total,
                     remainingCombinedSeconds=max(0.0,TOTAL-total))
        charge={"id":ID,"source":SOURCE,"status":state["status"],"startedAt":state["startedAt"],"finishedAt":state["finishedAt"],"seconds":elapsed}
        ledger={"schema":1,"id":ID,"status":state["status"],"combinedAllowanceSeconds":TOTAL,
                "prior":{"authority":d["priorLedger"],"chargedSeconds":PRIOR_SECONDS},
                "currentCharge":charge,"totalChargedSeconds":total,"remainingSeconds":max(0.0,TOTAL-total),
                "overrunSeconds":max(0.0,total-TOTAL),"operationalCapSeconds":CAP,
                "decision":ref(out/"decision.json"),"priorLedgersModified":False,
                "accounting":"Actual one-time original probe preparation is charged once within the same14400 scope; the actual first failed full52 charge remains immutable."}
        write(out/"ledger.json",ledger);state["ledger"]=ref(out/"ledger.json")
        checkpoint();fcntl.flock(lock,fcntl.LOCK_UN);lock.close()
    return 0 if state["status"]=="PREPARED" else 1
if __name__=="__main__":raise SystemExit(main())
