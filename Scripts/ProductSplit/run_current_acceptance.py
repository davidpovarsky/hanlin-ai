#!/usr/bin/env python3
"""Run the original paired native acceptance plus separately counted current groups.

The original runner, commands, selectors and result parsers stay authoritative.
Hosted state records prior Mac charges as history and never as current PASS.
"""
from pathlib import Path
import argparse
import datetime
import hashlib
import importlib.util
import json
import math
import os
import plistlib
import signal
import stat
import subprocess
import sys
import time
import uuid
import zipfile

ROOT = Path(os.environ["GITHUB_WORKSPACE"]).resolve()
BASE = Path(__file__).resolve().parent / "Acceptance"
EVIDENCE_ROOT = Path(os.environ["SPLIT_EVIDENCE"]).resolve()
OUTPUT = EVIDENCE_ROOT / "current-native"
DERIVED = Path(os.environ["SPLIT_DERIVED_DATA"]).resolve()
ID = "current-source-native-gha"
RUNNER_SHA = "a99b6194f8dd20bc30998ff2ad9e86ec219415a00615b250c65670f7dfcdba7d"
PRIOR_SECONDS = 706.9951568749966
SCOPE_SECONDS = 10800
GROUP_KEYS = ("handlerRegression", "routeContractGroup", "newHostedRegression", "assistantHostedRegression")


def now():
    return datetime.datetime.now(datetime.timezone.utc).isoformat()


def digest(path):
    with Path(path).open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def ref(path):
    path = Path(path)
    return {"path": str(path), "bytes": path.stat().st_size, "sha256": digest(path)}


def verified(row):
    path = Path(row["path"])
    assert path.is_file() and not path.is_symlink(), str(path)
    assert path.stat().st_size == row["bytes"] and digest(path) == row["sha256"], row
    return path


def write(path, value):
    path = Path(path)
    temporary = path.with_name(path.name + ".tmp")
    with temporary.open("w") as stream:
        json.dump(value, stream, indent=2)
        stream.write("\n")
        stream.flush()
        os.fsync(stream.fileno())
    temporary.replace(path)


def load_module(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


def command(argv, timeout=60):
    result = subprocess.run(argv, cwd=ROOT, capture_output=True, text=True, timeout=timeout)
    assert result.returncode == 0, {"argv": argv, "exitCode": result.returncode,
                                  "stdout": result.stdout, "stderr": result.stderr}
    return result.stdout


def inside(relative, root=ROOT):
    relative = Path(relative)
    assert not relative.is_absolute() and ".." not in relative.parts, str(relative)
    path = root / relative
    assert path.resolve().is_relative_to(root.resolve()), str(path)
    return path


def verify_relative(row, root=ROOT):
    path = inside(row["path"], root)
    return verified({**row, "path": str(path)})


def history():
    path = BASE / "history/validation-history.json"
    value = json.loads(path.read_text())
    rows = value["currentValidationHistory"]
    assert len(rows) == len({row["id"] for row in rows}) == 5
    assert [row["id"] for row in rows] == [
        "current-source-builds-v1", "camera-isolated-conformance-probe-v1",
        "camera-isolated-conformance-probe-v2", "current-source-swiftpm-v1",
        "current-source-swiftpm-v1-supervision"]
    assert value["validationScopeSeconds"] == SCOPE_SECONDS
    for row in rows:
        authority = json.loads(verify_relative(row["retainedAuthority"], path.parent).read_text())
        assert authority["id"] == row["id"] and authority["status"] == row["status"]
        field = row.get("secondsField", "actualElapsedSeconds")
        assert authority[field] == row["seconds"]
        assert isinstance(row["seconds"], (float, int)) and math.isfinite(row["seconds"]) and row["seconds"] > 0
        assert (row["authority"]["bytes"], row["authority"]["sha256"]) == (
            row["retainedAuthority"]["bytes"], row["retainedAuthority"]["sha256"])
        if "retainedController" in row:
            verify_relative(row["retainedController"], path.parent)
    assert math.fsum(row["seconds"] for row in rows) == value["chargedCurrentValidationBeforeSeconds"] == PRIOR_SECONDS
    assert value["remainingCurrentValidationSeconds"] == SCOPE_SECONDS - PRIOR_SECONDS
    assert value["successfulReuse"] is False
    assert value["retainedProofs"]
    for row in value["retainedProofs"]:
        verify_relative(row, path.parent)
    return value, ref(path)


def current_shipping_inventory():
    # Reuse the repository's complete source graph validator, then derive the
    # exact two-app/fourteen-extension placement consumed by the existing check.
    folder = ROOT / "Scripts/CI/IntegrationValidation"
    sys.path.insert(0, str(folder))
    module = load_module("hosted_current_project_graph", folder / "project_graph.py")
    project_path = ROOT / "AI_HLY.xcodeproj/project.pbxproj"
    project = module.parse_project(project_path.read_text())
    checked = module.validate_shipping_extension_inventory(project)
    assert checked == {"applications": 2, "extensions": 14, "shippingTargets": 16}
    objects = project["objects"]
    targets = {objects[key]["name"]: objects[key] for key in objects[project["rootObject"]]["targets"]}
    records = []
    for app_name, owner in [("HanlinApp", "ai"), ("HanlinMiniApps", "miniapps")]:
        app = targets[app_name]
        owned = [app, *[objects[objects[key]["target"]] for key in app["dependencies"]]]
        for target in owned:
            product_ref = target["productReference"]
            embedding = None
            if target is not app:
                matches = []
                for phase_id in app["buildPhases"]:
                    phase = objects[phase_id]
                    if phase["isa"] != "PBXCopyFilesBuildPhase":
                        continue
                    if any(objects[key].get("fileRef") == product_ref for key in phase["files"]):
                        matches.append({"dstSubfolderSpec": phase["dstSubfolderSpec"],
                                        "destinationPath": phase.get("dstPath", "")})
                assert len(matches) == 1, target["name"]
                embedding = matches[0]
            settings = {objects[key]["name"]: objects[key]["buildSettings"]
                        for key in objects[target["buildConfigurationList"]]["buildConfigurations"]}
            records.append({"target": target["name"], "owner": owner,
                            "product": objects[product_ref]["path"],
                            "settings": settings, "embedded": embedding})
    assert len(records) == len({row["target"] for row in records}) == 16
    value = {"schema": 1, "shippingCount": 16, "shipping": records, "project": ref(project_path)}
    path = OUTPUT / "shipping-inventory.json"
    write(path, value)
    return ref(path)


def source_closure(label):
    source = command(["git", "rev-parse", "HEAD"]).strip()
    tree = command(["git", "rev-parse", "HEAD^{tree}"]).strip()
    assert source == os.environ["GITHUB_SHA"]
    producer_path = EVIDENCE_ROOT / "host-sdk-producer.json"
    producer = json.loads(producer_path.read_text())
    assert producer["schemaVersion"] == 1 and producer["status"] == "VERIFIED_HOST_SDK"
    assert producer["sourceCommit"] == source and producer["sourceTree"] == tree
    assert str(producer["runID"]) == os.environ["GITHUB_RUN_ID"]
    assert str(producer["runAttempt"]) == os.environ.get("GITHUB_RUN_ATTEMPT", "1")
    assert producer["longJobs"] is True
    names = ["hostArchive", "shippingHostArchive", "hostMetadata", "sdkManifest",
             "sdkInputs", "sourcePatch", "nativeCatalog", "log"]
    paths = {name: verify_relative(producer[name]) for name in names}
    assert (producer["hostArchive"]["bytes"], producer["hostArchive"]["sha256"]) == (
        producer["shippingHostArchive"]["bytes"], producer["shippingHostArchive"]["sha256"])
    assert paths["hostArchive"] == ROOT / "build/runtime-host/RuntimeHostResources.zip"
    assert paths["shippingHostArchive"] == ROOT / "AI_HLY/RuntimeHostResources.zip"
    host_metadata = json.loads(paths["hostMetadata"].read_text())
    assert host_metadata["archiveSha256"] == producer["hostArchive"]["sha256"]
    assert host_metadata["sourceInputsHash"] == producer["hostMetadata"]["sourceInputsHash"]
    assert host_metadata["tests"] == host_metadata["jitlessArchiveSmoke"] == "passed"
    manifest = json.loads(paths["sdkManifest"].read_text())
    fingerprint = json.loads(command(["node", "Scripts/MiniApps/stage-sdk.mjs", "--fingerprint",
                                      "--repository", str(ROOT)], timeout=120))
    recorded_fingerprint = json.loads(paths["sdkInputs"].read_text())
    assert fingerprint == recorded_fingerprint
    assert manifest["sourceInputs"] == fingerprint["files"]
    assert manifest["inputSHA256"] == fingerprint["sha256"] == producer["sdkManifest"]["inputSHA256"]
    assert len(manifest["sourceInputs"]) == producer["sdkManifest"]["sourceInputCount"]
    assert len({row["path"] for row in manifest["sourceInputs"]}) == len(manifest["sourceInputs"])
    for row in manifest["sourceInputs"]:
        assert digest(inside(row["path"])) == row["sha256"], row["path"]
    with zipfile.ZipFile(paths["hostArchive"]) as archive:
        assert archive.read("MiniAppSDK/miniapp-sdk.json") == paths["sdkManifest"].read_bytes()
        assert len(archive.namelist()) == len(set(archive.namelist()))
        if label == "before":
            for row in manifest["files"]:
                member = "MiniAppSDK/" + row["path"]
                assert archive.getinfo(member).file_size == row["bytes"], member
                with archive.open(member) as stream:
                    assert hashlib.file_digest(stream, "sha256").hexdigest() == row["sha256"], member
        host_uncompressed = sum(item.file_size for item in archive.infolist())
    catalog = json.loads(paths["nativeCatalog"].read_text())
    assert catalog["inputSHA256"] == producer["nativeCatalog"]["inputSHA256"]
    for name, sha in catalog["inputSHA256"].items():
        assert digest(inside(name)) == sha, name
    native_module = load_module("hosted_prepared_native_catalog", ROOT / "Scripts/SDK/native_artifacts.py")
    assert {item["target"] for item in catalog["artifacts"]} == set(native_module.TARGETS)
    assert len(catalog["artifacts"]) == len(native_module.TARGETS)
    native_files = []
    for artifact in catalog["artifacts"]:
        assert artifact["kind"] == "xcframework"
        for library in artifact["libraries"]:
            path = inside(str(Path(artifact["installPath"]) / library["binary"]))
            actual = ref(path)
            assert actual["sha256"] == library["binarySHA256"], actual
            native_files.append(actual)
    assert native_files
    plan = json.loads((BASE / "groups.json").read_text())
    for row in plan["sourceBindings"]:
        verify_relative(row)
    assert digest(ROOT / "Scripts/ProductSplit/run_paired_acceptance.py") == plan["originalRunnerSHA256"] == RUNNER_SHA
    inventory = json.loads((BASE / "affected-swiftpm-test-plan.json").read_text())
    assert inventory["expectedDefinitions"] == 125 and inventory["expectedCases"] == 205
    selected_sources = []
    for family in inventory["families"]:
        for row in [family["source"], *family.get("additionalSources", [])]:
            path = inside(row["path"])
            assert digest(path) == row["sha256"]
            selected_sources.append(ref(path))
    assert len({row["path"] for row in selected_sources}) == 13
    tracked = []
    for entry in command(["git", "ls-files", "--stage", "-z"]).split("\0"):
        if not entry:
            continue
        details, name = entry.split("\t", 1)
        mode, oid, stage = details.split()
        assert stage == "0", entry
        path = ROOT / name
        if mode == "160000":
            tracked.append({"path": name, "mode": mode, "gitlink": oid})
        elif mode == "120000":
            assert path.is_symlink()
            tracked.append({"path": name, "mode": mode, "link": os.readlink(path)})
        else:
            assert mode in {"100644", "100755"} and path.is_file() and not path.is_symlink(), name
            tracked.append({"path": name, "mode": mode, "bytes": path.stat().st_size, "sha256": digest(path)})
    patch_result = subprocess.run(["git", "diff", "--binary", "HEAD", "--"], cwd=ROOT,
                                  capture_output=True, timeout=60)
    patch_path = OUTPUT / (label + "-source.patch")
    patch_path.write_bytes(patch_result.stdout)
    (OUTPUT / (label + "-source-diff-stderr.txt")).write_bytes(patch_result.stderr)
    assert patch_result.returncode == 0, {"exitCode": patch_result.returncode, "patch": str(patch_path)}
    patch = patch_result.stdout
    producer_patch = paths["sourcePatch"].read_bytes()
    same_patch = patch == producer_patch
    binding_path = OUTPUT / (label + "-producer-source-binding.json")
    write(binding_path, {"schema": 1, "observedAt": now(), "phase": label,
                         "status": "VERIFIED_PRODUCER_SOURCE_PATCH" if same_patch else "PRODUCER_SOURCE_DRIFT",
                         "source": source, "sourceTree": tree,
                         "producerPatch": ref(paths["sourcePatch"]), "currentPatch": ref(patch_path),
                         "exactBytesEqual": same_patch,
                         "boundary": "No tracked source mutation is expected after the Host producer receipt. "
                                     "Both actual diff files remain retained; drift is not accepted or rebound."})
    if not same_patch:
        raise RuntimeError("Producer-to-native tracked source drift; inspect " + str(binding_path))
    result = {"source": source, "sourceTree": tree, "producer": ref(producer_path),
              "trackedFiles": tracked, "sourcePatchSHA256": hashlib.sha256(patch).hexdigest(),
              "producerSourcePatch": ref(paths["sourcePatch"]), "producerSourcePatchVerified": True,
              "sdkManifest": ref(paths["sdkManifest"]), "sdkInputSHA256": manifest["inputSHA256"],
              "sdkSourceInputs": len(manifest["sourceInputs"]), "sdkPayloadFiles": len(manifest["files"]),
              "hostArchive": ref(paths["hostArchive"]), "shippingHostArchive": ref(paths["shippingHostArchive"]),
              "hostUncompressedBytes": host_uncompressed, "nativeCatalog": ref(paths["nativeCatalog"]),
              "nativeBinaries": native_files, "selectedSwiftPMSources": selected_sources,
              "boundary": "Actual post-preparation file closure; Git identity plus retained generated-source patch. No clean-worktree or prior native PASS inferred."}
    write(OUTPUT / (label + "-source-closure.json"), result)
    return result


def resource_assessment(source, tree, host_bytes):
    value = json.loads((BASE / "resource-model.json").read_text())
    assert value["status"] == "HOSTED_MODEL_BASIS_ACTUAL_BINDINGS_PENDING"
    value.update(status="CURRENT_HOSTED_PHASE_ESTIMATES", source=source, sourceTree=tree,
                 root=str(ROOT), derivedData=str(DERIVED))
    delta = max(0, host_bytes - value["basis"]["hostUncompressedBytes"])
    for phase, multiplier in [("handlerRegression", 2), ("fixturesInitial", 1),
                              ("originalMini25", 1), ("originalAI27", 1)]:
        value["phases"][phase]["additionalAllocationBytes"] += multiplier * delta
    workspace = ROOT / "build/SourcePackages/workspace-state.json"
    # The workflow cache is not a proven prepared graph. Reserve the original
    # full regeneration allowance rather than infer completeness from one file.
    package_growth = value["basis"]["packageRegenerationAllowanceBytes"]
    for phase in ["freshDeviceAndMiniBuild", "miniBuild"]:
        value["phases"][phase]["additionalAllocationBytes"] += package_growth
    value["hostedObservation"] = {
        "hostUncompressedBytes": host_bytes, "additionalHostGrowthBytes": delta,
        "packageWorkspace": ref(workspace) if workspace.is_file() else {"path": str(workspace), "exists": False},
        "packageRegenerationAllowanceBytes": package_growth,
        "boundary": "No package-cache credit is inferred from workspace presence. Package and compiler caches are incremental inputs only; both original builds execute and every test runs."}
    # Per-command live required() computes the actual current allocations;
    # there is no fixed historical Mac admission row.
    value.pop("minimumFreeBytes", None)
    path = OUTPUT / "resource-assessment.json"
    write(path, value)
    return ref(path)


def prepare_decision(before):
    plan = json.loads((BASE / "groups.json").read_text())
    d = {key: plan[key] for key in GROUP_KEYS}
    fixture = ROOT / "AI_HLYTests/Fixtures/HostServicesProbe.bundle/ExpoSwiftUIProbeA.hanlinExpo"
    queue_source = verify_relative(plan["queue"])
    queue_plan = BASE / "widget-host-action-test-plan.json"
    assert digest(queue_plan) == plan["queue"]["planSHA256"]
    d.update(schema=1, status="SEALED", id=ID, source=before["source"], sourceTree=before["sourceTree"],
             root=str(ROOT), evidenceRoot=str(EVIDENCE_ROOT), output=str(OUTPUT),
             derivedData=str(DERIVED), hostedFixture={"source": ref(fixture)},
             originalMainGuard=ref(BASE / "current_native_groups.py"),
             shippingInventory=current_shipping_inventory(),
             currentSDK={"manifest": before["sdkManifest"], "inputSHA256": before["sdkInputSHA256"],
                         "host": before["shippingHostArchive"], "sourceInputs": before["sdkSourceInputs"],
                         "payloadFiles": before["sdkPayloadFiles"], "producer": before["producer"]},
             affectedSwiftPM={"inventory": ref(BASE / "affected-swiftpm-test-plan.json"),
                              "verifier": ref(BASE / "verify_affected_swift_testing.py"),
                              "expectedDefinitions": 125, "expectedCases": 205},
             queueContractGroup={"id": "widget-host-action-queue", "suite": "HanlinWidgetHostActionTests",
                                 "target": "HanlinScriptExtensionsTests", "expectedFunctions": 10,
                                 "expectedParameterInstances": 16, "commandCeilingSeconds": 1200,
                                 "source": ref(queue_source), "testPlan": ref(queue_plan)})
    assessment = resource_assessment(before["source"], before["sourceTree"], before["hostUncompressedBytes"])
    d["resourceAssessment"] = {"authority": assessment}
    path = OUTPUT / "decision.json"
    write(path, d)
    return d, ref(path)


def verify_acceptance(d):
    evidence = EVIDENCE_ROOT / "paired-product"
    raw_path = evidence / "acceptance.json"
    raw = json.loads(raw_path.read_text())
    assert raw["sha"] == d["source"]
    assert all(raw[key] == "EXECUTED_PASS" for key in ["status", "build", "mini_build", "ai_build", "ui"])
    for key, count in [("original_runtime_summary", 25), ("summary", 27)]:
        summary = raw[key]
        assert summary["passedTests"] == count and summary.get("failedTests", 0) == summary.get("skippedTests", 0) == 0
        assert summary.get("totalTestCount", count) == count
    assert raw["native_adapter_assets"]["native_request_proof"] == "EXECUTED_PASS_RESOURCE_TRANSPORT"
    commands_path = evidence / "commands.jsonl"
    commands = [json.loads(line) for line in commands_path.read_text().splitlines() if line.strip()]
    for name in ["mini-build.log", "original-a2ui-generator.log", "ai-build.log", "original-runtimes.log", "paired-tests.log"]:
        rows = [row for row in commands if row["log"] == name]
        assert len(rows) == 1 and rows[0]["exit"] == 0
        assert digest(evidence / name) == rows[0]["sha256"]
    groups = []
    for key in GROUP_KEYS:
        expected = d[key]
        path = evidence / (expected["id"] + "-review.json")
        review = json.loads(path.read_text())
        assert review["source"] == d["source"] and review["status"] == "EXECUTED_PASS"
        assert review["commandExitCode"] == 0 and review["selectors"] == expected["selectors"]
        assert review["expectedCases"] == expected["expectedCases"]
        for proof in review["proofs"]:
            verified(proof)
        groups.append({"id": expected["id"], "authority": ref(path), "summary": review["summary"]})
    for label, definitions, cases in [("widget-host-action-queue", 10, 16), ("affected-swiftpm", 125, 205)]:
        path = evidence / (label + "-review.json")
        review = json.loads(path.read_text())
        assert review["status"] == "EXECUTED_PASS" and review["source"] == d["source"] and review["commandExitCode"] == 0
        if label == "widget-host-action-queue":
            assert review["verification"]["observedFunctions"] == definitions
            assert review["verification"]["observedParameterInstances"] == cases
        else:
            assert review["verification"]["status"] == "EXECUTED_PASS"
            assert review["expectedDefinitions"] == definitions and review["expectedCases"] == cases
        for proof in review["proofs"]:
            verified(proof)
        groups.append({"id": label, "authority": ref(path), "verification": review["verification"]})
    metadata = []
    for label in ["metadata-after-mini-build", "metadata-after-ai-build"]:
        path = evidence / label / "receipt.json"
        receipt = json.loads(path.read_text())
        assert receipt["status"] == "VERIFIED_COMPILED_METADATA" and not receipt["errors"]
        assert receipt["source"] == d["source"] and receipt["sourceTree"] == d["sourceTree"]
        for row in receipt["files"]:
            verified(row["retained"])
        verified(receipt["matchedSection"]["retained"])
        metadata.append(ref(path))
    shipping_path = evidence / "current-shipping-bundles.json"
    shipping = json.loads(shipping_path.read_text())
    assert shipping["status"] == "VERIFIED_16_BUILT_SHIPPING_BUNDLES" and shipping["source"] == d["source"]
    assert len(shipping["bundles"]) == 16
    for bundle in shipping["bundles"]:
        assert bundle["signatureExitCode"] == 0
        verified(bundle["info"])
        verified(bundle["executable"])
    return {"status": "EXECUTED_PASS", "source": d["source"], "sourceTree": d["sourceTree"],
            "originalAcceptance": ref(raw_path), "originalCommands": ref(commands_path),
            "original52": {"mini": raw["original_runtime_summary"], "ai": raw["summary"]},
            "separateGroups": groups, "compiledMetadata": metadata,
            "shippingBundles": ref(shipping_path),
            "boundary": "Actual original25+27, additional hosted13, queue10/16 and affected125/205. Historical Mac results are not reused as current PASS. Distribution and physical-device outcomes remain separate."}


def group_alive(pgid):
    try:
        os.killpg(pgid, 0)
        return True
    except ProcessLookupError:
        return False


def stop_group(process, cleanup):
    pgid = process.pid
    for sig, wait in [(signal.SIGINT, 10), (signal.SIGTERM, 5), (signal.SIGKILL, 5)]:
        if not group_alive(pgid):
            break
        os.killpg(pgid, sig)
        cleanup.append({"pgid": pgid, "signal": sig.name, "observedAt": now()})
        deadline = time.monotonic() + wait
        while group_alive(pgid) and time.monotonic() < deadline:
            process.poll()
            time.sleep(0.2)
    process.poll()
    return [pgid] if group_alive(pgid) else []


def clean_device():
    created = EVIDENCE_ROOT / "paired-product/created-simulator.txt"
    if not created.is_file():
        return {"status": "NOT_CREATED"}
    identifier = created.read_text().strip()
    assert str(uuid.UUID(identifier)).upper() == identifier.upper()
    def observe():
        value = json.loads(command(["xcrun", "simctl", "list", "devices", "--json"], timeout=30))
        rows = [row for group in value["devices"].values() for row in group if row["udid"] == identifier]
        assert len(rows) == 1 and rows[0]["name"] == "HanlinPaired-" + os.environ["GITHUB_RUN_ID"]
        return rows[0]
    before = observe()
    if before["state"] != "Shutdown":
        command(["xcrun", "simctl", "shutdown", identifier], timeout=60)
    after = observe()
    assert after["state"] == "Shutdown"
    return {"status": "SHUTDOWN", "creation": ref(created), "before": before, "after": after}


def coordinate():
    assert os.environ["PAIRED_TEST_SCOPE"] == "miniapp_complete"
    assert ROOT == Path(os.environ["GITHUB_WORKSPACE"]).resolve()
    assert EVIDENCE_ROOT.is_relative_to(ROOT / "build")
    assert DERIVED.is_relative_to(ROOT / "build") and not DERIVED.is_symlink()
    assert not (EVIDENCE_ROOT / "paired-product").exists(), "No replay of a prior paired attempt"
    OUTPUT.mkdir(parents=True, exist_ok=False)
    DERIVED.mkdir(parents=True, exist_ok=True)
    observed_started = time.monotonic()
    state = {"schema": 1, "id": ID, "status": "PREFLIGHT", "source": os.environ["GITHUB_SHA"],
             "runID": os.environ["GITHUB_RUN_ID"], "runAttempt": os.environ.get("GITHUB_RUN_ATTEMPT", "1"),
             "startedAt": now(), "executionStarted": False, "errors": [], "sourceErrors": [],
             "cleanupErrors": [], "cleanupSignals": [], "remainingOwnedProcessGroup": [],
             "chargeCommitted": False, "historicalMacResultsReusedAsPass": False,
             "python": {"executable": sys.executable, "version": sys.version,
                        "minimumVersion": [3, 11]}}
    write(OUTPUT / "state.json", state)
    process = None
    execution_started = None
    hist = None
    before = None
    try:
        hist, history_ref = history()
        state.update(historicalValidation=history_ref, priorChargedSeconds=PRIOR_SECONDS,
                     validationScopeSeconds=SCOPE_SECONDS, originalHistoricalRows=hist["currentValidationHistory"])
        assert command(["uname", "-m"]).strip() == "arm64"
        toolchain = {"xcode": command(["xcodebuild", "-version"]),
                     "swift": command(["xcrun", "swift", "--version"]),
                     "macOS": command(["sw_vers"]), "architecture": "arm64"}
        write(OUTPUT / "toolchain.json", toolchain)
        before = source_closure("before")
        d, decision_ref = prepare_decision(before)
        state.update(sourceTree=before["sourceTree"], decision=decision_ref,
                     sourceClosureBefore=ref(OUTPUT / "before-source-closure.json"),
                     readOnlyPreflightSeconds=time.monotonic() - observed_started)
        argv = [sys.executable, "-B", str(Path(__file__).resolve()), "--worker", "--decision", decision_ref["path"]]
        attempt_started = time.monotonic()
        process = subprocess.Popen(argv, cwd=ROOT, start_new_session=True)
        execution_started = attempt_started
        state.update(status="RUNNING", executionStarted=True, workerArgv=argv,
                     executionStartedAt=now(), workerPID=process.pid, ownedProcessGroup=process.pid)
        write(OUTPUT / "state.json", state)
        try:
            code = process.wait(timeout=SCOPE_SECONDS - PRIOR_SECONDS)
        except subprocess.TimeoutExpired:
            state["timedOut"] = True
            raise RuntimeError("Cumulative current-validation budget exhausted")
        state["workerExitCode"] = code
        assert code == 0, {"workerExitCode": code}
        state["result"] = verify_acceptance(d)
        state["status"] = "EXECUTED_PASS"
    except BaseException as error:
        state["status"] = "FAILED"
        state["errors"].append({"type": type(error).__name__, "message": str(error)})
    finally:
        if process is not None:
            try:
                state["remainingOwnedProcessGroup"] = stop_group(process, state["cleanupSignals"])
                state["workerExitCode"] = process.poll()
                assert not state["remainingOwnedProcessGroup"]
            except BaseException as error:
                state["cleanupErrors"].append({"type": type(error).__name__, "message": str(error)})
        try:
            state["ownedSimulator"] = clean_device()
        except BaseException as error:
            state["cleanupErrors"].append({"type": type(error).__name__, "message": str(error)})
        if before is not None:
            try:
                after = source_closure("after")
                state["sourceClosureAfter"] = ref(OUTPUT / "after-source-closure.json")
                assert before == after, "Actual source/SDK/native input closure changed during validation"
            except BaseException as error:
                state["sourceErrors"].append({"type": type(error).__name__, "message": str(error)})
        if state["sourceErrors"] or state["cleanupErrors"]:
            state["status"] = "FAILED"
        raw_path = EVIDENCE_ROOT / "paired-product/acceptance.json"
        if raw_path.is_file():
            state["originalPairedAcceptance"] = ref(raw_path)
            raw = json.loads(raw_path.read_text())
            for key in ["ui", "build", "mini_build", "ai_build", "physical_device", "provisioned_distribution"]:
                if key in raw:
                    state[key] = raw[key]
        elapsed = 0.0 if execution_started is None else time.monotonic() - execution_started
        state.update(finishedAt=now(), actualElapsedSeconds=elapsed,
                     observedTotalSeconds=time.monotonic() - observed_started)
        if hist is not None:
            rows = list(hist["currentValidationHistory"])
            if execution_started is not None:
                rows.append({"id": ID, "runID": state["runID"], "runAttempt": state["runAttempt"],
                             "source": state["source"], "status": state["status"], "seconds": elapsed,
                             "authority": "state.json"})
            total = math.fsum(row["seconds"] for row in rows)
            if total > SCOPE_SECONDS:
                state["status"] = "FAILED"
                state["errors"].append({"type": "BudgetExceeded", "actualTotalSeconds": total,
                                        "limitSeconds": SCOPE_SECONDS})
                if execution_started is not None:
                    rows[-1]["status"] = "FAILED"
            state.update(totalChargedCurrentValidationSeconds=total,
                         remainingCurrentValidationSeconds=max(0.0, SCOPE_SECONDS - total), chargeCommitted=True)
            write(OUTPUT / "ledger.json", {"schema": 1, "scopeSeconds": SCOPE_SECONDS,
                  "historicalMacSeconds": PRIOR_SECONDS, "entries": rows,
                  "actualTotalSeconds": total, "remainingSeconds": max(0.0, SCOPE_SECONDS - total),
                  "boundary": "All historical elapsed charges remain unchanged. Current row is actual hosted execution plus verification/cleanup; no current row before worker dispatch."})
        write(OUTPUT / "state.json", state)
    print(json.dumps({"status": state["status"], "state": ref(OUTPUT / "state.json"),
                      "actualElapsedSeconds": state["actualElapsedSeconds"]}), flush=True)
    return 0 if state["status"] == "EXECUTED_PASS" else 1


def main():
    if sys.version_info < (3, 11):
        raise RuntimeError("Current acceptance requires Python 3.11 or newer for hashlib.file_digest; "
                           "actual interpreter: " + sys.version)
    parser = argparse.ArgumentParser()
    parser.add_argument("--worker", action="store_true")
    parser.add_argument("--decision", type=Path)
    args = parser.parse_args()
    if args.worker:
        assert args.decision == OUTPUT / "decision.json"
        d = json.loads(args.decision.read_text())
        module = load_module("hosted_current_native_groups", verified(d["originalMainGuard"]))
        return module.run_original_with_groups(d)
    assert args.decision is None
    def interrupted(signum, frame):
        raise KeyboardInterrupt("Hosted acceptance received " + signal.Signals(signum).name)
    signal.signal(signal.SIGTERM, interrupted)
    return coordinate()


if __name__ == "__main__":
    raise SystemExit(main())
