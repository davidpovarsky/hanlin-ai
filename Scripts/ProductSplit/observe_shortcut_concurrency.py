"""Read-only proof for three real Shortcuts overlapping one live NativeScript owner.

The existing system-surface XCTest uses its separate runner-owned exchange.
Only exchange responses and independent evidence are written. No invocation,
receipt, grant, installed catalog or MiniApp state is created by this observer.
This pilot covers one NativeScript owner and three background NativeScript
actions; it is not the full SCRIPTABLE06 engine/device/window matrix.
"""
from pathlib import Path
import argparse
import json
import math
import os
import re
import signal
import subprocess
import time
import uuid
from urllib.parse import parse_qs, urlsplit

import observe_shortcut_surfaces as original

require = original.require
ObservationError = original.ObservationError
equal = original.equal_typed_json
ROUTE = "miniAppShortcutConcurrency"
EXCHANGE = "HanlinShortcutConcurrencyObservation"
RESPONSES = ("identity.json", "overlap.json", "actions-complete.json", "completion.json")
ROOT_KEYS = ("app", "data", "group", "extensions", "configuration", "infoSHA256")
CONTRACT_KEYS = ("schema", "runID", "engine", "surface", "scenario", "fixtureAppID",
                 "fixtureTitle", "startedAt", "challenge", "baselineCounter",
                 "ownerProcessID", "ownerStatePath", "ownerWindowID", "invocations")


def number(value):
    return type(value) in (int, float) and math.isfinite(value)


def valid_uuid(value):
    try:
        return type(value) is str and str(uuid.UUID(value)) == value
    except (ValueError, AttributeError):
        return False


def native_uuid(value):
    return type(value) is str and valid_uuid(value.lower())


def validate_request(request):
    require(type(request) is dict and type(request.get("schema")) is int
            and request["schema"] == 1, "Invalid concurrency request schema")
    projected = dict(request, surface="miniAppShortcut", expectedCanPresentUI=False)
    run_id = original.validate_request(projected)
    require(request.get("surface") == ROUTE and request["engine"] == "nativescript"
            and request.get("fixtureTitle") == "Surface NativeScript",
            "This pilot requires the actual NativeScript fixture")
    scenario = request.get("scenario")
    require(scenario in ("reverseCompletion", "cancelOne"), "Unknown concurrency scenario")
    original._epoch_milliseconds(request.get("startedAt"))
    require(type(request.get("ownerProcessID")) is int and request["ownerProcessID"] > 0,
            "The actual owner accessibility process ID is required")
    require(type(request.get("ownerStatePath")) is str
            and Path(request["ownerStatePath"]).is_absolute()
            and Path(request["ownerStatePath"]).name == "surface-proof.json",
            "The owner must expose its actual private state path")
    require(type(request.get("ownerWindowID")) is str and 0 < len(request["ownerWindowID"]) <= 128
            and "/" not in request["ownerWindowID"],
            "The actual initial foreground window identity must be observed in the fixture UI")
    invocations = request.get("invocations")
    require(type(invocations) is list and len(invocations) == 3,
            "Exactly three independently saved system actions are required")
    tokens, names = set(), set()
    expected_holds = [45000, 30000, 15000] if scenario == "reverseCompletion" else [45000, 30000, 60000]
    for index, row in enumerate(invocations):
        require(type(row) is dict and set(row) == {
            "token", "savedShortcutName", "configuredInput", "expectedTerminal"},
            "Unexpected invocation contract")
        token, name = row["token"], row["savedShortcutName"]
        require(valid_uuid(token) and token not in tokens, "Invocation tokens must be distinct UUIDs")
        require(type(name) is str and name == "Hanlin-NS-" + run_id[:8] + "-" + str(index + 1)
                and name not in names, "Saved Shortcut names must belong to this exact UI run")
        expected = "cancelled" if scenario == "cancelOne" and index == 2 else "succeeded"
        require(row["expectedTerminal"] == expected, "Unexpected terminal expectation")
        payload = row["configuredInput"]
        require(type(payload) is dict and payload.get("surface") == ROUTE
                and payload.get("challenge") == request["challenge"],
                "The saved action must carry the actual UI challenge")
        options = payload.get("concurrency")
        require(type(options) is dict and set(options) == {"schema", "token", "holdMilliseconds"}
                and type(options.get("schema")) is int and options["schema"] == 1
                and options.get("token") == token
                and type(options.get("holdMilliseconds")) is int
                and options["holdMilliseconds"] == expected_holds[index],
                "The authored hold and token must match the declared scenario")
        require(equal(payload.get("typed"), {
            "text": "שלום עולם", "count": 42, "enabled": True,
            "empty": None, "list": [True, 42, "שלום"]}),
            "The exact typed input control is missing or coerced")
        tokens.add(token)
        names.add(name)
    return run_id


def contract(request):
    validate_request(request)
    return {key: request[key] for key in CONTRACT_KEYS}


def invocation_map(request):
    return {row["token"]: row for row in request["invocations"]}


def validate_launches(request, require_all=False):
    expected = invocation_map(request)
    launches = request.get("launches", [])
    require(type(launches) is list and len(launches) <= 3, "Unexpected system launch count")
    seen = set()
    started = original._epoch_milliseconds(request["startedAt"])
    for launch in launches:
        require(type(launch) is dict and launch.get("token") in expected
                and launch["token"] not in seen, "A system action was launched twice or is foreign")
        configured = expected[launch["token"]]
        require(launch.get("savedShortcutName") == configured["savedShortcutName"]
                and launch.get("systemLaunchObserved") is True,
                "The actual saved system Shortcut must be observed")
        parsed = urlsplit(launch.get("url", ""))
        require(parsed.scheme == "shortcuts" and parsed.netloc == "run-shortcut"
                and parsed.path in ("", "/") and not parsed.fragment
                and parse_qs(parsed.query, strict_parsing=True) ==
                    {"name": [configured["savedShortcutName"]]},
                "Only the public saved-Shortcut OS URL is accepted")
        before = original._epoch_milliseconds(launch.get("requestedAt"))
        after = original._epoch_milliseconds(launch.get("observedAt"))
        require(started <= before <= after, "Invalid actual OS launch interval")
        seen.add(launch["token"])
    require(not require_all or len(seen) == 3, "All three real OS launches must precede overlap")
    return {row["token"]: row for row in launches}


def journal_documents(data_root, app_id):
    base = data_root / "Library" / "Application Support" / "Hanlin" / "MiniApps" / app_id
    paths = sorted((base / "State").glob("surface-invocation-*.json"))
    windows = base / "Windows"
    if windows.exists():
        require(not windows.is_symlink(), "Window storage cannot be a symbolic link")
        paths += sorted(windows.glob("*/State/surface-invocation-*.json"))
    require(len(paths) <= 512, "The authored journal inventory exceeds this bounded pilot")
    return [original.read_document(path, data_root) for path in paths]


def collect(request, identity, baseline_ids, commands, journals):
    """Join actual native commands and handler journals; no self-reported success."""
    expected = invocation_map(request)
    matched = {}
    for command_id, document in commands.items():
        if command_id in baseline_ids:
            continue
        row = document["value"]
        invocation = row.get("invocation", {})
        parameters = original.decode_value(invocation.get("parameters"))
        if type(parameters) is not dict or parameters.get("challenge") != request["challenge"]:
            continue
        require(invocation.get("identity") == identity["identity"]
                and invocation.get("entityID") == "surface.run"
                and parameters.get("surface") == ROUTE,
                "This challenge reached a foreign generation, action or route")
        options = parameters.get("concurrency")
        require(type(options) is dict, "The native invocation has no authored concurrency options")
        token = options.get("token")
        require(token in expected and token not in matched,
                "A fresh challenge executed an unknown or duplicate invocation token")
        require(equal(parameters, expected[token]["configuredInput"]),
                "Canonical native input differs from the exact saved JSON types or values")
        require(number(row.get("createdAt"))
                and row["createdAt"] >= original._epoch_milliseconds(request["startedAt"]),
                "The native invocation predates this UI attempt")
        delivery = invocation.get("delivery")
        require(type(delivery) is dict and type(delivery.get("schemaVersion")) is int
                and delivery["schemaVersion"] == 1
                and delivery.get("appID") == request["fixtureAppID"]
                and delivery.get("source") == "shortcuts"
                and delivery.get("userGesturePresent") is True
                and delivery.get("canPresentUI") is False
                and invocation.get("continueInForeground") is False,
                "The actual OS delivery is not this background Shortcuts action")
        receipt = row["receipt"]
        require(type(receipt.get("attempt")) is int and receipt["attempt"] == 1,
                "An action was retried or never owned by its actual executor")
        matched[token] = {"command": document, "commandID": command_id}
    journal_tokens = set()
    for document in journals:
        result = document["value"]
        if result.get("challenge") != request["challenge"]:
            continue
        note = result.get("concurrency")
        require(type(note) is dict and type(note.get("schema")) is int and note["schema"] == 1,
                "This challenge has a malformed authored journal")
        token = note.get("token")
        require(token in expected and token not in journal_tokens,
                "Duplicate handler execution must retain distinct journals and fail acceptance")
        journal_tokens.add(token)
        require(result.get("schemaVersion") == 1 and result.get("appID") == request["fixtureAppID"]
                and result.get("action") == "surface.run"
                and result.get("requestedSurface") == ROUTE
                and type(result.get("counter")) is int and result["counter"] == 1
                and equal(result.get("request"), expected[token]["configuredInput"])
                and type(note.get("holdMilliseconds")) is int
                and note["holdMilliseconds"] == expected[token]["configuredInput"]["concurrency"]["holdMilliseconds"],
                "The handler journal differs from its actual configured invocation")
        nonce = result.get("nonce")
        require(type(nonce) is str and re.fullmatch(r"[a-z0-9]+-[a-z0-9]+-[a-z0-9]+", nonce)
                and result.get("requestIDOrigin") == "javascript-handler"
                and result.get("requestID") == nonce,
                "The NativeScript handler needs its own fresh nonce")
        filename = "surface-invocation-" + token + "-" + nonce + ".json"
        path = Path(document["path"])
        require(note.get("journalFile") == filename and path.name == filename,
                "The durable journal filename is not bound to this handler and token")
        samples = result.get("presentationSamples")
        require(type(samples) is list and samples, "Actual native window samples are missing")
        for sample in samples:
            require(type(sample) is dict and type(sample.get("windowID")) is str
                    and sample["windowID"] and sample["windowID"] != request["ownerWindowID"]
                    and sample.get("statePath") == document["path"]
                    and sample.get("attached") is False
                    and sample.get("executionMode") == "headless-action"
                    and path.parts[-4:] == ("Windows", sample["windowID"], "State", filename),
                    "The action crossed a native window, state path or presentation boundary")
        window_ids = {sample["windowID"] for sample in samples}
        require(len(window_ids) == 1, "One invocation crossed native window ownership")
        require(original._epoch_milliseconds(result.get("startedAt")) >=
                original._epoch_milliseconds(request["startedAt"]),
                "A journal predates this actual UI attempt")
        if token in matched:
            matched[token].update(journal=document, nonce=nonce, windowID=next(iter(window_ids)))
    present = [row for row in matched.values() if "journal" in row]
    require(len({row["nonce"] for row in present}) == len(present)
            and len({row["windowID"] for row in present}) == len(present)
            and len({row["journal"]["path"] for row in present}) == len(present),
            "Concurrent actions shared a handler nonce, native window or private state")
    return matched


def live_holding(mapping, expected_tokens, at):
    if set(mapping) != set(expected_tokens) or any("journal" not in row for row in mapping.values()):
        return False
    leases = set()
    for row in mapping.values():
        receipt = row["command"]["value"]["receipt"]
        result = row["journal"]["value"]
        note = result["concurrency"]
        if receipt.get("status") != "running" or result.get("status") != "running" or note.get("phase") != "holding":
            return False
        require(receipt.get("cancellationRequested") is False and native_uuid(receipt.get("leaseID"))
                and number(receipt.get("leaseExpiresAt"))
                and receipt["leaseExpiresAt"] > at,
                "A supposed overlapping handler has no live uncancelled native lease")
        progress = original._epoch_milliseconds(note.get("reportedProgressAt"))
        require(at - 5000 <= progress <= at, "A holding journal has no fresh actual progress callback")
        leases.add(receipt["leaseID"].lower())
    require(len(leases) == 3, "All three real executor leases must be distinct")
    return True


def overlap(request, first, second, started_at, finished_at):
    """Two live observations with advancing native progress exclude serialized jobs."""
    validate_launches(request, require_all=True)
    require(number(started_at) and number(finished_at) and started_at < finished_at,
            "An actual observation interval is required")
    tokens = invocation_map(request)
    if not live_holding(first, tokens, started_at) or not live_holding(second, tokens, finished_at):
        return None
    rows = {}
    launches = validate_launches(request, require_all=True)
    for token in tokens:
        before, after = first[token], second[token]
        require(before["commandID"] == after["commandID"]
                and before["nonce"] == after["nonce"] and before["windowID"] == after["windowID"]
                and before["journal"]["path"] == after["journal"]["path"]
                and before["command"]["value"]["receipt"]["leaseID"] ==
                    after["command"]["value"]["receipt"]["leaseID"],
                "The handler or actual lease changed during overlap capture")
        p0 = original._epoch_milliseconds(before["journal"]["value"]["concurrency"]["reportedProgressAt"])
        p1 = original._epoch_milliseconds(after["journal"]["value"]["concurrency"]["reportedProgressAt"])
        if p1 <= p0:
            return None
        require(after["command"]["value"]["createdAt"] >=
                original._epoch_milliseconds(launches[token]["requestedAt"]),
                "The native command predates its actual OS launch")
        rows[token] = {"commandID": after["commandID"], "handlerNonce": after["nonce"],
                      "windowID": after["windowID"], "privateStatePath": after["journal"]["path"],
                      "leaseID": after["command"]["value"]["receipt"]["leaseID"],
                      "progressBefore": p0, "progressAfter": p1,
                      "first": before, "second": after}
    return {"schema": 1, "runID": request["runID"], "status": "OVERLAP_OBSERVED",
            "captureStartedAt": started_at, "captureFinishedAt": finished_at,
            "systemLaunches": request["launches"],
            "invocations": rows, "scope": "Three actual handlers with advancing progress and live distinct native leases."}


def require_cancelled_handler_not_completed(request, row):
    journal = row["journal"]["value"]
    require(journal.get("status") in ("running", "failed")
            and journal.get("concurrency", {}).get("phase") in ("holding", "runtimes", "failed"),
            "A native cancellation receipt cannot conceal a successfully completed handler")
    if type(journal.get("receipts")) is list and len(journal["receipts"]) == 5:
        try:
            original._validate_five_receipts(dict(journal, status="completed"), request)
        except ObservationError:
            pass  # Retain an actual partial/failed runtime outcome honestly.
        else:
            raise ObservationError("The cancelled handler completed all five runtimes after Stop")


def terminal(request, mapping, overlap_proof, now):
    require(overlap_proof is not None, "Terminal receipts cannot replace genuine handler overlap")
    expected = invocation_map(request)
    if set(mapping) != set(expected) or any("journal" not in row for row in mapping.values()):
        return None
    launches = validate_launches(request, require_all=True)
    results, execution_ids = {}, set()
    stop = request.get("stop")
    if request["scenario"] == "cancelOne":
        if stop is None:
            return None
        cancelled = request["invocations"][2]
        require(type(stop) is dict and stop.get("token") == cancelled["token"]
                and stop.get("savedShortcutName") == cancelled["savedShortcutName"]
                and stop.get("visibleShortcutName") == cancelled["savedShortcutName"]
                and stop.get("systemStopObserved") is True,
                "Only the visibly selected last-launched Shortcut may be cancelled")
        stop_at = original._epoch_milliseconds(stop.get("requestedAt"))
        stop_after = original._epoch_milliseconds(stop.get("observedAt"))
        require(overlap_proof["captureFinishedAt"] <= stop_at <= stop_after <= now,
                "The actual Stop must follow observed overlap")
    else:
        require(stop is None, "The reverse-completion case must not cancel an action")
    for token, spec in expected.items():
        row = mapping[token]
        original_row = overlap_proof["invocations"][token]
        require(row["commandID"] == original_row["commandID"] and row["nonce"] == original_row["handlerNonce"]
                and row["windowID"] == original_row["windowID"]
                and row["journal"]["path"] == original_row["privateStatePath"],
                "The terminal execution replaced an overlapping handler or window")
        receipt = row["command"]["value"]["receipt"]
        if receipt.get("status") in ("queued", "running"):
            return None
        require(receipt.get("status") == spec["expectedTerminal"]
                and receipt.get("leaseID") is None and receipt.get("leaseExpiresAt") is None
                and number(receipt.get("updatedAt")) and receipt["updatedAt"] <= now,
                "An action has the wrong actual terminal status or retains a lease")
        if spec["expectedTerminal"] == "cancelled":
            require(receipt.get("cancellationRequested") is True and receipt.get("value") is None
                    and receipt["updatedAt"] >= stop_at,
                    "The actual native executor must acknowledge cancellation without a result")
            hold_end = original._epoch_milliseconds(row["journal"]["value"]["startedAt"]) + \
                spec["configuredInput"]["concurrency"]["holdMilliseconds"]
            require(stop_after < hold_end,
                    "The selected system Stop must occur during the proved handler's authored hold")
            require_cancelled_handler_not_completed(request, row)
            # Progress was observed only after the authored hold began. Waiting
            # a full hold after that observation conservatively includes initial
            # journal-write delay; handler entry time alone would underestimate it.
            settled_after = max(hold_end, original_row["progressAfter"] +
                spec["configuredInput"]["concurrency"]["holdMilliseconds"]) + 1000
            if now < settled_after:
                return None
        else:
            require(receipt.get("cancellationRequested") is False and receipt.get("failure") is None,
                    "A successful action cannot conceal cancellation or failure")
            result = original.decode_value(receipt.get("value"))
            if type(result) is str:
                result = original.parse_json(result)
            require(type(result) is dict and equal(result, row["journal"]["value"]),
                    "Actual native returned value differs from its own durable handler result")
            require(result.get("concurrency", {}).get("phase") == "completed",
                    "The handler did not finish its authored invocation")
            ids = original._validate_five_receipts(result, request)
            require(not (ids & execution_ids), "Different invocations reused a runtime execution receipt")
            execution_ids.update(ids)
            require(original._epoch_milliseconds(result.get("finishedAt")) >=
                    original._epoch_milliseconds(result["startedAt"]) +
                    spec["configuredInput"]["concurrency"]["holdMilliseconds"],
                    "The authored hold was not actually observed before completion")
        results[token] = row
    if request["scenario"] == "reverseCompletion":
        tokens = [row["token"] for row in request["invocations"]]
        finished = [original._epoch_milliseconds(results[t]["journal"]["value"]["finishedAt"]) for t in tokens]
        native_finished = [results[t]["command"]["value"]["receipt"]["updatedAt"] for t in tokens]
        require(finished[2] < finished[1] < finished[0]
                and native_finished[2] < native_finished[1] < native_finished[0],
                "Actual handler and native terminal order must be C, B, A")
    return {"schema": 1, "runID": request["runID"], "status": "ACTIONS_COMPLETED",
            "scenario": request["scenario"], "invocations": results, "systemStop": request.get("stop"),
            "runtimeExecutionIDs": sorted(execution_ids), "observedAt": now,
            "scope": "Actual original native receipts after proved overlap; owner callback is still required."}


def owner_completion(request, prepared, owner, terminal_proof, mapping):
    require(set(mapping) == set(terminal_proof["invocations"])
            and len(mapping) == 3 and all("journal" in row for row in mapping.values()),
            "All three actual terminal commands and private journals must still be present")
    require(equal(request.get("stop"), terminal_proof["systemStop"]),
            "The actual selected system Stop observation changed after native completion")
    require(type(request.get("ownerProcessIDAfter")) is int
            and request["ownerProcessIDAfter"] == request["ownerProcessID"]
            and request.get("ownerCallbackObserved") is True,
            "The original owner process must remain alive and execute its real callback")
    require(owner["path"] == prepared["path"] == request["ownerStatePath"],
            "The owner callback changed private state storage")
    state = owner["value"]
    require(state.get("schemaVersion") == 1 and state.get("appID") == request["fixtureAppID"]
            and state.get("challenge") == request["challenge"]
            and type(state.get("counter")) is int and state["counter"] == 1,
            "The original owner did not retain its challenge and increment its private counter once")
    result = state.get("lastResult")
    require(type(result) is dict and result.get("caller") == "proof-ui"
            and equal(result.get("request"), {"surface": "foreground", "fixture": request["fixtureAppID"]}),
            "A real foreground callback from the original fixture UI is required")
    require(original._epoch_milliseconds(result.get("startedAt")) >= terminal_proof["observedAt"]
            and original._epoch_milliseconds(result.get("finishedAt")) >=
                original._epoch_milliseconds(result["startedAt"]),
            "The surviving owner's real callback must execute after native action completion")
    ids = original._validate_five_receipts(result, dict(request, surface="foreground"))
    require(not (ids & set(terminal_proof["runtimeExecutionIDs"])),
            "The owner's callback reused another invocation's runtime receipt")
    samples = result.get("presentationSamples")
    require(type(samples) is list and samples and all(type(row) is dict for row in samples),
            "The owner must expose actual window observations")
    windows = {row.get("windowID") for row in samples}
    require(windows == {request["ownerWindowID"]}
            and all(row.get("statePath") == prepared["path"] and row.get("executionMode") == "foreground"
                    for row in samples) and any(row.get("attached") is True for row in samples),
            "The actual owner callback did not retain its attached foreground window")
    require(not (windows & {row["windowID"] for row in mapping.values()}),
            "A background action replaced the visible owner's native window")
    if "Windows" in Path(prepared["path"]).parts:
        require(Path(prepared["path"]).parts[-4:] ==
                ("Windows", next(iter(windows)), "State", "surface-proof.json"),
                "The original owner's actual window path changed")
    for token, current in mapping.items():
        prior = terminal_proof["invocations"][token]
        require(current["commandID"] == prior["commandID"] and current["nonce"] == prior["nonce"]
                and current["windowID"] == prior["windowID"]
                and current["journal"]["path"] == prior["journal"]["path"],
                "A terminal invocation changed its actual handler, window or private path")
        if prior["command"]["value"]["receipt"]["status"] == "cancelled":
            require_cancelled_handler_not_completed(request, current)
        if prior["command"]["value"]["receipt"]["status"] == "succeeded":
            require(equal(current["journal"]["value"], prior["journal"]["value"]),
                    "A successful private invocation result changed after native completion")
        require(equal(current["command"]["value"], prior["command"]["value"]),
                "A native terminal result changed after the owner callback or late cancellation")
    return {"schema": 1, "runID": request["runID"], "status": "EXECUTED_PASS",
            "scenario": request["scenario"], "ownerProcessID": request["ownerProcessID"],
            "ownerProof": owner, "ownerRuntimeExecutionIDs": sorted(ids),
            "actions": terminal_proof, "scope": "NS owner + three background NS actions on this observed Simulator only."}


def current_identity(request, roots):
    snapshot = original.snapshot_document(roots["extensions"])
    identity = original.action_identity(request, snapshot)
    catalog = original.installed_catalog(roots["data"], identity)
    identity["installedRecord"] = catalog["value"]["packages"][identity["identity"]["installedPackageID"]]["record"]
    identity["catalogSHA256"] = catalog["sha256"]
    return identity


def same_identity(current, initial):
    require(all(equal(current[key], initial[key]) for key in
                ("identity", "appID", "actionID", "actionDisplayName", "hostActionHandler", "installedRecord")),
            "The actual installed generation, action or handler changed")


def verify_roots(args, initial):
    current = original.product_roots(args.device, args.bundle_id)
    require(all(current[key] == initial[key] for key in ROOT_KEYS),
            "Actual product containers or configuration changed during concurrency acceptance")
    return current


def write_response(directory, name, value, evidence):
    require(name in RESPONSES and directory.is_dir() and not directory.is_symlink(),
            "Not a runner-owned concurrency response")
    target = directory / name
    require(not target.exists(), "An observer response must never be overwritten")
    temporary = directory / (name + ".observer-tmp")
    with temporary.open("x") as stream:
        json.dump(value, stream, ensure_ascii=False, sort_keys=True, indent=2)
        stream.write("\n")
    os.replace(temporary, target)
    (evidence / name).write_text(json.dumps(value, ensure_ascii=False, sort_keys=True, indent=2) + "\n")


def observe(args, stopping=lambda: False):
    evidence = Path(args.output).resolve()
    initial_roots = original.product_roots(args.device, args.bundle_id)
    require(all(not evidence.is_relative_to(initial_roots[key]) for key in ("app", "data", "group")),
            "Evidence must be outside production containers")
    evidence.mkdir(parents=True, exist_ok=False)
    apps = original.system_app_observation(args.device, evidence)
    seen, last_error = {}, None
    end = time.monotonic() + args.duration
    while time.monotonic() < end and not stopping():
        case = None
        try:
            runner = original.os_container(args.device, args.runner_bundle_id, "data")
            exchange = runner / "Documents" / EXCHANGE
            active = original.read_document(exchange / "active.json", runner)["value"]
            run_id = active.get("runID")
            require(valid_uuid(run_id), "Invalid active concurrency run")
            directory = exchange / run_id
            request = original.read_document(directory / "request.json", runner)["value"]
            require(request.get("runID") == run_id and request.get("engine") == active.get("engine")
                    and request.get("surface") == active.get("surface"),
                    "Active and per-run concurrency requests differ")
            phase = request.get("phase")
            if phase in ("preparing", "finished"):
                time.sleep(0.25)
                continue
            seal = contract(request)
            case = seen.get(run_id)
            if case is None:
                require(phase == "prepared", "The observer must bind the actual owner before OS launch")
                roots = original.product_roots(args.device, args.bundle_id)
                identity = current_identity(request, roots)
                prepared = original.prepared_proof(request, original.proof_documents(roots["data"], request["fixtureAppID"]))
                require(prepared["path"] == request["ownerStatePath"],
                        "Visible owner state path differs from its actual private preparation")
                case_evidence = evidence / run_id
                case_evidence.mkdir(exist_ok=False)
                case = {"roots": roots, "identity": identity, "prepared": prepared,
                        "baselineIDs": set(original.queue_documents(roots["extensions"])),
                        "contract": seal, "phase": phase, "finished": False, "failed": False,
                        "evidence": case_evidence, "overlap": None, "terminal": None}
                seen[run_id] = case
                response = {"schema": 1, "runID": run_id, "status": "READY",
                            **identity["identity"], **identity, "systemApps": apps,
                            "preparedProof": prepared, "preparedContract": seal,
                            "actualContainers": {key: str(roots[key]) for key in ("app", "data", "group")},
                            "productInfoSHA256": roots["infoSHA256"]}
                write_response(directory, "identity.json", response, case_evidence)
            if case["finished"] or case["failed"]:
                time.sleep(0.25)
                continue
            require(equal(seal, case["contract"]), "Prepared invocation contract changed after admission")
            roots = case["roots"]
            if phase != case["phase"]:
                verify_roots(args, roots)
                case["phase"] = phase
            same_identity(current_identity(request, roots), case["identity"])
            launches = validate_launches(request)
            commands = original.queue_documents(roots["extensions"])
            journals = journal_documents(roots["data"], request["fixtureAppID"])
            mapping = collect(request, case["identity"], case["baselineIDs"], commands, journals)
            if case["terminal"] is None:
                owner = original.read_document(Path(case["prepared"]["path"]), roots["data"])
                require(owner["sha256"] == case["prepared"]["sha256"],
                        "A background action changed the original owner's private state")
            if len(launches) == 3 and case["overlap"] is None:
                before = time.time() * 1000
                if live_holding(mapping, invocation_map(request), before):
                    time.sleep(0.7)
                    current = collect(request, case["identity"], case["baselineIDs"],
                        original.queue_documents(roots["extensions"]),
                        journal_documents(roots["data"], request["fixtureAppID"]))
                    after = time.time() * 1000
                    result = overlap(request, mapping, current, before, after)
                    if result is not None:
                        case["overlap"] = result
                        write_response(directory, "overlap.json", result, case["evidence"])
                    mapping = current
            if case["overlap"] is not None and case["terminal"] is None:
                result = terminal(request, mapping, case["overlap"], time.time() * 1000)
                if result is not None:
                    case["terminal"] = result
                    write_response(directory, "actions-complete.json", result, case["evidence"])
            if phase == "owner-after" and case["terminal"] is not None:
                result = owner_completion(request, case["prepared"],
                    original.read_document(Path(case["prepared"]["path"]), roots["data"]),
                    case["terminal"], mapping)
                # A final fresh native read prevents a stale terminal snapshot from passing.
                final_mapping = collect(request, case["identity"], case["baselineIDs"],
                    original.queue_documents(roots["extensions"]),
                    journal_documents(roots["data"], request["fixtureAppID"]))
                result = owner_completion(request, case["prepared"],
                    original.read_document(Path(case["prepared"]["path"]), roots["data"]),
                    case["terminal"], final_mapping)
                result["overlap"] = case["overlap"]
                verify_roots(args, roots)
                same_identity(current_identity(request, roots), case["identity"])
                write_response(directory, "completion.json", result, case["evidence"])
                case["finished"] = True
            last_error = None
        except (OSError, ValueError, KeyError, TypeError, subprocess.TimeoutExpired) as error:
            if isinstance(error, ObservationError) and case is not None:
                case["failed"] = True
            message = type(error).__name__ + ": " + str(error)
            if message != last_error:
                with (evidence / "observations.jsonl").open("a") as stream:
                    stream.write(json.dumps({"at": time.time(), "error": message,
                                             "runFailed": bool(case and case["failed"])}) + "\n")
                last_error = message
        time.sleep(0.25)
    (evidence / "observer.json").write_text(json.dumps({
        "status": "OBSERVER_FINISHED", "scope": "Read-only coordination; the actual XCTest owns OS acceptance",
        "runs": {key: {"completionWritten": value["finished"], "failed": value["failed"]}
                 for key, value in seen.items()}, "lastObservationError": last_error}, indent=2) + "\n")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--device", required=True)
    parser.add_argument("--runner-bundle-id", required=True)
    parser.add_argument("--bundle-id", default="com.itorah.hanlinminiapps", choices=["com.itorah.hanlinminiapps"])
    parser.add_argument("--output", required=True)
    parser.add_argument("--duration", type=float, default=1500)
    args = parser.parse_args()
    require(0 < args.duration <= 7200, "Observer lifetime must be bounded")
    require(args.runner_bundle_id.endswith(".xctrunner"), "An actual XCTest runner bundle is required")
    stopping = [False]
    signal.signal(signal.SIGTERM, lambda signum, frame: stopping.__setitem__(0, True))
    signal.signal(signal.SIGINT, lambda signum, frame: stopping.__setitem__(0, True))
    observe(args, stopping=lambda: stopping[0])


if __name__ == "__main__":
    main()
