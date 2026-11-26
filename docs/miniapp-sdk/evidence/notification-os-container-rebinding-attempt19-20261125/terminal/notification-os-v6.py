"""DRAFT only. Native owner seals a final-input decision before any execution.
Extra OS900 uses the published original UI case and actual simctl-push worker.
No build, source/fixture generation or product queue writes. The sole intentional
product-container write stages the unchanged825-byte Actions input in Documents.
"""
from pathlib import Path
import argparse
import datetime
import fcntl
import hashlib
import importlib.util
import json
import os
import shlex
import plistlib
import signal
import subprocess
import sys
import time
import uuid

ID = "notification-os-v1"
SELECTOR = "HanlinMiniAppsUITests/MiniAppsProductionRuntimeUITests/testOriginalNotificationAuthorizationAndOSDeliveryToBothEngines"
WORKER = "Scripts/CI/observe_notification_os_delivery.py"
WORKER_SHA = "f6cf4e040f592fa94ebf9fd813b6e03d125d5c7c32dc2d2a43f3b42cdb33d085"
UI_SOURCE = "HanlinMiniAppsUITests/HanlinMiniAppsUITests.swift"
UI_SHA = "da0fa21f26b677f4d18f8e1972208b39e30401a127e9dd2a9643e0fe8d7ad17c"
RUNNER = "Scripts/ProductSplit/run_paired_acceptance.py"
RUNNER_SHA = "a99b6194f8dd20bc30998ff2ad9e86ec219415a00615b250c65670f7dfcdba7d"
HELPER_SHA = "dad6581212134987b666a5161ab33994e6d79b57ed38108faba6ffb22c3bb520"
ACTIONS = "Fixtures/Widgets/Hanlin-ScriptWidget-Actions.scripting"
ACTIONS_SHA = "33c717e2a454d8831364cb24b15b9e9e799cd3161b526013a15efe46485ebccb"
PRODUCT_ID = "com.itorah.hanlinminiapps"
GROUP = "group.com.itorah.chavrusachat"


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


def read_decision(path):
    raw = path.read_bytes()
    d = json.loads(raw)
    assert d["schema"] == 1 and d["id"] == ID and d["owner"] == "/root/native_execution"
    assert d["authorization"] == {"by": "/root", "scope": "separate original notification OS probe"}
    assert d["selector"] == SELECTOR and d["expectedTests"] == 1 and d["allowanceSeconds"] == 900
    assert d["separateFromPaired4500AndCompanion1200"] is True
    root = Path(d["root"]).resolve()
    helper = (root / d["originalController"]["path"]).resolve()
    assert helper.is_relative_to(root / "build/primary-control")
    assert digest(helper) == d["originalController"]["sha256"] == HELPER_SHA
    h = load_module(helper, "original_native_owner_helpers")
    for p, expected in [(RUNNER, RUNNER_SHA), (WORKER, WORKER_SHA), (UI_SOURCE, UI_SHA), (ACTIONS, ACTIONS_SHA)]:
        assert digest(root / p) == expected, p
    assert (root / ACTIONS).stat().st_size == 825
    return raw, d, root, h


def original_runner(root, evidence):
    sys.path.insert(0, str(root / "Scripts/ProductSplit"))
    r = load_module(root / RUNNER, "original_paired_for_notification_os")
    r.EVIDENCE = evidence
    return r


def child_setup(decision_path):
    _, d, root, h = read_decision(decision_path)
    out = h.relative(root, d["outputDirectory"])
    evidence = out / "setup"
    r = original_runner(root, evidence)
    device = str(uuid.UUID(d["simulator"]["udid"])).upper()
    _, raw = r.command(["xcrun", "simctl", "list", "devices", "-j"], "devices-before.json", timeout=15)
    found = [x for values in json.loads(raw)["devices"].values() for x in values if x["udid"].upper() == device]
    assert len(found) == 1 and found[0]["state"] in ("Booted", "Shutdown")
    if found[0]["state"] == "Shutdown":
        r.command(["xcrun", "simctl", "boot", device], "boot-owned.log", timeout=30)
    r.command(["xcrun", "simctl", "bootstatus", device, "-b"], "bootstatus.log", timeout=300)
    # Obtain the runner's true bundle ID from the completed built product.
    runner_info = Path(d["uiRunnerInfoPlist"]).resolve()
    info = plistlib.loads(runner_info.read_bytes())
    runner_bundle = info["CFBundleIdentifier"]
    assert isinstance(runner_bundle, str) and runner_bundle.endswith(".xctrunner")
    device_root = (Path.home() / "Library/Developer/CoreSimulator/Devices" / device / "data/Containers").resolve()
    actual = {}
    for role, bundle, kind in [("runnerData", runner_bundle, "data"),
                               ("appData", PRODUCT_ID, "data"),
                               ("appGroup", PRODUCT_ID, GROUP)]:
        # Same original simctl get_app_container syntax, bounded5s per lookup.
        _, raw = r.command(["xcrun", "simctl", "get_app_container", device, bundle, kind],
                           role + "-container.txt", timeout=5)
        path = Path(raw.strip()).resolve(strict=True)
        assert path.is_dir() and path.is_relative_to(device_root)
        actual[role] = str(path)
    assert actual["runnerData"] != actual["appData"]
    documents = Path(actual["appData"]) / "Documents"
    assert documents.is_dir()
    fixture = root / ACTIONS
    destination = documents / fixture.name
    if destination.exists():
        assert destination.is_file() and digest(destination) == ACTIONS_SHA
        staged = "REUSED_IDENTICAL_EXISTING_INPUT"
    else:
        # Only this already-authorized immutable import input is staged.
        with destination.open("xb") as stream:
            stream.write(fixture.read_bytes())
            stream.flush()
            os.fsync(stream.fileno())
        staged = "STAGED_ORIGINAL_INPUT"
    assert destination.stat().st_size == 825 and digest(destination) == ACTIONS_SHA
    existing = []
    for relative in ["AI_HLYUITests/Fixtures/ExpoSwiftUIProbeA.hanlinExpo",
                     "DemoMiniApps/hanlin-script-parity.hanlinNativeScript"]:
        original = root / relative
        installed_input = documents / original.name
        assert installed_input.is_file() and digest(installed_input) == digest(original)
        existing.append({"source": relative, "path": str(installed_input), "sha256": digest(original)})
    record = {"source": d["source"], "decisionSHA256": digest(decision_path), "observedAt": h.utc(),
              "device": device, "runnerBundleID": runner_bundle, "uiRunnerInfoSHA256": digest(runner_info),
              **actual, "actionInput": {"source": ACTIONS, "path": str(destination),
              "bytes": 825, "sha256": ACTIONS_SHA, "status": staged},
              "existingOriginalInputsVerifiedWithoutCopy": existing,
              "boundary": "OS returned current owned-device containers. No permission grant, registry, queue or receipt is manufactured."}
    h.write(out / "execution-containers.json", record)
    return 0


def child_test(decision_path):
    _, d, root, h = read_decision(decision_path)
    out = h.relative(root, d["outputDirectory"])
    evidence = out / "test"
    r = original_runner(root, evidence)
    device = str(uuid.UUID(d["simulator"]["udid"])).upper()
    argv = ["xcodebuild", "-project", "AI_HLY.xcodeproj",
            "-destination", "platform=iOS Simulator,id=" + device,
            "-parallel-testing-enabled", "NO", "-derivedDataPath", d["derivedData"],
            "-clonedSourcePackagesDirPath", str(root / "build/SourcePackages"),
            "-skipPackagePluginValidation", "-skipMacroValidation",
            "CODE_SIGNING_ALLOWED=YES", "CODE_SIGNING_REQUIRED=YES", "CODE_SIGN_IDENTITY=-",
            "-collect-test-diagnostics", "never", "-scheme", "HanlinMiniApps", "test-without-building",
            "-resultBundlePath", str(evidence / "NotificationOS.xcresult"),
            "-only-testing:" + SELECTOR]
    # Preserve the original UI600s executionTimeAllowance and worker650s limit.
    # Original1200s command timeout is bounded by the outer separate900s allowance.
    h.write(evidence / "selected-command.json", {"argv": argv, "selector": SELECTOR,
             "expectedTests": 1, "source": d["source"], "runnerSHA256": RUNNER_SHA})
    code, _ = r.command(argv, "notification-os-tests.log", timeout=1200, allow_failure=True)
    result = evidence / "NotificationOS.xcresult"
    assert (result / "Info.plist").is_file(), "Actual XCTest result must finalize"
    summary = r.verify_native_result(result, "notification-os", [SELECTOR], 1, code)
    h.write(evidence / "result-review.json", {"status": "EXECUTED_PASS", "source": d["source"],
             "selector": SELECTOR, "commandExitCode": code, "summary": summary,
             "resultInfoSHA256": digest(result / "Info.plist"),
             "summarySHA256": digest(evidence / "notification-os-summary.json"),
             "nodesSHA256": digest(evidence / "notification-os-nodes.json"),
             "selectorVerifierLogSHA256": digest(evidence / "notification-os-selected-tests.log"),
             "reviewedAt": h.utc(), "requiresSeparateWorkerResult": True})
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
    parser.add_argument("--child", choices=["setup", "test"])
    args = parser.parse_args()
    decision_path = args.decision.resolve()
    if args.child:
        return child_setup(decision_path) if args.child == "setup" else child_test(decision_path)
    decision_bytes, d, root, h = read_decision(decision_path)
    ctrl = root / "build/primary-control"
    out = h.relative(root, d["outputDirectory"])
    assert out.is_relative_to(ctrl) and not out.exists()
    lock = (ctrl / "native-continuation-owner.lock").open("a")
    fcntl.flock(lock.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
    primary_path = ctrl / "state.json"
    assert digest(primary_path) == d["primaryStateSHA256"]
    primary_bytes = primary_path.read_bytes()
    primary = json.loads(primary_bytes)
    assert primary["source"] == d["source"] and primary["status"] in ("COMPLETED", "FAIL", "PAUSED_AFTER_PHASE")
    assert primary["activeElapsedSeconds"] == d["activeBaselineSeconds"]
    assert h.run(["git", "rev-parse", "HEAD"], cwd=root) == d["source"]
    assert h.run(["git", "rev-parse", "HEAD^{tree}"], cwd=root) == d["sourceTree"]
    assert hashlib.sha256(subprocess.check_output(["git", "diff", "--binary", "HEAD"], cwd=root)).hexdigest() == d["preparedTrackedDiffSHA256"]
    required = d["requiredFiles"]
    assert {RUNNER, WORKER, UI_SOURCE, ACTIONS, "Scripts/CI/verify_selected_tests.py",
            "AI_HLYUITests/Fixtures/ExpoSwiftUIProbeA.hanlinExpo",
            "DemoMiniApps/hanlin-script-parity.hanlinNativeScript", "AI_HLY/RuntimeHostResources.zip"} <= {x["path"] for x in required}
    for item in required:
        assert digest(h.relative(root, item["path"])) == item["sha256"]
    assert digest(root / "AI_HLY/RuntimeHostResources.zip") == d["sdk"]["archiveSHA256"]
    assert digest(h.relative(root, d["sdk"]["manifestPath"])) == d["sdk"]["manifestSHA256"]
    sdk = json.loads(h.relative(root, d["sdk"]["manifestPath"]).read_text())
    assert sdk["inputSHA256"] == d["sdk"]["inputSHA256"]
    products_root = Path(d["derivedData"]).resolve() / "Build/Products"
    products = d["productFiles"]
    assert {"miniAppExecutable", "miniRuntimeImage", "miniHostResource", "uiRunnerInfo",
            "uiRunnerExecutable", "uiTestExecutable", "xctestrun"} <= {x["role"] for x in products}
    for item in products:
        p = Path(item["path"]).resolve()
        assert p.is_file() and p.is_relative_to(products_root) and digest(p) == item["sha256"]
        if item["role"] == "miniHostResource":
            assert item["sha256"] == d["sdk"]["archiveSHA256"]
    assert any(x["role"] == "uiRunnerInfo" and Path(x["path"]).resolve() == Path(d["uiRunnerInfoPlist"]).resolve() for x in products)
    assert d["productProvenance"]["source"] == d["source"]
    for item in d["productProvenance"]["receipts"]:
        assert digest(h.relative(root, item["path"])) == item["sha256"]

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
    prior_records = {}
    for role in ["pairedTerminal", "ns5Terminal"]:
        item = d[role]
        p = h.relative(root, item["path"])
        assert digest(p) == item["sha256"]
        state = json.loads(p.read_text())
        assert state["source"] == d["source"] and state["status"] in ("EXECUTED_PASS", "FAILED", "TIMED_OUT")
        assert not state["remainingOwnedProcessGroup"] and not state["cleanupErrors"] and not state["sourceErrors"]
        exclusion = historical_group_exclusion(state, item, root, Path(d["derivedData"]), live_group, h.utc)
        if exclusion is not None:
            historical_group_exclusions.append(exclusion)
        prior_records[role] = state
    paired, ns5 = prior_records["pairedTerminal"], prior_records["ns5Terminal"]
    assert ns5["id"] == "companion-native-v1-ns5" and ns5.get("chargeCommitted") is True
    ownership = Path(paired["pairedEvidence"]).resolve() / "created-simulator.txt"
    assert ownership.is_relative_to(ctrl) and digest(ownership) == d["simulator"]["ownershipSHA256"]
    device = str(uuid.UUID(ownership.read_text().strip())).upper()
    assert device == str(uuid.UUID(d["simulator"]["udid"])).upper()
    assert ns5["ownedSimulatorCleanup"]["device"] == device and ns5["ownedSimulatorCleanup"]["observedState"] == "Shutdown"
    prior_controllers = {paired["controllerPID"], ns5["controllerPID"], primary.get("controllerPID")} - {None}
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

    companion_ledger_path = ctrl / "companion-native-v1/ledger.json"
    assert digest(companion_ledger_path) == d["companionLedgerSHA256"]
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
    for name in ["setup", "test"]:
        (out / name).mkdir()
    frozen = out / "decision.json"
    frozen.write_bytes(decision_bytes)
    (out / "primary-state-before.json").write_bytes(primary_bytes)
    (out / "companion-ledger-before.json").write_bytes(companion_ledger_path.read_bytes())
    for role in ["pairedTerminal", "ns5Terminal"]:
        (out / (role + "-before.json")).write_bytes(h.relative(root, d[role]["path"]).read_bytes())
    state_path, ledger_path, events = out / "state.json", out / "ledger.json", out / "events.jsonl"
    baseline, allowance = primary["activeElapsedSeconds"], 900
    ledger = {"schema": 1, "id": ID, "maximumActiveSeconds": 900, "activeElapsedSeconds": 0,
              "charges": [], "source": d["source"], "separateFromPaired4500AndCompanion1200": True}
    h.write(ledger_path, ledger)
    state = {"schema": 1, "id": ID, "owner": d["owner"], "source": d["source"],
             "status": "STARTING", "selector": SELECTOR, "expectedTests": 1,
             "controllerPID": os.getpid(), "activeBaselineSeconds": baseline, "allowanceSeconds": 900,
             "decisionSHA256": hashlib.sha256(decision_bytes).hexdigest(),
             "original52Status": paired.get("original52"), "NS5Status": ns5["status"],
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
               DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer", GITHUB_WORKSPACE=str(root),
               GITHUB_SHA=d["source"], SPLIT_EVIDENCE=str(out), SPLIT_DERIVED_DATA=d["derivedData"],
               PAIRED_TEST_SCOPE="miniapp_complete", RUNNER_TEMP=str(root / "build/primary-temp"))
    processes, streams = {}, {}
    start = time.monotonic()
    checkpoint("prepared", startedAt=h.utc())
    running = dict(primary)
    running.update(status="RUNNING", phase=ID, controllerPID=os.getpid())
    h.write(primary_path, running)

    def interrupt(signum, frame):
        raise InterruptedError("OS probe received signal " + str(signum))

    signal.signal(signal.SIGTERM, interrupt)
    signal.signal(signal.SIGINT, interrupt)

    def launch(role, argv):
        stream = (out / (role + ".log")).open("xb")
        streams[role] = stream
        process = subprocess.Popen(argv, cwd=root, env=env, stdout=stream,
                                   stderr=subprocess.STDOUT, start_new_session=True)
        processes[role] = process
        state.setdefault("ownedProcessGroups", {})[role] = {"pid": process.pid, "pgid": process.pid, "argv": argv}
        checkpoint("launched_" + role, status="RUNNING")
        return process

    def remaining():
        value = allowance - (time.monotonic() - start)
        if value <= 0:
            raise TimeoutError("Separate900s original OS probe allowance elapsed")
        return value

    error = None
    try:
        own = str(Path(__file__).resolve())
        setup = launch("setup", [sys.executable, own, "--decision", str(frozen), "--child", "setup"])
        while True:
            try:
                code = setup.wait(timeout=min(30, remaining()))
                break
            except subprocess.TimeoutExpired:
                checkpoint("setup_heartbeat", elapsedSeconds=time.monotonic() - start)
        assert code == 0, "Owned simulator/container/input setup failed"
        containers_path = out / "execution-containers.json"
        containers = json.loads(containers_path.read_text())
        assert containers["source"] == d["source"] and containers["decisionSHA256"] == digest(frozen)
        assert containers["device"] == device
        started_after = time.time()
        worker_argv = [sys.executable, str(root / WORKER), "--device", device,
                       "--runner-data", containers["runnerData"], "--app-data", containers["appData"],
                       "--app-group", containers["appGroup"], "--output", str(out / "observation"),
                       "--started-after", str(started_after), "--timeout", "650"]
        worker = launch("worker", worker_argv)
        assert worker.poll() is None, "Original observer terminated before the UI test"
        test = launch("test", [sys.executable, own, "--decision", str(frozen), "--child", "test"])
        checkpoint("worker_preceded_test", executionContainersSHA256=digest(containers_path),
                   exchangeStartedAfter=started_after, workerPID=worker.pid, testPID=test.pid)
        while True:
            remaining()
            test_code, worker_code = test.poll(), worker.poll()
            if test_code is not None and test_code != 0:
                raise RuntimeError("Original selected XCTest/verification failed")
            if test_code is not None and worker_code is not None:
                break
            try:
                (test if test_code is None else worker).wait(timeout=min(30, remaining()))
            except subprocess.TimeoutExpired:
                pass
            checkpoint("heartbeat", elapsedSeconds=time.monotonic() - start,
                       testExitCode=test.poll(), workerExitCode=worker.poll())
        assert test_code == worker_code == 0
        review_path = out / "test/result-review.json"
        observer_path = out / "observation/observation-result.json"
        review, observation = json.loads(review_path.read_text()), json.loads(observer_path.read_text())
        assert review["status"] == observation["status"] == "EXECUTED_PASS"
        assert review["source"] == d["source"] and review["selector"] == SELECTOR
        assert review["summary"]["passedTests"] == 1 and not review["summary"].get("failedTests", 0) and not review["summary"].get("skippedTests", 0)
        assert observation["requiresSeparateXCTestTerminalResult"] is True
        checkpoint("actual_terminal", status="EXECUTED_PASS", testExitCode=0, workerExitCode=0,
                   resultReviewSHA256=digest(review_path), observationResultSHA256=digest(observer_path))
    except BaseException as failure:
        error = type(failure).__name__ + ": " + str(failure)
        checkpoint("actual_terminal", status="TIMED_OUT" if isinstance(failure, TimeoutError) else "FAILED", error=error)
    finally:
        signal.signal(signal.SIGTERM, signal.SIG_IGN)
        signal.signal(signal.SIGINT, signal.SIG_IGN)
        cleanup_errors, remaining_groups = [], {}
        for role, process in processes.items():
            try:
                members = live_group(process.pid)
                state.setdefault("ownedGroupsAtCleanup", {})[role] = members
                for sig, seconds in [(signal.SIGTERM, 20), (signal.SIGKILL, 10)]:
                    if not members:
                        break
                    try:
                        os.killpg(process.pid, sig)
                    except ProcessLookupError:
                        pass
                    deadline = time.monotonic() + seconds
                    while members and time.monotonic() < deadline:
                        if process.poll() is None:
                            try:
                                process.wait(timeout=1)
                            except subprocess.TimeoutExpired:
                                pass
                        else:
                            time.sleep(0.25)
                        members = live_group(process.pid)
                process.wait(timeout=5)
                remaining_groups[role] = members
                state.setdefault("observedExitCodes", {})[role] = process.returncode
                if members:
                    cleanup_errors.append(role + " PGID survived bounded cleanup")
            except Exception as failure:
                cleanup_errors.append(role + " group cleanup: " + str(failure))
            finally:
                streams[role].close()
        state["remainingOwnedProcessGroups"] = remaining_groups
        try:
            result = subprocess.run(["xcrun", "simctl", "shutdown", device], capture_output=True,
                                    text=True, timeout=30, env=env)
            devices = json.loads(h.run(["xcrun", "simctl", "list", "devices", "-j"], env=env, timeout=15))
            found = [x for values in devices["devices"].values() for x in values if x["udid"].upper() == device]
            observed = found[0]["state"] if len(found) == 1 else "UNKNOWN"
            state["ownedSimulatorCleanup"] = {"device": device, "ownership": str(ownership),
                "exitCode": result.returncode, "stdout": result.stdout, "stderr": result.stderr,
                "observedState": observed, "observedAt": h.utc()}
            if observed != "Shutdown":
                cleanup_errors.append("Owned simulator not confirmed Shutdown")
        except Exception as failure:
            cleanup_errors.append("Simulator cleanup: " + str(failure))
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
            for item in products:
                if digest(item["path"]) != item["sha256"]:
                    source_errors.append("Product changed: " + item["path"])
            for role in ["pairedTerminal", "ns5Terminal"]:
                if digest(h.relative(root, d[role]["path"])) != d[role]["sha256"]:
                    source_errors.append("Historical terminal changed: " + role)
            if digest(companion_ledger_path) != d["companionLedgerSHA256"]:
                source_errors.append("Original companion1200 ledger changed")
        except Exception as failure:
            source_errors.append("Final input observation: " + str(failure))
        state["sourceErrors"] = source_errors
        if source_errors:
            state["status"] = "INPUT_DRIFT"
        elapsed = time.monotonic() - start
        log_files = [{"path": p.name, "bytes": p.stat().st_size, "sha256": digest(p)}
                     for p in out.glob("*.log") if p.is_file()]
        checkpoint("charge_ready", finishedAt=h.utc(), elapsedSeconds=elapsed, chargedSeconds=elapsed,
                   cumulativeActiveSeconds=baseline + elapsed, allowanceExceededDuringCleanup=elapsed > 900,
                   processLogs=log_files)
        try:
            current = json.loads(primary_path.read_text())
            assert current["activeElapsedSeconds"] == baseline and current.get("controllerPID") == os.getpid()
            charge = {"id": ID, "source": d["source"], "status": state["status"],
                      "elapsedSeconds": elapsed, "statePath": str(state_path),
                      "decisionSHA256": state["decisionSHA256"], "selector": SELECTOR,
                      "separateFromPaired4500AndCompanion1200": True}
            ledger["activeElapsedSeconds"] = elapsed
            ledger["charges"].append(charge)
            h.write(ledger_path, ledger)
            current["activeElapsedSeconds"] = baseline + elapsed
            current.setdefault("osProbeCharges", []).append(charge)
            current.update(status=primary["status"] if state["status"] == "EXECUTED_PASS" else "FAIL",
                           phase=primary.get("phase"), controllerPID=None, finishedAt=state["finishedAt"])
            if error:
                current["error"] = error
            h.write(primary_path, current)
            state["chargeCommitted"] = True
        except Exception as failure:
            state.update(status="LEDGER_RECONCILIATION_REQUIRED", ledgerError=str(failure),
                         uncommittedOrPartiallyCommittedChargeSeconds=elapsed)
        checkpoint("finalized", status=state["status"])
    return 0 if state["status"] == "EXECUTED_PASS" else 1


if __name__ == "__main__":
    raise SystemExit(main())
