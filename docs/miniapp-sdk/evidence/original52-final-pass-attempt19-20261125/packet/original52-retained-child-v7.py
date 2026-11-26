"""Execute fresh original MiniApps25 and AI27 on authenticated retained products.
No build, package preparation, installation, input replacement, or result aggregation.
"""
from pathlib import Path
import argparse, ast, datetime, hashlib, importlib.util, json, os, plistlib, signal, subprocess, sys, time, traceback, uuid

SOURCE = "d4a0b115b106d4250ea40ad66153d5156847a07c"
MINI_SOURCE = "d4a0b115b106d4250ea40ad66153d5156847a07c"
PROBE_SOURCE = "6c006c948f0a6f371f7fc68b90e393f43734f8dd"
TREE = "f7a6596a1ef53d8d962ceb9f619460ffa19ee91e"
SDK_SOURCE = "a2c8a1b1be746461272ba77254603304567c309d"
RUNNER = "Scripts/ProductSplit/run_paired_acceptance.py"
RUNNER_SHA = "a99b6194f8dd20bc30998ff2ad9e86ec219415a00615b250c65670f7dfcdba7d"
REQUEST_ID = "4f2ecda0-9c21-46a2-b2e1-8cd4f017c623"
COUNTS = {"OriginalRuntimes": 25, "Paired": 27}
CEILINGS = {"OriginalRuntimes": 2400, "Paired": 2100}

def digest(path):
    value = hashlib.sha256()
    with Path(path).open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            value.update(block)
    return value.hexdigest()

def utc():
    return datetime.datetime.now(datetime.timezone.utc).isoformat()

def write(path, value):
    temporary = path.with_name(path.name + ".tmp")
    temporary.write_text(json.dumps(value, indent=2) + "\n")
    temporary.replace(path)

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--decision", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    decision = json.loads(args.decision.read_text())
    root = Path(decision["root"]).resolve()
    ctrl = root / "build/primary-control"
    out = args.output.resolve()
    assert root == Path.cwd().resolve()
    assert out == (root / decision["outputDirectory"]).resolve() / "native-result"
    assert out.is_relative_to(ctrl) and not out.exists()
    assert decision["source"] == SOURCE and decision["sourceTree"] == TREE
    assert subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=root, text=True).strip() == SOURCE
    assert subprocess.check_output(["git", "rev-parse", "HEAD^{tree}"], cwd=root, text=True).strip() == TREE
    assert decision["commandCeilingsSeconds"] == CEILINGS
    def checked(key, decode=True):
        row = decision["setup"][key]
        path = (root / row["path"]).resolve()
        assert path.is_relative_to(ctrl) and not path.is_symlink()
        assert digest(path) == row["sha256"], key
        return json.loads(path.read_text()) if decode else path
    focus = checked("focusTerminal")
    previous = checked("focusChild")
    manual_previous = checked("manualFocusChild")
    built = checked("builtInputBindings")
    original = checked("originalMiniCommand")
    setup = checked("originalSetup")
    production = checked("fixtureProduction")
    staged = checked("stagedInputs")
    ownership = checked("ownership", False)
    verifier = checked("modalVerifier", False)
    assert focus["source"] == previous["source"] == SOURCE
    assert focus["status"] == previous["status"] == "FOCUSED_PASS" and focus["chargeCommitted"]
    assert not focus["remainingOwnedProcessGroup"] and not focus["cleanupErrors"] and not focus["sourceErrors"]
    assert not previous["cleanupErrors"] and not previous["sourceErrors"] and not previous["errors"]
    assert set(previous["groups"]) == {"FocusedRepair1"}
    assert manual_previous["source"] == PROBE_SOURCE and manual_previous["status"] == "FOCUSED_FAILED"
    assert decision["setup"]["manualFocusChild"]["sha256"] == "7cb9bda65b2cad09de873402d449aee0999fa88ad6b47d713514149afaea8d23"
    assert not manual_previous["sourceErrors"] and not manual_previous["cleanupErrors"]
    for parent, name, selector in [
        (previous, "FocusedRepair1", "AI_HLYUITests/MiniAppAuthoringUITests/testTypeErrorRepairsThroughOriginalAgentBuildAndCompanionImport"),
        (manual_previous, "FocusedManual1", "HanlinMiniAppsUITests/MiniAppsProductionRuntimeUITests/testStandaloneExpoManualInputLayoutAndDataAdapters")]:
        row = parent["groups"][name]
        assert row["selectors"] == [selector]
        assert row["status"] == "PASS" and row["resultFinalized"] and row["exitCode"] == 0
        assert row["summary"]["totalTestCount"] == row["summary"]["passedTests"] == 1
        assert row["summary"]["failedTests"] == row["summary"]["skippedTests"] == 0
    assert {("/pixel.png", 200), ("/missing.png", 404)} <= {
        (row["path"], row["status"]) for row in manual_previous["nativeAdapterRequests"]}
    assert previous["reusedManualProof"] == {"authority": decision["setup"]["manualFocusChild"],
        "group": manual_previous["groups"]["FocusedManual1"],
        "nativeAdapterRequests": manual_previous["nativeAdapterRequests"]}
    assert previous["original52"] == "NOT_RUN"
    assert previous["originalTestBuilds"] == "PASS"
    assert previous["builtInputBindings"]["sha256"] == decision["setup"]["builtInputBindings"]["sha256"]
    assert previous["fixtureProduction"]["sha256"] == decision["setup"]["fixtureProduction"]["sha256"]
    assert previous["stagedInputs"]["sha256"] == decision["setup"]["stagedInputs"]["sha256"]
    device = str(uuid.UUID(ownership.read_text().strip())).upper()
    assert device == previous["simulator"] == decision["simulator"]["udid"]
    assert previous["ownedSimulatorCleanup"]["state"] == "Shutdown"
    assert built["source"] == built["aiBuildProducerSource"] == SOURCE
    assert built["miniBuildProducerSource"] == MINI_SOURCE and built["SDKProducerSource"] == SDK_SOURCE
    assert built["originalTestBuilds"] == "PASS"
    assert "authenticatedMiniReuse" not in built and "authenticatedAIReuse" not in built
    assert len(previous["reusedSetup"]) == 1 and previous["reusedSetup"][0]["status"] == "REUSED_AUTHENTICATED_OWNED_DEVICE"
    products_root = Path(decision["derivedData"]).resolve() / "Build/Products"
    assert built["files"] == decision["productFiles"]
    for row in built["files"]:
        path = Path(row["path"]).resolve()
        assert path.is_relative_to(products_root) and path.is_file()
        assert path.stat().st_size == row["size"] and digest(path) == row["sha256"], row["path"]
    assert production["source"] == PROBE_SOURCE and production["SDKProducerSource"] == SDK_SOURCE
    assert production["exitCode"] == 0 and production["argv"] == ["node", "Scripts/Expo/build-probe.mjs"]
    for row in production["after"]:
        path = root / row["path"]
        assert path.stat().st_size == row["bytes"] and digest(path) == row["sha256"], row["path"]
    replacement = staged["replacement"]
    staged_files = staged["unchanged"] + [{"name": replacement["name"], **replacement["after"]}]
    staged_files.sort(key=lambda row: row["name"])
    assert len(staged_files) == 11 and len({row["name"] for row in staged_files}) == 11
    assert staged_files == decision["stagedFiles"]
    assert digest(root / "AI_HLY/RuntimeHostResources.zip") == decision["sdk"]["archiveSHA256"]

    runner_path = root / RUNNER
    assert digest(runner_path) == RUNNER_SHA
    sys.path.insert(0, str(root / "Scripts/ProductSplit"))
    spec = importlib.util.spec_from_file_location("original_paired52_retained_products", runner_path)
    paired = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(paired)
    assert paired.TEST_SCOPE == "miniapp_complete"
    ai_selectors, ai_expected = paired.TEST_PLANS["miniapp_complete"]
    assert ai_expected == 27 and original["original27Selectors"] == ai_selectors
    # Bind the original in-function Mini17 literal plus original SDK04 additions.
    literals = []
    for node in ast.walk(ast.parse(runner_path.read_text())):
        if isinstance(node, ast.Assign) and any(isinstance(t, ast.Name) and t.id == "runtime_selectors" for t in node.targets):
            if isinstance(node.value, ast.List):
                candidate = ast.literal_eval(node.value)
                if len(candidate) == 17:
                    literals.append(candidate)
    assert len(literals) == 1
    mini_selectors = literals[0] + [s for s in paired.SDK04_MINIAPPS_SELECTORS if s not in literals[0]]
    assert len(mini_selectors) == 25
    old_argv = original["argv"]
    assert [x.removeprefix("-only-testing:") for x in old_argv if x.startswith("-only-testing:")] == mini_selectors
    assert "test-without-building" in old_argv and old_argv[old_argv.index("-scheme") + 1] == "HanlinMiniApps"
    assert old_argv[old_argv.index("-destination") + 1] == "platform=iOS Simulator,id=" + device
    assert Path(old_argv[old_argv.index("-derivedDataPath") + 1]).resolve() == Path(decision["derivedData"]).resolve()
    assert old_argv[old_argv.index("-collect-test-diagnostics") + 1] == "never"
    base = old_argv[:old_argv.index("-scheme")]
    expected_old = base + ["-scheme", "HanlinMiniApps", "test-without-building", "-resultBundlePath",
                          old_argv[old_argv.index("-resultBundlePath") + 1]] + ["-only-testing:" + x for x in mini_selectors]
    assert old_argv == expected_old
    groups = {"OriginalRuntimes": {"expected": 25, "selectors": mini_selectors},
              "Paired": {"expected": 27, "selectors": ai_selectors}}
    assert decision["groups"] == groups
    modal = setup["external_modal_fixture"]
    assert modal["status"] == "REAL_IMPORT_AND_INCOMING_REQUEST_STAGED"
    assert modal["simulator_udid"] == device and modal["request"]["request_id"] == REQUEST_ID
    assert not modal["runtime_result_synthesized"] and not modal["request"]["result_synthesized"]
    assert modal["verify_command"] == [str(verifier), "verify", modal["shared_group_container"]]

    out.mkdir()
    paired.EVIDENCE = out
    (out / "created-simulator.txt").write_bytes(ownership.read_bytes())
    state = {"schema": 1, "owner": "/root/native_execution", "source": SOURCE, "tree": TREE,
             "status": "RUNNING", "startedAt": utc(), "pid": os.getpid(), "simulator": device,
             "pairedEvidence": str(out), "original52": "NOT_RUN", "original25": "NOT_RUN", "original27": "NOT_RUN",
             "groups": {}, "selectors": {k: v["selectors"] for k, v in groups.items()},
             "originalTestBuilds": "REUSED_AUTHENTICATED_FOCUS_PRODUCTS", "SDKProducerSource": SDK_SOURCE,
             "miniBuildProducerSource": MINI_SOURCE, "aiBuildProducerSource": SOURCE,
             "setup": decision["setup"], "errors": [], "sourceErrors": [], "cleanupErrors": [],
             "nativeAdapterRequests": [], "nativeAdapterAssets": {},
             "boundary": "Fresh original25+27 on retained warm owned simulator; no aggregation of focused results."}
    started = time.monotonic()
    def save():
        state["observedAt"] = utc()
        state["elapsedSeconds"] = time.monotonic() - started
        write(out / "state.json", state)
    original_command = paired.command
    def command(argv, name, timeout=60, allow_failure=False):
        state["phase"] = name
        save()
        return original_command(argv, name, timeout=timeout, allow_failure=allow_failure)
    paired.command = command
    class Cancelled(BaseException):
        pass
    def cancelled(signum, frame):
        raise Cancelled("Owned paired52 continuation cancellation")
    signal.signal(signal.SIGTERM, cancelled)
    signal.signal(signal.SIGINT, cancelled)
    asset_state = {}
    assets = None
    def execute_group(name, selectors, argv):
        result = out / (name + ".xcresult")
        row = {"status": "RUNNING", "startedAt": utc(), "selectors": selectors,
               "expectedTests": COUNTS[name], "commandTimeoutSeconds": CEILINGS[name],
               "argv": argv, "resultBundle": str(result)}
        state["groups"][name] = row
        save()
        code, _ = command(argv, "original-runtimes.log" if name == "OriginalRuntimes" else "paired-tests.log",
                          timeout=CEILINGS[name], allow_failure=True)
        row.update(exitCode=code, finishedAt=utc(), resultFinalized=(result / "Info.plist").is_file())
        if code == -1 or not row["resultFinalized"]:
            row.update(status="UNFINALIZED", error="No next native command after timeout/unfinalized result")
            save()
            raise RuntimeError(row["error"])
        error = None
        try:
            row["summary"] = paired.verify_native_result(result, name, selectors, COUNTS[name], code)
            row["status"] = "PASS"
        except Exception as failure:
            error = failure
            row.update(status="FAIL", error=type(failure).__name__ + ": " + str(failure))
        for suffix, key in [("-summary.json", "summarySHA256"), ("-nodes.json", "nodesSHA256"),
                            ("-selected-tests.log", "selectorVerifierSHA256")]:
            path = out / (name + suffix)
            if path.is_file():
                row[key] = digest(path)
                if suffix == "-summary.json":
                    row["summary"] = json.loads(path.read_text())
        save()
        export_code, _ = command(["xcrun", "xcresulttool", "export", "attachments", "--path", str(result),
                                 "--output-path", str(out / (name + "-attachments"))],
                                name + "-attachments-export.log", timeout=60, allow_failure=True)
        row["attachmentExportExitCode"] = export_code
        save()
        if error is not None:
            raise error
        assert export_code == 0, "Finalized test attachments must be retained"
        summary = row["summary"]
        assert summary["totalTestCount"] == summary["passedTests"] == COUNTS[name]
        assert summary["failedTests"] == summary["skippedTests"] == 0

    def observe_final_staged_inputs():
        # XCTest may rotate data containers. Observe the final route without restaging.
        record = {"schema": 1, "source": SOURCE, "simulator": device, "observedAt": utc(),
                  "authority": decision["setup"]["stagedInputs"], "status": "OBSERVATION_FAILED",
                  "preTestObservationPreserved": True, "files": [], "differences": []}
        try:
            code, raw = command(["xcrun", "simctl", "get_app_container", device,
                                 "com.itorah.hanlinminiapps", "data"],
                                "final-mini-data-container.txt", timeout=5, allow_failure=True)
            record["lookupExitCode"] = code
            assert code == 0, "Final Mini data container lookup failed"
            container = Path(raw.strip()).resolve(strict=True)
            expected_parent = Path("/Users/m1/Library/Developer/CoreSimulator/Devices") / device / "data/Containers/Data/Application"
            assert container.parent == expected_parent
            container_uuid = str(uuid.UUID(container.name)).upper()
            assert container_uuid == container.name.upper()
            documents = container / "Documents"
            assert documents.is_dir() and not documents.is_symlink()
            metadata = container / ".com.apple.mobile_container_manager.metadata.plist"
            assert metadata.is_file() and not metadata.is_symlink()
            metadata_bytes = metadata.read_bytes()
            identifier = plistlib.loads(metadata_bytes)["MCMMetadataIdentifier"]
            retained = out / "final-mini-container-metadata.plist"
            retained.write_bytes(metadata_bytes)
            record["metadata"] = {"sourcePath": str(metadata), "path": str(retained),
                "bytes": len(metadata_bytes), "sha256": hashlib.sha256(metadata_bytes).hexdigest(),
                "identifier": identifier, "containerUUID": container_uuid}
            record["documentsRoot"] = str(documents)
            assert identifier == "com.itorah.hanlinminiapps", "Final container identity mismatch"
            for expected in staged_files:
                path = documents / expected["name"]
                if not path.is_file() or path.is_symlink():
                    record["differences"].append({"name": expected["name"], "reason": "missing or symlink"})
                    continue
                actual = {"name": expected["name"], "bytes": path.stat().st_size, "sha256": digest(path)}
                record["files"].append(actual)
                expected_identity = {key: expected[key] for key in ["name", "bytes", "sha256"]}
                if actual != expected_identity:
                    record["differences"].append({"expected": expected_identity, "actual": actual})
            record["status"] = "EXECUTED_PASS" if not record["differences"] and len(record["files"]) == 11 else "MISMATCH"
        except Exception as failure:
            record["error"] = type(failure).__name__ + ": " + str(failure)
        record["finishedAt"] = utc()
        receipt = out / "staged-inputs-final-verification.json"
        write(receipt, record)
        state["stagedInputsFinalVerified"] = {**record, "receiptPath": str(receipt), "receiptSHA256": digest(receipt)}
        save()

    try:
        _, raw = command(["xcrun", "simctl", "list", "devices", "-j"], "devices-before.json")
        found = [x for values in json.loads(raw)["devices"].values() for x in values if x["udid"] == device]
        assert len(found) == 1 and found[0]["state"] == "Shutdown"
        command(["xcrun", "simctl", "boot", device], "boot.log")
        command(["xcrun", "simctl", "bootstatus", device, "-b"], "bootstatus.log", timeout=300)
        _, raw = command(["xcrun", "simctl", "get_app_container", device, "com.itorah.hanlinminiapps", "data"],
                         "retained-mini-data-container.txt", timeout=5)
        documents = Path(raw.strip()).resolve(strict=True) / "Documents"
        device_root = Path("/Users/m1/Library/Developer/CoreSimulator/Devices") / device
        assert documents.is_relative_to(device_root)
        for row in staged_files:
            path = documents / row["name"]
            assert not path.is_symlink() and path.stat().st_size == row["bytes"] and digest(path) == row["sha256"], row["name"]
        state["stagedInputsVerified"] = {"documentsRoot": str(documents), "files": staged_files,
                                        "authority": decision["setup"]["stagedInputs"], "observedAt": utc()}
        _, raw = command(["xcrun", "simctl", "get_app_container", device, "com.itorah.hanlinminiapps", "group.com.itorah.shared"],
                         "retained-modal-group-container.txt", timeout=5)
        group_path = Path(raw.strip()).resolve(strict=True)
        assert str(group_path) == modal["shared_group_container"] and group_path.is_relative_to(device_root)
        request_path = group_path / "MiniAppsBridge/v1/requests" / (REQUEST_ID + ".json")
        pending = decision["modalPending"]
        assert str(request_path) == pending["path"]
        assert request_path.stat().st_size == pending["bytes"] and digest(request_path) == pending["sha256"]
        record = json.loads(request_path.read_text())
        assert record["schemaVersion"] == 1 and record["request"]["id"].lower() == REQUEST_ID
        assert record.get("result") is None and record["acknowledged"] is False
        state["externalModalPending"] = {**pending, "observedAt": utc(), "resultAbsent": True}
        write(out / "retained-product-verification.json",
              {"source": SOURCE, "SDKProducerSource": SDK_SOURCE, "miniBuildProducerSource": MINI_SOURCE,
               "aiBuildProducerSource": SOURCE, "authority": decision["setup"]["builtInputBindings"],
               "files": built["files"], "observedAt": utc(), "buildExecuted": False})
        assets = paired.start_native_adapter_assets(asset_state)
        state["nativeAdapterAssets"] = asset_state["native_adapter_assets"]
        mini_argv = base + ["-scheme", "HanlinMiniApps", "test-without-building",
                           "-resultBundlePath", str(out / "OriginalRuntimes.xcresult")]
        mini_argv += ["-only-testing:" + item for item in mini_selectors]
        ai_argv = base + ["-scheme", "AI_HLY", "test-without-building", "-resultBundlePath", str(out / "Paired.xcresult"),
                         "-test-timeouts-enabled", "YES", "-maximum-test-execution-time-allowance", "600"]
        ai_argv += ["-only-testing:" + item for item in ai_selectors]
        write(out / "selected-commands.json", {"source": SOURCE, "originalRunnerSHA256": RUNNER_SHA,
              "OriginalRuntimes": mini_argv, "Paired": ai_argv, "groups": groups, "commandCeilingsSeconds": CEILINGS})
        execute_group("OriginalRuntimes", mini_selectors, mini_argv)
        state["original25"] = "EXECUTED_PASS"
        observed = {(x["path"], x["status"]) for x in asset_state["native_adapter_assets"]["requests"]}
        assert {("/pixel.png", 200), ("/missing.png", 404)} <= observed
        asset_state["native_adapter_assets"]["native_request_proof"] = "EXECUTED_PASS_RESOURCE_TRANSPORT"
        _, raw = command(modal["verify_command"], "external-modal-result.json")
        actual = json.loads(raw)
        assert actual["requestID"].lower() == REQUEST_ID and actual["status"] == "success"
        assert actual["message"] == "Modal invocation survived"
        state["externalModalResult"] = {"status": "EXECUTED_PASS", "command": modal["verify_command"],
            "exitCode": 0, "receiptPath": str(out / "external-modal-result.json"),
            "receiptSHA256": digest(out / "external-modal-result.json"), "actual": actual}
        save()
        execute_group("Paired", ai_selectors, ai_argv)
        state["original27"] = "EXECUTED_PASS"
        observe_final_staged_inputs()
        state["original52"] = "EXECUTED_PASS"
    except BaseException as failure:
        state["errors"].append(type(failure).__name__ + ": " + str(failure))
        (out / "wrapper-error.txt").write_text(traceback.format_exc())
    finally:
        if assets is not None:
            server, thread = assets
            try:
                server.shutdown()
                server.server_close()
                thread.join(timeout=5)
                if thread.is_alive():
                    state["cleanupErrors"].append("Owned image-server thread remains")
            except Exception as failure:
                state["cleanupErrors"].append("Owned image server: " + str(failure))
        state["nativeAdapterRequests"] = asset_state.get("native_adapter_assets", {}).get("requests", [])
        state["nativeAdapterAssets"] = asset_state.get("native_adapter_assets", {})
        for row in decision["requiredFiles"]:
            path = (root / row["path"]).resolve()
            if not path.is_relative_to(root) or not path.is_file() or digest(path) != row["sha256"]:
                state["sourceErrors"].append(row["path"])
        for row in built["files"]:
            if digest(row["path"]) != row["sha256"]:
                state["sourceErrors"].append("Product changed: " + row["path"])
        if state["errors"] or state["sourceErrors"] or state["cleanupErrors"]:
            state["status"] = "FAILED"
            if state["original52"] == "EXECUTED_PASS":
                state["original52"] = "INVALIDATED_BY_FINAL_CHECK"
        else:
            assert state["original52"] == "EXECUTED_PASS"
            state["status"] = "EXECUTED_PASS"
        state["phase"] = None
        state["finishedAt"] = utc()
        state["simulatorShutdownOwner"] = "outer controller after exact owned process-group cleanup"
        save()
    return 0 if state["status"] == "EXECUTED_PASS" else 1

if __name__ == "__main__":
    raise SystemExit(main())
