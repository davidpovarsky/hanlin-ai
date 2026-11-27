"""Independent recovery on a newly owned simulator using unchanged prebuilt artifacts.
Original UI case, Python worker and result verifier remain byte-identical.
The historical OS900 ledger is immutable; preparation and this observation share a new900.
This controller never restores or rewrites the disappeared historical primary state.
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

ID = "notification-os-recovery-v1"
ROOT = Path("/Users/m1/builds/hanlin-notification-os-recovery-20261125")
SOURCE = "d4a0b115b106d4250ea40ad66153d5156847a07c"
SDK_SOURCE = "a2c8a1b1be746461272ba77254603304567c309d"
PRODUCTS = Path("/Users/m1/caches/DerivedData/hanlin-ai-ce49e30d-miniapp-complete/Build/Products")
SELECTOR = "HanlinMiniAppsUITests/MiniAppsProductionRuntimeUITests/testOriginalNotificationAuthorizationAndOSDeliveryToBothEngines"
WORKER = "Scripts/CI/observe_notification_os_delivery.py"
WORKER_SHA = "f6cf4e040f592fa94ebf9fd813b6e03d125d5c7c32dc2d2a43f3b42cdb33d085"
RUNNER = "Scripts/ProductSplit/run_paired_acceptance.py"
RUNNER_SHA = "a99b6194f8dd20bc30998ff2ad9e86ec219415a00615b250c65670f7dfcdba7d"
ACTIONS = "Fixtures/Widgets/Hanlin-ScriptWidget-Actions.scripting"
ACTIONS_SHA = "33c717e2a454d8831364cb24b15b9e9e799cd3161b526013a15efe46485ebccb"
PRODUCT_ID = "com.itorah.hanlinminiapps"
GROUP = "group.com.itorah.chavrusachat"
RECEIPT_SHA = "3a51b93378c45a565a50355c7735d094a769b4c433808a06b1412e5ba22e1dba"
PREPARATION_SHA = "5c09ded5e075df3247287ed62e71e6abc52e6e15c4aa4f25c1c7892b71ad4886"
HISTORICAL_OS_SECONDS = math.fsum([353.58866224999656, 12.940106750000268, 530.7739816670073])
HISTORICAL_PRIMARY_SECONDS = 25204.83441242004
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
    assert d["schema"] == 1 and d["id"] == ID and d["owner"] == "/root/native_execution"
    assert d["authorization"] == {"by": "/root", "scope": "independent recovered-device original notification OS observation"}
    assert Path(d["root"]) == ROOT and ROOT.is_dir() and ROOT == ROOT.resolve()
    assert d["source"] == d["compiledConsumerSource"] == SOURCE and d["SDKProducerSource"] == SDK_SOURCE
    assert d["selector"] == SELECTOR and d["expectedTests"] == 1 and d["allowanceSeconds"] == 900
    assert d["outputDirectory"] == "build/" + ID
    assert d["resourceBoundBytes"] == RESOURCE_BOUND
    assert d["recoveryReceipt"] == {"path": str(ROOT / "recovery/receipt.json"), "bytes": 58635, "sha256": RECEIPT_SHA}
    recovery = json.loads(verify_file(d["recoveryReceipt"]).read_text())
    assert recovery["status"] == "PREPARED_SOURCE_AND_NEW_SHUTDOWN_DEVICE" and recovery["owner"] == d["owner"]
    assert recovery["root"] == str(ROOT) and recovery["source"] == recovery["compiledConsumerSource"] == SOURCE
    assert recovery["SDKProducerSource"] == SDK_SOURCE
    assert recovery["applicationInstall"] == recovery["applicationDocumentStaging"] == recovery["nativeTestExecution"] == "NOT_RUN"
    assert recovery["bootPerformed"] is False and recovery["error"] is None
    assert d["simulator"] == recovery["simulator"] and d["simulator"]["observedState"] == "Shutdown"
    assert d["productFiles"] == recovery["productFiles"] == recovery["productFilesBefore"] == recovery["productFilesAfter"]
    assert len(d["productFiles"]) == 44 and len({r["path"] for r in d["productFiles"]}) == 39
    assert d["sourceFiles"] == recovery["sourceFiles"] and len(d["sourceFiles"]) == 5
    assert d["fixtures"] == recovery["fixtures"] and len(d["fixtures"]) == 3
    assert d["stagedFiles"] == [{k: row[k] for k in ("name", "bytes", "sha256")} for row in d["fixtures"] if row["name"] != Path(ACTIONS).name]
    assert len(d["stagedFiles"]) == 2
    assert d["directArtifactObservation"] == {"kind": "UNCHANGED_PREBUILT_XCTESTRUN", "xctestrun": recovery["xctestrun"]}
    assert d["derivedData"] == str(PRODUCTS.parent.parent)
    assert d["uiRunnerInfoPlist"] == str(PRODUCTS / "Debug-iphonesimulator/HanlinMiniAppsUITests-Runner.app/Info.plist")
    assert d["preparationLedger"] == recovery["preparationLedger"] and d["preparationLedger"]["sha256"] == PREPARATION_SHA
    for key in ("historicalLedger", "historicalPrimary", "historicalTerminal", "historicalCleanupReconciliation"):
        assert d[key] == recovery[key] and d[key]["historical"] is True
    for row in d["sourceFiles"]:
        verify_file(row, ROOT)
    assert {row["path"]: row["sha256"] for row in d["sourceFiles"]}[RUNNER] == RUNNER_SHA
    assert {row["path"]: row["sha256"] for row in d["sourceFiles"]}[WORKER] == WORKER_SHA
    for row in d["fixtures"]:
        assert Path(row["sourcePath"]).is_relative_to(ROOT)
        verify_file({"path": row["sourcePath"], "bytes": row["bytes"], "sha256": row["sha256"]})
    controller = verify_file(d["controller"])
    assert controller == Path(__file__).resolve() == ROOT / "recovery/notification-os-recovery-v1.py"
    return raw, d, ROOT, SimpleNamespace(relative=relative, write=write, utc=utc, run=run)


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
    # Original install timeout300; install the existing Mini app and UI runner only.
    for name in ["HanlinMiniApps.app", "HanlinMiniAppsUITests-Runner.app"]:
        product = PRODUCTS / "Debug-iphonesimulator" / name
        assert product.is_dir()
        r.command(["xcrun", "simctl", "install", device, str(product)], name + "-install.log", timeout=300)
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
    documents.mkdir(exist_ok=True)
    assert documents.is_dir() and not documents.is_symlink()
    staged_files = []
    for row in d["fixtures"]:
        original = Path(row["sourcePath"])
        assert Path(row["name"]).name == row["name"] == original.name
        destination = documents / row["name"]
        assert not destination.exists(), "New owned device must receive each original fixture once"
        with destination.open("xb") as stream:
            stream.write(original.read_bytes())
            stream.flush()
            os.fsync(stream.fileno())
        assert destination.stat().st_size == row["bytes"] and digest(destination) == row["sha256"]
        staged_files.append({**row, "path": str(destination), "status": "COPIED_EXACT_ORIGINAL_INPUT"})
    fixture = root / ACTIONS
    destination = documents / fixture.name
    staged = "COPIED_EXACT_ORIGINAL_INPUT"
    identities = {
        "runnerData": inspect_current_container(actual["runnerData"], runner_bundle, device),
        "appData": inspect_current_container(actual["appData"], PRODUCT_ID, device),
        "appGroup": inspect_current_container(actual["appGroup"], GROUP, device, True),
    }
    record = {"source": d["source"], "decisionSHA256": digest(decision_path), "observedAt": h.utc(),
              "device": device, "runnerBundleID": runner_bundle, "uiRunnerInfoSHA256": digest(runner_info),
              **actual, "actionInput": {"source": ACTIONS, "path": str(destination),
              "bytes": 825, "sha256": ACTIONS_SHA, "status": staged},
              "originalInputsStaged": staged_files, "metadata": identities,
              "boundary": "OS returned current owned-device containers. No permission grant, registry, queue or receipt is manufactured."}
    h.write(out / "execution-containers.json", record)
    return 0

def child_test(decision_path):
    _, d, root, h = read_decision(decision_path)
    out = h.relative(root, d["outputDirectory"])
    evidence = out / "test"
    r = original_runner(root, evidence)
    device = str(uuid.UUID(d["simulator"]["udid"])).upper()
    artifact = d["directArtifactObservation"]["xctestrun"]
    xctestrun = Path(artifact["path"])
    assert xctestrun.stat().st_size == artifact["bytes"] and digest(xctestrun) == artifact["sha256"]
    argv = ["xcodebuild", "test-without-building", "-xctestrun", str(xctestrun),
            "-destination", "platform=iOS Simulator,id=" + device,
            "-parallel-testing-enabled", "NO", "-collect-test-diagnostics", "never",
            "-resultBundlePath", str(evidence / "NotificationOS.xcresult"),
            "-only-testing:" + SELECTOR]
    # Same original compiled UI case and worker limits; the new separate900s
    # observation bounds the original1200s command timeout without rebuilding.
    h.write(evidence / "selected-command.json", {"argv": argv, "selector": SELECTOR,
             "expectedTests": 1, "source": d["source"], "runnerSHA256": RUNNER_SHA,
             "executionMode": "UNCHANGED_PREBUILT_XCTESTRUN", "xctestrun": artifact})
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

def inspect_current_container(value, identifier, device, shared=False):
    path = Path(value)
    base = Path.home() / "Library/Developer/CoreSimulator/Devices" / device / "data/Containers"
    parent = base / ("Shared/AppGroup" if shared else "Data/Application")
    assert path.is_dir() and not path.is_symlink() and path == path.resolve(strict=True)
    assert path.parent == parent.resolve(strict=True)
    container_uuid = str(uuid.UUID(path.name)).upper()
    assert container_uuid == path.name.upper()
    metadata_path = path / ".com.apple.mobile_container_manager.metadata.plist"
    assert metadata_path.is_file() and not metadata_path.is_symlink()
    raw = metadata_path.read_bytes()
    metadata = plistlib.loads(raw)
    assert metadata["MCMMetadataIdentifier"] == identifier
    return {"path": str(path), "metadataPath": str(metadata_path), "metadataBytes": len(raw),
            "metadataSHA256": hashlib.sha256(raw).hexdigest(), "metadataIdentifier": identifier,
            "containerUUID": container_uuid, "metadataUUID": metadata.get("MCMMetadataUUID")}

def rebind_after_test_start(root, d, out, h, setup, test, started_after, remaining, checkpoint):
    evidence = out / "rebind"
    evidence.mkdir()
    r = original_runner(root, evidence)
    device, runner_bundle = setup["device"], setup["runnerBundleID"]
    attempt = 0
    last_heartbeat = time.monotonic()
    while True:
        remaining()
        assert test.poll() is None, "Original selected test exited before its fresh runner handshake"
        attempt += 1
        code, raw = r.command(["xcrun", "simctl", "get_app_container", device, runner_bundle, "data"],
            "runner-%04d.txt" % attempt, timeout=min(5, remaining()), allow_failure=True)
        if code == 0:
            runner = inspect_current_container(raw.strip(), runner_bundle, device)
            active_path = Path(runner["path"]) / "Documents/HanlinNotificationOSProbe/active.json"
            if active_path.is_file() and active_path.stat().st_mtime >= started_after:
                assert not active_path.is_symlink()
                before = active_path.stat()
                active_bytes = active_path.read_bytes()
                after = active_path.stat()
                assert (before.st_mtime_ns, before.st_size) == (after.st_mtime_ns, after.st_size)
                active = json.loads(active_bytes)
                assert set(active) == {"version", "runID", "challenge"} and active["version"] == 1
                assert str(uuid.UUID(active["runID"])) == active["runID"]
                assert active["challenge"].startswith("notification-os-")
                assert str(uuid.UUID(active["challenge"].removeprefix("notification-os-"))) == active["challenge"].removeprefix("notification-os-")
                break
        if time.monotonic() - last_heartbeat >= 30:
            checkpoint("waiting_for_fresh_test_runner", containerLookupAttempts=attempt,
                       exchangeStartedAfter=started_after)
            last_heartbeat = time.monotonic()
        time.sleep(min(0.5, remaining()))
    current = {"runnerData": runner["path"]}
    identities = {"runnerData": runner}
    for role, bundle, kind, identifier in [("appData", PRODUCT_ID, "data", PRODUCT_ID),
                                          ("appGroup", PRODUCT_ID, GROUP, GROUP)]:
        code, raw = r.command(["xcrun", "simctl", "get_app_container", device, bundle, kind],
            role + "-current.txt", timeout=min(5, remaining()))
        assert code == 0
        identities[role] = inspect_current_container(raw.strip(), identifier, device, role == "appGroup")
        current[role] = identities[role]["path"]
    assert current["runnerData"] != current["appData"]
    documents = Path(current["appData"]) / "Documents"
    assert documents.is_dir() and not documents.is_symlink()
    observed = []
    for row in d["stagedFiles"] + [{"name": Path(ACTIONS).name, "bytes": 825, "sha256": ACTIONS_SHA}]:
        assert Path(row["name"]).name == row["name"]
        path = documents / row["name"]
        assert path.is_file() and not path.is_symlink()
        assert path.stat().st_size == row["bytes"] and digest(path) == row["sha256"], row["name"]
        observed.append({**row, "path": str(path)})
    # Preserve exactly what the real test wrote; the control creates no exchange identity.
    assert active_path.read_bytes() == active_bytes and active_path.stat().st_mtime_ns == after.st_mtime_ns
    assert active_path.stat().st_mtime >= started_after and test.poll() is None
    (evidence / "active.json").write_bytes(active_bytes)
    for role, identity in identities.items():
        path = Path(identity["metadataPath"])
        assert digest(path) == identity["metadataSHA256"]
        (evidence / (role + "-metadata.plist")).write_bytes(path.read_bytes())
    record = {"source": d["source"], "decisionSHA256": digest(out / "decision.json"),
              "observedAt": h.utc(), "device": device, "runnerBundleID": runner_bundle,
              "setupAuthority": {"path": str(out / "execution-containers.json"),
                                 "sha256": digest(out / "execution-containers.json")},
              "exchangeStartedAfter": started_after, "lookupAttempts": attempt,
              "active": active, "activePath": str(active_path),
              "activeSHA256": hashlib.sha256(active_bytes).hexdigest(),
              "activeMtimeNs": after.st_mtime_ns, "metadata": identities,
              "documentsRoot": str(documents), "verifiedOriginalInputs": observed, **current,
              "boundary": "Current OS-returned containers and MCM identifiers after the actual fresh XCTest handshake. Read-only product/queue/receipt observation; no restaging or synthetic handshake."}
    h.write(out / "execution-containers-after-test.json", record)
    return record

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

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--decision", type=Path, required=True)
    parser.add_argument("--child", choices=["setup", "test"])
    args = parser.parse_args()
    decision_path = args.decision.resolve()
    if args.child:
        return child_setup(decision_path) if args.child == "setup" else child_test(decision_path)
    decision_bytes, d, root, h = read_decision(decision_path)
    out = h.relative(root, d["outputDirectory"])
    assert not out.exists(), "One-shot phase: existing output requires actual reconciliation, never blind replay"
    lock = (root / "recovery/native-owner.lock").open("a")
    fcntl.flock(lock.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
    required = d["sourceFiles"]
    products = d["productFiles"]
    for row in products:
        path = Path(row["path"])
        assert path.is_relative_to(PRODUCTS) and path == path.resolve()
        verify_file(row)
    artifact = d["directArtifactObservation"]["xctestrun"]
    assert artifact["bytes"] == 16737 and artifact["sha256"] == "2d6b493aa93663d03e17a15722eab010326b260ccbbb454ed12077cae45cda96"
    target = plistlib.loads(verify_file(artifact).read_bytes())["HanlinMiniAppsUITests"]
    assert target["IsUITestBundle"] is True
    assert target["TestHostPath"] == "__TESTROOT__/Debug-iphonesimulator/HanlinMiniAppsUITests-Runner.app"
    assert target["TestBundlePath"] == "__TESTHOST__/PlugIns/HanlinMiniAppsUITests.xctest"
    assert target["UITargetAppPath"] == "__TESTROOT__/Debug-iphonesimulator/HanlinMiniApps.app"
    assert target["TestHostBundleIdentifier"] == "com.itorah.hanlinminiapps.integration.uitests.xctrunner"
    historical = {key: json.loads(verify_file(d[key]).read_text()) for key in
                  ("historicalLedger", "historicalPrimary", "historicalTerminal", "historicalCleanupReconciliation")}
    old_ledger = historical["historicalLedger"]
    assert old_ledger["maximumActiveSeconds"] == 900
    assert len(old_ledger["charges"]) == 3
    assert old_ledger["activeElapsedSeconds"] == math.fsum(x["elapsedSeconds"] for x in old_ledger["charges"]) == HISTORICAL_OS_SECONDS
    assert historical["historicalPrimary"]["activeElapsedSeconds"] == HISTORICAL_PRIMARY_SECONDS
    assert historical["historicalPrimary"]["osProbeCharges"] == old_ledger["charges"]
    assert historical["historicalTerminal"]["status"] == "CLEANUP_INCOMPLETE"
    assert historical["historicalTerminal"]["cleanupErrors"] == ["test group cleanup: [Errno 1] Operation not permitted"]
    prep = json.loads(verify_file(d["preparationLedger"]).read_text())
    assert prep["id"] == ID and prep["maximumActiveSeconds"] == 900 and prep["separateFromOriginalOS900"] is True
    assert len(prep["charges"]) == 1 and prep["activeElapsedSeconds"] == math.fsum(x["elapsedSeconds"] for x in prep["charges"])
    prepared_seconds = prep["activeElapsedSeconds"]
    assert prepared_seconds == 1.332704125001328 and prep["remainingAllowanceSeconds"] == 900 - prepared_seconds
    device = str(uuid.UUID(d["simulator"]["udid"])).upper()
    ownership = verify_file(d["simulator"]["creationReceipt"])
    created = json.loads(ownership.read_text())
    assert created["owner"] == d["owner"] and created["root"] == str(root) and created["source"] == SOURCE
    assert created["device"] == device and created["historicalDeviceReused"] is False and created["bootPerformed"] is False
    assert created["actual"]["state"] == "Shutdown"
    current_devices = json.loads(h.run(["xcrun", "simctl", "list", "devices", "-j"], timeout=15))
    current = [x for x in current_devices["devices"].get(d["simulator"]["runtime"], []) if x["udid"].upper() == device]
    assert len(current) == 1 and current[0]["state"] == "Shutdown" and current[0]["isAvailable"] is True
    assert current[0]["name"] == d["simulator"]["name"] and current[0]["deviceTypeIdentifier"] == d["simulator"]["deviceType"]
    disk = h.run(["/bin/df", "-k", str(root)], timeout=15)
    free = int(disk.splitlines()[-1].split()[3]) * 1024
    assert free >= RESOURCE_BOUND, "Original approved single-case resource bound is not met"
    out.mkdir(parents=True)
    for name in ["setup", "test"]:
        (out / name).mkdir()
    frozen = out / "decision.json"
    frozen.write_bytes(decision_bytes)
    (out / "recovery-receipt.json").write_bytes(Path(d["recoveryReceipt"]["path"]).read_bytes())
    (out / "preparation-ledger-before.json").write_bytes(Path(d["preparationLedger"]["path"]).read_bytes())
    state_path, ledger_path, events = out / "state.json", out / "ledger.json", out / "events.jsonl"
    baseline, allowance = HISTORICAL_PRIMARY_SECONDS, 900 - prepared_seconds
    ledger = dict(prep)
    ledger["charges"] = list(prep["charges"])
    ledger.update(source=SOURCE, compiledConsumerSource=SOURCE, SDKProducerSource=SDK_SOURCE,
                  recoveryReceipt=d["recoveryReceipt"], historicalPrimary=d["historicalPrimary"])
    h.write(ledger_path, ledger)
    state = {"schema": 1, "id": ID, "owner": d["owner"], "source": SOURCE,
             "compiledConsumerSource": SOURCE, "SDKProducerSource": SDK_SOURCE,
             "status": "STARTING", "selector": SELECTOR, "expectedTests": 1,
             "controllerPID": os.getpid(), "activeBaselineSeconds": baseline, "allowanceSeconds": 900,
             "decisionSHA256": hashlib.sha256(decision_bytes).hexdigest(),
             "remainingAllowanceSeconds": allowance, "preparationChargedSeconds": prepared_seconds,
             "historicalOSChargedSeconds": HISTORICAL_OS_SECONDS,
             "historicalOriginalOSUnusedSeconds": 900 - HISTORICAL_OS_SECONDS,
             "historicalTerminalStatus": historical["historicalTerminal"]["status"],
             "postTerminalCleanupReconciliation": d["historicalCleanupReconciliation"],
             "independentNewDevice": d["simulator"], "recoveryReceipt": d["recoveryReceipt"],
             "directArtifactObservation": d["directArtifactObservation"],
             "resourceObservationAtLaunch": {"observedAt": h.utc(), "freeBytes": free, "df": disk},
             "boundary": "Independent new-device observation; immutable historical primary and original OS ledger are never rewritten."}

    def checkpoint(event, **fields):
        state.update(fields)
        h.write(state_path, state)
        with events.open("a") as stream:
            stream.write(json.dumps({"at": h.utc(), "event": event, **fields}) + "\n")
            stream.flush()
            os.fsync(stream.fileno())

    env = dict(os.environ)
    env.update(DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer", GITHUB_WORKSPACE=str(root),
               GITHUB_SHA=SOURCE, SPLIT_EVIDENCE=str(out), SPLIT_DERIVED_DATA=d["derivedData"],
               PAIRED_TEST_SCOPE="miniapp_complete", RUNNER_TEMP=str(root / "build/primary-temp"))
    (root / "build/primary-temp").mkdir(exist_ok=True)
    h.write(out / "execution-environment.json", {
        "perRun": {k: env[k] for k in ("DEVELOPER_DIR", "GITHUB_WORKSPACE", "GITHUB_SHA", "SPLIT_EVIDENCE",
                                     "SPLIT_DERIVED_DATA", "PAIRED_TEST_SCOPE", "RUNNER_TEMP")},
        "inheritedPATH": env.get("PATH"), "python": sys.executable,
        "externalNodeOrNpmCommand": "NOT_REQUIRED_OR_INVOKED",
        "plistEnvironment": "Exact original xctestrun bytes; no rewriting"})
    processes, streams = {}, {}
    start = time.monotonic()
    checkpoint("prepared", startedAt=h.utc())
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
            raise TimeoutError("Separate900s direct-artifact OS observation allowance elapsed")
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
        test = launch("test", [sys.executable, own, "--decision", str(frozen), "--child", "test"])
        rebound = rebind_after_test_start(root, d, out, h, containers, test, started_after, remaining, checkpoint)
        worker_argv = [sys.executable, str(root / WORKER), "--device", device,
                       "--runner-data", rebound["runnerData"], "--app-data", rebound["appData"],
                       "--app-group", rebound["appGroup"], "--output", str(out / "observation"),
                       "--started-after", str(started_after), "--timeout", "650"]
        worker = launch("worker", worker_argv)
        assert worker.poll() is None, "Original observer terminated at current-container launch"
        checkpoint("worker_bound_to_current_test", executionContainersSHA256=digest(containers_path),
                   reboundContainersSHA256=digest(out / "execution-containers-after-test.json"),
                   exchangeStartedAfter=started_after, activeIdentity=rebound["active"],
                   workerPID=worker.pid, testPID=test.pid)
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
        assert {key: observation[key] for key in ("version", "runID", "challenge")} == rebound["active"]
        assert json.loads((out / "observation/active.json").read_text()) == rebound["active"]
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
            for row in required:
                verify_file(row, root)
            for row in d["fixtures"]:
                verify_file({"path": row["sourcePath"], "bytes": row["bytes"], "sha256": row["sha256"]})
            for row in products:
                verify_file(row)
            for key in ("recoveryReceipt", "preparationLedger", "historicalLedger", "historicalPrimary",
                        "historicalTerminal", "historicalCleanupReconciliation"):
                verify_file(d[key])
            verify_file(d["simulator"]["creationReceipt"])
            verify_file(d["controller"])
        except Exception as failure:
            source_errors.append("Final immutable input observation: " + str(failure))
        state["sourceErrors"] = source_errors
        if source_errors:
            state["status"] = "INPUT_DRIFT"
        elapsed = time.monotonic() - start
        new_total = math.fsum([prepared_seconds, elapsed])
        log_files = [{"path": p.name, "bytes": p.stat().st_size, "sha256": digest(p)}
                     for p in out.glob("*.log") if p.is_file()]
        checkpoint("charge_ready", finishedAt=h.utc(), elapsedSeconds=elapsed, chargedSeconds=elapsed,
                   independentObservationChargedSeconds=new_total,
                   cumulativeActiveSeconds=math.fsum([baseline, new_total]),
                   cumulativeAllOSObservationSeconds=math.fsum([HISTORICAL_OS_SECONDS, new_total]),
                   allowanceExceededDuringCleanup=new_total > 900, processLogs=log_files)
        try:
            current = json.loads(ledger_path.read_text())
            assert current["charges"] == prep["charges"] and current["activeElapsedSeconds"] == prepared_seconds
            charge = {"id": ID, "source": SOURCE, "status": state["status"], "elapsedSeconds": elapsed,
                      "statePath": str(state_path), "decisionSHA256": state["decisionSHA256"],
                      "selector": SELECTOR, "separateFromOriginalOS900": True}
            current["charges"].append(charge)
            current["activeElapsedSeconds"] = math.fsum(x["elapsedSeconds"] for x in current["charges"])
            assert current["activeElapsedSeconds"] == new_total
            current["remainingAllowanceSeconds"] = 900 - new_total
            current["cumulativeAllOSObservationSeconds"] = math.fsum([HISTORICAL_OS_SECONDS, new_total])
            current["cumulativeActiveSeconds"] = math.fsum([baseline, new_total])
            h.write(ledger_path, current)
            state["chargeCommitted"] = True
        except Exception as failure:
            state.update(status="LEDGER_RECONCILIATION_REQUIRED", ledgerError=str(failure),
                         uncommittedOrPartiallyCommittedChargeSeconds=elapsed)
        checkpoint("finalized", status=state["status"])
    return 0 if state["status"] == "EXECUTED_PASS" else 1


if __name__ == "__main__":
    raise SystemExit(main())
