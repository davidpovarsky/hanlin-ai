"""Exercise both shipping products on one owned simulator and retain native evidence."""
from pathlib import Path
import hashlib
import json
import os
import plistlib
import shutil
import subprocess
import sys
import threading
import time
import uuid
import zipfile
from http.client import HTTPConnection
from http.server import BaseHTTPRequestHandler, HTTPServer
from urllib.parse import urlsplit

from simulator_entitlements import read_simulator_entitlements

ROOT = Path(__file__).resolve().parents[2]
EVIDENCE = Path(os.environ["SPLIT_EVIDENCE"]) / "paired-product"
GROUP = "group.com.itorah.chavrusachat"
TEST_SCOPE = os.environ.get("PAIRED_TEST_SCOPE", "cross_product")
TEST_PLANS = {
    "miniapp_authoring": ([
        "AI_HLYTests/PendingFirstTurnTests/importedMiniAppRepairDispatchesOnceAndPreservesDraftAndSettings",
        "AI_HLYTests/PendingFirstTurnTests/cancelledMiniAppRepairPreservesHomeDraft",
        "AI_HLYTests/HanlinScriptingPlatformCompositionTests/malformedImportedArchiveRetainsOriginalAndStructuredDiagnostic",
        "AI_HLYTests/MiniAppAuthoringToolTests/originalSDKWriteValidateBuildAndRepair",
        "AI_HLYTests/MiniAppAuthoringToolTests/sourceWritePreservesUnrelatedFilesAndTargetsRetainedSource",
        "AI_HLYTests/MiniAppAuthoringToolTests/originalExpoMetroBuildOnEmbeddedNode",
        "AI_HLYTests/HanlinOriginalScriptWidgetAPITests",
        "AI_HLYTests/HanlinNativePresentationTests",
        "AI_HLYTests/HanlinOriginalScriptWidgetLiveActivityTests",
        "AI_HLYTests/HanlinOriginalScriptWidgetControlTests",
        "AI_HLYTests/HanlinMiniAppStorageCapacityTests",
        "AI_HLYTests/HanlinOriginalExpoWidgetTests",
        "AI_HLYUITests/MiniAppAuthoringUITests"], 25),
    "cross_product": (["AI_HLYUITests/HanlinPairedProductUITests"], 3),
    "shared_ingress": (["AI_HLYTests/ShareInboxHostIntegrationTests", "AI_HLYUITests/HanlinShareInboxUITests"], 5),
    "product_and_share": (["AI_HLYUITests/HanlinPairedProductUITests",
                          "AI_HLYTests/ShareInboxHostIntegrationTests",
                          "AI_HLYUITests/HanlinShareInboxUITests"], 8),
}


COMMAND_HEARTBEAT_SECONDS = 30


def command(argv, name, timeout=60, allow_failure=False):
    started = time.monotonic()
    log_path = EVIDENCE / name
    identity = {"command_id": uuid.uuid4().hex, "argv": argv, "log": name,
        "runner_pid": os.getpid(), "pid": None, "started_at": time.time(), "timeout": timeout}

    def checkpoint(status, **details):
        # A running record is an observation, never evidence of completion. The
        # journal retains interrupted commands even when cleanup starts another.
        record = {**identity, "status": status, "observed_at": time.time(),
            "seconds": time.monotonic() - started, "log_bytes": log_path.stat().st_size,
            "completion_recorded": False, **details}
        encoded = json.dumps(record) + "\n"
        with (EVIDENCE / "command-events.jsonl").open("a") as journal:
            journal.write(encoded)
            journal.flush()
            os.fsync(journal.fileno())
        temporary = EVIDENCE / "active-command.json.tmp"
        with temporary.open("w") as current:
            current.write(encoded)
            current.flush()
            os.fsync(current.fileno())
        temporary.replace(EVIDENCE / "active-command.json")
        print(f"Paired command {status}: {name}; pid={record['pid']}; "
            f"elapsed={record['seconds']:.1f}s; log_bytes={record['log_bytes']}; "
            f"observed_exit={record.get('observed_returncode')}", flush=True)

    with log_path.open("wb") as log:
        checkpoint("starting")
        process = None
        try:
            # Keep subprocess.run's streaming, timeout kill/wait and exception
            # cleanup semantics; Popen exposes the actual PID for observations.
            with subprocess.Popen(argv, cwd=ROOT, stdout=log, stderr=subprocess.STDOUT) as process:
                identity["pid"] = process.pid
                stopped = threading.Event()
                observer = None
                timed_out = False

                def heartbeat():
                    while not stopped.wait(COMMAND_HEARTBEAT_SECONDS):
                        try:
                            observed = process.poll()
                            checkpoint("running" if observed is None else "exited_unrecorded",
                                observed_returncode=observed)
                        except Exception as error:
                            print(f"Command checkpoint unavailable: {name}: {error}", file=sys.stderr, flush=True)

                try:
                    observed = process.poll()
                    checkpoint("running" if observed is None else "exited_unrecorded",
                        observed_returncode=observed)
                    observer = threading.Thread(target=heartbeat, daemon=True)
                    observer.start()
                    process.communicate(timeout=timeout)
                    code = process.returncode
                except subprocess.TimeoutExpired:
                    timed_out = True
                    process.kill()
                    process.wait()
                    code = -1
                except BaseException:
                    process.kill()
                    raise
                finally:
                    stopped.set()
                    if observer is not None and observer.ident is not None:
                        observer.join()
        except BaseException as error:
            checkpoint("launch_failed" if process is None else "interrupted",
                exception_type=type(error).__name__, exception_message=str(error),
                observed_returncode=process.poll() if process is not None else None)
            raise
    output = log_path.read_bytes()
    with (EVIDENCE / "commands.jsonl").open("a") as log:
        log.write(json.dumps({"argv": argv, "exit": code, "seconds": time.monotonic() - started,
            "log": name, "sha256": hashlib.sha256(output).hexdigest()}) + "\n")
        log.flush()
        os.fsync(log.fileno())
    checkpoint("timed_out" if timed_out else "completed", completion_recorded=True,
        exit=code, observed_returncode=process.returncode)
    if code and not allow_failure:
        raise RuntimeError(f"{argv[0]} exit {code}; inspect {name}")
    return code, output.decode(errors="replace")


def capture_app_intents_metadata(app):
    """Preserve compiler output without interpreting its schema or claiming execution."""
    destination = EVIDENCE / "app-intents-metadata" / app.name
    receipt = destination.parent / (app.name + ".json")
    result = {"source_app": str(app), "status": "NOT_PRESENT", "directories": [],
              "intent_execution": "NOT_RUN", "receipt": receipt.relative_to(EVIDENCE).as_posix()}
    try:
        destination.parent.mkdir(parents=True, exist_ok=True)
        if not app.is_dir():
            result["status"] = "APP_BUNDLE_MISSING"
        else:
            metadata = []
            for directory, children, _ in os.walk(app):
                for name in list(children):
                    if name.casefold() == "metadata.appintents":
                        metadata.append(Path(directory) / name)
                        children.remove(name)
            for original in sorted(metadata):
                relative = original.relative_to(app)
                copied = destination / relative
                shutil.copytree(original, copied)
                files = []
                for file in sorted(copied.rglob("*")):
                    if file.is_file():
                        contents = file.read_bytes()
                        files.append({"path": file.relative_to(destination).as_posix(),
                                      "bytes": len(contents), "sha256": hashlib.sha256(contents).hexdigest()})
                result["directories"].append({"path": relative.as_posix(),
                    "evidence_path": copied.relative_to(EVIDENCE).as_posix(), "files": files})
            if metadata:
                result["status"] = "CAPTURED"
    except Exception as error:
        result.update(status="CAPTURE_ERROR", error=str(error))
    try:
        receipt.write_text(json.dumps(result, indent=2) + "\n")
    except OSError as error:
        result["receipt_error"] = str(error)
    print("App Intents metadata evidence: " + app.name + " " + result["status"], flush=True)
    return result


def fixture_archive(sha):
    source = ROOT / "Tests/ProductSplit/TransferFixture"
    destination = EVIDENCE / "HanlinTransferAcceptance.zip"
    hashes = {}
    with zipfile.ZipFile(destination, "w", zipfile.ZIP_DEFLATED) as archive:
        for name in ["script.json", "index.tsx"]:
            file = source / name
            relative = file.relative_to(ROOT).as_posix()
            committed = subprocess.check_output(["git", "show", f"{sha}:{relative}"], cwd=ROOT)
            if file.read_bytes() != committed:
                raise RuntimeError("Transfer input differs from the recorded source commit")
            hashes[relative] = hashlib.sha256(committed).hexdigest()
            item = zipfile.ZipInfo(name, (2026, 1, 1, 0, 0, 0))
            item.compress_type = zipfile.ZIP_DEFLATED
            archive.writestr(item, committed)
    (EVIDENCE / "fixture-provenance.json").write_text(json.dumps({
        "sha": sha, "sources": hashes,
        "archive_sha256": hashlib.sha256(destination.read_bytes()).hexdigest(),
        "scope": "Original source package input only; installation and saved state are produced through the shipping importer and runtime UI."
    }, indent=2) + "\n")
    return destination


def authoring_fixtures(documents):
    """Create input through the original build, then introduce a real TS error."""
    sdk_extract = EVIDENCE / "original-authoring-sdk"
    sdk_extract.mkdir()
    with zipfile.ZipFile(ROOT / "AI_HLY/RuntimeHostResources.zip") as packed:
        members = [name for name in packed.namelist() if name.startswith("MiniAppSDK/")]
        if not members:
            raise RuntimeError("The actual shipping archive has no authoring SDK")
        packed.extractall(sdk_extract, members=members)
    fixture_root = EVIDENCE / "authoring-fixture"
    command(["node", "Scripts/ProductSplit/prepare_authoring_fixture.mjs",
        str(sdk_extract / "MiniAppSDK"), str(fixture_root)], "authoring-fixture-build.log", timeout=300)
    receipt = json.loads((fixture_root / "fixture.json").read_text())
    source = Path(receipt["preparedPackagePath"])
    destination = documents / "MiniAppTypeError.hanlinNativeScript"
    with zipfile.ZipFile(destination, "x", zipfile.ZIP_DEFLATED) as packed:
        for file in sorted(source.rglob("*")):
            if file.is_file():
                packed.write(file, file.relative_to(source).as_posix())
    invalid = documents / "InvalidMiniApp.zip"
    invalid.write_bytes(b"This deliberately invalid input is not a ZIP archive.")
    receipt["archiveSHA256"] = hashlib.sha256(destination.read_bytes()).hexdigest()
    receipt["invalidArchiveSHA256"] = hashlib.sha256(invalid.read_bytes()).hexdigest()
    (EVIDENCE / "authoring-fixture-provenance.json").write_text(json.dumps(receipt, indent=2) + "\n")
    valid_source = Path(receipt["validPreparedPackagePath"])
    valid_archive = EVIDENCE / "NativeScriptAuthoringExample.hanlinNativeScript"
    with zipfile.ZipFile(valid_archive, "x", zipfile.ZIP_DEFLATED) as packed:
        for file in sorted(valid_source.rglob("*")):
            if file.is_file():
                packed.write(file, file.relative_to(valid_source).as_posix())
    command(["node", "Scripts/MiniApps/miniapp.mjs", "build",
        "--sdk", str(sdk_extract / "MiniAppSDK"), "--engine", "expo",
        "--project", str(ROOT / "Scripts/Expo/miniapps/modular-text-search"),
        "--archive", str(EVIDENCE / "ModularTextSearch.hanlinExpo"),
        "--report", str(EVIDENCE / "modular-search-build.json")],
        "modular-search-build.log", timeout=300)
    sample_report = json.loads((EVIDENCE / "modular-search-build.json").read_text())
    if not sample_report.get("succeeded"):
        raise RuntimeError("The actual original modular-search source did not build for this host")
    # Independent SDK-only projects are rebuilt against the exact SDK embedded
    # in this host, then imported by the real MiniApps UI below. Keep their source
    # identity separate from portable authoring proof and observed native results.
    sdk_only_archives = []
    sdk_only_provenance = []
    independent_sources = json.loads((ROOT / "docs/miniapp-sdk/evidence/sdk-only-authoring-20261124/repository-source-provenance.json").read_text())["projects"]
    for engine, project_name, archive_name in [
        ("expo", "sdk-only-departure-budget", "SDKOnlyDepartureBudget.hanlinExpo"),
        ("nativescript", "sdk-only-table-share", "SDKOnlyTableShare.hanlinNativeScript"),
    ]:
        project = ROOT / "Scripts/MiniApps/Examples" / project_name
        archive = EVIDENCE / archive_name
        report_path = EVIDENCE / (project_name + "-build.json")
        # The public CLI writes its private .hanlin-build staging under a project.
        # Capture only actual authored inputs before invoking it; ordinary source
        # directories called build or dist are not excluded.
        source_hashes = {str(file.relative_to(project)): hashlib.sha256(file.read_bytes()).hexdigest()
                         for file in sorted(project.rglob("*"))
                         if file.is_file() and ".hanlin-build" not in file.relative_to(project).parts}
        independent = next(item for item in independent_sources
                           if item["repositoryProject"] == str(project.relative_to(ROOT)))
        expected_hashes = {item["path"]: item["sha256"] for item in independent["files"]}
        if source_hashes != expected_hashes:
            raise RuntimeError("SDK-only inputs differ from the retained independent source proof: " + project_name)
        command(["node", "Scripts/MiniApps/miniapp.mjs", "build",
            "--sdk", str(sdk_extract / "MiniAppSDK"), "--engine", engine,
            "--project", str(project), "--archive", str(archive),
            "--report", str(report_path)], project_name + "-build.log", timeout=300)
        report = json.loads(report_path.read_text())
        if not report.get("succeeded"):
            raise RuntimeError("The independent SDK-only " + engine + " source did not build for this host")
        sdk_only_archives.append(archive)
        sdk_only_provenance.append({
            "engine": engine, "source_project": str(project.relative_to(ROOT)),
            "source_hashes": source_hashes,
            "archive": archive.name, "archive_sha256": hashlib.sha256(archive.read_bytes()).hexdigest(),
            "report": report_path.name, "report_sha256": hashlib.sha256(report_path.read_bytes()).hexdigest(),
            "sdk_manifest_sha256": hashlib.sha256((sdk_extract / "MiniAppSDK/miniapp-sdk.json").read_bytes()).hexdigest(),
            "native_result": "NOT_RUN; requires the selected real importer and native interaction cases",
        })
    (EVIDENCE / "sdk-only-package-provenance.json").write_text(json.dumps(sdk_only_provenance, indent=2) + "\n")
    (EVIDENCE / "sample-package-hashes.json").write_text(json.dumps({
        file.name: hashlib.sha256(file.read_bytes()).hexdigest()
        for file in [valid_archive, EVIDENCE / "ModularTextSearch.hanlinExpo", *sdk_only_archives]
    }, indent=2) + "\n")
    # The SDK already lives in the shipping app/archive; this extraction is only
    # the fixture producer's temporary compiler input, never an installed result.
    shutil.rmtree(sdk_extract)


def verify_native_result(result, prefix, selectors, expected, code):
    _, raw = command(["xcrun", "xcresulttool", "get", "test-results", "summary",
        "--path", str(result)], prefix + "-summary.json")
    summary = json.loads(raw)
    command(["xcrun", "xcresulttool", "get", "test-results", "tests",
        "--path", str(result)], prefix + "-nodes.json")
    command([sys.executable, "Scripts/CI/verify_selected_tests.py", "--results",
        str(EVIDENCE / (prefix + "-nodes.json")), "--selectors", ",".join(selectors)],
        prefix + "-selected-tests.log")
    if code or summary.get("passedTests") != expected or summary.get("failedTests", 0) or summary.get("skippedTests", 0):
        raise RuntimeError("Original runtime acceptance did not execute every selected case: " + prefix)
    return summary


def start_native_adapter_assets(state):
    """Own a real loopback image transport; never synthesize an adapter result."""
    image_path = ROOT / "Fixtures/ExpoSwiftUIProbe/native-adapter-assets/pixel.png"
    image = image_path.read_bytes()
    if not image.startswith(b"\x89PNG\r\n\x1a\n"):
        raise RuntimeError("The native adapter PNG fixture is missing or malformed")
    requests = []
    origin = "http://localhost:49173"

    class AssetHandler(BaseHTTPRequestHandler):
        def setup(self):
            super().setup()
            self.connection.settimeout(5)

        def do_GET(self):
            resource = urlsplit(self.path).path
            status, content_type, body = {
                "/health": (200, "text/plain", b"ready"),
                "/pixel.png": (200, "image/png", image),
            }.get(resource, (404, "text/plain", b"Missing native adapter fixture"))
            self.send_response(status)
            self.send_header("Content-Type", content_type)
            self.send_header("Content-Length", str(len(body)))
            self.send_header("Cache-Control", "no-store")
            self.end_headers()
            self.wfile.write(body)
            requests.append({"path": resource, "status": status, "bytes": len(body),
                "sha256": hashlib.sha256(body).hexdigest(), "at": time.time()})

        def log_message(self, format, *args):
            pass

    server = HTTPServer(("127.0.0.1", 49173), AssetHandler)
    thread = threading.Thread(target=lambda: server.serve_forever(poll_interval=0.1), daemon=True)
    thread.start()
    try:
        connection = HTTPConnection("127.0.0.1", 49173, timeout=5)
        try:
            connection.request("GET", "/health")
            response = connection.getresponse()
            if response.status != 200 or response.read() != b"ready":
                raise RuntimeError("Owned native adapter HTTP endpoint did not become ready")
        finally:
            connection.close()
    except Exception:
        server.shutdown()
        server.server_close()
        thread.join(timeout=5)
        raise
    state["native_adapter_assets"] = {"origin": origin,
        "source": str(image_path.relative_to(ROOT)), "bytes": len(image),
        "sha256": hashlib.sha256(image).hexdigest(),
        "scope": "Exact PNG and real HTTP404 only; no mocked renderer, adapter or event.",
        "requests": requests, "native_request_proof": "NOT_RUN"}
    return server, thread


def main():
    EVIDENCE.mkdir(parents=True, exist_ok=False)
    state = {"status": "INFRA_ERROR", "ui": "NOT_RUN", "build": "NOT_RUN",
        "physical_device": "NOT_RUN", "provisioned_distribution": "NOT_RUN",
        "scope": "Two shipping targets, actual App Group, original Host request/return/cancel, original ScriptUI import and private-data transfer/rollback",
        "model_boundary": "Existing opt-in simulator HTTP acceptance provider; all Host, permission, OS transitions, storage and result handling are real.",
        "started_at": time.time()}
    simulator = None
    adapter_assets = None
    try:
        if TEST_SCOPE not in TEST_PLANS:
            raise RuntimeError("Unknown original-product acceptance scope")
        selectors, expected_tests = TEST_PLANS[TEST_SCOPE]
        state["test_scope"] = TEST_SCOPE
        state["selected_tests"] = selectors
        if TEST_SCOPE == "miniapp_authoring":
            state["scope"] = "Original SDK/tools, source diagnostics, native repair sheet, durable AI handoff, actual build/install and NativeScript/Expo runtime controls in both shipping products"
            state["model_boundary"] = "Only the HTTP model response sequence and the native adapter image fixture resources are deterministic. All source edits, TypeScript diagnostics, Metro/ESM production, imports, receipts, native rendering and UI events are original production code."
        if TEST_SCOPE == "product_and_share":
            state["scope"] += "; original share ingress to Composer and SDK"
            state["os_share_sheet"] = "NOT_RUN; input uses original store APIs and NSItemProvider in the native host suite"
        if TEST_SCOPE == "shared_ingress":
            state["scope"] = "Actual original App Group ingress, verified file copies, original Composer and SDK consumption"
            state["os_share_sheet"] = "NOT_RUN; input uses original store APIs and NSItemProvider in the native host suite"
        _, raw = command(["git", "rev-parse", "HEAD"], "source-sha.txt")
        state["sha"] = raw.strip()
        _, sdk = command(["xcrun", "--sdk", "iphonesimulator", "--show-sdk-version"], "sdk.txt")
        sdk = sdk.strip()
        if int(sdk.split(".")[0]) != 27:
            raise RuntimeError("Acceptance requires the installed stable iOS 27 SDK")
        _, raw = command(["xcrun", "simctl", "list", "runtimes", "-j"], "runtimes.json")
        runtime = next(r for r in json.loads(raw)["runtimes"] if r.get("isAvailable")
            and not r.get("isInternal") and r["identifier"].endswith("iOS-" + sdk.replace(".", "-")))
        _, raw = command(["xcrun", "simctl", "list", "devicetypes", "-j"], "device-types.json")
        supported = {item["identifier"] for item in runtime["supportedDeviceTypes"]}
        device_family = "iPad" if TEST_SCOPE == "miniapp_authoring" else "iPhone"
        device = next(item for item in json.loads(raw)["devicetypes"]
            if item.get("productFamily") == device_family and item["identifier"] in supported)
        _, raw = command(["xcrun", "simctl", "create",
            "HanlinPaired-" + os.environ.get("GITHUB_RUN_ID", "local"),
            device["identifier"], runtime["identifier"]], "created-simulator.txt")
        simulator = raw.strip()
        state.update(simulator=simulator, runtime=runtime["identifier"], device=device["name"])
        # Boot the owned device before compilation. Its first-boot OS services can
        # finish while Xcode builds; previously the first app install immediately
        # followed a cold boot (176.55s on one runner, timed out on the other).
        # Resolve read-only CLI metadata and capture host resources BEFORE first
        # boot. Run 44248241361 stalled even help/ps while the fresh OS initialized,
        # so its product build and all eight acceptance cases never started.
        command(["xcrun", "simctl", "help", "get_app_container"], "container-command-help.txt")
        command(["sysctl", "hw.memsize", "hw.ncpu"], "before-boot-host-resources.txt")
        command(["vm_stat"], "before-boot-memory.txt")
        command(["ps", "-axo", "pid,ppid,%cpu,%mem,state,etime,comm"], "before-boot-processes.txt")
        command(["xcrun", "simctl", "boot", simulator], "boot.log")
        command(["xcrun", "simctl", "bootstatus", simulator, "-b"], "bootstatus.log", timeout=300)
        derived = Path(os.environ["SPLIT_DERIVED_DATA"])
        products = {
            "com.itorah.chavrusachat": derived / "Build/Products/Debug-iphonesimulator/AI_Hanlin.app",
            "com.itorah.hanlinminiapps": derived / "Build/Products/Debug-iphonesimulator/HanlinMiniApps.app"
        }
        state["app_intents_metadata"] = {}
        base = ["xcodebuild", "-project", "AI_HLY.xcodeproj",
            "-destination", "platform=iOS Simulator,id=" + simulator,
            "-parallel-testing-enabled", "NO", "-derivedDataPath", str(derived),
            "-clonedSourcePackagesDirPath", str(ROOT / "build/SourcePackages"),
            # Same already-pinned A2UI generator/macros as the original app CI.
            # Noninteractive runners have no Xcode trust-confirmation UI.
            "-skipPackagePluginValidation", "-skipMacroValidation",
            # Simulator ad-hoc signing includes the targets' existing entitlements.
            # No team, provisioning profile, application ID or distribution signing is changed.
            "CODE_SIGNING_ALLOWED=YES", "CODE_SIGNING_REQUIRED=YES", "CODE_SIGN_IDENTITY=-"]
        state["status"] = "BUILD_FAILED"
        # Same bounded cold MiniApps compilation budget as standalone acceptance.
        # This does not extend first-launch, routing, cancellation or UI deadlines.
        mini_action = "build-for-testing" if TEST_SCOPE == "miniapp_authoring" else "build"
        command(base + ["-scheme", "HanlinMiniApps", mini_action,
            "-resultBundlePath", str(EVIDENCE / "MiniBuild.xcresult")], "mini-build.log", timeout=2400)
        state["mini_build"] = "EXECUTED_PASS"
        state["app_intents_metadata"]["com.itorah.hanlinminiapps"] = capture_app_intents_metadata(products["com.itorah.hanlinminiapps"])
        # The original full-app workflow uses this exact pinned upstream generator:
        # Xcode 27.2 advertises its outputs but can omit the generator build commands.
        # The helper verifies every input against the resolved commit before running it.
        command([sys.executable, "Scripts/CI/stage_a2ui_schemas.py",
            "--source-packages-path", str(ROOT / "build/SourcePackages"),
            "--derived-data-path", str(derived),
            "--evidence", str(EVIDENCE / "original-a2ui-schemas")],
            "original-a2ui-generator.log", timeout=360)
        state["build"] = "EXECUTED_FAIL"
        state["ai_build"] = "EXECUTED_FAIL"
        command(base + ["-scheme", "AI_HLY", "build-for-testing",
            "-resultBundlePath", str(EVIDENCE / "AIBuild.xcresult")], "ai-build.log", timeout=1800)
        state["ai_build"] = "EXECUTED_PASS"
        state["app_intents_metadata"]["com.itorah.chavrusachat"] = capture_app_intents_metadata(products["com.itorah.chavrusachat"])
        state["build"] = "EXECUTED_PASS"
        state["status"] = "INFRA_ERROR"
        expected_names = {"com.itorah.chavrusachat": "Hanlin AI",
                          "com.itorah.hanlinminiapps": "Hanlin MiniApps"}
        state["product_identity"] = {}
        for bundle, product in products.items():
            info = plistlib.loads((product / "Info.plist").read_bytes())
            if info["CFBundleIdentifier"] != bundle:
                raise RuntimeError("Built product identity differs from its original target")
            if info.get("CFBundleDisplayName") != expected_names[bundle]:
                raise RuntimeError("Installed product display name differs from the approved two-app identity")
            state["product_identity"][bundle] = {"display_name": info["CFBundleDisplayName"],
                "info_plist_sha256": hashlib.sha256((product / "Info.plist").read_bytes()).hexdigest()}
            icon = info.get("CFBundleIcons", {}).get("CFBundlePrimaryIcon", {})
            assets = product / "Assets.car"
            if icon.get("CFBundleIconName") != "AppIcon" or not assets.is_file() or assets.stat().st_size == 0:
                raise RuntimeError("Built product must contain its compiled original Hanlin app icon")
            state["product_identity"][bundle]["app_icon"] = {
                "name": icon["CFBundleIconName"],
                "compiled_catalog_sha256": hashlib.sha256(assets.read_bytes()).hexdigest()}
            command(["codesign", "--verify", "--deep", "--strict", str(product)], bundle + "-signature.log")
            executable_name = info["CFBundleExecutable"]
            if Path(executable_name).name != executable_name:
                raise RuntimeError("Built executable must be inside its original app bundle")
            proof = read_simulator_entitlements(product / executable_name)
            source = ROOT / ("AI_HLY/AI_HLY.entitlements" if bundle == "com.itorah.chavrusachat"
                             else "HanlinMiniAppsApp/HanlinMiniApps.entitlements")
            required = plistlib.loads(source.read_bytes())["com.apple.security.application-groups"]
            actual = proof["entitlements"].get("com.apple.security.application-groups", [])
            if GROUP not in required or not set(required).issubset(actual):
                raise RuntimeError("Original App Groups are absent from the built simulator executable")
            proof["source_entitlements_sha256"] = hashlib.sha256(source.read_bytes()).hexdigest()
            (EVIDENCE / (bundle + "-embedded-entitlements.json")).write_text(
                json.dumps(proof, indent=2) + "\n")
        # Install both original products before asking either for shared state.
        # One measured cold install already consumed 176.55s of the former 180s
        # limit. This single bounded attempt retains its actual timing and exit.
        for bundle, product in products.items():
            command(["xcrun", "simctl", "install", simulator, str(product)],
                bundle + "-install.log", timeout=300)
        containers = {}
        for bundle in products:
            # Let the shipping bootstrap request its real OS container. No group
            # directory, response, grant, or acceptance result is synthesized.
            command(["xcrun", "simctl", "launch", simulator, bundle,
                "-AppleLanguages", "(en)", "-AppleLocale", "en_US"],
                bundle + "-first-launch.log", timeout=120)
            _, raw = command(["xcrun", "simctl", "get_app_container", simulator, bundle, GROUP],
                bundle + "-group-container.txt", timeout=180)
            container = Path(raw.strip()).resolve(strict=True)
            if not container.is_dir():
                raise RuntimeError("The OS did not return an existing shared container directory")
            containers[bundle] = str(container)
            command(["xcrun", "simctl", "terminate", simulator, bundle],
                bundle + "-first-launch-terminate.log", timeout=60)
        if len(set(containers.values())) != 1:
            raise RuntimeError("The installed products do not share the OS-provided App Group container")
        state["app_group"] = {"status": "EXECUTED_PASS", "containers": containers}
        if TEST_SCOPE == "miniapp_authoring":
            _, raw = command(["xcrun", "simctl", "get_app_container", simulator,
                "com.itorah.hanlinminiapps", "data"], "authoring-mini-data-container.txt")
            documents = Path(raw.strip()) / "Documents"
            documents.mkdir(exist_ok=True)
            authoring_fixtures(documents)
            runtime_inputs = [
                ROOT / "DemoMiniApps/hanlin-script-parity.hanlinNativeScript",
                ROOT / "AI_HLYUITests/Fixtures/ExpoSwiftUIProbeA.hanlinExpo",
                ROOT / "AI_HLYUITests/Fixtures/ExpoNativeAPIProbeA.hanlinExpo",
                ROOT / "AI_HLYUITests/Fixtures/ExpoWidgetsProbeA.hanlinExpo",
                ROOT / "AI_HLYUITests/Fixtures/ExpoWidgetsProbeB.hanlinExpo",
                EVIDENCE / "ModularTextSearch.hanlinExpo",
                EVIDENCE / "SDKOnlyDepartureBudget.hanlinExpo",
                EVIDENCE / "SDKOnlyTableShare.hanlinNativeScript"]
            state["runtime_inputs"] = []
            for source in runtime_inputs:
                destination = documents / source.name
                if destination.exists():
                    raise RuntimeError("Owned fresh simulator has an unexpected runtime input")
                shutil.copy2(source, destination)
                digest = hashlib.sha256(source.read_bytes()).hexdigest()
                if hashlib.sha256(destination.read_bytes()).hexdigest() != digest:
                    raise RuntimeError("Runtime fixture bytes changed")
                state["runtime_inputs"].append({"source": os.path.relpath(source, ROOT), "sha256": digest})
            # Existing owner fixture: actual ScriptUI import and nested modal in
            # the original cross-app mailbox group, not synthetic Expo runtimes.
            _, raw = command([sys.executable, "Scripts/ProductSplit/stage_external_modal_fixture.py",
                "--simulator-udid", simulator, "--app-path", str(products["com.itorah.hanlinminiapps"]),
                "--evidence", str(EVIDENCE / "external-modal-fixture")],
                "external-modal-fixture-stage.log", timeout=180)
            modal_fixture = json.loads(raw)
            state["external_modal_fixture"] = modal_fixture
            runtime_selectors = [
                "HanlinMiniAppsUITests/MiniAppsProductionRuntimeUITests/testStandaloneNativeScriptUsesRealRuntimesAndSurvivesRelaunch",
                "HanlinMiniAppsUITests/MiniAppsProductionRuntimeUITests/testStandaloneExpoRendersNativeControlsAndRunsReactEvents",
                "HanlinMiniAppsUITests/MiniAppsProductionRuntimeUITests/testStandaloneExpoManualInputLayoutAndDataAdapters",
                "HanlinMiniAppsUITests/MiniAppsProductionRuntimeUITests/testStandaloneExpoManualPresentationAdaptersAndDismissalEvents",
                "HanlinMiniAppsUITests/MiniAppsProductionRuntimeUITests/testStandaloneExpoNativeAPIUsesActualUIKitAndWorklets",
                "HanlinMiniAppsUITests/MiniAppsProductionRuntimeUITests/testStandaloneExpoWidgetsUsesOriginalTimelinesAndLiveActivities",
                "HanlinMiniAppsUITests/MiniAppsProductionRuntimeUITests/testStandaloneModularSearchLoadsActualSefariaText",
                "HanlinMiniAppsUITests/MiniAppsProductionRuntimeUITests/testStandaloneSDKOnlyExpoPackageImportsRendersAndHandlesEvents",
                "HanlinMiniAppsUITests/MiniAppsProductionRuntimeUITests/testStandaloneSDKOnlyNativeScriptPackageImportsRendersAndHandlesEvents",
                "HanlinMiniAppsTests/CrossAppInvocationTests/testCancelAndDisplayDoneReturnNoDocumentMutation",
                "HanlinMiniAppsTests/CrossAppInvocationTests/testReusingValueWindowKeepsItsInvocationBindingCurrent",
                "HanlinMiniAppsTests/CrossAppInvocationTests/testRemovingInvocationOwnerCancelsWhileSessionIsStillRetained",
                "HanlinMiniAppsTests/CrossAppInvocationTests/testActualIncomingRequestsCreateDistinctIPadScenes",
                "HanlinMiniAppsTests/NativeScriptWindowOwnershipTests/testUnrelatedAndLateWindowCleanupPreservesNativeScriptOwner",
                "HanlinMiniAppsTests/NativeScriptHostServicesLifetimeTests/testInvalidationReleasesHandlersAndRejectsLateActions",
                "HanlinMiniAppsTests/NativeScriptHostServicesLifetimeTests/testBridgeInvalidationReleasesPendingCallbacksBeforeProviderCancellation",
                "HanlinMiniAppsUITests/MiniAppsExternalModalLifetimeUITests/testExternalInvocationSurvivesNestedFullScreenModal"]
            adapter_assets = start_native_adapter_assets(state)
            state["original_runtime_selectors"] = runtime_selectors
            runtime_result = EVIDENCE / "OriginalRuntimes.xcresult"
            argv = base + ["-scheme", "HanlinMiniApps", "test-without-building",
                "-resultBundlePath", str(runtime_result)]
            argv += ["-only-testing:" + selector for selector in runtime_selectors]
            code, _ = command(argv, "original-runtimes.log", timeout=1200, allow_failure=True)
            state["original_runtime_summary"] = verify_native_result(runtime_result, "original-runtimes",
                runtime_selectors, 17, code)
            observed_images = {(request["path"], request["status"])
                for request in state["native_adapter_assets"]["requests"]}
            if not {("/pixel.png", 200), ("/missing.png", 404)}.issubset(observed_images):
                raise RuntimeError("Native adapter UI passed without the required real image HTTP requests")
            state["native_adapter_assets"]["native_request_proof"] = "EXECUTED_PASS_RESOURCE_TRANSPORT"
            _, raw = command(modal_fixture["verify_command"], "external-modal-result.json")
            state["external_modal_result"] = json.loads(raw)
        if TEST_SCOPE in {"cross_product", "product_and_share"}:
            archive = fixture_archive(state["sha"])
            _, raw = command(["xcrun", "simctl", "get_app_container", simulator,
                "com.itorah.chavrusachat", "data"], "ai-data-container.txt")
            documents = Path(raw.strip()) / "Documents"
            documents.mkdir(exist_ok=True)
            if (documents / archive.name).exists():
                raise RuntimeError("The fresh owned simulator already has a transfer package input")
            shutil.copy2(archive, documents / archive.name)
        result = EVIDENCE / "Paired.xcresult"
        argv = base + ["-scheme", "AI_HLY", "test-without-building",
            "-resultBundlePath", str(result),
            "-test-timeouts-enabled", "YES", "-maximum-test-execution-time-allowance", "600"]
        argv += ["-only-testing:" + selector for selector in selectors]
        code, _ = command(argv, "paired-tests.log", timeout=2100, allow_failure=True)
        state["status"] = "INFRA_ERROR"
        if result.exists():
            _, raw = command(["xcrun", "xcresulttool", "get", "test-results", "summary",
                "--path", str(result)], "test-summary.json")
            summary = json.loads(raw)
            state["summary"] = summary
            command(["xcrun", "xcresulttool", "get", "test-results", "tests",
                "--path", str(result)], "test-nodes.json")
            command([sys.executable, "Scripts/CI/verify_selected_tests.py",
                "--results", str(EVIDENCE / "test-nodes.json"), "--selectors", ",".join(selectors)],
                "requested-tests.log")
            if code == 0 and summary.get("passedTests") == expected_tests and summary.get("failedTests", 0) == 0 \
                    and summary.get("skippedTests", 0) == 0:
                state.update(status="EXECUTED_PASS", ui="EXECUTED_PASS")
            elif summary.get("failedTests", 0):
                state.update(status="TEST_FAILED", ui="TEST_FAILED")
        if state["status"] != "EXECUTED_PASS":
            raise RuntimeError("Original native acceptance did not pass every case in the recorded scope")
    except Exception as error:
        state["error"] = str(error)
        print(str(error), file=sys.stderr)
        if simulator:
            diagnostics = [
                (["xcrun", "simctl", "list", "devices", "-j"], "failure-device-state.json"),
                (["xcrun", "simctl", "listapps", simulator], "failure-installed-apps.plist"),
                (["ps", "-axo", "pid,ppid,state,etime,comm"], "failure-processes.txt"),
                (["vm_stat"], "failure-memory.txt"),
                (["xcrun", "simctl", "io", simulator, "screenshot",
                  str(EVIDENCE / "failure.png")], "screenshot.log"),
            ]
            state["diagnostic_errors"] = []
            for argv, name in diagnostics:
                try:
                    command(argv, name, timeout=30)
                except Exception as capture:
                    state["diagnostic_errors"].append(str(capture))
    finally:
        if adapter_assets:
            server, thread = adapter_assets
            server.shutdown()
            server.server_close()
            thread.join(timeout=5)
        # Retain the actual test attachments for visual inspection of the sheet
        # and repaired app; a final simulator screenshot is not a substitute.
        if TEST_SCOPE == "miniapp_authoring":
            state["attachment_exports"] = []
            for name in ["OriginalRuntimes", "Paired"]:
                bundle = EVIDENCE / (name + ".xcresult")
                if not bundle.exists():
                    continue
                destination = EVIDENCE / (name.lower() + "-attachments")
                try:
                    code, _ = command(["xcrun", "xcresulttool", "export", "attachments",
                        "--path", str(bundle), "--output-path", str(destination)],
                        name.lower() + "-attachments-export.log", timeout=60, allow_failure=True)
                    state["attachment_exports"].append({"result": bundle.name,
                        "path": destination.name, "exit_code": code})
                except Exception as error:
                    state["attachment_exports"].append({"result": bundle.name, "error": str(error)})
        state["result_bundles"] = [p.name for p in EVIDENCE.glob("*.xcresult")]
        state["duration_seconds"] = time.time() - state["started_at"]
        (EVIDENCE / "acceptance.json").write_text(json.dumps(state, indent=2) + "\n")
        if simulator:
            # Preserve the dedicated simulator and its data for failure diagnosis.
            try:
                subprocess.run(["xcrun", "simctl", "shutdown", simulator], stdout=subprocess.DEVNULL,
                    stderr=subprocess.DEVNULL, timeout=30)
            except subprocess.TimeoutExpired:
                pass
    return 0 if state["status"] == "EXECUTED_PASS" else 1


if __name__ == "__main__":
    sys.exit(main())
