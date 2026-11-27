"""Read-only evidence for four real saved, paced Shortcuts exceeding 300 seconds.

The authored workload performs 35 real runtime calls separated by 34 ten-second
pacing intervals. This is outstanding OS-intent time, not 340 seconds of CPU or
network work. XCTest alone operates the actual saved Shortcut and Stop control.
Only this observer's evidence and the XCTest-owned exchange are written here.
"""
from pathlib import Path
import argparse
import datetime
import hashlib
import json
import math
import os
import plistlib
import re
import signal
import subprocess
import time
import uuid

import observe_shortcut_surfaces as shared
import observe_shortcut_concurrency as concurrency
import observe_share_translation_surfaces as archive_binding
from observe_runtime_image_origin import parse_process

require = shared.require
equal = shared.equal_typed_json
ROUTE = "miniAppShortcutLongRunning"
EXCHANGE = "HanlinShortcutLongRunningObservation"
PROFILE = "paced-35-v1"
KINDS = ("node", "typeScript", "localPython", "javaScriptCore", "shell")
ROOT_KEYS = concurrency.ROOT_KEYS
MINIMUM_SECONDS = 300
MAX_OBSERVATION_GAP = 10
POST_STOP_SECONDS = 30
POST_START_CANCEL_SECONDS = 360
RESPONSES = ("identity.json", "running.json", "long-running.json", "terminal.json", "completion.json", "failure.json")
CONTRACT_KEYS = ("schema", "runID", "engine", "surface", "scenario", "fixtureAppID", "fixtureTitle",
                 "startedAt", "challenge", "baselineCounter", "ownerProcessID", "ownerAccessibilityHeader",
                 "ownerWindowID", "token", "savedShortcutName", "configuredInput")
FIXTURE_FILES = {
    "expo": ("package.json", "script.json", "tsconfig.json", "hanlin.authoring.json", "index.ts", "proof.ts", "App.tsx"),
    "nativescript": ("package.json", "script.json", "tsconfig.json", "hanlin.authoring.json", "index.ts", "proof.ts")}
SOURCE_FILES = tuple("Fixtures/ShortcutLongRunning/" + engine + "/" + name
                     for engine, names in FIXTURE_FILES.items() for name in names) + (
    "AI_HLYUITests/HanlinEntrypointSystemSurfaceUITests.swift",
    "Scripts/ProductSplit/run_paired_acceptance.py",
    "Scripts/ProductSplit/observe_shortcut_long_running.py",
    "Scripts/ProductSplit/observe_shortcut_surfaces.py",
    "Scripts/ProductSplit/observe_shortcut_concurrency.py",
    "Scripts/ProductSplit/observe_share_translation_surfaces.py",
    "Scripts/ProductSplit/observe_runtime_image_origin.py",
    "Scripts/CI/Tests/test_shortcut_long_running_observer.py")


def finite(value):
    return type(value) in (int, float) and math.isfinite(value)


def canonical_uuid(value):
    require(concurrency.valid_uuid(value), "Expected a canonical lowercase UUID")
    return value


def app_id(engine):
    return "hanlin.longrunning." + engine


def title(engine):
    return "Long Running Expo" if engine == "expo" else "Long Running NativeScript"


def file_record(path):
    path = Path(path)
    require(path.is_file() and not path.is_symlink(), "A declared original input or product is absent")
    raw = path.read_bytes()
    return {"bytes": len(raw), "sha256": shared.digest(raw)}


def product_records(app):
    app = Path(app)
    info = plistlib.loads((app / "Info.plist").read_bytes())
    executable = info["CFBundleExecutable"]
    require(type(executable) is str and "/" not in executable, "Invalid actual executable name")
    names = ["Info.plist", executable]
    names += sorted(path.name for path in app.glob("*.debug.dylib"))
    return {name: file_record(app / name) for name in names}


def create_inputs(root, evidence, runner, test, state, simulator):
    """Original runner input binding, after the existing producer and app builds."""
    root, evidence, runner, test = (Path(value).resolve(strict=True) for value in (root, evidence, runner, test))
    built = state["long_running_fixtures"]
    require(built.get("status") == "BUILT_AND_STAGED_INPUTS_ONLY", "The original fixture producer did not succeed")
    archives = {}
    for row in built["archives"]:
        engine = row["engine"]
        name = "LongRunningExpo.hanlinExpo" if engine == "expo" else "LongRunningNativeScript.hanlinNativeScript"
        path = evidence / "shortcut-long-running-fixtures" / name
        require(engine in FIXTURE_FILES and row["archive"] == name and file_record(path)["sha256"] == row["archiveSHA256"],
                "The original producer archive changed")
        archives[engine] = {"path": str(path), "sha256": row["archiveSHA256"]}
    require(set(archives) == set(FIXTURE_FILES), "Both independent long-running archives are required")
    app = runner.parent / "HanlinMiniApps.app"
    require(app.is_dir(), "The original MiniApps product is missing")
    value = {"schema": 1, "scope": "miniapp_shortcut_long_running_os", "device": simulator,
             "sourceSHA": state["sha"], "root": str(root), "surfaceArchives": archives,
             "sourceFiles": {name: file_record(root / name) for name in SOURCE_FILES},
             "app": product_records(app), "testRelativePath": test.relative_to(runner).as_posix(),
             "test": product_records(test), "runner": product_records(runner),
             "shippingArchiveSHA256": built["shippingArchiveSHA256"]}
    path = evidence / "shortcut-long-running-inputs.json"
    with path.open("x") as stream:
        json.dump(value, stream, indent=2, sort_keys=True); stream.write("\n")
    return {"path": str(path), **file_record(path)}


def load_inputs(path, evidence):
    path = Path(path)
    require(path == evidence.parent / "shortcut-long-running-inputs.json", "Input manifest is outside this attempt")
    document = shared.read_document(path, evidence.parent)
    value = document["value"]
    require(type(value.get("schema")) is int and value["schema"] == 1
            and value.get("scope") == "miniapp_shortcut_long_running_os", "Unknown original input manifest")
    require(type(value.get("sourceFiles")) is dict and set(value["sourceFiles"]) == set(SOURCE_FILES),
            "Incomplete exact source closure")
    root = Path(value["root"]).resolve(strict=True)
    require(all(file_record(root / name) == record for name, record in value["sourceFiles"].items()),
            "Actual admitted source bytes changed")
    require(set(value.get("surfaceArchives", {})) == set(FIXTURE_FILES), "Archive input set changed")
    for engine, row in value["surfaceArchives"].items():
        name = "LongRunningExpo.hanlinExpo" if engine == "expo" else "LongRunningNativeScript.hanlinNativeScript"
        require(row.get("path") == str(evidence.parent / "shortcut-long-running-fixtures" / name)
                and file_record(Path(row["path"]))["sha256"] == row.get("sha256"), "Archive identity changed")
    return document


def validate_request(request):
    require(type(request) is dict and type(request.get("schema")) is int and request["schema"] == 1,
            "Unknown long-running request")
    run_id = canonical_uuid(request.get("runID"))
    engine = request.get("engine")
    require(engine in FIXTURE_FILES and request.get("surface") == ROUTE
            and request.get("fixtureAppID") == app_id(engine) and request.get("fixtureTitle") == title(engine),
            "This case is not an independent long-running fixture")
    require(request.get("scenario") in ("return", "cancel"), "Unknown long-running scenario")
    challenge = request.get("challenge")
    require(type(challenge) is str and re.fullmatch(r"[a-z0-9]+-[a-z0-9]+-[a-z0-9]+", challenge)
            and type(request.get("baselineCounter")) is int and request["baselineCounter"] == 0,
            "The original visible preparation is missing")
    shared._epoch_milliseconds(request.get("startedAt"))
    pid = request.get("ownerProcessID")
    require(type(pid) is int and pid > 0 and type(request.get("ownerAccessibilityHeader")) is str
            and re.match(r"^Attributes: Application, .*?, pid: " + str(pid) + r",", request["ownerAccessibilityHeader"]),
            "The actual public app accessibility PID is not bound")
    owner = request.get("ownerWindowID")
    require((engine == "expo" and owner is None) or
            (engine == "nativescript" and type(owner) is str and 0 < len(owner) <= 128 and "/" not in owner),
            "The original native owner window identity is missing")
    token = canonical_uuid(request.get("token"))
    require(request.get("savedShortcutName") == "Hanlin-LR-" + engine + "-" + run_id[:8],
            "The saved Shortcut name does not identify this case")
    expected = {"surface": ROUTE, "challenge": challenge,
                "longRunning": {"schema": 1, "token": token, "profile": PROFILE},
                "typed": {"text": "שלום עולם", "count": 42, "enabled": True, "empty": None,
                          "list": [True, 42, "שלום"]}}
    require(equal(request.get("configuredInput"), expected), "The saved exact typed profile differs")
    return {key: request[key] for key in CONTRACT_KEYS}


def validate_saved_launch(request):
    saved, launch = request.get("savedConfiguration"), request.get("launch")
    if saved is None or launch is None:
        return False
    require(type(saved) is dict and saved.get("savedShortcutName") == request["savedShortcutName"]
            and saved.get("reopened") is True and saved.get("allowLongRunning") is True
            and saved.get("openWhenRun") is False and saved.get("resultChainConfigured") is True,
            "Actual saved/reopened system settings are not the declared long-running background action")
    require(type(launch) is dict and launch.get("savedShortcutName") == request["savedShortcutName"]
            and launch.get("systemRunTapped") is True, "The actual saved system Run control was not used")
    require(shared._epoch_milliseconds(request["startedAt"]) <= shared._epoch_milliseconds(saved.get("observedAt"))
            <= shared._epoch_milliseconds(launch.get("requestedAt"))
            <= shared._epoch_milliseconds(launch.get("observedAt")), "Invalid saved action chronology")
    return True


def validate_receipts(result, request):
    rows, note = result.get("receipts"), result.get("longRunning")
    require(type(rows) is list and len(rows) <= 35 and type(note) is dict, "Invalid authored receipt inventory")
    completed = note.get("completedUnitCount")
    require(type(completed) is int and 0 <= completed <= len(rows) <= min(35, completed + 1),
            "Progress led actual completed runtime receipts")
    seen = set()
    for ordinal, row in enumerate(rows, 1):
        kind = KINDS[(ordinal - 1) % len(KINDS)]
        marker = ":".join((request["fixtureAppID"], request["challenge"], result["nonce"], str(ordinal), kind, "42"))
        require(type(row) is dict and type(row.get("ordinal")) is int and row["ordinal"] == ordinal
                and row.get("kind") == kind and row.get("marker") == marker,
                "Runtime ordinal, source marker or original engine changed")
        receipt = row.get("receipt")
        require(type(receipt) is dict and type(receipt.get("executionID")) is str
                and receipt["executionID"] and receipt["executionID"] not in seen,
                "Runtime execution receipts are absent, duplicated or foreign")
        seen.add(receipt["executionID"])
        if ordinal > completed:
            continue  # An actual failure may be retained but cannot advance progress.
        require(finite(receipt.get("durationMilliseconds")) and receipt["durationMilliseconds"] >= 0
                and receipt.get("didTimeOut") is False and receipt.get("wasCancelled") is False
                and receipt.get("outputWasTruncated") is False
                and ("exitCode" not in receipt or type(receipt["exitCode"]) is int and receipt["exitCode"] == 0),
                "Progress counted failed, cancelled, truncated or timed-out work")
        require(receipt.get("value") == marker if kind == "javaScriptCore" else
                type(receipt.get("stdout")) is str and marker in receipt["stdout"].splitlines(),
                "The real runtime output does not contain its exact invocation marker")
    require(type(note.get("reportCount")) is int and note["reportCount"] >= completed
            and type(note.get("totalUnitCount")) is int and note["totalUnitCount"] == 35
            and type(note.get("completedPacingTicks")) is int and 0 <= note["completedPacingTicks"] <= 340,
            "The bounded completed-work progress contract changed")
    if note["reportCount"]:
        require(note.get("progressMessage") == "LR " + request["token"] + " " + str(completed) + "/35 receipts",
                "The reported native progress message differs from completed work")
        shared._epoch_milliseconds(note.get("reportedProgressAt"))
    return seen


def collect(request, identity, baseline_ids, commands, journals):
    matches = []
    for command_id, document in commands.items():
        if command_id in baseline_ids:
            continue
        row = document["value"]; invocation = row.get("invocation", {})
        parameters = shared.decode_value(invocation.get("parameters"))
        if type(parameters) is not dict or parameters.get("challenge") != request["challenge"]:
            continue
        require(equal(parameters, request["configuredInput"]) and invocation.get("identity") == identity["identity"]
                and invocation.get("entityID") == "surface.run", "Fresh input reached a foreign action or generation")
        delivery = invocation.get("delivery")
        require(type(delivery) is dict and type(delivery.get("schemaVersion")) is int and delivery["schemaVersion"] == 1
                and delivery.get("appID") == request["fixtureAppID"] and delivery.get("source") == "shortcuts"
                and delivery.get("userGesturePresent") is True and delivery.get("canPresentUI") is False
                and invocation.get("continueInForeground") is False, "The real action was not a background system delivery")
        require(finite(row.get("createdAt")) and row["createdAt"] >= shared._epoch_milliseconds(request["startedAt"])
                and type(row["receipt"].get("attempt")) is int and row["receipt"]["attempt"] == 1,
                "The actual command is stale, unowned or retried")
        matches.append((command_id, document))
    require(len(matches) <= 1, "The fresh saved action executed more than once")
    actual = [doc for doc in journals if doc["value"].get("challenge") == request["challenge"]]
    require(len(actual) <= 1, "Duplicate actual handler journals are not a single invocation")
    if not matches or not actual:
        return None
    command_id, command = matches[0]; journal = actual[0]; result = journal["value"]
    note, nonce = result.get("longRunning"), result.get("nonce")
    require(type(result.get("schemaVersion")) is int and result["schemaVersion"] == 1
            and result.get("appID") == request["fixtureAppID"] and result.get("action") == "surface.run"
            and result.get("requestedSurface") == ROUTE and equal(result.get("request"), request["configuredInput"])
            and type(result.get("counter")) is int and result["counter"] == 1,
            "The actual handler result is not this configured invocation")
    require(type(nonce) is str and re.fullmatch(r"[a-z0-9]+-[a-z0-9]+-[a-z0-9]+", nonce)
            and type(note) is dict and type(note.get("schema")) is int and note["schema"] == 1
            and note.get("token") == request["token"] and note.get("profile") == PROFILE,
            "Handler nonce or fixed authored profile changed")
    filename = "surface-invocation-" + request["token"] + "-" + nonce + ".json"
    require(note.get("journalFile") == filename and Path(journal["path"]).name == filename,
            "Actual journal path is not bound to this invocation")
    require(shared._epoch_milliseconds(result.get("startedAt")) >= shared._epoch_milliseconds(request["startedAt"]),
            "The handler entry predates this run")
    window_id = None
    if request["engine"] == "expo":
        require(result.get("requestIDOrigin") == "host-invocation"
                and str(uuid.UUID(result.get("requestID", ""))) == command_id
                and Path(journal["path"]).parts[-3:] == (request["fixtureAppID"], "State", filename),
                "Expo's actual command UUID or canonical private state differs")
        require(result.get("presentationSamples") == [], "Expo cannot fabricate NativeScript window samples")
    else:
        require(result.get("requestIDOrigin") == "javascript-handler" and result.get("requestID") == nonce,
                "The actual NativeScript handler nonce is not correlated")
        samples = result.get("presentationSamples")
        require(type(samples) is list and samples, "NativeScript's real presentation sample is missing")
        for sample in samples:
            require(type(sample) is dict and type(sample.get("windowID")) is str and sample["windowID"]
                    and sample["windowID"] != request["ownerWindowID"]
                    and sample.get("statePath") == journal["path"] and sample.get("attached") is False
                    and sample.get("executionMode") == "headless-action"
                    and Path(journal["path"]).parts[-4:] == ("Windows", sample["windowID"], "State", filename),
                    "Background work crossed its actual own headless window or private path")
        ids = {sample["windowID"] for sample in samples}
        require(len(ids) == 1, "One handler crossed actual native windows")
        window_id = next(iter(ids))
    execution_ids = validate_receipts(result, request)
    return {"commandID": command_id, "command": command, "journal": journal,
            "nonce": nonce, "windowID": window_id,
            "runtimeExecutionIDs": [row["receipt"]["executionID"] for row in result["receipts"]]}


def live_observation(row, process, epoch_ms, monotonic):
    receipt = row["command"]["value"]["receipt"]
    result = row["journal"]["value"]; note = result["longRunning"]
    require(receipt.get("status") == "running" and receipt.get("cancellationRequested") is False
            and concurrency.native_uuid(receipt.get("leaseID")) and finite(receipt.get("leaseExpiresAt"))
            and receipt["leaseExpiresAt"] > epoch_ms and result.get("status") == "running"
            and note.get("phase") in ("entered", "executing", "pacing"),
            "The genuine command/handler/current lease are no longer jointly running")
    require(note["reportCount"] > 0 and shared._epoch_milliseconds(note["reportedProgressAt"]) <= epoch_ms,
            "No actual native progress callback was acknowledged")
    return {"at": epoch_ms, "monotonic": monotonic, "process": process,
            "commandID": row["commandID"], "leaseID": receipt["leaseID"], "leaseExpiresAt": receipt["leaseExpiresAt"],
            "nonce": row["nonce"], "windowID": row["windowID"], "journalPath": row["journal"]["path"],
            "journalSHA256": row["journal"]["sha256"], "completed": note["completedUnitCount"],
            "reportCount": note["reportCount"], "reportedProgressAt": note["reportedProgressAt"],
            "runtimeExecutionIDs": row["runtimeExecutionIDs"]}


def extend_interval(samples, observed):
    require(finite(observed.get("monotonic")) and finite(observed.get("at")), "Missing actual monotonic observation")
    if samples:
        before, first = samples[-1], samples[0]
        require(0 < observed["monotonic"] - before["monotonic"] <= MAX_OBSERVATION_GAP,
                "The actual sampled live-lease interval has a gap")
        require(all(equal(observed[key], first[key]) for key in
                    ("commandID", "leaseID", "nonce", "windowID", "journalPath", "process")),
                "The live interval crossed a command, process start, lease, handler or window")
        require(observed["completed"] >= before["completed"] and observed["reportCount"] >= before["reportCount"]
                and observed["runtimeExecutionIDs"][:len(before["runtimeExecutionIDs"])] == before["runtimeExecutionIDs"],
                "Actual completed work/progress was replaced or went backwards")
    samples.append(observed)
    require(len(samples) <= 600, "The observation interval exceeded its finite evidence bound")
    elapsed = observed["monotonic"] - samples[0]["monotonic"]
    if elapsed <= MINIMUM_SECONDS:
        return None
    require(observed["reportCount"] > samples[0]["reportCount"] and observed["completed"] > samples[0]["completed"],
            "Elapsed pacing alone cannot replace actual completed runtime progress")
    return {"status": "LONG_RUNNING_OBSERVED", "elapsedMonotonicSeconds": elapsed,
            "first": samples[0], "last": observed, "sampleCount": len(samples),
            "maximumSampleGapSeconds": max(b["monotonic"] - a["monotonic"] for a, b in zip(samples, samples[1:])),
            "scope": "Actual saved background intent with periodic live-lease/process/journal observations; paced finite work."}


def validate_progress_ui(row, request, maximum_completed):
    require(type(row) is dict and row.get("token") == request["token"] and type(row.get("text")) is str,
            "The actual system progress output is missing")
    match = re.fullmatch(r"LR " + re.escape(request["token"]) + r" ([0-9]+)/35 receipts", row["text"])
    require(match is not None and type(row.get("completed")) is int and row["completed"] == int(match[1])
            and 0 <= row["completed"] <= maximum_completed,
            "Visible system progress differs from the completed actual receipts")
    shared._epoch_milliseconds(row.get("observedAt"))
    return row


def terminal_result(request, row, long_proof, now):
    require(long_proof is not None, "Terminal results cannot substitute for the >300s actual running interval")
    first = long_proof["first"]
    require(all(row[key] == first[key] for key in ("commandID", "nonce", "windowID"))
            and row["journal"]["path"] == first["journalPath"], "Terminal result changed handler identity")
    receipt = row["command"]["value"]["receipt"]
    if receipt.get("status") in ("queued", "running"):
        return None
    expected = "succeeded" if request["scenario"] == "return" else "cancelled"
    require(receipt.get("status") == expected and receipt.get("leaseID") is None
            and receipt.get("leaseExpiresAt") is None and finite(receipt.get("updatedAt"))
            and receipt["updatedAt"] <= now, "Actual terminal state or lease teardown is incorrect")
    result = row["journal"]["value"]
    if expected == "succeeded":
        value = shared.decode_value(receipt.get("value"))
        if type(value) is str:
            value = shared.parse_json(value)
        require(receipt.get("cancellationRequested") is False and receipt.get("failure") is None
                and equal(value, result) and result.get("status") == "completed"
                and result["longRunning"].get("phase") == "completed"
                and result["longRunning"]["completedUnitCount"] == 35 and len(result["receipts"]) == 35
                and result["longRunning"]["completedPacingTicks"] == 340,
                "Actual native success did not return all 35 exact completed units")
    else:
        stop = request.get("stop")
        if stop is None:
            # The actual native cancellation may settle between XCTest's tap
            # and atomic publication of its observed Stop. Keep waiting for
            # that independent evidence; a cancelled receipt alone cannot pass.
            return None
        require(type(stop) is dict and stop.get("token") == request["token"]
                and stop.get("visibleShortcutName") == request["savedShortcutName"]
                and stop.get("systemStopObserved") is True
                and long_proof["last"]["at"] <= shared._epoch_milliseconds(stop.get("requestedAt"))
                <= shared._epoch_milliseconds(stop.get("observedAt")) <= now,
                "The genuine selected system Stop did not follow the >300s live observation")
        require(receipt.get("cancellationRequested") is True and receipt.get("value") is None
                and receipt["updatedAt"] >= shared._epoch_milliseconds(stop["requestedAt"])
                and result.get("status") in ("running", "failed")
                and result["longRunning"].get("phase") in ("entered", "executing", "pacing", "failed")
                and result["longRunning"]["completedUnitCount"] < 35 and len(result["receipts"]) < 35,
                "Cancellation concealed completed work, a returned value, or a successful late handler")
    return {"schema": 1, "runID": request["runID"], "status": "TERMINAL_OBSERVED",
            "scenario": request["scenario"], "command": row["command"], "journal": row["journal"],
            "invocationID": row["commandID"], "nonce": row["nonce"], "windowID": row["windowID"],
            "runtimeExecutionIDs": row["runtimeExecutionIDs"], "longRunning": long_proof}


def verify_cancelled_work_unchanged(previous, current):
    """Freeze successful work at the first observed actual cancelled receipt.

    A trailing real failed/cancelled attempt may still be retained by the
    handler. It cannot become completed work or hide a later successful unit.
    """
    before, after = previous["journal"]["value"], current["journal"]["value"]
    prior = before["receipts"]
    rows = after["receipts"]
    require(after["longRunning"]["completedUnitCount"] == before["longRunning"]["completedUnitCount"]
            and len(rows) >= len(prior) and equal(rows[:len(prior)], prior),
            "Successful runtime work changed after the first actual cancelled receipt")
    for row in rows[len(prior):]:
        receipt = row["receipt"]
        failed = (receipt.get("wasCancelled") is True or receipt.get("didTimeOut") is True
                  or receipt.get("outputWasTruncated") is True
                  or type(receipt.get("exitCode")) is int and receipt["exitCode"] != 0)
        require(failed, "A later successful runtime unit arrived after native cancellation")


def process_observation(args, request, roots):
    info = plistlib.loads((roots["app"] / "Info.plist").read_bytes())
    executable = (roots["app"] / info["CFBundleExecutable"]).resolve(strict=True)
    require(args.device.lower() in {part.lower() for part in executable.parts}, "Installed app is outside the owned Simulator")
    argv = ["/bin/ps", "-ww", "-p", str(request["ownerProcessID"]), "-o", "pid=,ppid=,lstart=,comm="]
    process = subprocess.run(argv, capture_output=True, timeout=8, env={**os.environ, "LC_ALL": "C", "TZ": "UTC"})
    require(process.returncode == 0, "The actual owned application process is no longer observable")
    try:
        result = parse_process(process.stdout.decode(), request["ownerProcessID"])
    except RuntimeError as error:
        raise shared.ObservationError(str(error)) from error
    require(Path(result["path"]).resolve(strict=True) == executable
            and math.floor(shared._epoch_milliseconds(request["startedAt"]) / 1000) <= result["launchEpoch"] <= time.time(),
            "The actual PID is not this attempt's installed MiniApps process")
    return result


def verify_current(args, roots, inputs):
    current = shared.product_roots(args.device, args.bundle_id)
    require(all(current[key] == roots[key] for key in ROOT_KEYS), "Actual app/data/group/extension containers changed")
    require(product_records(current["app"]) == inputs["app"], "Installed app differs from the compiled product")
    runner = shared.os_container(args.device, args.runner_bundle_id, "app")
    relative = Path(inputs["testRelativePath"])
    require(not relative.is_absolute() and ".." not in relative.parts and relative.parts[0] == "PlugIns",
            "Invalid original XCTest bundle path")
    require(product_records(runner) == inputs["runner"] and product_records(runner / relative) == inputs["test"],
            "Actual installed XCTest runner/product changed")
    return current


def facts(request, roots, inputs, evidence):
    snapshot = shared.snapshot_document(roots["extensions"])
    identity = shared.action_identity(request, snapshot)
    catalog = shared.installed_catalog(roots["data"], identity)
    source = archive_binding.verify_installed_fixture_archive(roots["data"], identity["identity"], catalog,
        inputs["surfaceArchives"][request["engine"]], evidence.parent)
    identity["installedRecord"] = catalog["value"]["packages"][identity["identity"]["installedPackageID"]]["record"]
    return identity, source


def close_observation(request, row, data):
    if request["engine"] == "expo":
        return {"scope": "Expo: actual native lease release and unchanged existing owner; no per-action native-window close claim."}
    path = Path(row["journal"]["path"]).parent / ("long-running-close-" + request["token"] + "-" + row["nonce"] + ".json")
    if not path.exists():
        return None
    document = shared.read_document(path, data); value = document["value"]
    require(type(value.get("schema")) is int and value["schema"] == 1 and value.get("event") == "close"
            and value.get("appID") == request["fixtureAppID"] and value.get("windowID") == row["windowID"]
            and value.get("token") == request["token"] and value.get("nonce") == row["nonce"]
            and value.get("journalFile") == Path(row["journal"]["path"]).name
            and value.get("statePath") == str(path), "The real native close event belongs to another window or invocation")
    require(shared._epoch_milliseconds(value.get("at")) >= shared._epoch_milliseconds(row["journal"]["value"]["startedAt"]),
            "Native close observation predates this actual handler")
    return document


def write_response(directory, name, value, evidence):
    require(name in RESPONSES and directory.is_dir() and not directory.is_symlink(), "Not an owned exchange response")
    target = directory / name
    require(not target.exists(), "An observer response cannot be overwritten")
    temporary = directory / (name + ".observer-tmp")
    with temporary.open("x") as stream:
        json.dump(value, stream, ensure_ascii=False, sort_keys=True, indent=2); stream.write("\n")
    os.replace(temporary, target)
    (evidence / name).write_text(json.dumps(value, ensure_ascii=False, sort_keys=True, indent=2) + "\n")


def observe(args, stopping=lambda: False):
    evidence = Path(args.output).resolve()
    roots = shared.product_roots(args.device, args.bundle_id)
    require(all(not evidence.is_relative_to(roots[key]) for key in ("app", "data", "group")), "Evidence is inside production storage")
    evidence.mkdir(parents=True, exist_ok=False)
    admitted = load_inputs(args.inputs, evidence)
    require(admitted["value"]["device"] == args.device, "Input admission names a different owned Simulator")
    apps = shared.system_app_observation(args.device, evidence)
    seen = {}; last_error = None; end = time.monotonic() + args.duration
    while time.monotonic() < end and not stopping():
        case = None; directory = None
        try:
            runner = shared.os_container(args.device, args.runner_bundle_id, "data")
            exchange = runner / "Documents" / EXCHANGE
            active = shared.read_document(exchange / "active.json", runner)["value"]
            run_id = canonical_uuid(active.get("runID")); directory = exchange / run_id
            request = shared.read_document(directory / "request.json", runner)["value"]
            require(request.get("runID") == run_id and request.get("engine") == active.get("engine")
                    and request.get("surface") == active.get("surface"), "Active request and current case differ")
            phase = request.get("phase")
            if phase in ("preparing", "finished"):
                time.sleep(0.5); continue
            contract = validate_request(request); case = seen.get(run_id)
            if case is None:
                require(phase == "prepared", "Observer must admit the actual prepared owner before launch")
                roots = shared.product_roots(args.device, args.bundle_id)
                verify_current(args, roots, admitted["value"])
                identity, source = facts(request, roots, admitted["value"], evidence)
                prepared = shared.prepared_proof(request, shared.proof_documents(roots["data"], request["fixtureAppID"]))
                process = process_observation(args, request, roots)
                folder = evidence / run_id; folder.mkdir(exist_ok=False)
                case = {"roots": roots, "identity": identity, "source": source, "prepared": prepared,
                        "process": process, "baseline": set(shared.queue_documents(roots["extensions"])),
                        "contract": contract, "evidence": folder, "samples": [], "finished": False, "failed": False,
                        "running": None, "long": None, "terminal": None, "terminalWritten": False,
                        "lastSample": None, "phase": phase, "stopMonotonic": None}
                seen[run_id] = case
                write_response(directory, "identity.json", {"schema": 1, "runID": run_id, "status": "READY",
                    **identity, "systemApps": apps, "source": source, "preparedProof": prepared,
                    "actualProcess": process, "inputManifestSHA256": admitted["sha256"]}, folder)
            if case["failed"] or case["finished"]:
                time.sleep(0.5); continue
            require(equal(contract, case["contract"]), "The admitted input or owner contract changed")
            roots = case["roots"]
            if phase != case["phase"]:
                verify_current(args, roots, admitted["value"]); case["phase"] = phase
            current_identity = concurrency.current_identity(request, roots)
            concurrency.same_identity(current_identity, case["identity"])
            prepared = shared.read_document(Path(case["prepared"]["path"]), roots["data"])
            require(prepared["sha256"] == case["prepared"]["sha256"], "A background action altered its prepared owner's state")
            if not validate_saved_launch(request):
                time.sleep(0.5); continue
            row = collect(request, case["identity"], case["baseline"], shared.queue_documents(roots["extensions"]),
                          concurrency.journal_documents(roots["data"], request["fixtureAppID"]))
            if row is None:
                time.sleep(0.5); continue
            require(row["command"]["value"]["createdAt"] >= shared._epoch_milliseconds(request["launch"]["requestedAt"]),
                    "The actual native command predates the UI's saved Run action")
            now, monotonic = time.time() * 1000, time.monotonic()
            native_status = row["command"]["value"]["receipt"].get("status")
            if native_status == "running" and row["journal"]["value"]["longRunning"]["reportCount"] == 0:
                time.sleep(0.5); continue
            if case["running"] is None and native_status == "running":
                process = process_observation(args, request, roots)
                require(process == case["process"], "The owner process was replaced before actual admission")
                observed = live_observation(row, process, now, monotonic)
                case["running"] = observed
                write_response(directory, "running.json", {"schema": 1, "runID": run_id, "status": "RUNNING_OBSERVED",
                    "observation": observed}, case["evidence"])
            if phase == "home-observed" and case["long"] is None:
                home = request.get("homeObservation")
                require(type(home) is dict and home.get("homePressed") is True
                        and home.get("miniAppsForeground") is False and home.get("shortcutsForeground") is False,
                        "The real OS Home action did not background both applications")
                require(shared._epoch_milliseconds(request["launch"]["observedAt"])
                        <= shared._epoch_milliseconds(home.get("observedAt")) <= now,
                        "The actual Home observation predates this real launch or is in the future")
                validate_progress_ui(request.get("initialSystemProgress"), request, row["journal"]["value"]["longRunning"]["completedUnitCount"])
                if case["lastSample"] is None or monotonic - case["lastSample"] >= 1:
                    process = process_observation(args, request, roots)
                    require(process == case["process"], "The actual app process changed during background execution")
                    observed = live_observation(row, process, now, monotonic)
                    value = extend_interval(case["samples"], observed)
                    case["lastSample"] = monotonic
                    with (case["evidence"] / "live-observations.jsonl").open("a") as stream:
                        stream.write(json.dumps(observed, sort_keys=True) + "\n")
                    if value is not None:
                        case["long"] = {"schema": 1, "runID": run_id, **value}
                        write_response(directory, "long-running.json", case["long"], case["evidence"])
            if case["long"] is None and native_status not in ("queued", "running"):
                raise shared.ObservationError("The real action terminated before a >300s sampled running interval")
            if request.get("stop") is not None and case["stopMonotonic"] is None:
                case["stopMonotonic"] = monotonic
            if case["long"] is not None:
                value = terminal_result(request, row, case["long"], now)
                if value is not None:
                    if case["terminal"] is None:
                        case["terminal"] = value
                    require(equal(value["command"], case["terminal"]["command"]), "Native terminal receipt changed after settlement")
                    if request["scenario"] == "return":
                        require(equal(value["journal"], case["terminal"]["journal"]), "Successful handler changed after return")
                    else:
                        verify_cancelled_work_unchanged(case["terminal"], value)
                        # Re-read every observed iteration. A late successful
                        # unit or handler must fail even after a legitimate
                        # cancelled native receipt was first seen.
                        if monotonic < max(case["samples"][0]["monotonic"] + POST_START_CANCEL_SECONDS,
                                           case["stopMonotonic"] + POST_STOP_SECONDS):
                            time.sleep(0.5); continue
                    closed = close_observation(request, row, roots["data"])
                    if closed is None:
                        time.sleep(0.5); continue
                    if not case["terminalWritten"]:
                        value["nativeWindowClose"] = closed
                        value["postStopObservationSeconds"] = monotonic - case["stopMonotonic"] if case["stopMonotonic"] is not None else None
                        case["terminal"] = value
                        write_response(directory, "terminal.json", value, case["evidence"])
                        case["terminalWritten"] = True
            if phase == "system-result-observed" and case["terminalWritten"]:
                require(request.get("ownerProcessIDAfter") == request["ownerProcessID"], "The final public owner PID changed")
                require(process_observation(args, request, roots) == case["process"], "The final actual app process changed")
                progress = validate_progress_ui(request.get("finalSystemProgress"), request,
                    row["journal"]["value"]["longRunning"]["completedUnitCount"])
                require(progress["completed"] >= request["initialSystemProgress"]["completed"], "Actual visible progress regressed")
                if request["scenario"] == "return":
                    require(equal(request.get("systemChainedResult"), row["journal"]["value"]),
                            "The genuine Get Text → Show Result JSON differs from native returned work")
                else:
                    require(request.get("systemCancelledObserved") is True and request.get("systemChainedResult") is None,
                            "System Stop did not leave the actual selected action stopped without a result")
                final_inputs = load_inputs(args.inputs, evidence)
                require(final_inputs["sha256"] == admitted["sha256"], "Original input admission changed")
                final_identity, source = facts(request, roots, admitted["value"], evidence)
                concurrency.same_identity(final_identity, case["identity"])
                require(equal(source, case["source"]), "The current installed source changed")
                # Final post-XCTest container and product readback, immediately
                # before publishing completion, prevents stale MCM acceptance.
                verify_current(args, roots, admitted["value"])
                write_response(directory, "completion.json", {"schema": 1, "runID": run_id, "status": "EXECUTED_PASS",
                    "scenario": request["scenario"], "engine": request["engine"], "terminal": case["terminal"],
                    "inputManifestSHA256": admitted["sha256"], "sourceSHA": admitted["value"]["sourceSHA"],
                    "scope": "This owned Simulator's saved >300s background paced action; no physical lock/network/APNs or CPU-duration claim."}, case["evidence"])
                case["finished"] = True
            last_error = None
        except (OSError, ValueError, KeyError, TypeError, subprocess.TimeoutExpired) as error:
            message = type(error).__name__ + ": " + str(error)
            if isinstance(error, shared.ObservationError) and case is not None:
                case["failed"] = True
                if directory is not None and not (directory / "failure.json").exists():
                    write_response(directory, "failure.json", {"schema": 1, "runID": request["runID"],
                        "status": "FAILED", "reason": message}, case["evidence"])
            if message != last_error:
                with (evidence / "observations.jsonl").open("a") as stream:
                    stream.write(json.dumps({"at": time.time(), "error": message, "failed": bool(case and case["failed"])}) + "\n")
                last_error = message
        time.sleep(0.5)
    (evidence / "observer.json").write_text(json.dumps({"status": "OBSERVER_FINISHED",
        "runs": {key: {"completionWritten": value["finished"], "failed": value["failed"]} for key, value in seen.items()},
        "scope": "Read-only actual evidence; original XCTest supplies OS actions", "lastObservationError": last_error}, indent=2) + "\n")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--device", required=True)
    parser.add_argument("--runner-bundle-id", required=True)
    parser.add_argument("--bundle-id", default="com.itorah.hanlinminiapps", choices=["com.itorah.hanlinminiapps"])
    parser.add_argument("--inputs", required=True)
    parser.add_argument("--output", required=True)
    parser.add_argument("--duration", type=float, default=2100)
    args = parser.parse_args()
    require(0 < args.duration <= 2100 and args.runner_bundle_id.endswith(".xctrunner"), "Invalid bounded original runner admission")
    stopping = [False]
    signal.signal(signal.SIGTERM, lambda signum, frame: stopping.__setitem__(0, True))
    signal.signal(signal.SIGINT, lambda signum, frame: stopping.__setitem__(0, True))
    observe(args, stopping=lambda: stopping[0])


if __name__ == "__main__":
    main()
