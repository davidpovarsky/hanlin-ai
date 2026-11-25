"""DRAFT: execute only by the native owner with a newly sealed final-input decision.
Uses the unchanged original paired command/result verifier; no build, preparation,
fixture production or product queue writes. The existing companion ledger is kept.
"""
from pathlib import Path
import argparse
import datetime
import fcntl
import hashlib
import importlib.util
import json
import math
import os
import shlex
import signal
import subprocess
import sys
import time
import uuid

ID = "companion-native-v1-ns5"
ORIGINAL_SELECTOR = "AI_HLYTests/HanlinUnifiedHostServicesE2ETests/actualNativeScriptImportsTheGeneratedTypedFacadeAndCallsEveryEngine"
SELECTOR = ORIGINAL_SELECTOR + "()"
RUNNER = "Scripts/ProductSplit/run_paired_acceptance.py"
RUNNER_SHA = "a99b6194f8dd20bc30998ff2ad9e86ec219415a00615b250c65670f7dfcdba7d"
HELPER_SHA = "dad6581212134987b666a5161ab33994e6d79b57ed38108faba6ffb22c3bb520"
ORIGINAL_CHARGE = 26.137203625010443
TEST_SOURCE = "AI_HLYTests/NativeScriptRuntimeWireTests.swift"
TEST_SOURCE_SHA = "4ac7ed256f861133e3b84eda85d1f5df659317477c6a42c637a42a59def46835"


def load_module(path, name):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def digest(path):
    h = hashlib.sha256()
    with Path(path).open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def load_decision(path):
    raw = path.read_bytes()
    d = json.loads(raw)
    assert d["schema"] == 1 and d["id"] == ID and d["owner"] == "/root/native_execution"
    assert d["authorization"]["by"] == "/root"
    assert d["authorization"]["scope"] == "remaining original NS5 companion without rebuilding"
    assert d["selector"] == SELECTOR and d["expectedTests"] == 1
    assert d["originalCompanionAllowanceSeconds"] == 1200
    assert d["priorCompanionChargeSeconds"] == ORIGINAL_CHARGE
    assert d["allowanceSeconds"] == 1200 - ORIGINAL_CHARGE
    assert d["paired4500Separate"] is True
    root = Path(d["root"]).resolve()
    helper_path = (root / d["originalController"]["path"]).resolve()
    assert helper_path.is_relative_to(root / "build/primary-control")
    assert d["originalController"]["sha256"] == HELPER_SHA == digest(helper_path)
    helper = load_module(helper_path, "original_native_continuation_helpers")
    assert digest(root / RUNNER) == RUNNER_SHA
    assert digest(root / TEST_SOURCE) == TEST_SOURCE_SHA
    return raw, d, root, helper


def native_child(decision_path):
    _, d, root, h = load_decision(decision_path)
    out = h.relative(root, d["outputDirectory"])
    evidence = out / "native-result"
    assert evidence.is_dir()
    sys.path.insert(0, str(root / "Scripts/ProductSplit"))
    runner = load_module(root / RUNNER, "original_paired_acceptance_for_ns5")
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


def historical_group_exclusion(terminal, authority, root, derived, live_group, utc):
    pgid = int(terminal["phasePID"])
    initial = live_group(pgid)
    if not initial:
        return None
    # Numeric process-group identifiers can be reused after an authenticated clear.
    assert terminal.get("remainingOwnedProcessGroup") == []
    finished = datetime.datetime.fromisoformat(terminal["finishedAt"])
    assert finished.tzinfo is not None
    finished = finished.astimezone(datetime.timezone.utc)
    pids = {line.split()[0] for line in initial}
    argv = ["/bin/ps", "-p", ",".join(sorted(pids, key=int)),
            "-o", "pid=,pgid=,state=,lstart=,command="]
    query = subprocess.run(argv, text=True, capture_output=True, timeout=10,
                           env=dict(os.environ, TZ="UTC", LC_ALL="C"))
    assert query.returncode == 0 or (query.returncode == 1 and not query.stdout.strip() and not query.stderr.strip()), query.stderr
    months = {month: number for number, month in enumerate("Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec".split(), 1)}
    markers = [str(root), str(derived)]
    device = terminal.get("ownedSimulatorCleanup", {}).get("device")
    if device:
        markers.append(str(device))
    members = []
    for line in query.stdout.splitlines():
        values = line.split(None, 8)
        assert len(values) == 9, line
        if values[0] not in pids or values[1] != str(pgid) or values[2].startswith("Z"):
            continue
        started = datetime.datetime(int(values[7]), months[values[4]], int(values[5]),
            *map(int, values[6].split(":")), tzinfo=datetime.timezone.utc)
        command = values[8]
        related = [marker for marker in markers if marker and marker in command]
        assert started > finished and not related, {"historicalPGID": pgid,
            "terminal": authority, "finishedAt": finished.isoformat(),
            "startedAtUTC": started.isoformat(), "command": command, "ownedMarkers": related}
        members.append({"pid": int(values[0]), "pgid": pgid, "state": values[2],
            "startedAtUTC": started.isoformat(), "command": command})
    remaining = {int(line.split()[0]) for line in live_group(pgid)}
    assert remaining <= {member["pid"] for member in members}, "Historical group changed during targeted identity observation"
    if not members:
        return None
    return {"terminal": authority, "historicalPGID": pgid, "priorFinishedAt": terminal["finishedAt"],
        "priorRemainingOwnedProcessGroup": [], "observedAt": utc(),
        "disposition": "UNRELATED_PGID_REUSE_AFTER_AUTHENTICATED_CLEAR",
        "query": {"argv": argv, "environment": {"TZ": "UTC", "LC_ALL": "C"},
                  "exitCode": query.returncode, "stdout": query.stdout, "stderr": query.stderr},
        "members": members, "recheckedLivePIDs": sorted(remaining)}

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--decision", type=Path, required=True)
    parser.add_argument("--native-child", action="store_true")
    args = parser.parse_args()
    decision_path = args.decision.resolve()
    if args.native_child:
        return native_child(decision_path)
    decision_bytes, d, root, h = load_decision(decision_path)
    ctrl = root / "build/primary-control"
    out = h.relative(root, d["outputDirectory"])
    assert out.is_relative_to(ctrl) and not out.exists()
    lock = (ctrl / "native-continuation-owner.lock").open("a")
    fcntl.flock(lock.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
    primary_path = ctrl / "state.json"
    ledger_path = ctrl / "companion-native-v1/ledger.json"
    companion_decision_path = ctrl / "companion-native-v1/decision.json"
    notification_review_path = ctrl / "companion-native-v1/notification-package/result-review.json"
    for path, key in [(primary_path, "primaryStateSHA256"), (ledger_path, "companionLedgerSHA256"),
                      (companion_decision_path, "originalCompanionDecisionSHA256"),
                      (notification_review_path, "notificationReviewSHA256")]:
        assert digest(path) == d[key], "Final decision binding changed: " + str(path)
    primary_bytes, ledger_bytes = primary_path.read_bytes(), ledger_path.read_bytes()
    primary, ledger = json.loads(primary_bytes), json.loads(ledger_bytes)
    original_decision = json.loads(companion_decision_path.read_text())
    notification = json.loads(notification_review_path.read_text())
    assert original_decision["allowanceSeconds"] == 1200 and original_decision["paired4500Separate"]
    assert original_decision["scope"] == ["HanlinNotificationInvocationTests", ORIGINAL_SELECTOR]
    assert notification["status"] == "EXECUTED_PASS" and notification["failed"] == notification["skipped"] == 0
    assert ledger["maximumActiveSeconds"] == 1200 and ledger["activeElapsedSeconds"] == ORIGINAL_CHARGE
    assert math.fsum(x["elapsedSeconds"] for x in ledger["charges"]) == ORIGINAL_CHARGE
    assert [x["id"] for x in ledger["charges"]] == ["companion-native-v1-notification-package"]
    assert ledger["remainingSelectors"] == [ORIGINAL_SELECTOR]
    assert ledger["charges"][0]["logSHA256"] == notification["logSHA256"]
    assert primary["status"] in ("COMPLETED", "FAIL", "PAUSED_AFTER_PHASE")
    assert primary["source"] == d["source"] and primary["activeElapsedSeconds"] == d["activeBaselineSeconds"]
    assert h.run(["git", "rev-parse", "HEAD"], cwd=root) == d["source"]
    assert h.run(["git", "rev-parse", "HEAD^{tree}"], cwd=root) == d["sourceTree"]
    assert hashlib.sha256(subprocess.check_output(["git", "diff", "--binary", "HEAD"], cwd=root)).hexdigest() == d["preparedTrackedDiffSHA256"]
    paired_path = h.relative(root, d["pairedTerminal"]["path"])
    assert digest(paired_path) == d["pairedTerminal"]["sha256"]
    paired = json.loads(paired_path.read_text())
    assert paired["source"] == d["source"]
    assert paired["status"] in ("EXECUTED_PASS", "FAILED", "TIMED_OUT")
    assert not paired["remainingOwnedProcessGroup"] and not paired["cleanupErrors"] and not paired["sourceErrors"]
    paired_evidence = Path(paired["pairedEvidence"]).resolve()
    assert paired_evidence.is_relative_to(ctrl)
    ownership = paired_evidence / "created-simulator.txt"
    assert digest(ownership) == d["simulator"]["ownershipSHA256"]
    device = str(uuid.UUID(ownership.read_text().strip())).upper()
    assert device == str(uuid.UUID(d["simulator"]["udid"])).upper()
    assert paired["ownedSimulatorCleanup"]["device"] == device
    assert paired["ownedSimulatorCleanup"]["observedState"] == "Shutdown"

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

    historical_group_exclusions = []
    exclusion = historical_group_exclusion(paired, d["pairedTerminal"], root, Path(d["derivedData"]), live_group, h.utc)
    if exclusion is not None:
        historical_group_exclusions.append(exclusion)
    prior_controllers = {paired["controllerPID"], primary.get("controllerPID")} - {None}
    historic_pids = prior_controllers - {os.getpid()}
    process_rows = []
    if historic_pids:
        query = subprocess.run(["/bin/ps", "-p", ",".join(str(pid) for pid in sorted(historic_pids)),
                                "-o", "pid=,state=,command="], text=True, capture_output=True, timeout=10)
        assert query.returncode == 0 or (query.returncode == 1 and not query.stdout.strip() and not query.stderr.strip()), query.stderr
        process_rows = query.stdout.splitlines()
    for pid in historic_pids:
        for line in process_rows:
            values = line.split(None, 2)
            if len(values) != 3 or values[0] != str(pid) or values[1].startswith("Z"):
                continue
            try:
                arguments = shlex.split(values[2])
            except ValueError:
                # ps renders argv without guaranteed shell quoting.
                arguments = values[2].split()
            # PIDs can be reused. Only the actual Python control script in this
            # owned checkout identifies a surviving controller; never stop or
            # reject an unrelated process merely because it has a historical PID.
            python = bool(arguments) and Path(arguments[0]).name.lower().startswith("python")
            owned_script = any(argument.startswith(str(ctrl) + "/")
                               and Path(argument).suffix == ".py" for argument in arguments[1:])
            if python and owned_script:
                raise RuntimeError("Prior owned controller remains active: " +
                                   json.dumps({"pid": pid, "argv": arguments}, sort_keys=True))

    required = d["requiredFiles"]
    source_paths = {x["path"] for x in required}
    assert {RUNNER, TEST_SOURCE, "AI_HLYTests/HanlinUnifiedHostServicesE2ETests.swift",
            "Scripts/CI/verify_selected_tests.py", "AI_HLY/RuntimeHostResources.zip"} <= source_paths
    for item in required:
        assert digest(h.relative(root, item["path"])) == item["sha256"]
    assert d["sdk"]["archiveSHA256"] == digest(root / "AI_HLY/RuntimeHostResources.zip")
    assert digest(h.relative(root, d["sdk"]["manifestPath"])) == d["sdk"]["manifestSHA256"]
    sdk = json.loads(h.relative(root, d["sdk"]["manifestPath"]).read_text())
    assert sdk["inputSHA256"] == d["sdk"]["inputSHA256"]
    products_root = Path(d["derivedData"]).resolve() / "Build/Products"
    product_files = d["productFiles"]
    assert {"aiAppExecutable", "aiTestExecutable", "aiRuntimeImage", "aiHostResource", "xctestrun"} <= {x["role"] for x in product_files}
    for item in product_files:
        product = Path(item["path"]).resolve()
        assert product.is_relative_to(products_root) and product.is_file()
        assert digest(product) == item["sha256"]
        if item["role"] == "aiHostResource":
            assert item["sha256"] == d["sdk"]["archiveSHA256"]
    assert d["productProvenance"]["source"] == d["source"]
    for item in d["productProvenance"]["receipts"]:
        assert digest(h.relative(root, item["path"])) == item["sha256"]
    assert d["resourceAssessment"]["decision"] == "FITS_MEASURED_NEXT_PHASE"
    disk = h.run(["df", "-k", "/System/Volumes/Data"])
    free = int(disk.splitlines()[-1].split()[3]) * 1024
    assert free >= d["resourceAssessment"]["estimatedIncrementalBytes"] + d["resourceAssessment"]["concurrentAndOSAllowanceBytes"]
    original_node = d["originalNode"]
    node_path = Path(original_node["path"]).resolve(strict=True)
    assert original_node["path"] == "/Users/m1/builds/hanlin-ai-ce49e30d-miniapp-complete-tools/node-v24.5.0-darwin-arm64/bin/node"
    assert str(node_path) == original_node["path"]
    assert node_path.is_file() and os.access(node_path, os.X_OK)
    assert node_path.stat().st_size == 116870064
    assert digest(node_path) == original_node["sha256"] == "336b5b3ebc5deb86df842102b20b6e4761605b7a667823e68dda7761b91a161b"
    installed_inputs = []
    for engine in ["Expo", "NativeScript"]:
        receipt = json.loads((root / "Scripts" / engine / "node_modules/.hanlin-miniapp-install.json").read_text())
        installed_inputs.append(receipt["inputs"])
    node_identity = json.loads(h.run([str(node_path), "-p",
        "JSON.stringify({node:process.versions.node,platform:process.platform,architecture:process.arch})"], timeout=10))
    assert all(all(node_identity[k] == inputs[k] for k in node_identity) for inputs in installed_inputs)
    assert node_identity["node"] == original_node["version"] == "24.5.0"
    assert node_identity["platform"] == "darwin" and node_identity["architecture"] == "arm64"

    out.mkdir()
    (out / "native-result").mkdir()
    frozen_decision = out / "decision.json"
    frozen_decision.write_bytes(decision_bytes)
    (out / "primary-state-before.json").write_bytes(primary_bytes)
    (out / "companion-ledger-before.json").write_bytes(ledger_bytes)
    (out / "original-companion-decision.json").write_bytes(companion_decision_path.read_bytes())
    (out / "notification-result-review.json").write_bytes(notification_review_path.read_bytes())
    (out / "paired-terminal-before.json").write_bytes(paired_path.read_bytes())
    state_path, events = out / "state.json", out / "events.jsonl"
    baseline, allowance = primary["activeElapsedSeconds"], d["allowanceSeconds"]
    state = {"schema": 1, "id": ID, "owner": d["owner"], "source": d["source"],
             "status": "STARTING", "selector": SELECTOR, "expectedTests": 1,
             "controllerPID": os.getpid(), "activeBaselineSeconds": baseline,
             "originalCompanionAllowanceSeconds": 1200, "priorCompanionChargeSeconds": ORIGINAL_CHARGE,
             "allowanceSeconds": allowance, "paired4500Separate": True,
             "decisionSHA256": hashlib.sha256(decision_bytes).hexdigest(),
             "original52Status": paired.get("original52"), "nativeResult": "NOT_RUN",
             "historicalProcessGroupExclusions": historical_group_exclusions,
             "resourceObservationAtLaunch": {"observedAt": h.utc(), "freeBytes": free, "df": disk}}

    state["originalNode"] = {**original_node, "bytes": node_path.stat().st_size, "observedIdentity": node_identity}

    def checkpoint(event, **fields):
        state.update(fields)
        h.write(state_path, state)
        with events.open("a") as stream:
            stream.write(json.dumps({"at": h.utc(), "event": event, **fields}) + "\n")
            stream.flush()
            os.fsync(stream.fileno())

    env = dict(os.environ)
    tools = root.parent / (root.name + "-tools")
    env.update(PATH=str(node_path.parent) + ":" + str(tools / "bin") + ":/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin",
               DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer",
               GITHUB_WORKSPACE=str(root), GITHUB_SHA=d["source"],
               SPLIT_EVIDENCE=str(out), SPLIT_DERIVED_DATA=d["derivedData"],
               PAIRED_TEST_SCOPE="miniapp_complete", RUNNER_TEMP=str(root / "build/primary-temp"))
    argv = [sys.executable, str(Path(__file__).resolve()), "--decision", str(frozen_decision), "--native-child"]
    log = out / "controller-child.log"
    process, exit_code, error = None, None, None
    start = time.monotonic()
    checkpoint("prepared", startedAt=h.utc(), argv=argv)
    running_primary = dict(primary)
    running_primary.update(status="RUNNING", controllerPID=os.getpid(), phase=ID)
    h.write(primary_path, running_primary)

    def interrupted(signum, frame):
        raise InterruptedError("NS5 companion received signal " + str(signum))

    signal.signal(signal.SIGTERM, interrupted)
    signal.signal(signal.SIGINT, interrupted)
    try:
        with log.open("xb") as stream:
            process = subprocess.Popen(argv, cwd=root, env=env, stdout=stream,
                                       stderr=subprocess.STDOUT, start_new_session=True)
            checkpoint("launched", status="RUNNING", phasePID=process.pid, nativeResult="RUNNING")
            while True:
                remaining = allowance - (time.monotonic() - start)
                if remaining <= 0:
                    raise TimeoutError("Remaining original1200s companion allowance elapsed")
                try:
                    exit_code = process.wait(timeout=min(30, remaining))
                    break
                except subprocess.TimeoutExpired:
                    checkpoint("heartbeat", elapsedSeconds=time.monotonic() - start,
                               logBytes=log.stat().st_size)
        review_path = out / "native-result/result-review.json"
        review = json.loads(review_path.read_text()) if review_path.exists() else {}
        assert exit_code == 0 and review.get("status") == "EXECUTED_PASS"
        assert review["source"] == d["source"] and review["selector"] == SELECTOR
        assert review["summary"]["passedTests"] == 1 and not review["summary"].get("failedTests", 0) and not review["summary"].get("skippedTests", 0)
        checkpoint("actual_terminal", status="EXECUTED_PASS", nativeResult="EXECUTED_PASS",
                   resultReviewSHA256=digest(review_path), exitCode=exit_code)
    except BaseException as failure:
        error = type(failure).__name__ + ": " + str(failure)
        checkpoint("actual_terminal", status="TIMED_OUT" if isinstance(failure, TimeoutError) else "FAILED",
                   nativeResult="FAILED_OR_INCOMPLETE", error=error, exitCode=exit_code)
    finally:
        signal.signal(signal.SIGTERM, signal.SIG_IGN)
        signal.signal(signal.SIGINT, signal.SIG_IGN)
        cleanup_errors = []
        if process is not None:
            try:
                members = live_group(process.pid)
                state["ownedProcessGroupAtCleanup"] = members
                for sig, seconds in [(signal.SIGTERM, 20), (signal.SIGKILL, 10)]:
                    if not members:
                        break
                    try:
                        os.killpg(process.pid, sig)
                    except ProcessLookupError:
                        pass
                    until = time.monotonic() + seconds
                    while members and time.monotonic() < until:
                        if process.poll() is None:
                            try:
                                process.wait(timeout=1)
                            except subprocess.TimeoutExpired:
                                pass
                        else:
                            time.sleep(0.25)
                        members = live_group(process.pid)
                process.wait(timeout=5)
                state["remainingOwnedProcessGroup"] = members
                state["observedPhaseExitCode"] = process.returncode
                if members:
                    cleanup_errors.append("Owned phase group survived bounded TERM/KILL")
            except Exception as failure:
                cleanup_errors.append("Owned phase cleanup: " + str(failure))
        try:
            result = subprocess.run(["xcrun", "simctl", "shutdown", device],
                                    capture_output=True, text=True, timeout=30, env=env)
            devices = json.loads(h.run(["xcrun", "simctl", "list", "devices", "-j"], env=env, timeout=15))
            found = [x for values in devices["devices"].values() for x in values if x["udid"].upper() == device]
            observed = found[0]["state"] if len(found) == 1 else "UNKNOWN"
            state["ownedSimulatorCleanup"] = {"device": device, "ownership": str(ownership),
                "exitCode": result.returncode, "stdout": result.stdout, "stderr": result.stderr,
                "observedState": observed, "observedAt": h.utc()}
            if observed != "Shutdown":
                cleanup_errors.append("Owned simulator not confirmed Shutdown")
        except Exception as failure:
            cleanup_errors.append("Owned simulator cleanup: " + str(failure))
        state["cleanupErrors"] = cleanup_errors
        if cleanup_errors:
            state["status"] = "CLEANUP_INCOMPLETE"
        source_errors = []
        try:
            if h.run(["git", "rev-parse", "HEAD"], cwd=root) != d["source"]:
                source_errors.append("Git HEAD changed")
            for item in required:
                if digest(h.relative(root, item["path"])) != item["sha256"]:
                    source_errors.append("Source changed: " + item["path"])
            for item in product_files:
                if digest(item["path"]) != item["sha256"]:
                    source_errors.append("Product changed: " + item["path"])
            if digest(companion_decision_path) != d["originalCompanionDecisionSHA256"] or digest(notification_review_path) != d["notificationReviewSHA256"]:
                source_errors.append("Historical companion decision or notification result changed")
        except Exception as failure:
            source_errors.append("Final input observation: " + str(failure))
        state["sourceErrors"] = source_errors
        if source_errors:
            state["status"] = "INPUT_DRIFT"
        elapsed = time.monotonic() - start
        checkpoint("charge_ready", finishedAt=h.utc(), elapsedSeconds=elapsed, chargedSeconds=elapsed,
                   cumulativeActiveSeconds=baseline + elapsed,
                   cumulativeCompanionSeconds=ORIGINAL_CHARGE + elapsed,
                   allowanceExceededDuringCleanup=elapsed > allowance,
                   logBytes=log.stat().st_size if log.exists() else 0,
                   logSHA256=digest(log) if log.exists() else None)
        try:
            current = json.loads(primary_path.read_text())
            assert current["activeElapsedSeconds"] == baseline and current.get("controllerPID") == os.getpid()
            assert digest(ledger_path) == d["companionLedgerSHA256"]
            charge = {"id": ID, "source": d["source"], "status": state["status"],
                      "elapsedSeconds": elapsed, "statePath": str(state_path),
                      "decisionSHA256": state["decisionSHA256"], "logSHA256": state["logSHA256"],
                      "exitCode": exit_code, "selector": SELECTOR}
            updated_ledger = json.loads(ledger_bytes)
            updated_ledger["activeElapsedSeconds"] = ORIGINAL_CHARGE + elapsed
            updated_ledger["charges"].append(charge)
            if state["status"] == "EXECUTED_PASS":
                updated_ledger["remainingSelectors"] = []
                updated_ledger.setdefault("verifiedResults", []).append({
                    "path": str(out / "native-result/result-review.json"),
                    "sha256": state["resultReviewSHA256"], "status": "EXECUTED_PASS"})
            h.write(ledger_path, updated_ledger)
            current["activeElapsedSeconds"] = baseline + elapsed
            current.setdefault("companionCharges", []).append(charge)
            current.update(status=primary["status"] if state["status"] == "EXECUTED_PASS" else "FAIL",
                           phase=primary.get("phase"), controllerPID=None, finishedAt=state["finishedAt"])
            if error:
                current["error"] = error
            h.write(primary_path, current)
            state["chargeCommitted"] = True
            state["companionLedgerAfterSHA256"] = digest(ledger_path)
        except Exception as failure:
            state.update(status="LEDGER_RECONCILIATION_REQUIRED",
                         ledgerError=str(failure), uncommittedOrPartiallyCommittedChargeSeconds=elapsed)
        checkpoint("finalized", status=state["status"])
    return 0 if state["status"] == "EXECUTED_PASS" else 1


if __name__ == "__main__":
    raise SystemExit(main())
