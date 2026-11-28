#!/usr/bin/env python3
"""Continue the original full52 scope after authentic missing-producer preparation.
Same original main, builds, fixtures, cases and result verifier; cumulative14400 accounting.
"""
from pathlib import Path
import argparse
import datetime
import fcntl
import hashlib
import json
import math
import os
import signal
import subprocess
import sys
import time
import uuid
import zipfile

ID = "paired52-sdk20-v2"
ROOT = Path("/Users/m1/builds/hanlin-notification-wire-fix-20261125")
DERIVED = Path("/Users/m1/caches/DerivedData/hanlin-notification-wire-fix-20261125")
SOURCE = "7f5dad540ade7fec6e5ace980eb99d1d6d0c2e8f"
TREE = "c0f027896b1edd67ea824c48b2b3bbf7c4e5e73a"
RUNNER = "Scripts/ProductSplit/run_paired_acceptance.py"
RUNNER_SHA = "a99b6194f8dd20bc30998ff2ad9e86ec219415a00615b250c65670f7dfcdba7d"
HOST_SHA = "ed18d93a88a1020bc2140417cea3847daf3d03472cdd4769d9a5ac4e44f48a22"
SDK_SHA = "6f11ed8da3df18627f05932d47b5b68dec54eb26ac396151a21cbc8c3e65800e"
SDK_INPUT = "0388d52ec3ceef1adddb21a8718566876db0ef693520bc761e4ec57573a96514"
NODE_SHA = "336b5b3ebc5deb86df842102b20b6e4761605b7a667823e68dda7761b91a161b"
PYTHON = Path("/opt/homebrew/opt/python@3.12/libexec/bin/python3")
PYTHON_SHA = "ab825fde913c394f6fb8dc57da39108ad98e1827a5404119993de3d3bc6d8fb7"
TOTAL_ALLOWANCE = 14400.0
PRIOR_RUN_SOURCE = "7f5dad540ade7fec6e5ace980eb99d1d6d0c2e8f"
PRIOR_RUN_SECONDS = 2501.629630375013
ORIGINAL_MAIN_GUARD_SHA = "a31179f13706cf7a130bef2768afaf316ae541350d3dd439bf4fa6773bd4a825"

def now():
    return datetime.datetime.now(datetime.timezone.utc).isoformat()

def digest(path):
    h = hashlib.sha256()
    with Path(path).open("rb") as f:
        for block in iter(lambda: f.read(1024 * 1024), b""):
            h.update(block)
    return h.hexdigest()

def reference(path):
    p = Path(path)
    return {"path": str(p), "bytes": p.stat().st_size, "sha256": digest(p)}

def verified(ref):
    assert isinstance(ref, dict) and isinstance(ref["bytes"], int)
    assert ref["bytes"] >= 0 and len(ref["sha256"]) == 64
    p = Path(ref["path"])
    assert p.is_file() and p.stat().st_size == ref["bytes"] and digest(p) == ref["sha256"], str(p)
    return p

def write_json(path, data):
    p = Path(path); temporary = p.with_name(p.name + ".tmp")
    with temporary.open("w") as f:
        json.dump(data, f, indent=2); f.write("\n"); f.flush(); os.fsync(f.fileno())
    temporary.replace(p)

def read_command(argv, timeout=15, **kwargs):
    return subprocess.run(argv, check=True, capture_output=True, text=True,
                          timeout=timeout, **kwargs).stdout.strip()

def source_closure(d):
    assert read_command(["git", "-C", str(ROOT), "rev-parse", "HEAD"]) == SOURCE
    assert read_command(["git", "-C", str(ROOT), "rev-parse", "HEAD^{tree}"]) == TREE
    subprocess.run(["git", "-C", str(ROOT), "diff", "--cached", "--quiet"], check=True, timeout=15)
    diff = subprocess.run(["git", "-C", str(ROOT), "diff", "--binary", "HEAD", "--"],
                          check=True, capture_output=True, timeout=15).stdout
    assert hashlib.sha256(diff).hexdigest() == d["preparedTrackedDiffSHA256"]
    assert digest(ROOT / RUNNER) == RUNNER_SHA
    host = ROOT / "AI_HLY/RuntimeHostResources.zip"
    assert digest(host) == HOST_SHA
    with zipfile.ZipFile(host) as packed:
        raw = packed.read("MiniAppSDK/miniapp-sdk.json")
    assert hashlib.sha256(raw).hexdigest() == SDK_SHA
    sdk = json.loads(raw)
    assert sdk["inputSHA256"] == SDK_INPUT and len(sdk["sourceInputs"]) == 235
    rows = {row["path"]: row["sha256"] for row in sdk["sourceInputs"]}
    assert len(rows) == 235 and len(d["consumerSourceHashes"]) == 15
    for name, expected in {**rows, **d["consumerSourceHashes"], **d["additionalSourceHashes"]}.items():
        path = ROOT / name
        assert path.resolve().is_relative_to(ROOT.resolve()) and digest(path) == expected, name
    return {"source": SOURCE, "tree": TREE, "sdkSourceInputs": 235,
            "consumerSourceFiles": 15, "hostSHA256": HOST_SHA,
            "sdkManifestSHA256": SDK_SHA, "sdkInputSHA256": SDK_INPUT,
            "trackedDiffSHA256": d["preparedTrackedDiffSHA256"]}

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

def original_records(evidence):
    path = evidence / "commands.jsonl"
    return [json.loads(line) for line in path.read_text().splitlines()] if path.exists() else []

def created_device(evidence):
    records = original_records(evidence)
    created = [r for r in records if r.get("log") == "created-simulator.txt" and r.get("exit") == 0]
    if not created:
        return None
    assert len(created) == 1
    raw = (evidence / "created-simulator.txt").read_text().strip()
    device = str(uuid.UUID(raw)).upper()
    devices = json.loads(read_command(["xcrun", "simctl", "list", "devices", "-j"], timeout=30))
    matches = [v for values in devices["devices"].values() for v in values if v["udid"] == device]
    assert len(matches) == 1 and matches[0]["name"] == "HanlinPaired-" + ID
    return matches[0]

def verify_terminal(evidence, d, returncode):
    assert returncode == 0, returncode
    acceptance = evidence / "acceptance.json"
    a = json.loads(acceptance.read_text())
    assert a["sha"] == SOURCE and a["test_scope"] == "miniapp_complete"
    assert a["status"] == a["ui"] == a["build"] == a["mini_build"] == a["ai_build"] == "EXECUTED_PASS"
    assert a["selected_tests"] == d["selectors"]["ai"]
    assert a["original_runtime_selectors"] == d["selectors"]["mini"]
    for name, count in [("original_runtime_summary", 25), ("summary", 27)]:
        summary = a[name]
        assert summary["passedTests"] == count and summary.get("failedTests", 0) == 0 and summary.get("skippedTests", 0) == 0
    records = original_records(evidence)
    required = ["mini-build.log", "ai-build.log", "original-runtimes.log", "paired-tests.log",
                "original-runtimes-selected-tests.log", "requested-tests.log"]
    for name in required:
        rows = [r for r in records if r.get("log") == name]
        assert len(rows) == 1 and rows[0]["exit"] == 0, name
    assert a["app_group"]["status"] == "EXECUTED_PASS"
    assert a["native_adapter_assets"]["native_request_proof"] == "EXECUTED_PASS_RESOURCE_TRANSPORT"
    bound = []
    for product in ["HanlinMiniApps.app", "AI_Hanlin.app"]:
        app = DERIVED / "Build/Products/Debug-iphonesimulator" / product
        hosts = list(app.rglob("RuntimeHostResources.zip"))
        assert hosts, str(app)
        for host in hosts:
            assert digest(host) == HOST_SHA, str(host)
            bound.append(reference(host))
    hosted_path = evidence / "hosted-fixture-built-check.json"
    hosted = json.loads(hosted_path.read_text())
    assert hosted["status"] == "VERIFIED_PREREQUISITE" and hosted["source"] == SOURCE
    assert hosted["originalBuildLog"] == "ai-build.log" and hosted["originalBuildExitCode"] == 0 and hosted["originalCommandUnchanged"] is True
    assert hosted["sourceResource"] == d["hostedFixture"]["source"]
    verified(hosted["sourceResource"]); verified(hosted["builtResource"])
    assert hosted["builtResource"]["bytes"] == hosted["sourceResource"]["bytes"] and hosted["builtResource"]["sha256"] == hosted["sourceResource"]["sha256"]
    proofs = [hosted_path, acceptance, evidence / "commands.jsonl", evidence / "command-events.jsonl",
              evidence / "original-runtimes-summary.json", evidence / "original-runtimes-nodes.json",
              evidence / "original-runtimes-selected-tests.log", evidence / "test-summary.json",
              evidence / "test-nodes.json", evidence / "requested-tests.log"]
    assert (evidence / "OriginalRuntimes.xcresult").is_dir() and (evidence / "Paired.xcresult").is_dir()
    return {"status": "EXECUTED_PASS", "mini": {"passed": 25, "failed": 0, "skipped": 0},
            "ai": {"passed": 27, "failed": 0, "skipped": 0}, "proofs": [reference(p) for p in proofs],
            "builtHostArchives": bound, "simulator": a["simulator"]}

def continuation_scope(d):
    assert d["combinedAllowanceSeconds"] == TOTAL_ALLOWANCE
    assert d["priorWholeRun"]["terminal"]["sha256"] == "62fa0f2144ce6dd280e8a6615baea3f2ec822beb13f544528e9ec79b3e3d241a"
    assert d["priorWholeRun"]["ledger"]["sha256"] == "f62166616dc312aa689cc2543bbe1f0ca1c9e75d619c0061bccda4f1c488e75f"
    previous = json.loads(verified(d["priorWholeRun"]["terminal"]).read_text())
    previous_ledger = json.loads(verified(d["priorWholeRun"]["ledger"]).read_text())
    assert previous["id"] == previous_ledger["id"] == "paired52-sdk20-v1"
    assert previous["source"] == PRIOR_RUN_SOURCE and previous["status"] == previous_ledger["status"] == "FAILED"
    assert not previous["sourceErrors"] and not previous["cleanupErrors"] and not previous["remainingOwnedProcessGroup"]
    assert previous["chargedSeconds"] == previous_ledger["chargedSeconds"] == PRIOR_RUN_SECONDS
    assert previous_ledger["allowanceSeconds"] == TOTAL_ALLOWANCE
    probe = json.loads(verified(d["probePreparation"]["state"]).read_text())
    probe_ledger = json.loads(verified(d["probePreparation"]["ledger"]).read_text())
    assert probe["id"] == probe_ledger["id"] == "probe-fixture-sdk20-preparation-v1"
    assert d["probePreparation"]["state"]["sha256"] == "949660502e1637c5c96aa41372e07d380fe36a0bab586c0f43cc87e7fbcd50d9"
    assert d["probePreparation"]["ledger"]["sha256"] == "fd4e5beca04d71756853be1b9f0badb74f0d0d58bee6213782c22fac2782b4b1"
    assert probe["source"] == PRIOR_RUN_SOURCE and probe["status"] == probe_ledger["status"] == "SOURCE_CHANGED"
    assert probe["sourceErrors"] == ["AssertionError()"] and not probe["cleanupErrors"] and not probe["remainingOwnedProcessGroup"]
    assert probe["ledger"] == d["probePreparation"]["ledger"]
    assert probe["exitCode"] == 0 and probe["operationalCapSeconds"] == 600
    assert probe["nativeBuildOrTestInvoked"] is False and probe["preparedChanges"] == []
    # Preserve the raw wrapper failure. Its only false assumption was that the
    # original generated resource must be ignored; it is actually untracked.
    assert d["probePreparation"]["reconciliation"]["sha256"] == "449cc069f7e23873b6da57e3af283ae0f135ac25d0d8677157e2d9978b1a0651"
    reconciled = json.loads(verified(d["probePreparation"]["reconciliation"]).read_text())
    assert reconciled["source"] == SOURCE and reconciled["state"] == d["probePreparation"]["state"]
    assert reconciled["ledger"] == d["probePreparation"]["ledger"]
    assert reconciled["originalProducerExitCode"] == 0 and reconciled["rawTerminalStatus"] == "SOURCE_CHANGED"
    assert reconciled["rawSourceErrors"] == probe["sourceErrors"]
    assert reconciled["initialSource"] == reconciled["finalSource"] == probe["initialSource"] == probe["finalSource"]
    hosted_relative = "AI_HLYTests/Fixtures/HostServicesProbe.bundle/ExpoSwiftUIProbeA.hanlinExpo"
    expected_commands = [
        ["git", "-C", str(ROOT), "check-ignore", "-v", hosted_relative],
        ["git", "-C", str(ROOT), "check-ignore", "-q", hosted_relative],
        ["git", "-C", str(ROOT), "ls-files", "--error-unmatch", hosted_relative],
        ["git", "-C", str(ROOT), "status", "--porcelain=v1", "--untracked-files=all", "--", hosted_relative],
        ["git", "-C", str(ROOT), "diff", "--binary", "HEAD", "--"],
    ]
    assert [row["argv"] for row in reconciled["commands"]] == expected_commands
    assert [row["exitCode"] for row in reconciled["commands"]] == [1, 1, 1, 0, 0]
    assert reconciled["commands"][3]["stdout"] == "?? " + hosted_relative + "\n"
    assert reconciled["commands"][4]["stdout"] == ""
    assert len(reconciled["postRequiredFilesVerified"]) == 11
    for row in reconciled["postRequiredFilesVerified"]:
        verified(row)
    assert probe_ledger["prior"]["authority"] == d["priorWholeRun"]["ledger"]
    assert probe_ledger["prior"]["chargedSeconds"] == PRIOR_RUN_SECONDS and probe_ledger["priorLedgersModified"] is False
    assert probe_ledger["combinedAllowanceSeconds"] == TOTAL_ALLOWANCE
    seconds = probe["actualElapsedSeconds"]
    assert math.isfinite(seconds) and seconds >= 0 and probe_ledger["currentCharge"]["seconds"] == seconds
    prior_charged = math.fsum([PRIOR_RUN_SECONDS, seconds])
    assert prior_charged == probe_ledger["totalChargedSeconds"] == probe["totalChargedSeconds"] == d["priorChargedSeconds"]
    allowance = TOTAL_ALLOWANCE - prior_charged
    assert allowance > 0 and d["allowanceSeconds"] == allowance and probe_ledger["remainingSeconds"] == allowance
    assert d["hostedFixture"]["source"] == reconciled["hostedResource"] and d["hostedFixture"]["gitDisposition"] == "UNTRACKED_NOT_IGNORED"
    assert verified(d["hostedFixture"]["source"]) == ROOT / hosted_relative
    verified(probe["preparedDiff"])
    before = {row["relativePath"]: row for row in probe["outputsBefore"]}
    after = {row["relativePath"]: row for row in probe["outputsAfter"]}
    assert len(before) == len(after) == 13 and set(before) == set(after)
    assert before[hosted_relative]["exists"] is False
    for name, row in after.items():
        assert row["exists"]
        verified({k: row[k] for k in ("path", "bytes", "sha256")})
        if name != hosted_relative:
            assert before[name]["bytes"] == row["bytes"] and before[name]["sha256"] == row["sha256"]
    assert {k: after[hosted_relative][k] for k in ("path", "bytes", "sha256")} == d["hostedFixture"]["source"]
    guard = verified(d["originalMainGuard"])
    assert guard == ROOT / "validation/run-original-paired-with-hosted-check-v1.py" and digest(guard) == ORIGINAL_MAIN_GUARD_SHA
    history = [
        {"id": previous["id"], "seconds": PRIOR_RUN_SECONDS, "status": previous["status"], "authority": d["priorWholeRun"]["ledger"]},
        {"id": probe["id"], "seconds": seconds, "status": probe["status"], "authority": d["probePreparation"]["ledger"],
         "originalProducerExitCode": 0, "reconciliation": d["probePreparation"]["reconciliation"]},
    ]
    return history, allowance

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--decision", required=True)
    args = parser.parse_args()
    decision_path = Path(args.decision)
    d = json.loads(decision_path.read_text())
    assert d["schema"] == 1 and d["status"] == "SEALED" and d["id"] == ID
    assert d["source"] == SOURCE and d["root"] == str(ROOT) and d["derivedData"] == str(DERIVED)
    assert d["scope"] == "miniapp_complete"
    scope_history, allowance = continuation_scope(d)
    assert d["expectedCases"] == {"mini": 25, "ai": 27} and len(d["selectors"]["mini"]) == 25
    assert digest(__file__) == d["controllerSHA256"]
    out = ROOT / "validation" / ID
    assert d["output"] == str(out) and not out.exists()
    assert d["nativePreparation"]["status"] == "PREPARED"
    prep = json.loads(verified(d["nativePreparation"]["authority"]).read_text())
    assert prep["status"] == "PREPARED" and prep["source"] == prep["sourceAfter"] == d["nativePreparation"]["producerSource"] == PRIOR_RUN_SOURCE
    assert not prep["errors"] and not prep["sourceErrors"] and not prep["cleanupErrors"]
    assert prep["sdkSourceInputsVerified"] == 235
    assert prep["preparedDiff"]["sha256"] == d["preparedTrackedDiffSHA256"]
    verified(prep["preparedDiff"])
    verified(prep["frameworkReceipt"])
    prep_ledger = json.loads(verified(prep["ledger"]).read_text())
    assert prep_ledger["totalChargedSeconds"] == prep["totalChargedSeconds"]
    assert prep_ledger["charges"][-1]["seconds"] == prep["actualElapsedSeconds"]
    assert prep_ledger["priorLedgersModified"] is False
    assert d["componentHistory"] and all(row["accountingRelation"] for row in d["componentHistory"])
    for row in d["componentHistory"]:
        assert math.isfinite(row["seconds"]) and row["seconds"] >= 0
        verified(row["authority"])
    assert isinstance(d["resourceAssessment"]["minimumFreeBytes"], int) and d["resourceAssessment"]["minimumFreeBytes"] > 0
    for ref in d["requiredFiles"]:
        verified(ref)
    initial = source_closure(d)
    node = ROOT / "Tools/node-v24.5.0-darwin-arm64/bin/node"
    assert digest(node) == NODE_SHA and os.access(node, os.X_OK)
    observed_node = json.loads(read_command([str(node), "-p",
        "JSON.stringify({version:process.version,platform:process.platform,arch:process.arch})"], timeout=10))
    assert observed_node == {"version": "v24.5.0", "platform": "darwin", "arch": "arm64"}
    assert digest(PYTHON) == PYTHON_SHA and os.access(PYTHON, os.X_OK)
    observed_python = json.loads(read_command([str(PYTHON), "-c",
        "import inspect,json,sys,tarfile; print(json.dumps({'version':sys.version.split()[0],"
        "'extractFilter':'filter' in inspect.signature(tarfile.TarFile.extractall).parameters}))"], timeout=10))
    assert observed_python == {"version": "3.12.16", "extractFilter": True}
    env = os.environ.copy()
    env.update(d["environment"])
    env.update(PATH=str(node.parent) + os.pathsep + str(PYTHON.parent) + os.pathsep + env["PATH"],
               GITHUB_WORKSPACE=str(ROOT), GITHUB_SHA=SOURCE, GITHUB_RUN_ID=ID,
               SPLIT_EVIDENCE=str(out / "original"), SPLIT_DERIVED_DATA=str(DERIVED),
               PAIRED_TEST_SCOPE="miniapp_complete")
    assert env["DEVELOPER_DIR"] == "/Applications/Xcode.app/Contents/Developer"
    assert env["RUNNER_TEMP"] == str(ROOT / "build/primary-temp")
    lock_path = ROOT / "validation/.paired52-sdk20-owner.lock"
    lock = lock_path.open("a+")
    fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
    stat = os.statvfs(ROOT)
    free = stat.f_bavail * stat.f_frsize
    assert free >= d["resourceAssessment"]["minimumFreeBytes"], {"free": free, "required": d["resourceAssessment"]}
    out.mkdir()
    (out / "decision.json").write_bytes(decision_path.read_bytes())
    evidence = out / "original/paired-product"
    started = time.monotonic()
    state = {"schema": 1, "id": ID, "source": SOURCE, "status": "RUNNING", "startedAt": now(),
             "controllerPID": os.getpid(), "childPID": None, "allowanceSeconds": allowance,
             "initialSource": initial, "initialFreeBytes": free, "node": observed_node, "python": observed_python,
             "componentHistory": d["componentHistory"], "nativePreparation": d["nativePreparation"],
             "scopeHistory": scope_history, "combinedAllowanceSeconds": TOTAL_ALLOWANCE,
             "priorChargedSeconds": d["priorChargedSeconds"],
             "sourceErrors": [], "cleanupErrors": [], "result": None}
    child = None
    def checkpoint():
        state["observedActiveSeconds"] = time.monotonic() - started
        state["observedAt"] = now()
        write_json(out / "state.json", state)
    def interrupted(signum, frame):
        raise KeyboardInterrupt("Controller signal " + str(signum))
    signal.signal(signal.SIGTERM, interrupted)
    signal.signal(signal.SIGINT, interrupted)
    checkpoint()
    try:
        with (out / "runner.log").open("xb") as log:
            child = subprocess.Popen([str(PYTHON), str(verified(d["originalMainGuard"])), "--decision", str(out / "decision.json")], cwd=ROOT, env=env,
                                     stdout=log, stderr=subprocess.STDOUT, start_new_session=True)
            state["childPID"] = child.pid
            checkpoint()
            while child.poll() is None:
                remaining = allowance - (time.monotonic() - started)
                if remaining <= 0:
                    raise TimeoutError("Original whole-run allowance exhausted")
                try:
                    child.wait(timeout=min(15.0, remaining))
                except subprocess.TimeoutExpired:
                    checkpoint()
        state["childExit"] = child.returncode
        state["result"] = verify_terminal(evidence, d, child.returncode)
        state["status"] = "EXECUTED_PASS"
    except BaseException as error:
        state["status"] = "FAILED"
        state["error"] = {"type": type(error).__name__, "message": str(error)}
    finally:
        signal.signal(signal.SIGTERM, signal.SIG_IGN)
        signal.signal(signal.SIGINT, signal.SIG_IGN)
        if child is not None:
            try:
                for sig, seconds in [(signal.SIGINT, 30), (signal.SIGTERM, 20), (signal.SIGKILL, 10)]:
                    if not live_group(child.pid):
                        break
                    os.killpg(child.pid, sig)
                    deadline = time.monotonic() + seconds
                    while time.monotonic() < deadline and live_group(child.pid):
                        time.sleep(0.25)
                try:
                    child.wait(timeout=1)
                except subprocess.TimeoutExpired:
                    pass
                state["childExit"] = child.poll()
                state["remainingOwnedProcessGroup"] = live_group(child.pid)
                if state["remainingOwnedProcessGroup"]:
                    raise RuntimeError("Owned original-runner process group remains")
            except BaseException as error:
                state["cleanupErrors"].append({"type": type(error).__name__, "message": str(error)})
        try:
            device = created_device(evidence)
            state["ownedSimulator"] = device
            if device and device["state"] != "Shutdown":
                record = subprocess.run(["xcrun", "simctl", "shutdown", device["udid"]],
                                        capture_output=True, text=True, timeout=30)
                state["shutdown"] = {"exit": record.returncode, "stdout": record.stdout, "stderr": record.stderr}
                if record.returncode:
                    raise RuntimeError("Owned simulator shutdown failed")
                device = created_device(evidence)
                state["ownedSimulator"] = device
            if device and device["state"] != "Shutdown":
                raise RuntimeError("Owned simulator is not Shutdown")
        except BaseException as error:
            state["cleanupErrors"].append({"type": type(error).__name__, "message": str(error)})
        try:
            state["finalSource"] = source_closure(d)
        except BaseException as error:
            state["sourceErrors"].append({"type": type(error).__name__, "message": str(error)})
        if state["cleanupErrors"]:
            state["status"] = "CLEANUP_INCOMPLETE"
        elif state["sourceErrors"]:
            state["status"] = "SOURCE_CHANGED"
        charged = time.monotonic() - started
        state["finishedAt"] = now()
        state["chargedSeconds"] = charged
        cumulative = math.fsum([d["priorChargedSeconds"], charged])
        state["totalChargedSeconds"] = cumulative
        ledger = {"schema": 1, "id": ID, "status": state["status"], "allowanceSeconds": allowance,
                  "chargedSeconds": charged, "remainingSeconds": max(0.0, allowance - charged),
                  "overrunSeconds": max(0.0, charged - allowance),
                  "componentHistory": d["componentHistory"], "nativePreparation": d["nativePreparation"],
                  "scopeHistory": scope_history, "combinedAllowanceSeconds": TOTAL_ALLOWANCE,
                  "priorChargedSeconds": d["priorChargedSeconds"], "totalChargedSeconds": cumulative,
                  "remainingCombinedSeconds": max(0.0, TOTAL_ALLOWANCE - cumulative),
                  "accounting": "The original14400 scope retains the actual first failed full52 and one-time original probe preparation charges. This current whole-run charge includes cleanup; no prior ledger or test result is reset, relabeled or aggregated into PASS.",
                  "startedAt": state["startedAt"], "finishedAt": state["finishedAt"],
                  "decision": reference(out / "decision.json")}
        write_json(out / "ledger.json", ledger)
        checkpoint()
        fcntl.flock(lock, fcntl.LOCK_UN)
        lock.close()
    return 0 if state["status"] == "EXECUTED_PASS" else 1

if __name__ == "__main__":
    sys.exit(main())
