"""Current SDK20 original five-runtime NativeScript companion.
The selected original function, xcodebuild argv and original result verifier remain unchanged.
This new1200s phase keeps whole-run and historical accounting separate.
"""
from pathlib import Path
from types import SimpleNamespace
import argparse
import datetime
import fcntl
import hashlib
import importlib.util
import json
import math
import os
import plistlib
import signal
import subprocess
import sys
import time
import uuid

ID = "nativescript-five-sdk20-v1"
GATE = "nativescript-five"
ALLOWANCE = 1200
PAIRED_ID = "paired52-sdk20-v2"
PAIRED_CONTROLLER_SHA = "a9040dd634acfe7d1d01d6f477771f9033ab305cde9576b1b5d5ad6423726bcb"
PAIRED_DECISION_SHA = "10e76a4916899f9345cb30421cc4b84566b1cf2b0f054005c70e80c52dce5928"
HOST_SHA = "ed18d93a88a1020bc2140417cea3847daf3d03472cdd4769d9a5ac4e44f48a22"
ROOT = Path("/Users/m1/builds/hanlin-notification-wire-fix-20261125")
SOURCE = "7f5dad540ade7fec6e5ace980eb99d1d6d0c2e8f"
SDK_SOURCE = "dff3b45c99a57bf8fe8ec721db3fa1fafce7134b"
PRODUCTS = Path("/Users/m1/caches/DerivedData/hanlin-notification-wire-fix-20261125/Build/Products")
SELECTOR = "AI_HLYTests/HanlinUnifiedHostServicesE2ETests/actualNativeScriptImportsTheGeneratedTypedFacadeAndCallsEveryEngine()"
WORKER = "Scripts/CI/observe_notification_os_delivery.py"
WORKER_SHA = "f6cf4e040f592fa94ebf9fd813b6e03d125d5c7c32dc2d2a43f3b42cdb33d085"
RUNNER = "Scripts/ProductSplit/run_paired_acceptance.py"
RUNNER_SHA = "a99b6194f8dd20bc30998ff2ad9e86ec219415a00615b250c65670f7dfcdba7d"
ACTIONS = "Fixtures/Widgets/Hanlin-ScriptWidget-Actions.scripting"
ACTIONS_SHA = "33c717e2a454d8831364cb24b15b9e9e799cd3161b526013a15efe46485ebccb"
PRODUCT_ID = "com.itorah.hanlinminiapps"
GROUP = "group.com.itorah.chavrusachat"
HISTORICAL_OS_SECONDS = math.fsum([353.58866224999656, 12.940106750000268, 530.7739816670073])
HISTORICAL_RECOVERY_OS_SECONDS = 233.90022650000174
HISTORICAL_PRIMARY_SECONDS = 25438.734638920043
RESOURCE_BOUND = 5679053931


def digest(path):
    h = hashlib.sha256()
    with Path(path).open("rb") as stream:
        for b in iter(lambda: stream.read(1024 * 1024), b""):
            h.update(b)
    return h.hexdigest()

def load_module(path, name):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module

def utc():
    return datetime.datetime.now(datetime.timezone.utc).isoformat()

def write(path, value):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(path.name + ".tmp")
    with temporary.open("w") as stream:
        stream.write(json.dumps(value, indent=2, ensure_ascii=False) + "\n")
        stream.flush()
        os.fsync(stream.fileno())
    temporary.replace(path)

def relative(root, value):
    path = (root / value).resolve()
    assert path.is_relative_to(root), value
    return path

def run(argv, **kwargs):
    result = subprocess.run(argv, capture_output=True, text=True, check=True, **kwargs)
    return result.stdout.strip()

def verify_file(row, root=None):
    path = relative(root, row["path"]) if root is not None else Path(row["path"])
    assert path.is_file() and not path.is_symlink(), str(path)
    assert path.stat().st_size == row["bytes"] and digest(path) == row["sha256"], str(path)
    return path

def read_decision(path):
    raw = path.read_bytes()
    d = json.loads(raw)
    assert d["schema"] == 1 and d["status"] == "SEALED" and d["id"] == ID and d["gate"] == GATE
    assert d["owner"] == "/root/native_execution" and d["authorization"]["by"] == "/root"
    assert Path(d["root"]) == ROOT and ROOT.is_dir() and ROOT == ROOT.resolve()
    assert d["source"] == d["compiledConsumerSource"] == SOURCE and d["SDKProducerSource"] == SDK_SOURCE
    assert d["selector"] == SELECTOR and d["expectedTests"] == 1 and d["allowanceSeconds"] == ALLOWANCE
    assert d["outputDirectory"] == "validation/" + ID and d["resourceBoundBytes"] == RESOURCE_BOUND
    assert d["derivedData"] == str(PRODUCTS.parent.parent)
    assert d["pairedController"]["sha256"] == PAIRED_CONTROLLER_SHA
    assert d["pairedDecision"]["sha256"] == PAIRED_DECISION_SHA
    for row in d["sourceFiles"]:
        verify_file(row, ROOT)
    assert {row["path"]: row["sha256"] for row in d["sourceFiles"]}[RUNNER] == RUNNER_SHA
    if GATE == "notification-os":
        assert {row["path"]: row["sha256"] for row in d["sourceFiles"]}[WORKER] == WORKER_SHA
        assert len(d["fixtures"]) == 3
        assert d["stagedFiles"] == [{k: row[k] for k in ("name", "bytes", "sha256")} for row in d["fixtures"] if row["name"] != Path(ACTIONS).name]
        for row in d["fixtures"]:
            assert Path(row["sourcePath"]).is_relative_to(ROOT)
            verify_file({"path": row["sourcePath"], "bytes": row["bytes"], "sha256": row["sha256"]})
    controller = verify_file(d["controller"])
    assert controller == Path(__file__).resolve() == ROOT / "validation" / (ID + ".py")
    return raw, d, ROOT, SimpleNamespace(relative=relative, write=write, utc=utc, run=run)

def current_authority(d):
    # Use the already reviewed whole-run source guard, not a reconstructed historical checkout.
    paired_controller = verify_file(d["pairedController"])
    paired = load_module(paired_controller, "current_paired_sdk20_authority")
    paired_decision = json.loads(verify_file(d["pairedDecision"]).read_text())
    terminal = json.loads(verify_file(d["pairedTerminal"]).read_text())
    ledger = json.loads(verify_file(d["pairedLedger"]).read_text())
    assert terminal["id"] == ledger["id"] == paired_decision["id"] == PAIRED_ID
    assert terminal["source"] == paired_decision["source"] == SOURCE
    assert terminal["status"] == ledger["status"] == terminal["result"]["status"] == "EXECUTED_PASS"
    assert terminal["result"]["mini"] == {"passed": 25, "failed": 0, "skipped": 0}
    assert terminal["result"]["ai"] == {"passed": 27, "failed": 0, "skipped": 0}
    assert not terminal["sourceErrors"] and not terminal["cleanupErrors"] and not terminal["remainingOwnedProcessGroup"]
    prior_scope, paired_allowance = paired.continuation_scope(paired_decision)
    assert ledger["chargedSeconds"] == terminal["chargedSeconds"]
    assert ledger["allowanceSeconds"] == terminal["allowanceSeconds"] == paired_allowance
    assert ledger["scopeHistory"] == terminal["scopeHistory"] == prior_scope
    assert ledger["combinedAllowanceSeconds"] == terminal["combinedAllowanceSeconds"] == paired_decision["combinedAllowanceSeconds"] == 14400
    assert ledger["priorChargedSeconds"] == terminal["priorChargedSeconds"] == paired_decision["priorChargedSeconds"]
    assert ledger["totalChargedSeconds"] == terminal["totalChargedSeconds"] == math.fsum([ledger["priorChargedSeconds"], ledger["chargedSeconds"]])
    assert ledger["decision"]["sha256"] == PAIRED_DECISION_SHA
    for proof in terminal["result"]["proofs"]:
        verify_file(proof)
    closure = paired.source_closure(paired_decision)
    assert closure == terminal["initialSource"] == terminal["finalSource"]
    evidence = ROOT / "validation" / PAIRED_ID / "original/paired-product"
    ownership = verify_file(d["simulatorOwnership"])
    assert ownership == evidence / "created-simulator.txt"
    device = str(uuid.UUID(ownership.read_text().strip())).upper()
    assert terminal["ownedSimulator"] == d["simulator"] and terminal["ownedSimulator"]["state"] == "Shutdown"
    assert terminal["ownedSimulator"]["udid"].upper() == device
    current = paired.created_device(evidence)
    assert current["udid"].upper() == device and current["state"] == "Shutdown" and current["isAvailable"] is True
    built = json.loads(verify_file(d["builtInputs"]).read_text())
    metadata = json.loads(verify_file(d["productMetadata"]).read_text())
    assert built["source"] == built["miniBuildProducerSource"] == built["aiBuildProducerSource"] == metadata["source"] == SOURCE
    assert built["SDKProducerSource"] == SDK_SOURCE and built["originalTestBuilds"] == "PASS"
    assert built["hostArchiveSHA256"] == HOST_SHA and metadata["builtInputBindings"]["sha256"] == d["builtInputs"]["sha256"]
    products = [{"path": x["path"], "bytes": x["size"], "sha256": x["sha256"]} for x in built["files"]]
    products += [{k: x[k] for k in ("path", "bytes", "sha256")} for x in metadata["files"]]
    assert products == d["productFiles"]
    for product in products:
        path = Path(product["path"])
        assert path.is_relative_to(PRODUCTS) and path.resolve().is_relative_to(PRODUCTS)
        verify_file(product)
        if path.name == "RuntimeHostResources.zip":
            assert product["sha256"] == HOST_SHA
    roles = {x["role"]: x for x in metadata["files"]}
    assert set(roles) == {"aiXctestrun", "miniXctestrun", "uiRunnerInfo", "uiRunnerExecutable"}
    if GATE == "notification-os":
        assert d["directArtifactObservation"] == {"kind": "UNCHANGED_PREBUILT_XCTESTRUN", "xctestrun": {k: roles["miniXctestrun"][k] for k in ("path", "bytes", "sha256")}}
        assert d["uiRunnerInfoPlist"] == roles["uiRunnerInfo"]["path"]
    history = list(paired_decision["componentHistory"])
    for component in history:
        verify_file(component["authority"])
    history.extend({**row, "accountingRelation": "Actual earlier charge within the original14400 whole-run scope, retained once; not charged to this new companion ledger."}
                   for row in prior_scope)
    history.append({"id": PAIRED_ID, "seconds": ledger["chargedSeconds"], "authority": d["pairedLedger"],
                    "accountingRelation": "Separate actual current original full52 run. Not charged again to this new companion ledger."})
    if GATE == "notification-os":
        ns = json.loads(verify_file(d["priorNativeScript"]["state"]).read_text())
        ns_ledger = json.loads(verify_file(d["priorNativeScript"]["ledger"]).read_text())
        assert ns["id"] == ns_ledger["id"] == "nativescript-five-sdk20-v1"
        assert ns["source"] == SOURCE and ns["status"] == ns_ledger["status"] == "EXECUTED_PASS"
        assert not ns["sourceErrors"] and not ns["cleanupErrors"] and not ns["remainingOwnedProcessGroup"]
        assert ns_ledger["chargedSeconds"] == ns["chargedSeconds"] and ns_ledger["allowanceSeconds"] == 1200
        review = json.loads(verify_file(ns["resultReview"]).read_text())
        assert review["status"] == "EXECUTED_PASS" and review["expectedTests"] == 1
        assert review["summary"]["passedTests"] == 1 and review["summary"].get("failedTests", 0) == review["summary"].get("skippedTests", 0) == 0
        history.append({"id": ns["id"], "seconds": ns["chargedSeconds"], "authority": d["priorNativeScript"]["ledger"],
                        "accountingRelation": "Separate actual current NativeScript five-runtime case. Not charged again to the new OS ledger."})
    return paired, paired_decision, terminal, ledger, history

def original_runner(root, evidence):
    sys.path.insert(0, str(root / "Scripts/ProductSplit"))
    previous_evidence = os.environ.get("SPLIT_EVIDENCE")
    os.environ["SPLIT_EVIDENCE"] = str(evidence)
    try:
        r = load_module(root / RUNNER, "original_paired_for_notification_os")
    finally:
        if previous_evidence is None:
            os.environ.pop("SPLIT_EVIDENCE", None)
        else:
            os.environ["SPLIT_EVIDENCE"] = previous_evidence
    r.EVIDENCE = evidence
    return r

def live_group(pgid):
        pgid = int(pgid)
        assert pgid > 1
        try:
            os.killpg(pgid, 0)
        except ProcessLookupError:
            return []
        candidates = subprocess.run(["/usr/bin/pgrep", "-g", str(pgid)],
                                    text=True, capture_output=True, timeout=10)
        assert candidates.returncode == 0 or (candidates.returncode == 1 and not candidates.stdout.strip() and not candidates.stderr.strip()), candidates.stderr
        pids = candidates.stdout.split()
        if not pids:
            return []
        assert all(pid.isdigit() and int(pid) > 1 for pid in pids)
        query = subprocess.run(["/bin/ps", "-p", ",".join(pids), "-o", "pid=,pgid=,state="],
                               text=True, capture_output=True, timeout=10)
        assert query.returncode == 0 or (query.returncode == 1 and not query.stdout.strip() and not query.stderr.strip()), query.stderr
        return [line for line in query.stdout.splitlines() if len(v := line.split()) == 3
                and v[0] in pids and v[1] == str(pgid) and not v[2].startswith("Z")]

def native_child(decision_path):
    _, d, root, h = read_decision(decision_path)
    out = h.relative(root, d["outputDirectory"])
    evidence = out / "native-result"
    assert evidence.is_dir()
    sys.path.insert(0, str(root / "Scripts/ProductSplit"))
    runner = original_runner(root, evidence)
    runner.EVIDENCE = evidence
    device = str(uuid.UUID(d["simulator"]["udid"])).upper()
    _, raw = runner.command(["xcrun", "simctl", "list", "devices", "-j"], "devices-before.json")
    devices = [x for values in json.loads(raw)["devices"].values() for x in values
               if x["udid"].upper() == device]
    assert len(devices) == 1 and devices[0]["state"] in ("Booted", "Shutdown")
    if devices[0]["state"] == "Shutdown":
        runner.command(["xcrun", "simctl", "boot", device], "boot-retained-owned-simulator.log")
    runner.command(["xcrun", "simctl", "bootstatus", device, "-b"], "bootstatus.log", timeout=300)
    # Exactly the original base/options, including its external600s case cap.
    # The selected original function's internal120s deadline is unchanged.
    argv = ["xcodebuild", "-project", "AI_HLY.xcodeproj",
            "-destination", "platform=iOS Simulator,id=" + device,
            "-parallel-testing-enabled", "NO", "-derivedDataPath", d["derivedData"],
            "-clonedSourcePackagesDirPath", str(root / "build/SourcePackages"),
            "-skipPackagePluginValidation", "-skipMacroValidation",
            "CODE_SIGNING_ALLOWED=YES", "CODE_SIGNING_REQUIRED=YES", "CODE_SIGN_IDENTITY=-",
            "-collect-test-diagnostics", "never", "-scheme", "AI_HLY", "test-without-building",
            "-resultBundlePath", str(evidence / "NS5.xcresult"),
            "-test-timeouts-enabled", "YES", "-maximum-test-execution-time-allowance", "600",
            "-only-testing:" + SELECTOR]
    h.write(evidence / "selected-command.json", {"argv": argv, "selector": SELECTOR,
            "expectedTests": 1, "runnerSHA256": RUNNER_SHA, "source": d["source"],
            "boundary": "Selected companion only; never changes original52 status"})
    code, _ = runner.command(argv, "ns5-tests.log", timeout=2100, allow_failure=True)
    result = evidence / "NS5.xcresult"
    assert (result / "Info.plist").is_file(), "Actual xcresult must be finalized"
    summary = runner.verify_native_result(result, "ns5", [SELECTOR], 1, code)
    h.write(evidence / "result-review.json", {"status": "EXECUTED_PASS", "source": d["source"],
            "selector": SELECTOR, "expectedTests": 1, "summary": summary,
            "commandExitCode": code, "resultBundle": str(result),
            "resultInfoSHA256": digest(result / "Info.plist"),
            "summarySHA256": digest(evidence / "ns5-summary.json"),
            "nodesSHA256": digest(evidence / "ns5-nodes.json"),
            "selectorVerifierLogSHA256": digest(evidence / "ns5-selected-tests.log"),
            "reviewedAt": h.utc(), "original52Status": "UNCHANGED_BY_COMPANION"})
    return 0

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--decision", type=Path, required=True)
    parser.add_argument("--native-child", action="store_true")
    args = parser.parse_args()
    decision_path = args.decision.resolve()
    if args.native_child:
        return native_child(decision_path)
    raw, d, root, h = read_decision(decision_path)
    out = relative(root, d["outputDirectory"])
    assert not out.exists(), "One-shot current case: retain any existing output for reconciliation"
    lock = (root / "validation/native-owner.lock").open("a")
    fcntl.flock(lock.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
    paired, paired_decision, paired_terminal, paired_ledger, history = current_authority(d)
    device = str(uuid.UUID(d["simulator"]["udid"])).upper()
    vfs = os.statvfs(root)
    free = vfs.f_bavail * vfs.f_frsize
    assert free >= RESOURCE_BOUND
    env = dict(os.environ)
    env.update(paired_decision["environment"])
    env["PATH"] = str(ROOT / "Tools/node-v24.5.0-darwin-arm64/bin") + os.pathsep + str(paired.PYTHON.parent) + os.pathsep + env["PATH"]
    assert Path(sys.executable).resolve() == Path(paired_decision["python"]["resolvedPath"])
    env.update(GITHUB_WORKSPACE=str(root), GITHUB_SHA=SOURCE, SPLIT_EVIDENCE=str(out),
               SPLIT_DERIVED_DATA=d["derivedData"], PAIRED_TEST_SCOPE="miniapp_complete")
    out.mkdir()
    (out / "native-result").mkdir()
    frozen = out / "decision.json"
    frozen.write_bytes(raw)
    (out / "paired-state-before.json").write_bytes(Path(d["pairedTerminal"]["path"]).read_bytes())
    write(out / "execution-environment.json", {"perRun": {k: env[k] for k in
        ("DEVELOPER_DIR", "RUNNER_TEMP", "GITHUB_WORKSPACE", "GITHUB_SHA", "SPLIT_EVIDENCE", "SPLIT_DERIVED_DATA", "PAIRED_TEST_SCOPE", "PATH")},
        "python": sys.executable, "producerInvocation": "NONE", "originalCommandLimitsUnchanged": True})
    started = time.monotonic()
    state = {"schema": 1, "id": ID, "source": SOURCE, "compiledConsumerSource": SOURCE,
             "SDKProducerSource": SDK_SOURCE, "status": "RUNNING", "startedAt": utc(),
             "selector": SELECTOR, "expectedTests": 1, "allowanceSeconds": ALLOWANCE,
             "controllerPID": os.getpid(), "childPID": None, "sourceErrors": [], "cleanupErrors": [],
             "remainingOwnedProcessGroup": [], "currentPairedTerminal": d["pairedTerminal"],
             "componentHistory": history, "ownedSimulator": d["simulator"], "initialFreeBytes": free,
             "boundary": "Only the original selected five-runtime NativeScript case; no current full52 or historical result is rewritten."}
    proc = None
    def checkpoint():
        state["observedAt"] = utc()
        state["observedActiveSeconds"] = time.monotonic() - started
        write(out / "state.json", state)
    def interrupt(signum, frame):
        raise InterruptedError("Current NS-five observation signal " + str(signum))
    signal.signal(signal.SIGTERM, interrupt)
    signal.signal(signal.SIGINT, interrupt)
    checkpoint()
    try:
        argv = [sys.executable, str(Path(__file__).resolve()), "--decision", str(frozen), "--native-child"]
        with (out / "native-child.log").open("xb") as log:
            proc = subprocess.Popen(argv, cwd=root, env=env, stdout=log, stderr=subprocess.STDOUT, start_new_session=True)
            state["childPID"] = proc.pid
            state["childArgv"] = argv
            checkpoint()
            while proc.poll() is None:
                remaining = ALLOWANCE - (time.monotonic() - started)
                if remaining <= 0:
                    raise TimeoutError("Separate1200s current NS-five allowance elapsed")
                try:
                    proc.wait(timeout=min(30.0, remaining))
                except subprocess.TimeoutExpired:
                    checkpoint()
        state["childExitCode"] = proc.returncode
        assert proc.returncode == 0, "Original NS-five test/verification child failed"
        result_path = out / "native-result/result-review.json"
        review = json.loads(result_path.read_text())
        assert review["status"] == "EXECUTED_PASS" and review["source"] == SOURCE
        assert review["selector"] == SELECTOR and review["expectedTests"] == 1 and review["commandExitCode"] == 0
        assert review["summary"]["passedTests"] == 1 and review["summary"].get("failedTests", 0) == review["summary"].get("skippedTests", 0) == 0
        for name, key in [("ns5-summary.json", "summarySHA256"), ("ns5-nodes.json", "nodesSHA256"),
                          ("ns5-selected-tests.log", "selectorVerifierLogSHA256")]:
            assert digest(out / "native-result" / name) == review[key]
        state["resultReview"] = {"path": str(result_path), "bytes": result_path.stat().st_size, "sha256": digest(result_path)}
        state["status"] = "EXECUTED_PASS"
    except BaseException as error:
        state["status"] = "TIMED_OUT" if isinstance(error, TimeoutError) else "FAILED"
        state["error"] = {"type": type(error).__name__, "message": str(error)}
    finally:
        signal.signal(signal.SIGTERM, signal.SIG_IGN)
        signal.signal(signal.SIGINT, signal.SIG_IGN)
        if proc is not None:
            try:
                members = live_group(proc.pid)
                state["ownedGroupAtCleanup"] = members
                for sig, seconds in [(signal.SIGTERM, 20), (signal.SIGKILL, 10)]:
                    if not members:
                        break
                    try:
                        os.killpg(proc.pid, sig)
                    except ProcessLookupError:
                        pass
                    deadline = time.monotonic() + seconds
                    while members and time.monotonic() < deadline:
                        if proc.poll() is None:
                            try:
                                proc.wait(timeout=1)
                            except subprocess.TimeoutExpired:
                                pass
                        else:
                            time.sleep(0.25)
                        members = live_group(proc.pid)
                proc.wait(timeout=5)
                state["remainingOwnedProcessGroup"] = members
                state["childExitCode"] = proc.returncode
                if members:
                    raise RuntimeError("Owned current NS-five process group survived cleanup")
            except BaseException as error:
                state["cleanupErrors"].append(repr(error))
        try:
            observed = paired.created_device(root / "validation" / PAIRED_ID / "original/paired-product")
            assert observed and observed["udid"].upper() == device
            if observed["state"] != "Shutdown":
                command = subprocess.run(["xcrun", "simctl", "shutdown", device], capture_output=True,
                                         text=True, timeout=30, env=env)
                state["shutdown"] = {"exitCode": command.returncode, "stdout": command.stdout, "stderr": command.stderr}
            observed = paired.created_device(root / "validation" / PAIRED_ID / "original/paired-product")
            assert observed and observed["udid"].upper() == device and observed["state"] == "Shutdown"
            state["ownedSimulatorCleanup"] = {"device": device, "observedState": "Shutdown", "observedAt": utc()}
        except BaseException as error:
            state["cleanupErrors"].append(repr(error))
        try:
            current_authority(d)
            for row in d["sourceFiles"]:
                verify_file(row, root)
            verify_file(d["controller"])
        except BaseException as error:
            state["sourceErrors"].append(repr(error))
        if state["cleanupErrors"]:
            state["status"] = "CLEANUP_INCOMPLETE"
        elif state["sourceErrors"]:
            state["status"] = "INPUT_DRIFT"
        elapsed = time.monotonic() - started
        state["finishedAt"] = utc()
        state["chargedSeconds"] = elapsed
        ledger = {"schema": 1, "id": ID, "source": SOURCE, "status": state["status"],
                  "allowanceSeconds": ALLOWANCE, "chargedSeconds": elapsed,
                  "remainingSeconds": max(0.0, ALLOWANCE - elapsed), "overrunSeconds": max(0.0, elapsed - ALLOWANCE),
                  "startedAt": state["startedAt"], "finishedAt": state["finishedAt"],
                  "decision": {"path": str(frozen), "bytes": len(raw), "sha256": digest(frozen)},
                  "componentHistory": history, "historicalLedgersModified": False,
                  "accounting": "Only this new current-source NS-five observation is charged here; every earlier component ledger remains separate and is not reset or summed."}
        write(out / "ledger.json", ledger)
        checkpoint()
        fcntl.flock(lock, fcntl.LOCK_UN)
        lock.close()
    return 0 if state["status"] == "EXECUTED_PASS" else 1


if __name__ == "__main__":
    raise SystemExit(main())
