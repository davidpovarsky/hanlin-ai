"""Current SDK20 original notification case on the completed original paired-run device.
The original UI selector, observer, test/rebind functions and result verifier are retained.
This new 900-second ledger preserves all earlier component ledgers without rewriting them.
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

ID = "notification-os-sdk20-v1"
GATE = "notification-os"
ALLOWANCE = 900
PAIRED_ID = "paired52-sdk20-v2"
PAIRED_CONTROLLER_SHA = "a9040dd634acfe7d1d01d6f477771f9033ab305cde9576b1b5d5ad6423726bcb"
PAIRED_DECISION_SHA = "10e76a4916899f9345cb30421cc4b84566b1cf2b0f054005c70e80c52dce5928"
HOST_SHA = "ed18d93a88a1020bc2140417cea3847daf3d03472cdd4769d9a5ac4e44f48a22"
ROOT = Path("/Users/m1/builds/hanlin-notification-wire-fix-20261125")
SOURCE = "7f5dad540ade7fec6e5ace980eb99d1d6d0c2e8f"
SDK_SOURCE = "dff3b45c99a57bf8fe8ec721db3fa1fafce7134b"
PRODUCTS = Path("/Users/m1/caches/DerivedData/hanlin-notification-wire-fix-20261125/Build/Products")
SELECTOR = "HanlinMiniAppsUITests/MiniAppsProductionRuntimeUITests/testOriginalNotificationAuthorizationAndOSDeliveryToBothEngines"
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
        if destination.exists():
            assert destination.is_file() and not destination.is_symlink()
            status = "EXISTING_EXACT_ORIGINAL_INPUT_VERIFIED"
        else:
            with destination.open("xb") as stream:
                stream.write(original.read_bytes())
                stream.flush()
                os.fsync(stream.fileno())
            status = "COPIED_EXACT_ORIGINAL_INPUT"
        assert destination.stat().st_size == row["bytes"] and digest(destination) == row["sha256"]
        staged_files.append({**row, "path": str(destination), "status": status})
    fixture = root / ACTIONS
    destination = documents / fixture.name
    staged = next(x["status"] for x in staged_files if x["name"] == fixture.name)
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
    lock = (root / "validation/native-owner.lock").open("a")
    fcntl.flock(lock.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
    paired, paired_decision, paired_terminal, paired_ledger, history = current_authority(d)
    required, products = d["sourceFiles"], d["productFiles"]
    artifact = d["directArtifactObservation"]["xctestrun"]
    target = plistlib.loads(verify_file(artifact).read_bytes())["HanlinMiniAppsUITests"]
    assert target["IsUITestBundle"] is True
    assert target["TestHostPath"] == "__TESTROOT__/Debug-iphonesimulator/HanlinMiniAppsUITests-Runner.app"
    assert target["TestBundlePath"] == "__TESTHOST__/PlugIns/HanlinMiniAppsUITests.xctest"
    assert target["UITargetAppPath"] == "__TESTROOT__/Debug-iphonesimulator/HanlinMiniApps.app"
    assert target["TestHostBundleIdentifier"] == "com.itorah.hanlinminiapps.integration.uitests.xctrunner"
    device = str(uuid.UUID(d["simulator"]["udid"])).upper()
    ownership = verify_file(d["simulatorOwnership"])
    current_devices = json.loads(h.run(["xcrun", "simctl", "list", "devices", "-j"], timeout=15))
    current = [x for values in current_devices["devices"].values() for x in values if x["udid"].upper() == device]
    assert len(current) == 1 and current[0]["state"] == "Shutdown" and current[0]["isAvailable"] is True
    assert current[0]["name"] == d["simulator"]["name"] and current[0]["deviceTypeIdentifier"] == d["simulator"]["deviceTypeIdentifier"]
    disk = h.run(["/bin/df", "-k", str(root)], timeout=15)
    free = int(disk.splitlines()[-1].split()[3]) * 1024
    assert free >= RESOURCE_BOUND, "Original approved single-case resource bound is not met"
    out.mkdir(parents=True)
    for name in ["setup", "test"]:
        (out / name).mkdir()
    frozen = out / "decision.json"
    frozen.write_bytes(decision_bytes)
    (out / "paired-state-before.json").write_bytes(Path(d["pairedTerminal"]["path"]).read_bytes())
    state_path, ledger_path, events = out / "state.json", out / "ledger.json", out / "events.jsonl"
    allowance = ALLOWANCE
    ledger = {"schema": 1, "id": ID, "source": SOURCE, "maximumActiveSeconds": ALLOWANCE,
              "charges": [], "activeElapsedSeconds": 0.0, "componentHistory": history,
              "separateCurrentSourceObservation": True, "historicalLedgersModified": False}
    h.write(ledger_path, ledger)
    state = {"schema": 1, "id": ID, "owner": d["owner"], "source": SOURCE,
             "compiledConsumerSource": SOURCE, "SDKProducerSource": SDK_SOURCE,
             "status": "STARTING", "selector": SELECTOR, "expectedTests": 1,
             "controllerPID": os.getpid(), "allowanceSeconds": ALLOWANCE,
             "decisionSHA256": hashlib.sha256(decision_bytes).hexdigest(),
             "remainingAllowanceSeconds": allowance, "componentHistory": history,
             "historicalOSChargedSeconds": HISTORICAL_OS_SECONDS,
             "historicalIndependentOSRecoverySeconds": HISTORICAL_RECOVERY_OS_SECONDS,
             "historicalAggregateSecondsIncludingBothOSScopes": HISTORICAL_PRIMARY_SECONDS,
             "ownedSimulator": d["simulator"], "currentPairedTerminal": d["pairedTerminal"],
             "currentNativeScriptTerminal": d["priorNativeScript"]["state"],
             "directArtifactObservation": d["directArtifactObservation"],
             "resourceObservationAtLaunch": {"observedAt": h.utc(), "freeBytes": free, "df": disk},
             "boundary": "New current-source OS observation only. Original full52 and NS-five results and all historical ledgers remain immutable."}

    def checkpoint(event, **fields):
        state.update(fields)
        h.write(state_path, state)
        with events.open("a") as stream:
            stream.write(json.dumps({"at": h.utc(), "event": event, **fields}) + "\n")
            stream.flush()
            os.fsync(stream.fileno())

    env = dict(os.environ)
    env.update(paired_decision["environment"])
    env["PATH"] = str(ROOT / "Tools/node-v24.5.0-darwin-arm64/bin") + os.pathsep + str(paired.PYTHON.parent) + os.pathsep + env["PATH"]
    assert Path(sys.executable).resolve() == Path(paired_decision["python"]["resolvedPath"])
    env.update(DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer", GITHUB_WORKSPACE=str(root),
               GITHUB_SHA=SOURCE, SPLIT_EVIDENCE=str(out), SPLIT_DERIVED_DATA=d["derivedData"],
               PAIRED_TEST_SCOPE="miniapp_complete", RUNNER_TEMP=str(root / "build/primary-temp"))
    (root / "build/primary-temp").mkdir(exist_ok=True)
    h.write(out / "execution-environment.json", {
        "perRun": {k: env[k] for k in ("DEVELOPER_DIR", "GITHUB_WORKSPACE", "GITHUB_SHA", "SPLIT_EVIDENCE",
                                     "SPLIT_DERIVED_DATA", "PAIRED_TEST_SCOPE", "RUNNER_TEMP")},
        "inheritedPATH": env.get("PATH"), "python": sys.executable,
        "externalNodeOrNpmCommand": "No producer invocation; the original pinned current Node/Python PATH is retained",
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
            raise TimeoutError("Separate current-source900s OS observation allowance elapsed")
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
            current_authority(d)
            verify_file(d["simulatorOwnership"])
            verify_file(d["controller"])
        except Exception as failure:
            source_errors.append("Final immutable input observation: " + str(failure))
        state["sourceErrors"] = source_errors
        if source_errors:
            state["status"] = "INPUT_DRIFT"
        elapsed = time.monotonic() - start
        log_files = [{"path": p.name, "bytes": p.stat().st_size, "sha256": digest(p)}
                     for p in out.glob("*.log") if p.is_file()]
        checkpoint("charge_ready", finishedAt=h.utc(), elapsedSeconds=elapsed, chargedSeconds=elapsed,
                   remainingAllowanceSeconds=max(0.0, ALLOWANCE - elapsed),
                   overrunSeconds=max(0.0, elapsed - ALLOWANCE), processLogs=log_files)
        try:
            current = json.loads(ledger_path.read_text())
            assert current["charges"] == [] and current["activeElapsedSeconds"] == 0.0
            charge = {"id": ID, "source": SOURCE, "status": state["status"], "elapsedSeconds": elapsed,
                      "statePath": str(state_path), "decisionSHA256": state["decisionSHA256"],
                      "selector": SELECTOR, "separateCurrentSourceObservation": True}
            current["charges"].append(charge)
            current["activeElapsedSeconds"] = elapsed
            current["status"] = state["status"]
            current["remainingAllowanceSeconds"] = max(0.0, ALLOWANCE - elapsed)
            current["overrunSeconds"] = max(0.0, elapsed - ALLOWANCE)
            current["accounting"] = "Only this new current-source observation is charged here. All earlier components, including both historical OS scopes, remain separate and are not summed or reset."
            h.write(ledger_path, current)
            state["chargeCommitted"] = True
        except Exception as failure:
            state.update(status="LEDGER_RECONCILIATION_REQUIRED", ledgerError=str(failure),
                         uncommittedOrPartiallyCommittedChargeSeconds=elapsed)
        checkpoint("finalized", status=state["status"])
    return 0 if state["status"] == "EXECUTED_PASS" else 1


if __name__ == "__main__":
    raise SystemExit(main())
