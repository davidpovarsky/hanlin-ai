"""Exercise both shipping products on one owned simulator and retain native evidence."""
from pathlib import Path
import hashlib
import datetime
import html
import json
import os
import plistlib
import re
import stat
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
REQUESTED_TEST_SCOPE = os.environ.get("PAIRED_TEST_SCOPE", "cross_product")
RUN_EXTRA26 = REQUESTED_TEST_SCOPE == "miniapp_complete_with_extra26"
TEST_SCOPE = "miniapp_complete" if RUN_EXTRA26 else REQUESTED_TEST_SCOPE
EXTRA26_ORIGINAL54_DEADLINE = None
TEST_PLANS = {
    "miniapp_authoring": ([
        "AI_HLYTests/PendingFirstTurnTests/importedMiniAppRepairDispatchesOnceAndPreservesDraftAndSettings()",
        "AI_HLYTests/PendingFirstTurnTests/cancelledMiniAppRepairPreservesHomeDraft()",
        "AI_HLYTests/HanlinScriptingPlatformCompositionTests/malformedImportedArchiveRetainsOriginalAndStructuredDiagnostic()",
        "AI_HLYTests/MiniAppAuthoringToolTests/originalSDKWriteValidateBuildAndRepair()",
        "AI_HLYTests/MiniAppAuthoringToolTests/sourceWritePreservesUnrelatedFilesAndTargetsRetainedSource()",
        "AI_HLYTests/MiniAppAuthoringToolTests/originalExpoMetroBuildOnEmbeddedNode()",
        "AI_HLYTests/HanlinOriginalScriptWidgetAPITests",
        "AI_HLYTests/HanlinNativePresentationTests",
        "AI_HLYTests/HanlinOriginalScriptWidgetLiveActivityTests",
        "AI_HLYTests/HanlinOriginalScriptWidgetControlTests",
        "AI_HLYTests/HanlinMiniAppStorageCapacityTests",
        "AI_HLYTests/HanlinOriginalExpoWidgetTests",
        "AI_HLYUITests/MiniAppAuthoringUITests"], 27),
    "miniapp_sdk04": ([
        "AI_HLYTests/HanlinExpoHostServicesAcceptanceTests/testInstalledExpoActionsReturnActualReplyAndFailure",
        "AI_HLYTests/HanlinExpoHostServicesAcceptanceTests/testPreparedExpoWidgetPublicationReachesExistingConsumer"], 2),
    "cross_product": (["AI_HLYUITests/HanlinPairedProductUITests"], 3),
    "shared_ingress": (["AI_HLYTests/ShareInboxHostIntegrationTests", "AI_HLYUITests/HanlinShareInboxUITests"], 5),
    "product_and_share": (["AI_HLYUITests/HanlinPairedProductUITests",
                          "AI_HLYTests/ShareInboxHostIntegrationTests",
                          "AI_HLYUITests/HanlinShareInboxUITests"], 8),
}


# The earlier42 app cases never executed after the failed first product build.
# Complete acceptance combines their exact plan with only the new current cases.
TEST_PLANS["miniapp_complete"] = (
    TEST_PLANS["miniapp_authoring"][0] + TEST_PLANS["miniapp_sdk04"][0], 29)

# Additional real-system route in this original runner. The original paired54
# selectors/counts remain unchanged and are not replaced by this scope.
TEST_PLANS["miniapp_shortcuts_os"] = ([
    "AI_HLYUITests/HanlinEntrypointSystemSurfaceUITests/testExpoRunMiniAppActionSavedBackgroundReturnsTypedResult",
    "AI_HLYUITests/HanlinEntrypointSystemSurfaceUITests/testNativeScriptRunMiniAppActionSavedBackgroundReturnsTypedResult",
    "AI_HLYUITests/HanlinEntrypointSystemSurfaceUITests/testExpoRunMiniAppActionSavedForegroundReturnsTypedResult",
    "AI_HLYUITests/HanlinEntrypointSystemSurfaceUITests/testNativeScriptRunMiniAppActionSavedForegroundReturnsTypedResult",
], 4)

TEST_PLANS["miniapp_widget_recovery_os"] = ([
    "AI_HLYUITests/HanlinEntrypointSystemSurfaceUITests/testMiniAppsPlacedWidgetRetainsLastGoodAfterRealFailureAndRecovers",
], 1)

# Genuine independent named placements and sequential native Toggle/Add/Refresh.
TEST_PLANS["miniapp_widget_state_os"] = ([
    "AI_HLYUITests/HanlinEntrypointSystemSurfaceUITests/testMiniAppsPlacedWidgetToggleKeepsIndependentInstanceState",
], 1)

# One physically placed A, an untouched native B and actual public VoiceOver.
TEST_PLANS["miniapp_widget_voiceover_os"] = ([
    "AI_HLYUITests/HanlinEntrypointSystemSurfaceUITests/testMiniAppsPlacedWidgetToggleVoiceOverAnnouncesAndSetsBothValues",
], 1)

# Four separate actual Home Screen family placements and effective rotations.
TEST_PLANS["miniapp_widget_families_os"] = ([
    "AI_HLYUITests/HanlinEntrypointSystemSurfaceUITests/testMiniAppsSmallWidgetRetainsFamilyAndInstanceAcrossRotation",
    "AI_HLYUITests/HanlinEntrypointSystemSurfaceUITests/testMiniAppsMediumWidgetRetainsFamilyAndInstanceAcrossRotation",
    "AI_HLYUITests/HanlinEntrypointSystemSurfaceUITests/testMiniAppsLargeWidgetRetainsFamilyAndInstanceAcrossRotation",
    "AI_HLYUITests/HanlinEntrypointSystemSurfaceUITests/testMiniAppsExtraLargeWidgetRetainsFamilyAndInstanceAcrossRotation",
], 4)

# Additive NS-owner/three-background-action OS pilot; original plans stay intact.
TEST_PLANS["miniapp_shortcut_concurrency_os"] = ([
    "AI_HLYUITests/HanlinEntrypointSystemSurfaceUITests/testNativeScriptOwnerSurvivesThreeOverlappingBackgroundShortcutsInReverseOrder",
    "AI_HLYUITests/HanlinEntrypointSystemSurfaceUITests/testNativeScriptOwnerSurvivesCancellingOneOfThreeOverlappingBackgroundShortcuts",
], 2)

# Admit the original ten existing real-system methods; do not duplicate paired54.
TEST_PLANS["miniapp_system_surfaces_os"] = ([
    "AI_HLYUITests/HanlinEntrypointSystemSurfaceUITests/testExpoPlacedWidgetInvokesAllFiveRuntimes",
    "AI_HLYUITests/HanlinEntrypointSystemSurfaceUITests/testNativeScriptPlacedWidgetInvokesAllFiveRuntimes",
    "AI_HLYUITests/HanlinEntrypointSystemSurfaceUITests/testExpoLiveActivityInvokesAllFiveRuntimes",
    "AI_HLYUITests/HanlinEntrypointSystemSurfaceUITests/testNativeScriptLiveActivityInvokesAllFiveRuntimes",
    "AI_HLYUITests/HanlinEntrypointSystemSurfaceUITests/testExpoShortcutInvokesAllFiveRuntimes",
    "AI_HLYUITests/HanlinEntrypointSystemSurfaceUITests/testNativeScriptShortcutInvokesAllFiveRuntimes",
    "AI_HLYUITests/HanlinEntrypointSystemSurfaceUITests/testExpoSystemShareInvokesAllFiveRuntimes",
    "AI_HLYUITests/HanlinEntrypointSystemSurfaceUITests/testNativeScriptSystemShareInvokesAllFiveRuntimes",
    "AI_HLYUITests/HanlinEntrypointSystemSurfaceUITests/testExpoSystemTranslationInvokesAllFiveRuntimes",
    "AI_HLYUITests/HanlinEntrypointSystemSurfaceUITests/testNativeScriptSystemTranslationInvokesAllFiveRuntimes",
], 10)

# Real shipping Studio/gallery UI; no external producer or seeded project source.
TEST_PLANS["miniapp_studio_gallery_os"] = ([
    "AI_HLYUITests/HanlinEntrypointSystemSurfaceUITests/testStudioExpoHelloWorldCopiesEditsBuildsInstallsAndRuns",
    "AI_HLYUITests/HanlinEntrypointSystemSurfaceUITests/testStudioDepartureBudgetCopiesEditsBuildsInstallsAndRuns",
    "AI_HLYUITests/HanlinEntrypointSystemSurfaceUITests/testStudioNativeScriptHelloWorldCopiesEditsBuildsInstallsAndRuns",
    "AI_HLYUITests/HanlinEntrypointSystemSurfaceUITests/testStudioTableShareCopiesEditsBuildsInstallsAndRuns",
    "AI_HLYUITests/HanlinEntrypointSystemSurfaceUITests/testStudioNativeImageDrawingCopiesEditsBuildsInstallsAndRuns",
], 5)

# Actual shipping editor operations; all original paired plans remain unchanged.
TEST_PLANS["miniapp_studio_editor_os"] = ([
    "AI_HLYUITests/HanlinEntrypointSystemSurfaceUITests/testStudioExpoCreatesMovesStylesAndReopensSource",
    "AI_HLYUITests/HanlinEntrypointSystemSurfaceUITests/testStudioNativeScriptCreatesMovesStylesAndReopensSource",
    "AI_HLYUITests/HanlinEntrypointSystemSurfaceUITests/testStudioOriginalTypeScriptHelpPreferencesAndLiveLogExport",
    "AI_HLYUITests/HanlinEntrypointSystemSurfaceUITests/testStudioImportsActualFilesSourceAndReopensIndependentEdit",
    "AI_HLYUITests/HanlinEntrypointSystemSurfaceUITests/testStudioTwoRealWindowsConflictReloadAndRecoverSeparateCopy",
], 5)

SDK04_MINIAPPS_SELECTORS = (
    "HanlinMiniAppsUITests/MiniAppsProductionRuntimeUITests/testStandaloneExpoGeneratedGroupBoxSlotsAndInstalledMetadata",
    "HanlinMiniAppsUITests/MiniAppsProductionRuntimeUITests/testStandaloneExpoGeneratedEditButtonEditsOriginalList",
    "HanlinMiniAppsUITests/MiniAppsProductionRuntimeUITests/testStandaloneExpoGeneratedEmptyViewReportsNativeLayout",
    "HanlinMiniAppsUITests/MiniAppsProductionRuntimeUITests/testStandaloneExpoGeneratedModifierAccessibilityAndGeometry",
    "HanlinMiniAppsUITests/MiniAppsProductionRuntimeUITests/testStandaloneExpoGeneratedModifierHitTestingAndSubmitScope",
    "HanlinMiniAppsUITests/MiniAppsProductionRuntimeUITests/testStandaloneExpoGeneratedModifierNativeContainerContexts",
    "HanlinMiniAppsUITests/MiniAppsProductionRuntimeUITests/testStandaloneExpoHostServicesUseRealStorageRuntimeAndWidgetPublication",
    "HanlinMiniAppsUITests/MiniAppsProductionRuntimeUITests/testStandaloneExpoRendersNativeControlsAndRunsReactEvents",
    "HanlinMiniAppsTests/CrossAppInvocationTests/testUnavailableCallbackRetainsResultForSourceRecovery",
)


COMMAND_HEARTBEAT_SECONDS = 30


TEST_PLANS['miniapp_shortcut_long_running_os'] = ([
    "AI_HLYUITests/HanlinEntrypointSystemSurfaceUITests/testExpoSavedLongRunningBackgroundActionReturnsAfterThreeHundredSeconds",
    "AI_HLYUITests/HanlinEntrypointSystemSurfaceUITests/testNativeScriptSavedLongRunningBackgroundActionReturnsAfterThreeHundredSeconds",
    "AI_HLYUITests/HanlinEntrypointSystemSurfaceUITests/testExpoSavedLongRunningBackgroundActionCancelsAfterThreeHundredSeconds",
    "AI_HLYUITests/HanlinEntrypointSystemSurfaceUITests/testNativeScriptSavedLongRunningBackgroundActionCancelsAfterThreeHundredSeconds",
], 4)


def select_paired_runtime(runtimes, sdk, requested=None):
    identifier = requested or "com.apple.CoreSimulator.SimRuntime.iOS-" + sdk.replace(".", "-")
    if not identifier.startswith("com.apple.CoreSimulator.SimRuntime.iOS-"):
        raise RuntimeError("Paired acceptance requires an exact iOS simulator runtime identifier")
    matches = [runtime for runtime in runtimes
        if runtime.get("identifier") == identifier and runtime.get("isAvailable")
        and not runtime.get("isInternal")]
    if len(matches) != 1:
        raise RuntimeError("Requested paired iOS simulator runtime is unavailable or ambiguous: " + identifier)
    return matches[0]


def command(argv, name, timeout=60, allow_failure=False):
    if EXTRA26_ORIGINAL54_DEADLINE is not None:
        timeout = EXTRA26_ORIGINAL54_DEADLINE.limit(name, timeout)
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


def command_phase_status(record):
    if record.get("completion_recorded"):
        if record["status"] == "timed_out":
            return "TIMED_OUT"
        if record["status"] == "completed" and record.get("exit") is not None:
            return "EXECUTED_PASS" if record["exit"] == 0 else "EXECUTED_FAIL"
    return {"launch_failed": "LAUNCH_FAILED", "interrupted": "INTERRUPTED"}.get(record["status"], "INCOMPLETE")


def record_build_phases(state):
    """Use durable build observations; later diagnostic commands cannot replace them."""
    phases = {"mini-build.log": "mini_build", "ai-build.log": "ai_build"}
    state.update(mini_build="NOT_RUN", ai_build="NOT_RUN", build_commands={})
    journal = EVIDENCE / "command-events.jsonl"
    try:
        records = [json.loads(line) for line in journal.read_text().splitlines()] if journal.exists() else []
    except (OSError, ValueError) as error:
        state.update(build="INCOMPLETE", mini_build="UNKNOWN", ai_build="UNKNOWN", build_evidence_error=str(error))
        return
    for record in records:
        phase = phases.get(record.get("log"))
        if phase:
            state[phase] = command_phase_status(record)
            state["build_commands"][phase] = {key: record.get(key) for key in
                ("log", "command_id", "status", "completion_recorded", "exit", "observed_returncode")}
    values = [state[phase] for phase in phases.values()]
    if all(value == "EXECUTED_PASS" for value in values):
        state["build"] = "EXECUTED_PASS"
    else:
        state["build"] = next((value for value in reversed(values) if value not in {"NOT_RUN", "EXECUTED_PASS"}),
            "INCOMPLETE" if "EXECUTED_PASS" in values else "NOT_RUN")


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


def start_native_adapter_assets(state, extra_resources=None, request_log=None):
    """Own a real loopback image transport; never synthesize an adapter result."""
    image_path = ROOT / "Fixtures/ExpoSwiftUIProbe/native-adapter-assets/pixel.png"
    image = image_path.read_bytes()
    if not image.startswith(b"\x89PNG\r\n\x1a\n"):
        raise RuntimeError("The native adapter PNG fixture is missing or malformed")
    requests = []
    origin = "http://localhost:49173"
    resources = {"/health": (200, "text/plain", b"ready"),
                 "/pixel.png": (200, "image/png", image)}
    for path, row in (extra_resources or {}).items():
        if not re.fullmatch(r"/surfaces/[0-9a-f-]{36}/(expo|nativescript)", path) \
                or type(row) is not tuple or len(row) != 3 or row[:2] != (200, "text/html; charset=utf-8") \
                or type(row[2]) is not bytes or len(row[2]) > 65536:
            raise RuntimeError("Only bounded original Translation pages may extend the owned HTTP endpoint")
        resources[path] = row
    if request_log is not None:
        request_log = Path(request_log)
        if request_log.parent.resolve(strict=True) != EVIDENCE.resolve(strict=True):
            raise RuntimeError("The actual HTTP transport log must stay in owned evidence")
        with request_log.open("x"):
            pass

    class AssetHandler(BaseHTTPRequestHandler):
        def setup(self):
            super().setup()
            self.connection.settimeout(5)

        def do_GET(self):
            resource = urlsplit(self.path).path
            status, content_type, body = resources.get(
                resource, (404, "text/plain", b"Missing native adapter fixture"))
            self.send_response(status)
            self.send_header("Content-Type", content_type)
            self.send_header("Content-Length", str(len(body)))
            self.send_header("Cache-Control", "no-store")
            self.end_headers()
            self.wfile.write(body)
            observed = {"path": resource, "status": status, "bytes": len(body),
                        "sha256": hashlib.sha256(body).hexdigest(), "at": time.time()}
            if request_log is not None:
                observed.update(at=datetime.datetime.now(datetime.timezone.utc).isoformat(timespec="microseconds"),
                                method="GET", userAgent=self.headers.get("User-Agent", ""))
                with request_log.open("a") as stream:
                    stream.write(json.dumps(observed, ensure_ascii=False, sort_keys=True) + "\n")
                    stream.flush()
                    os.fsync(stream.fileno())
            requests.append(observed)

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
    if extra_resources:
        state["native_adapter_assets"]["system_surface_pages"] = {
            path: {"bytes": len(row[2]), "sha256": hashlib.sha256(row[2]).hexdigest()}
            for path, row in extra_resources.items()}
        state["native_adapter_assets"]["system_surface_transport_log"] = str(request_log)
        state["native_adapter_assets"]["scope"] += " Real Safari pages are input transport only."
    return server, thread




def widget_recovery_fixture(documents):
    """Stage only original authored package input; the UI performs installation."""
    name = "Hanlin-Expo-Widget-Interactive-Matrix.hanlinExpo"
    source = ROOT / "Fixtures/Widgets" / name
    rows = json.loads((ROOT / "Fixtures/Widgets/SHA256.json").read_text())
    matches = [row for row in rows if row.get("archive") == name]
    if len(matches) != 1:
        raise RuntimeError("The original Matrix archive has no unique producer manifest")
    actual = hashlib.sha256(source.read_bytes()).hexdigest()
    if actual != matches[0]["sha256"]:
        raise RuntimeError("Matrix input differs from the original producer manifest")
    for mirror in ("AI_HLYUITests/Fixtures", "AI_HLYTests/Fixtures/WidgetEngineFixtures.bundle"):
        if hashlib.sha256((ROOT / mirror / name).read_bytes()).hexdigest() != actual:
            raise RuntimeError("Original Matrix archive mirrors differ")
    destination = documents / name
    if destination.exists():
        raise RuntimeError("The fresh owned simulator already has a Matrix package input")
    shutil.copy2(source, destination)
    if hashlib.sha256(destination.read_bytes()).hexdigest() != actual:
        raise RuntimeError("The original Matrix source archive changed during staging")
    receipt = {"status": "STAGED_INPUT_ONLY", "archive": name, "archiveSHA256": actual,
               "sourceSHA256": matches[0]["sources"]["widget.jsx"],
               "scope": "Original package input only; no installed catalog, state, receipt or render is written"}
    (EVIDENCE / "widget-recovery-fixture.json").write_text(json.dumps(receipt, indent=2) + "\n")
    return receipt


def shortcut_surface_fixtures(documents):
    """Use the existing authored sources and the shipping SDK/original CLI."""
    work = EVIDENCE / "shortcut-surface-fixtures"
    work.mkdir()
    extracted = work / "original-shipping-sdk"
    extracted.mkdir()
    archive = ROOT / "AI_HLY/RuntimeHostResources.zip"
    archive_sha = hashlib.sha256(archive.read_bytes()).hexdigest()
    with zipfile.ZipFile(archive) as packed:
        members = [name for name in packed.namelist() if name.startswith("MiniAppSDK/")]
        if not members or any(".." in Path(name).parts for name in members):
            raise RuntimeError("The actual shipping archive has no valid authoring SDK")
        packed.extractall(extracted, members=members)
    sdk = extracted / "MiniAppSDK"
    inputs = {}
    for engine in ("expo", "nativescript"):
        project = ROOT / "Fixtures/HostActionSurfaces" / engine
        names = ["package.json", "script.json", "tsconfig.json", "hanlin.authoring.json",
                 "index.ts", "proof.ts"] + (["App.tsx", "widget.json"] if engine == "expo" else ["widget.jsx"])
        for name in names:
            source = project / name
            inputs[source.relative_to(ROOT).as_posix()] = hashlib.sha256(source.read_bytes()).hexdigest()
    rows = []
    try:
        for engine, name in (("expo", "SurfaceExpo.hanlinExpo"),
                             ("nativescript", "SurfaceNativeScript.hanlinNativeScript")):
            project = ROOT / "Fixtures/HostActionSurfaces" / engine
            validate_report = work / (engine + "-validate.json")
            build_report = work / (engine + "-build.json")
            prepared = work / name
            base = ["node", "Scripts/MiniApps/miniapp.mjs", "--sdk", str(sdk), "--project", str(project)]
            command(base[:2] + ["validate"] + base[2:] + ["--report", str(validate_report)],
                    engine + "-surface-validate.log", timeout=300)
            command(base[:2] + ["build"] + base[2:] +
                    ["--archive", str(prepared), "--report", str(build_report)],
                    engine + "-surface-build.log", timeout=600)
            for report in (validate_report, build_report):
                if json.loads(report.read_text()).get("succeeded") is not True:
                    raise RuntimeError("The original surface authoring operation did not succeed")
            destination = documents / name
            if destination.exists():
                raise RuntimeError("The owned simulator already has a surface fixture archive")
            shutil.copy2(prepared, destination)
            digest = hashlib.sha256(prepared.read_bytes()).hexdigest()
            if hashlib.sha256(destination.read_bytes()).hexdigest() != digest:
                raise RuntimeError("Original surface fixture bytes changed during staging")
            rows.append({"engine": engine, "archive": name, "archiveSHA256": digest,
                         "validateReportSHA256": hashlib.sha256(validate_report.read_bytes()).hexdigest(),
                         "buildReportSHA256": hashlib.sha256(build_report.read_bytes()).hexdigest()})
        if any(hashlib.sha256((ROOT / name).read_bytes()).hexdigest() != expected
               for name, expected in inputs.items()):
            raise RuntimeError("The original authoring operation changed a fixture input")
        receipt = {"status": "BUILT_AND_STAGED_INPUTS_ONLY", "shippingArchiveSHA256": archive_sha,
                   "sourceFiles": inputs, "archives": rows,
                   "scope": "Original authoring/import inputs; no system action or execution result is inferred"}
        (work / "provenance.json").write_text(json.dumps(receipt, indent=2) + "\n")
        return receipt
    finally:
        # Only this invocation's regenerable extraction is removed. Reports,
        # authored inputs and actual output archives remain.
        shutil.rmtree(extracted)



def long_running_shortcut_fixtures(documents):
    """Independent authored packages through the existing shipping SDK/CLI."""
    work = EVIDENCE / "shortcut-long-running-fixtures"
    work.mkdir()
    extracted = work / "original-shipping-sdk"
    extracted.mkdir()
    archive = ROOT / "AI_HLY/RuntimeHostResources.zip"
    archive_sha = hashlib.sha256(archive.read_bytes()).hexdigest()
    with zipfile.ZipFile(archive) as packed:
        members = [name for name in packed.namelist() if name.startswith("MiniAppSDK/")]
        if not members or any(".." in Path(name).parts for name in members):
            raise RuntimeError("The actual shipping archive has no valid authoring SDK")
        packed.extractall(extracted, members=members)
    sdk = extracted / "MiniAppSDK"
    from observe_shortcut_long_running import FIXTURE_FILES
    inputs = {"Fixtures/ShortcutLongRunning/" + engine + "/" + name:
              hashlib.sha256((ROOT / "Fixtures/ShortcutLongRunning" / engine / name).read_bytes()).hexdigest()
              for engine, names in FIXTURE_FILES.items() for name in names}
    rows = []
    try:
        for engine, name in (("expo", "LongRunningExpo.hanlinExpo"),
                             ("nativescript", "LongRunningNativeScript.hanlinNativeScript")):
            project = ROOT / "Fixtures/ShortcutLongRunning" / engine
            validate_report = work / (engine + "-validate.json")
            build_report = work / (engine + "-build.json")
            prepared = work / name
            base = ["node", "Scripts/MiniApps/miniapp.mjs", "--sdk", str(sdk), "--project", str(project)]
            command(base[:2] + ["validate"] + base[2:] + ["--report", str(validate_report)],
                    engine + "-long-running-validate.log", timeout=300)
            command(base[:2] + ["build"] + base[2:] +
                    ["--archive", str(prepared), "--report", str(build_report)],
                    engine + "-long-running-build.log", timeout=600)
            for report in (validate_report, build_report):
                if json.loads(report.read_text()).get("succeeded") is not True:
                    raise RuntimeError("The original long-running authoring operation did not succeed")
            destination = documents / name
            if destination.exists():
                raise RuntimeError("The owned simulator already has a long-running fixture archive")
            shutil.copy2(prepared, destination)
            digest = hashlib.sha256(prepared.read_bytes()).hexdigest()
            if hashlib.sha256(destination.read_bytes()).hexdigest() != digest:
                raise RuntimeError("Original fixture bytes changed during staging")
            rows.append({"engine": engine, "archive": name, "archiveSHA256": digest,
                         "validateReportSHA256": hashlib.sha256(validate_report.read_bytes()).hexdigest(),
                         "buildReportSHA256": hashlib.sha256(build_report.read_bytes()).hexdigest()})
        if any(hashlib.sha256((ROOT / name).read_bytes()).hexdigest() != expected for name, expected in inputs.items()):
            raise RuntimeError("The original authoring operation changed a fixture input")
        receipt = {"status": "BUILT_AND_STAGED_INPUTS_ONLY", "shippingArchiveSHA256": archive_sha,
                   "sourceFiles": inputs, "archives": rows,
                   "scope": "Independent original authoring inputs only; no system execution is inferred"}
        (work / "provenance.json").write_text(json.dumps(receipt, indent=2) + "\n")
        return receipt
    finally:
        shutil.rmtree(extracted)


def system_surface_inputs(surface_inputs):
    """Retain actual archive inputs and two real Safari pages for the original ten cases."""
    seed = str(uuid.uuid4())
    archives = {}
    expected = {"expo": "SurfaceExpo.hanlinExpo", "nativescript": "SurfaceNativeScript.hanlinNativeScript"}
    rows = surface_inputs.get("archives", [])
    if len(rows) != 2 or {row.get("engine") for row in rows} != set(expected):
        raise RuntimeError("Both original authored surface archives are required")
    for row in rows:
        engine = row["engine"]
        path = EVIDENCE / "shortcut-surface-fixtures" / expected[engine]
        if row.get("archive") != path.name or path.is_symlink() or not path.is_file():
            raise RuntimeError("The actual produced surface archive is missing")
        digest = hashlib.sha256(path.read_bytes()).hexdigest()
        if digest != row.get("archiveSHA256"):
            raise RuntimeError("The produced surface archive changed before OS admission")
        archives[engine] = {"path": str(path.resolve()), "sha256": digest}
    pages = EVIDENCE / "system-surface-pages"
    pages.mkdir()
    translations, resources = {}, {}
    for engine in expected:
        text = "Hanlin Translation input " + seed + " " + engine + " שלום עולם"
        route = "/surfaces/" + seed + "/" + engine
        body = ("<!doctype html><html><head><meta charset=\"utf-8\">"
                "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">"
                "<title>MiniApps Translation input</title></head><body>"
                "<p style=\"font-size:24px;margin:48px\" dir=\"auto\">" + html.escape(text) +
                "</p></body></html>\n").encode("utf-8")
        (pages / (engine + ".html")).write_bytes(body)
        translations[engine] = {"url": "http://localhost:49173" + route, "text": text,
                                "htmlSHA256": hashlib.sha256(body).hexdigest()}
        resources[route] = (200, "text/html; charset=utf-8", body)
    responses = EVIDENCE / "system-surface-share-inputs"
    responses.mkdir()
    # The observer exclusively creates its own request/evidence directory later.
    value = {"schema": 1, "seed": seed, "surfaceArchives": archives,
             "translation": translations,
             "transportLog": str((EVIDENCE / "system-surface-http-requests.jsonl").resolve()),
             "shareInputProducer": {"requestRoot": str((EVIDENCE / "shortcut-observer").resolve()),
                                    "responseRoot": str(responses.resolve())}}
    data = (json.dumps(value, ensure_ascii=False, sort_keys=True, indent=2) + "\n").encode("utf-8")
    path = EVIDENCE / "system-surface-inputs.json"
    with path.open("xb") as stream:
        stream.write(data)
    return {"path": str(path.resolve()), "sha256": hashlib.sha256(data).hexdigest(),
            "bytes": len(data), "value": value}, resources


def stage_system_surface_share_input(request_path, inputs, resolve_data, stopping=lambda: False):
    """Create only ordinary Files inputs after the actual UI-prepared challenge.

    This producer never writes the observer exchange or a production grant,
    command, receipt, catalog or private proof. Its response is input provenance.
    """
    from observe_shortcut_surfaces import (
        read_document, require, proof_documents, prepared_proof, _epoch_milliseconds)
    manifest_path = Path(inputs["path"])
    evidence = manifest_path.parent.resolve(strict=True)
    actual_manifest = read_document(manifest_path, evidence)
    require(actual_manifest["sha256"] == inputs["sha256"]
            and actual_manifest["value"] == inputs["value"], "The admitted input manifest changed")
    manifest = inputs["value"]
    require(type(manifest.get("schema")) is int and manifest["schema"] == 1,
            "Unknown original input manifest")
    producer = manifest["shareInputProducer"]
    request_root = evidence / "shortcut-observer"
    response_root = evidence / "system-surface-share-inputs"
    require(producer == {"requestRoot": str(request_root), "responseRoot": str(response_root)}
            and response_root.is_dir() and not response_root.is_symlink(),
            "Input producer paths must be the original owned evidence directories")
    request_path = Path(request_path)
    require(request_path.parent.parent == request_root
            and request_path.name == "share-input-request.json",
            "Only the original observer's per-run input request is accepted")
    document = read_document(request_path, evidence)
    require(document["bytes"] <= 65536, "The ordinary input request exceeds its bound")
    request = document["value"]
    fields = {"schema", "runID", "engine", "appID", "seed", "challenge",
              "preparedProofSHA256", "dataContainer", "startedAt"}
    require(isinstance(request, dict) and set(request) == fields
            and type(request.get("schema")) is int and request["schema"] == 1,
            "Unknown ordinary Share input request")
    run_id, engine, seed = request["runID"], request["engine"], request["seed"]
    require(isinstance(run_id, str) and str(uuid.UUID(run_id)) == run_id
            and request_path.parent.name == run_id
            and isinstance(seed, str) and str(uuid.UUID(seed)) == seed
            and seed == manifest["seed"], "The ordinary input request belongs to another run")
    require(engine in ("expo", "nativescript")
            and request["appID"] == "hanlin.surface." + engine,
            "The input request must name an original authored fixture")
    require(isinstance(request["challenge"], str) and len(request["challenge"]) <= 256
            and re.fullmatch(r"[a-z0-9]+-[a-z0-9]+-[a-z0-9]+", request["challenge"])
            and isinstance(request["preparedProofSHA256"], str)
            and re.fullmatch(r"[0-9a-f]{64}", request["preparedProofSHA256"]),
            "The input must bind a fresh observed preparation")
    _epoch_milliseconds(request["startedAt"])
    declared = Path(request["dataContainer"])
    require(declared.is_absolute() and not declared.is_symlink(), "Invalid actual product container")
    actual_data = Path(resolve_data())
    require(actual_data.is_absolute() and not actual_data.is_symlink()
            and actual_data.resolve(strict=True) == declared
            and declared.is_dir(), "The OS-provided MiniApps container changed")
    documents = declared / "Documents"
    require(documents.is_dir() and not documents.is_symlink(),
            "Use only the actual MiniApps Documents directory")
    prepared = prepared_proof(
        {"fixtureAppID": request["appID"], "challenge": request["challenge"], "baselineCounter": 0},
        proof_documents(declared, request["appID"]))
    require(prepared["sha256"] == request["preparedProofSHA256"],
            "The private UI preparation changed before ordinary input staging")
    require(not stopping(), "Input staging stopped before writing ordinary files")
    response_path = response_root / (run_id + ".json")
    require(not response_path.exists() and not response_path.is_symlink(),
            "This run already has an input producer response")
    folder_name = "HanlinSurfaceInputs-" + run_id
    folder = documents / folder_name
    folder.mkdir(exist_ok=False)
    shared = {"schema": 1, "kind": "hanlin.surface.share-input", "runID": run_id,
              "appID": request["appID"], "seed": seed, "challenge": request["challenge"]}
    contents = {
        "share-input.json": json.dumps(shared, ensure_ascii=False, sort_keys=True, indent=2) + "\n",
        "share-note.txt": "Hanlin Share input " + seed + " " + run_id + " " + engine +
                          " " + request["challenge"] + "\n",
    }
    files = []
    for name, text in contents.items():
        data = text.encode("utf-8")
        path = folder / name
        with path.open("xb") as stream:
            stream.write(data)
            stream.flush()
            os.fsync(stream.fileno())
        info = path.lstat()
        require(stat.S_ISREG(info.st_mode) and info.st_nlink == 1
                and path.read_bytes() == data, "The ordinary staged input bytes changed")
        files.append({"name": name, "bytes": len(data), "sha256": hashlib.sha256(data).hexdigest(),
                      "text": text})
    require(not stopping(), "Input staging stopped before provenance admission")
    current_data = Path(resolve_data())
    require(not current_data.is_symlink() and current_data.resolve(strict=True) == declared,
            "The actual product container changed during ordinary input staging")
    current = prepared_proof(
        {"fixtureAppID": request["appID"], "challenge": request["challenge"], "baselineCounter": 0},
        proof_documents(declared, request["appID"]))
    require(current["sha256"] == prepared["sha256"]
            and read_document(request_path, evidence)["sha256"] == document["sha256"],
            "The preparation/request changed during ordinary input staging")
    require(not stopping(), "Input staging stopped before retaining provenance")
    response = {**request, "status": "STAGED_INPUTS_ONLY",
                "producerRequestSHA256": document["sha256"],
                "shareInputFolder": folder_name, "shareInputFiles": files}
    with response_path.open("x") as stream:
        stream.write(json.dumps(response, ensure_ascii=False, sort_keys=True, indent=2) + "\n")
        stream.flush()
        os.fsync(stream.fileno())
    return response


def start_system_surface_input_producer(simulator, inputs, state):
    """Bounded original-runner input coordination; never an acceptance result."""
    stopped = threading.Event()
    report = {"status": "RUNNING_INPUT_PRODUCER", "runs": {}, "errors": [],
              "scope": "Only fresh normal Documents inputs and owned evidence; no OS result is inferred"}
    state["system_surface_share_inputs"] = report
    request_root = Path(inputs["value"]["shareInputProducer"]["requestRoot"])
    processed = set()

    def resolve_data():
        result = subprocess.run(["xcrun", "simctl", "get_app_container", simulator,
                                 "com.itorah.hanlinminiapps", "data"],
                                capture_output=True, text=True, timeout=20)
        if result.returncode != 0:
            raise RuntimeError("The actual OS did not resolve the current MiniApps data container")
        return Path(result.stdout.strip())

    def produce():
        try:
            while not stopped.wait(0.1):
                if not request_root.exists():
                    continue
                if request_root.is_symlink():
                    raise RuntimeError("The original observer request directory changed")
                for path in sorted(request_root.glob("*/share-input-request.json")):
                    if stopped.is_set():
                        return
                    if path in processed:
                        continue
                    processed.add(path)
                    if len(processed) > 2:
                        raise RuntimeError("The original plan permits exactly two Share input runs")
                    response = stage_system_surface_share_input(path, inputs, resolve_data, stopped.is_set)
                    if any(item["engine"] == response["engine"] for item in report["runs"].values()):
                        raise RuntimeError("The original plan cannot stage a duplicate Share engine")
                    report["runs"][response["runID"]] = response
        except Exception as error:
            report["errors"].append(type(error).__name__ + ": " + str(error))
        finally:
            report["status"] = "INPUT_PRODUCER_FAILED" if report["errors"] else "INPUT_PRODUCER_STOPPED"

    thread = threading.Thread(target=produce, name="original-share-input-producer", daemon=True)
    thread.start()
    return stopped, thread


def finish_system_surface_input_producer(producer, state):
    stopped, thread = producer
    stopped.set()
    thread.join(timeout=25)
    report = state["system_surface_share_inputs"]
    if thread.is_alive():
        report["errors"].append("The bounded input producer did not stop")
        report["status"] = "INPUT_PRODUCER_FAILED"
    report["allSelectedInputsStaged"] = (
        not report["errors"] and not thread.is_alive() and len(report["runs"]) == 2
        and {row["engine"] for row in report["runs"].values()} == {"expo", "nativescript"}
        and all(row["status"] == "STAGED_INPUTS_ONLY" for row in report["runs"].values()))
    return report["allSelectedInputsStaged"]


def start_shortcut_observer(derived, simulator, state):
    candidates = []
    for runner in (derived / "Build/Products/Debug-iphonesimulator").glob("*-Runner.app"):
        if not (runner / "Info.plist").is_file():
            continue
        for test in (runner / "PlugIns").glob("*.xctest"):
            if (test / "Info.plist").is_file():
                info = plistlib.loads((test / "Info.plist").read_bytes())
                if info.get("CFBundleExecutable") == "AI_HLYUITests":
                    candidates.append((runner, test))
    if len(candidates) != 1:
        raise RuntimeError("The actual AI_HLYUITests runner bundle is absent or ambiguous")
    runner, test = candidates[0]
    info_bytes = (runner / "Info.plist").read_bytes()
    info = plistlib.loads(info_bytes)
    bundle = info.get("CFBundleIdentifier", "")
    if not bundle.endswith(".xctrunner"):
        raise RuntimeError("The actual XCTest runner bundle has an invalid identity")
    long_running = TEST_SCOPE == "miniapp_shortcut_long_running_os"
    concurrency = TEST_SCOPE == "miniapp_shortcut_concurrency_os"
    observer_script = "observe_shortcut_long_running.py" if long_running else ("observe_shortcut_concurrency.py" if concurrency else "observe_shortcut_surfaces.py")
    observer_name = "shortcut-long-running-observer" if long_running else ("shortcut-concurrency-observer" if concurrency else "shortcut-observer")
    observer_output = EVIDENCE / observer_name
    argv = [sys.executable, "Scripts/ProductSplit/" + observer_script,
            "--device", simulator, "--runner-bundle-id", bundle,
            "--output", str(observer_output), "--duration",
            "7200" if TEST_SCOPE in {"miniapp_studio_gallery_os", "miniapp_studio_editor_os"} else
            "5400" if TEST_SCOPE == "miniapp_system_surfaces_os" else "2100"]
    if long_running:
        from observe_shortcut_long_running import create_inputs
        state["long_running_inputs"] = create_inputs(ROOT, EVIDENCE, runner, test, state, simulator)
        argv += ["--inputs", state["long_running_inputs"]["path"]]
    if TEST_SCOPE == "miniapp_system_surfaces_os":
        argv += ["--system-inputs", state["system_surface_inputs"]["path"]]
    if TEST_SCOPE == "miniapp_studio_editor_os":
        argv += ["--studio-inputs", state["studio_inputs_manifest"]["path"]]
    if TEST_SCOPE in {"miniapp_widget_recovery_os", "miniapp_widget_state_os", "miniapp_widget_voiceover_os", "miniapp_widget_families_os"}:
        argv += ["--widget-fixture", str(ROOT / "Fixtures/Widgets/Hanlin-Expo-Widget-Interactive-Matrix.hanlinExpo")]
    if TEST_SCOPE == "miniapp_widget_state_os":
        from observe_widget_state import create_inputs
        state["widget_state_inputs"] = create_inputs(ROOT, derived, EVIDENCE, runner, test, state, simulator)
        argv += ["--widget-state-inputs", state["widget_state_inputs"]["path"]]
    if TEST_SCOPE == "miniapp_widget_voiceover_os":
        from observe_widget_voiceover import create_inputs
        state["widget_voiceover_inputs"] = create_inputs(ROOT, derived, EVIDENCE, runner, test, state, simulator)
        argv += ["--widget-voiceover-inputs", state["widget_voiceover_inputs"]["path"]]
    if TEST_SCOPE == "miniapp_widget_families_os":
        from observe_widget_families import create_inputs
        state["widget_families_inputs"] = create_inputs(ROOT, derived, EVIDENCE, runner, test, state, simulator)
        argv += ["--widget-families-inputs", state["widget_families_inputs"]["path"]]
    output = (EVIDENCE / (observer_name + ".log")).open("w")
    process = subprocess.Popen(argv, cwd=ROOT, stdout=output, stderr=subprocess.STDOUT)
    state["shortcut_observer"] = {"argv": argv, "runnerBundleIdentifier": bundle,
        "outputDirectory": str(observer_output),
        "runnerInfoSHA256": hashlib.sha256(info_bytes).hexdigest(),
        "testBundle": str(test), "scope": "Read-only original XCTest exchange; no production state writes"}
    return process, output


def finish_shortcut_observer(observer, state):
    process, output = observer
    try:
        if process.poll() is None:
            process.terminate()
        code = process.wait(timeout=30)
    except subprocess.TimeoutExpired:
        process.kill()
        code = process.wait(timeout=10)
    finally:
        output.close()
    state["shortcut_observer"]["exitCode"] = code
    report = Path(state["shortcut_observer"]["outputDirectory"]) / "observer.json"
    if report.is_file():
        state["shortcut_observer"]["report"] = json.loads(report.read_text())
    return code


def main():
    global EXTRA26_ORIGINAL54_DEADLINE
    EVIDENCE.mkdir(parents=True, exist_ok=False)
    state = {"status": "INFRA_ERROR", "ui": "NOT_RUN", "build": "NOT_RUN",
        "mini_build": "NOT_RUN", "ai_build": "NOT_RUN",
        "physical_device": "NOT_RUN", "provisioned_distribution": "NOT_RUN",
        "scope": "Two shipping targets, actual App Group, original Host request/return/cancel, original ScriptUI import and private-data transfer/rollback",
        "model_boundary": "Existing opt-in simulator HTTP acceptance provider; all Host, permission, OS transitions, storage and result handling are real.",
        "started_at": time.time()}
    simulator = None
    adapter_assets = None
    shortcut_observer = None
    system_input_producer = None
    studio_input_producer = None
    system_resources = None
    extra26_inputs = None
    extra26_products = None
    try:
        if RUN_EXTRA26:
            from paired_extra26 import Original54Deadline
            EXTRA26_ORIGINAL54_DEADLINE = Original54Deadline(EVIDENCE)
        if TEST_SCOPE not in TEST_PLANS:
            raise RuntimeError("Unknown original-product acceptance scope")
        selectors, expected_tests = TEST_PLANS[TEST_SCOPE]
        state["test_scope"] = TEST_SCOPE
        state["selected_tests"] = selectors
        if RUN_EXTRA26:
            state["requested_test_scope"] = REQUESTED_TEST_SCOPE
            state["continuation_scope"] = "Original paired54, then the unchanged original extra26 on these same products"
        if TEST_SCOPE == "miniapp_shortcut_long_running_os":
            state["long_running_scope"] = {"cases": 4, "profile": "paced-35-v1",
                "scope": "Real saved background return/cancel after >300s on both engines; paced finite work, Simulator only"}
        if TEST_SCOPE == "miniapp_shortcuts_os":
            state["scope"] = "Four additional real Shortcuts cases: current installed action, saved background/foreground preference, typed JSON and built-in result chain"
            state["model_boundary"] = "No model response fixture; original authoring SDK, importer, system UI, invocation executor and private/durable results"
            state["acceptance_boundary"] = "Simulator Shortcuts only; native snippets, cancellation, Home Screen, Hebrew UI and locked physical-device acceptance remain separate"
        if TEST_SCOPE == "miniapp_widget_recovery_os":
            state["scope"] = "Standalone MiniApps real WidgetKit medium-family last-good failure and authored recovery"
            state["model_boundary"] = "Original Matrix producer archive, shipping importer, real SpringBoard actions, actual read-only state/cache and filtered system-log observations"
            state["acceptance_boundary"] = "One medium-family Simulator case; the other seven OS families, appearance/orientation, physical devices and network/corrupt-resource cases remain separate"
        if TEST_SCOPE == "miniapp_widget_state_os":
            state["scope"] = "Two independently named standalone medium widgets; six genuine sequential Toggle/Add/Refresh actions with host termination observed"
            state["model_boundary"] = "Original Matrix archive, importer, WidgetKit gallery/configuration, real native controls and read-only current state/cache/nonces; no production-state writes"
            state["acceptance_boundary"] = "One iPad Simulator case only; no concurrent/replayed delivery, cold start, disabled controls, VoiceOver, other families/appearance or physical-device claim"
        if TEST_SCOPE == "miniapp_widget_voiceover_os":
            state["scope"] = "One standalone medium widget through actual English public VoiceOver off/on/off and two native Toggle actions; one untouched native B variant"
            state["model_boundary"] = "Original Matrix/importer, real gallery/configuration, public speech and doubleTap, current native state/cache/nonces and prior VoiceOver restoration"
            state["acceptance_boundary"] = "One iPad Simulator pilot only; no second physical placement, private focus API, concurrent delivery, cold start, disabled controls, other languages/families or physical-device claim"
        if TEST_SCOPE == "miniapp_widget_families_os":
            state["scope"] = "Four actual named iPad Home Screen Small/Medium/Large/Extra Large placements with fresh native family renders and portrait/landscape/portrait observations"
            state["model_boundary"] = "Unchanged original Matrix, real gallery labels and saved instance readback, native cache identity, actual AX/PNG geometry, owned-widget removal and prior orientation restoration"
            state["acceptance_boundary"] = "Only actually offered Home Screen families; no Today View portrait, Lock Screen accessory, VoiceOver, appearance/RTL or physical-device claim"
        if TEST_SCOPE == "miniapp_shortcut_concurrency_os":
            state["scope"] = "Two additional genuine Shortcuts cases: one live NativeScript owner plus three background NS actions, actual handler/lease overlap and separate windows, reverse completion or selected system Stop, followed by the original owner callback"
            state["model_boundary"] = "Original authoring/importer, actual OS URLs/Stop UI, real native commands and per-window journals; no production queue, receipt or state seeding"
            state["acceptance_boundary"] = "NS-owner/NS-background iPad Simulator pilot only; Expo combinations, iPhone, multi-scene restoration, duplicate URLs, cold/warm/foreground matrix, actual timeout and physical-device acceptance remain separate"
        if TEST_SCOPE == "miniapp_system_surfaces_os":
            state["scope"] = "The original ten system-surface UI methods: both engines through genuine WidgetKit, ActivityKit, legacy Shortcuts, Files Share and system Translation"
            state["model_boundary"] = "Original authored SDK archives, actual saved inputs/Safari pages and real OS UI; observers read canonical identity, private runtime output and durable native receipts"
            state["acceptance_boundary"] = "Original iPad Simulator pilot only; all supported Widget families/appearance, seven ActivityKit regions, physical devices and account-backed surfaces remain separate"
        if TEST_SCOPE == "miniapp_studio_gallery_os":
            state["scope"] = "Five actual shipping Gallery examples: two independent copies, real editor changes, original validation/build/install and unchanged runtime callbacks"
            state["model_boundary"] = "No model or external producer; the UI alone creates/edits project source, while the original observer reads bundled SDK, copies, compiled archive and current installed source"
            state["acceptance_boundary"] = "Local iPad Simulator gallery path only; iCloud/account, physical device, broader editor/folder/conflict UX and native image pixel review remain separate"
        if TEST_SCOPE == "miniapp_studio_editor_os":
            state["scope"] = "Five actual local Studio editor cases: both engines' files/folders/style, original TypeScript help/preferences/log export, Files source import and two real iPad windows' conflict/recovery"
            state["model_boundary"] = "Only a fresh ordinary Documents import input is copied from the actual bundled SDK; shipping UI alone writes Studio files, recovery journals, settings and exported logs"
            state["acceptance_boundary"] = "Local iPad Simulator editor path only; signed-account iCloud/offline/sync/remote-conflict and physical-device acceptance remain separate"
        if TEST_SCOPE in {"miniapp_authoring", "miniapp_complete"}:
            state["scope"] = "Original SDK/tools, source diagnostics, native repair sheet, durable AI handoff, actual build/install and NativeScript/Expo runtime controls in both shipping products"
            state["model_boundary"] = "Only the HTTP model response sequence and the native adapter image fixture resources are deterministic. All source edits, TypeScript diagnostics, Metro/ESM production, imports, receipts, native rendering and UI events are original production code."
        if TEST_SCOPE == "miniapp_sdk04":
            state["scope"] = "Focused current Expo runtime metadata, generated view/modifier behavior, real files/runtime and installed action-to-widget publication across both shipping products"
            state["model_boundary"] = "Actual original SDK-built Expo probe, installed platform/store/session and original UI controls. No model responses or synthetic widget publication results."
            state["acceptance_boundary"] = "Eight selected MiniApps UI cases, one MiniApps callback-result case and two AI hosted native cases; no all83 modifier semantics, document launch scene, WidgetKit OS rendering, physical device or previously selected42-case inference."
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
        requested_runtime = os.environ.get("PAIRED_SIM_RUNTIME")
        runtime = select_paired_runtime(json.loads(raw)["runtimes"], sdk, requested_runtime)
        state["simulator_runtime_selection"] = {
            "build_sdk_version": sdk,
            "requested_runtime": requested_runtime,
            "selected_runtime": runtime["identifier"],
            "runtime_version": runtime.get("version"),
        }
        _, raw = command(["xcrun", "simctl", "list", "devicetypes", "-j"], "device-types.json")
        supported = {item["identifier"] for item in runtime["supportedDeviceTypes"]}
        device_family = "iPad" if TEST_SCOPE in {"miniapp_authoring", "miniapp_sdk04", "miniapp_complete", "miniapp_shortcuts_os", "miniapp_shortcut_concurrency_os", "miniapp_shortcut_long_running_os", "miniapp_widget_recovery_os", "miniapp_widget_state_os", "miniapp_widget_voiceover_os", "miniapp_widget_families_os", "miniapp_system_surfaces_os", "miniapp_studio_gallery_os", "miniapp_studio_editor_os"} else "iPhone"
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
        if RUN_EXTRA26:
            from paired_extra26 import capture_inputs
            extra26_inputs = capture_inputs(ROOT, EVIDENCE, state, command)
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
        # Preserve XCTest results/attachments without a second, 600-second
        # simulator sysdiagnose after a failure. Targeted capture remains below.
        test_base = base + ["-collect-test-diagnostics", "never"]
        state["status"] = "BUILD_FAILED"
        # The observed cold first-product build was still compiling after 40 min.
        # Allow 60 min for that build; first-launch, routing and UI deadlines stay unchanged.
        mini_action = "build-for-testing" if TEST_SCOPE in {"miniapp_authoring", "miniapp_sdk04", "miniapp_complete"} else "build"
        command(base + ["-scheme", "HanlinMiniApps", mini_action,
            "-resultBundlePath", str(EVIDENCE / "MiniBuild.xcresult")], "mini-build.log", timeout=3600)
        state["app_intents_metadata"]["com.itorah.hanlinminiapps"] = capture_app_intents_metadata(products["com.itorah.hanlinminiapps"])
        # The original full-app workflow uses this exact pinned upstream generator:
        # Xcode 27.2 advertises its outputs but can omit the generator build commands.
        # The helper verifies every input against the resolved commit before running it.
        command([sys.executable, "Scripts/CI/stage_a2ui_schemas.py",
            "--source-packages-path", str(ROOT / "build/SourcePackages"),
            "--derived-data-path", str(derived),
            "--evidence", str(EVIDENCE / "original-a2ui-schemas")],
            "original-a2ui-generator.log", timeout=360)
        command(base + ["-scheme", "AI_HLY", "build-for-testing",
            "-resultBundlePath", str(EVIDENCE / "AIBuild.xcresult")], "ai-build.log", timeout=1800)
        state["app_intents_metadata"]["com.itorah.chavrusachat"] = capture_app_intents_metadata(products["com.itorah.chavrusachat"])
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
            _, resource_result = command([sys.executable,
                "Scripts/Runtime/validate_ios_system_resources.py",
                "--repository-root", str(ROOT), "--app", str(product)],
                bundle + "-ios-system-resources.json")
            state["product_identity"][bundle]["ios_system_resources"] = json.loads(resource_result)
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
        if RUN_EXTRA26:
            from paired_extra26 import capture_products
            extra26_products = capture_products(derived, EVIDENCE, state)
        if TEST_SCOPE in {"miniapp_widget_recovery_os", "miniapp_widget_state_os", "miniapp_widget_voiceover_os", "miniapp_widget_families_os"}:
            _, raw = command(["xcrun", "simctl", "get_app_container", simulator,
                "com.itorah.hanlinminiapps", "data"], "widget-recovery-mini-data-container.txt")
            documents = Path(raw.strip()) / "Documents"
            documents.mkdir(exist_ok=True)
            state["widget_recovery_input"] = widget_recovery_fixture(documents)
        if TEST_SCOPE == "miniapp_shortcut_long_running_os":
            _, raw = command(["xcrun", "simctl", "get_app_container", simulator,
                "com.itorah.hanlinminiapps", "data"], "long-running-mini-data-container.txt")
            documents = Path(raw.strip()) / "Documents"
            documents.mkdir(exist_ok=True)
            state["long_running_fixtures"] = long_running_shortcut_fixtures(documents)
        if TEST_SCOPE in {"miniapp_shortcuts_os", "miniapp_shortcut_concurrency_os", "miniapp_system_surfaces_os"}:
            _, raw = command(["xcrun", "simctl", "get_app_container", simulator,
                "com.itorah.hanlinminiapps", "data"], "shortcuts-mini-data-container.txt")
            documents = Path(raw.strip()) / "Documents"
            documents.mkdir(exist_ok=True)
            state["shortcut_surface_inputs"] = shortcut_surface_fixtures(documents)
            if TEST_SCOPE == "miniapp_system_surfaces_os":
                inputs, system_resources = system_surface_inputs(state["shortcut_surface_inputs"])
                state["system_surface_inputs"] = inputs
        if TEST_SCOPE in {"miniapp_authoring", "miniapp_complete"}:
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
            if TEST_SCOPE == "miniapp_complete":
                runtime_selectors += [selector for selector in SDK04_MINIAPPS_SELECTORS if selector not in runtime_selectors]
            adapter_assets = start_native_adapter_assets(state)
            state["original_runtime_selectors"] = runtime_selectors
            runtime_result = EVIDENCE / "OriginalRuntimes.xcresult"
            argv = test_base + ["-scheme", "HanlinMiniApps", "test-without-building",
                "-resultBundlePath", str(runtime_result)]
            argv += ["-only-testing:" + selector for selector in runtime_selectors]
            code, _ = command(argv, "original-runtimes.log", timeout=2400 if TEST_SCOPE == "miniapp_complete" else 1200, allow_failure=True)
            state["original_runtime_summary"] = verify_native_result(runtime_result, "original-runtimes",
                runtime_selectors, 17 if TEST_SCOPE == "miniapp_authoring" else 25, code)
            observed_images = {(request["path"], request["status"])
                for request in state["native_adapter_assets"]["requests"]}
            if not {("/pixel.png", 200), ("/missing.png", 404)}.issubset(observed_images):
                raise RuntimeError("Native adapter UI passed without the required real image HTTP requests")
            state["native_adapter_assets"]["native_request_proof"] = "EXECUTED_PASS_RESOURCE_TRANSPORT"
            _, raw = command(modal_fixture["verify_command"], "external-modal-result.json")
            state["external_modal_result"] = json.loads(raw)
        if TEST_SCOPE == "miniapp_sdk04":
            _, raw = command(["xcrun", "simctl", "get_app_container", simulator,
                "com.itorah.hanlinminiapps", "data"], "sdk04-mini-data-container.txt")
            documents = Path(raw.strip()) / "Documents"
            documents.mkdir(exist_ok=True)
            source = ROOT / "AI_HLYUITests/Fixtures/ExpoSwiftUIProbeA.hanlinExpo"
            destination = documents / source.name
            if destination.exists():
                raise RuntimeError("Owned fresh simulator has an unexpected SDK04 runtime input")
            shutil.copy2(source, destination)
            digest = hashlib.sha256(source.read_bytes()).hexdigest()
            if hashlib.sha256(destination.read_bytes()).hexdigest() != digest:
                raise RuntimeError("SDK04 runtime fixture bytes changed")
            state["runtime_inputs"] = [{"source": os.path.relpath(source, ROOT), "sha256": digest}]
            runtime_selectors = list(SDK04_MINIAPPS_SELECTORS)
            state["original_runtime_selectors"] = runtime_selectors
            runtime_result = EVIDENCE / "OriginalRuntimes.xcresult"
            argv = test_base + ["-scheme", "HanlinMiniApps", "test-without-building",
                "-resultBundlePath", str(runtime_result)]
            argv += ["-only-testing:" + selector for selector in runtime_selectors]
            code, _ = command(argv, "original-runtimes.log", timeout=1200, allow_failure=True)
            state["original_runtime_summary"] = verify_native_result(runtime_result, "original-runtimes",
                runtime_selectors, 9, code)
        if TEST_SCOPE in {"cross_product", "product_and_share"}:
            archive = fixture_archive(state["sha"])
            _, raw = command(["xcrun", "simctl", "get_app_container", simulator,
                "com.itorah.chavrusachat", "data"], "ai-data-container.txt")
            documents = Path(raw.strip()) / "Documents"
            documents.mkdir(exist_ok=True)
            if (documents / archive.name).exists():
                raise RuntimeError("The fresh owned simulator already has a transfer package input")
            shutil.copy2(archive, documents / archive.name)
        if TEST_SCOPE in {"miniapp_shortcuts_os", "miniapp_shortcut_concurrency_os", "miniapp_shortcut_long_running_os", "miniapp_widget_recovery_os", "miniapp_widget_state_os", "miniapp_widget_voiceover_os", "miniapp_widget_families_os", "miniapp_system_surfaces_os", "miniapp_studio_gallery_os", "miniapp_studio_editor_os"}:
            if TEST_SCOPE == "miniapp_system_surfaces_os":
                adapter_assets = start_native_adapter_assets(
                    state, system_resources, state["system_surface_inputs"]["value"]["transportLog"])
                system_input_producer = start_system_surface_input_producer(
                    simulator, state["system_surface_inputs"], state)
            if TEST_SCOPE == "miniapp_studio_editor_os":
                from studio_source_input import create_manifest, start
                state["studio_inputs_manifest"] = create_manifest(EVIDENCE)
                studio_input_producer = start(simulator, state["studio_inputs_manifest"], state)
            shortcut_observer = start_shortcut_observer(derived, simulator, state)
        result = EVIDENCE / "Paired.xcresult"
        argv = test_base + ["-scheme", "AI_HLY", "test-without-building",
            "-resultBundlePath", str(result),
            "-test-timeouts-enabled", "YES", "-maximum-test-execution-time-allowance",
            "1200" if TEST_SCOPE in {"miniapp_studio_gallery_os", "miniapp_studio_editor_os"} else "600"]
        argv += ["-only-testing:" + selector for selector in selectors]
        code, _ = command(argv, "paired-tests.log",
                          timeout=7200 if TEST_SCOPE in {"miniapp_studio_gallery_os", "miniapp_studio_editor_os"} else
                          5400 if TEST_SCOPE == "miniapp_system_surfaces_os" else 2100,
                          allow_failure=True)
        if system_input_producer:
            finish_system_surface_input_producer(system_input_producer, state)
            system_input_producer = None
        if studio_input_producer:
            from studio_source_input import finish
            finish(studio_input_producer, state)
            studio_input_producer = None
        if shortcut_observer:
            observer_code = finish_shortcut_observer(shortcut_observer, state)
            shortcut_observer = None
            report = state["shortcut_observer"].get("report", {})
            runs = report.get("runs", {})
            state["shortcut_observer"]["allSelectedCasesObserved"] = (
                observer_code == 0 and len(runs) == expected_tests and all(
                    row.get("completionWritten") is True for row in runs.values()))
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
        if TEST_SCOPE in {"miniapp_shortcuts_os", "miniapp_shortcut_concurrency_os", "miniapp_shortcut_long_running_os", "miniapp_widget_recovery_os", "miniapp_widget_state_os", "miniapp_widget_voiceover_os", "miniapp_widget_families_os", "miniapp_system_surfaces_os", "miniapp_studio_gallery_os", "miniapp_studio_editor_os"} and not state["shortcut_observer"].get("allSelectedCasesObserved"):
            state["status"] = "INFRA_ERROR"
            raise RuntimeError("The real system-surface observer did not retain every correlated terminal result")
        if TEST_SCOPE == "miniapp_system_surfaces_os" and not state["system_surface_share_inputs"].get("allSelectedInputsStaged"):
            state["status"] = "INFRA_ERROR"
            raise RuntimeError("The original Share cases did not receive both actual challenge-bound input sets")
        if TEST_SCOPE == "miniapp_studio_editor_os" and not state["studio_source_inputs"].get("allSelectedInputsStaged"):
            state["status"] = "INFRA_ERROR"
            raise RuntimeError("The actual Files import case did not receive its independently bound ordinary source input")
        if state["status"] != "EXECUTED_PASS":
            raise RuntimeError("Original native acceptance did not pass every case in the recorded scope")
        if RUN_EXTRA26:
            from paired_extra26 import continue_after_paired
            state["status"] = "EXTRA26_NOT_RUN"
            state["original54_job_budget"] = EXTRA26_ORIGINAL54_DEADLINE.complete()
            EXTRA26_ORIGINAL54_DEADLINE = None
            original54 = json.loads(json.dumps(state))
            original54["status"] = "EXECUTED_PASS"
            state["original54_status"] = "EXECUTED_PASS"
            state["extra26"] = continue_after_paired(
                ROOT, EVIDENCE, derived, original54, extra26_inputs, extra26_products, command)
            state["status"] = "EXECUTED_PASS"
    except Exception as error:
        EXTRA26_ORIGINAL54_DEADLINE = None  # Failure-only diagnostics cannot launch continuation.
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
                (["xcrun", "simctl", "spawn", simulator, "log", "show",
                  "--last", "15m", "--style", "compact", "--info", "--predicate",
                  'process == "HanlinMiniApps" AND (category == "MiniAppsCatalog" OR eventMessage BEGINSWITH "miniapps.catalog.restore ")'],
                 "failure-catalog-startup.log"),
            ]
            state["diagnostic_errors"] = []
            for argv, name in diagnostics:
                try:
                    command(argv, name, timeout=30)
                except Exception as capture:
                    state["diagnostic_errors"].append(str(capture))
    finally:
        if system_input_producer:
            finish_system_surface_input_producer(system_input_producer, state)
        if studio_input_producer:
            from studio_source_input import finish
            finish(studio_input_producer, state)
        if shortcut_observer:
            finish_shortcut_observer(shortcut_observer, state)
        if adapter_assets:
            server, thread = adapter_assets
            server.shutdown()
            server.server_close()
            thread.join(timeout=5)
        # Retain the actual test attachments for visual inspection of the sheet
        # and repaired app; a final simulator screenshot is not a substitute.
        if TEST_SCOPE in {"miniapp_authoring", "miniapp_sdk04", "miniapp_complete", "miniapp_shortcuts_os", "miniapp_shortcut_concurrency_os", "miniapp_shortcut_long_running_os", "miniapp_widget_recovery_os", "miniapp_widget_state_os", "miniapp_widget_voiceover_os", "miniapp_widget_families_os", "miniapp_system_surfaces_os", "miniapp_studio_gallery_os", "miniapp_studio_editor_os"}:
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
        record_build_phases(state)
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
