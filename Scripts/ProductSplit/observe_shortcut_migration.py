"""Read-only evidence for one genuine old-five/current-nine saved Shortcut.

The UI creates/imports only before baseline. This reader requires two real
native commands and private results, actual saved editor and Show Result
readback, and the separate setup process's single verified in-place upgrade.
"""
from pathlib import Path
import json
import os
import re
import time
import uuid

import shortcut_migration_contract as contract
import observe_shortcut_surfaces as shared
import observe_shortcut_native_lists as lists
import observe_shortcut_long_running as products
import observe_share_translation_surfaces as archive_binding

require = shared.require


def current_inputs(args, evidence, stage):
    path = Path(args.migration_inputs)
    require(path == evidence.parent / "shortcut-migration-inputs.json",
            "Migration inputs are outside their owned attempt")
    document = shared.read_document(path, evidence.parent)
    value = document["value"]
    require(value.get("schema") == 1 and value.get("scope") in contract.SCOPES
            and contract.SCOPES[value["scope"]] == value.get("engine")
            and value.get("device") == args.device
            and value.get("runnerBundleID") == args.runner_bundle_id
            and value.get("expectedMethod") == contract.METHODS[value["engine"]],
            "Migration input scope/source/device differs")
    root = Path(value["root"])
    require(contract.git(root, "rev-parse", "HEAD").decode().strip() == value["sourceSHA"]
            and set(value["sourceFiles"]) == set(contract.source_files(value["engine"]))
            and all(contract.file_record(root / name) == row for name, row in value["sourceFiles"].items()),
            "The exact migration source closure changed")
    contract.checked_file(value["oldAdmission"])
    archive = contract.checked_file(value["archive"])
    require(archive == evidence.parent / "shortcut-migration-fixture" /
            lists.engine_contract(value["engine"])["archive"], "The once-imported archive changed")
    contract.descriptor_current(value["descriptor"])
    runner = shared.os_container(args.device, args.runner_bundle_id, "app")
    relative = Path(value["testRelativePath"])
    require(relative == Path("PlugIns/AI_HLYUITests.xctest")
            and products.product_records(runner) == value["runner"]
            and products.product_records(runner / relative) == value["test"],
            "The actual current UI runner/test product changed")
    roots = shared.product_roots(args.device, contract.APP)
    require(contract.same_product(contract.product(roots["app"], stage), value[stage]),
            "The installed app is not the admitted " + stage + " product")
    return document, roots


def terminal_result(request, identity, baseline_ids, commands, armed_at):
    expected = contract.expected_values(request["runID"])
    contract.saved_editor(request)
    engine = request["engine"]; engine_contract = lists.engine_contract(engine)
    matches = []
    for command_id, document in commands.items():
        row = document["value"]; invocation = row.get("invocation", {})
        if command_id in baseline_ids or invocation.get("identity") != identity["identity"] \
                or invocation.get("entityID") != lists.ACTION:
            continue
        require(type(row.get("createdAt")) in (int, float) and row["createdAt"] >= armed_at,
                "The migration command predates its actual saved-Shortcut arm")
        contract.native_values(invocation.get("parameters"), request["runID"])
        matches.append((command_id, document))
    require(len(matches) <= 1, "The saved migration action executed more than once in this phase")
    if not matches:
        return None
    command_id, document = matches[0]
    row = document["value"]; invocation = row["invocation"]; receipt = row["receipt"]
    if receipt.get("status") in ("queued", "running"):
        return None
    require(receipt.get("status") == "succeeded" and receipt.get("failure") is None
            and receipt.get("cancellationRequested") is False and receipt.get("leaseID") is None
            and receipt.get("leaseExpiresAt") is None
            and type(receipt.get("attempt")) is int and receipt["attempt"] == 1,
            "The genuine migration action did not succeed once without cancellation or a retained lease")
    delivery = invocation.get("delivery", {})
    require(delivery.get("schemaVersion") == 1 and delivery.get("appID") == engine_contract["appID"]
            and delivery.get("source") == "shortcuts" and delivery.get("userGesturePresent") is True
            and delivery.get("canPresentUI") is False and invocation.get("continueInForeground") is False,
            "The saved action changed its real Shortcuts/background delivery")
    result = shared.decode_value(receipt.get("value"))
    if type(result) is str:
        result = shared.parse_json(result)
    require(type(result) is dict and result.get("schema") == 1
            and result.get("appID") == engine_contract["appID"] and result.get("actionID") == lists.ACTION,
            "The actual returned result belongs to another fixture/action")
    lists.result_values(result.get("values"), expected)
    require(result.get("observedTypes") == ["string", "string", "number", "number", "boolean", "boolean"],
            "The real handler received different scalar types")
    require(type(result.get("nonce")) is str and re.fullmatch(r"[a-z0-9]+-[a-z0-9]+", result["nonce"]),
            "The actual handler result is not fresh nonce-bound")
    if engine == "nativescript":
        require(type(result.get("caller")) is str and result["caller"]
                and result.get("executionMode") == "headless-action" and result.get("attached") is False,
                "The actual NativeScript saved action did not remain headless")
        require(type(result.get("windowID")) is str
                and re.fullmatch(r"[A-Za-z0-9_-]{1,128}", result["windowID"]),
                "The actual NativeScript window identity is missing")
    else:
        require(result.get("caller") == "hanlin.host"
                and type(result.get("invocationID")) is str
                and str(uuid.UUID(result["invocationID"])) == command_id.lower()
                and result.get("stateFile") == "native-list-" + result["nonce"] + ".json",
                "The Expo private result is not bound to this real native command")
    require(shared._epoch_milliseconds(result.get("observedAt")) >= armed_at,
            "The real handler result predates this saved Shortcut execution")
    return {"invocationID": command_id, "command": document, "result": result}


def write_reply(directory, evidence, filename, value):
    require(re.fullmatch(r"identity\.json|armed-[01]\.json|completion-[01]\.json|baseline\.json|upgraded\.json|completion\.json", filename),
            "Unknown migration reply")
    require(directory.is_dir() and not directory.is_symlink()
            and not (directory / filename).exists(), "Migration replies must be new and owned")
    temporary = directory / (filename + ".migration-tmp")
    with temporary.open("x", encoding="utf-8") as stream:
        json.dump(value, stream, ensure_ascii=False, sort_keys=True, indent=2, allow_nan=False)
        stream.write("\n")
    os.replace(temporary, directory / filename)
    with (evidence / filename).open("xb") as retained:
        retained.write((directory / filename).read_bytes())


def same_installation(case, roots, identity, installed, inputs):
    require(case["inputsSHA256"] == inputs["sha256"] and case["identity"] == identity
            and shared.equal_typed_json(case["installed"], installed)
            and case["containers"] == {key: str(roots[key]) for key in ("data", "group", "extensions")},
            "The saved package, generation, source or actual containers changed")


def complete_upgrade(args, request, directory, evidence, case, inputs):
    path = evidence.parent / "migration-upgrade-result.json"
    if not path.exists():
        return False
    outcome = shared.read_document(path, evidence.parent)
    value = outcome["value"]
    prefix = {"schema": 1, "runID": request["runID"]}
    if value.get("status") != "UPGRADED":
        write_reply(directory, evidence / request["runID"], "upgraded.json",
                    {**prefix, "status": "FAILED", "actualSetupOutcome": outcome})
        case["upgradeFailure"] = outcome
        return True
    require(value.get("runID") == request["runID"] and value.get("device") == args.device
            and value.get("engine") == request["engine"] and value.get("installCount") == 1
            and value.get("inputsSHA256") == inputs["sha256"]
            and value.get("identity") == case["identity"]
            and value.get("containers") == case["containers"]
            and value.get("shortcutsData") == case["shortcutsData"],
            "The actual upgrade belongs to another source/device/installation")
    current, roots = current_inputs(args, evidence, "current")
    identity, catalog = lists.current_identity(roots, request["engine"])
    installed = archive_binding.verify_installed_fixture_archive(
        roots["data"], identity["identity"], catalog, current["value"]["archive"], evidence.parent)
    same_installation(case, roots, identity, installed, current)
    baseline = case["steps"][0]
    require(shared.read_document(Path(baseline["privateProof"]["path"]), roots["data"]) == baseline["privateProof"],
            "The real baseline result did not survive the actual upgrade")
    require(str(shared.os_container(args.device, "com.apple.shortcuts", "data")) == case["shortcutsData"],
            "The actual Shortcuts data container changed")
    case["upgrade"] = outcome
    case["actualRoots"] = roots
    write_reply(directory, evidence / request["runID"], "upgraded.json",
                {**prefix, "status": "UPGRADED", "actualSetupOutcome": outcome,
                 "oldParameterCount": 5, "currentParameterCount": 9,
                 "identity": identity, "preservedBaseline": baseline["privateProof"]})
    return True


def observe_case(args, request, directory, evidence, seen):
    run_id = request.get("runID")
    contract.expected_values(run_id)
    engine = request.get("engine")
    require(engine in contract.METHODS and request.get("schema") == 1
            and request.get("surface") == contract.SURFACE
            and request.get("testMethod") == contract.METHODS[engine]
            and request.get("fixtureAppID") == lists.engine_contract(engine)["appID"],
            "Unknown genuine migration case")
    shared._epoch_milliseconds(request.get("startedAt"))
    phase = request.get("phase")
    case = seen.get(run_id)
    if case is not None:
        require(request["engine"] == case["engine"] and request["startedAt"] == case["startedAt"]
                and str(directory) == case["directory"], "The migration case identity changed")
        if case["phase"] == phase and phase not in ("migration-sent", "migration-upgrade-requested"):
            return
        if case["phase"] == phase == "migration-upgrade-requested":
            if case.get("upgrade") is None and case.get("upgradeFailure") is None:
                complete_upgrade(args, request, directory, evidence, case, case["inputs"])
            return
    stage = "current" if case is not None and case.get("upgrade") is not None else "old"
    # Pending command polling reuses the admitted inputs; a real terminal is
    # admitted again from current installed bytes before any completion reply.
    pending = case is not None and phase == case["phase"] == "migration-sent"
    if pending:
        inputs, roots, identity, installed = (case[key] for key in ("inputs", "actualRoots", "identity", "installed"))
    else:
        inputs, roots = current_inputs(args, evidence, stage)
        require(inputs["value"]["engine"] == engine, "The engine differs from its separately owned device")
        identity, catalog = lists.current_identity(roots, engine)
        installed = archive_binding.verify_installed_fixture_archive(
            roots["data"], identity["identity"], catalog, inputs["value"]["archive"], evidence.parent)
    commands = shared.queue_documents(roots["extensions"])
    prefix = {"schema": 1, "runID": run_id}
    if case is None:
        require(phase == "migration-installed" and not seen,
                "This fresh owned device accepts exactly one old-to-new case")
        target = evidence / run_id; target.mkdir()
        own = [key for key, row in commands.items()
               if row["value"].get("invocation", {}).get("identity") == identity["identity"]]
        require(not own, "The fresh old fixture already has an action execution")
        shortcuts_data = shared.os_container(args.device, "com.apple.shortcuts", "data")
        case = {"engine": engine, "startedAt": request["startedAt"], "directory": str(directory),
                "phase": phase, "identity": identity, "installed": installed,
                "containers": {key: str(roots[key]) for key in ("data", "group", "extensions")},
                "shortcutsData": str(shortcuts_data), "inputsSHA256": inputs["sha256"],
                "inputs": inputs, "actualRoots": roots, "steps": [], "armed": None,
                "initialIDs": set(commands), "upgrade": None, "finished": False}
        seen[run_id] = case
        write_reply(directory, target, "identity.json", {**prefix, "status": "READY", **identity,
            "systemApps": shared.system_app_observation(args.device, target),
            "inputManifest": inputs, "installedFixture": installed,
            "baselineProduct": inputs["value"]["old"], "oldParameterCount": 5})
        return
    same_installation(case, roots, identity, installed, inputs)
    target = evidence / run_id
    if phase == "migration-arm":
        step = request.get("step")
        require(type(step) is int and step == len(case["steps"]) and step in (0, 1)
                and case["armed"] is None and (step == 0 or case["upgrade"] is not None),
                "Saved migration executions must arm once in old/upgrade/current order")
        editor = contract.saved_editor(request)
        require(editor["actionElement"]["label"] == identity["actionDisplayName"],
                "The reopened Shortcut displays another actual installed action")
        own = {key for key, row in commands.items()
               if row["value"].get("invocation", {}).get("identity") == identity["identity"]
               and row["value"]["invocation"].get("entityID") == lists.ACTION}
        require(own == {row["invocationID"] for row in case["steps"]},
                "An extra fixture action executed outside its two armed runs")
        if step == 1:
            baseline_editor = case["steps"][0]["editor"]
            require(editor["rawInput"] == baseline_editor["rawInput"]
                    and editor["savedShortcutName"] == baseline_editor["savedShortcutName"]
                    and editor["inputMode"] == baseline_editor["inputMode"]
                    and editor["actionElement"]["label"] == baseline_editor["actionElement"]["label"],
                    "The existing saved action/input was rewritten or replaced after upgrade")
        at = time.time() * 1000
        case["armed"] = {"step": step, "baseline": set(commands), "at": at,
                         "editor": editor, "savedShortcutName": request["savedShortcutName"]}
        write_reply(directory, target, f"armed-{step}.json",
                    {**prefix, "status": "ARMED", "step": step, "observedAtMilliseconds": at})
    elif phase == "migration-sent":
        arm = case["armed"]
        require(arm is not None and request.get("step") == arm["step"]
                and request.get("editor") == arm["editor"]
                and request.get("savedShortcutName") == arm["savedShortcutName"]
                and request.get("systemLaunchObserved") is True, "The actual armed saved UI launch changed")
        if arm.get("terminal") is not None:
            return
        result = terminal_result(request, identity, arm["baseline"], commands, arm["at"])
        if result is None:
            case["phase"] = phase
            return
        fresh_inputs, fresh_roots = current_inputs(args, evidence, stage)
        fresh_identity, fresh_catalog = lists.current_identity(fresh_roots, engine)
        fresh_installed = archive_binding.verify_installed_fixture_archive(
            fresh_roots["data"], fresh_identity["identity"], fresh_catalog,
            fresh_inputs["value"]["archive"], evidence.parent)
        same_installation(case, fresh_roots, fresh_identity, fresh_installed, fresh_inputs)
        payload = result["result"]
        private = lists.result_document(fresh_roots, identity, payload, engine)
        require(lists.json_equal(private["value"], payload),
                "The native migration result differs from its invocation-owned private file")
        require(all(old["result"]["nonce"] != payload["nonce"] for old in case["steps"]),
                "The post-upgrade execution reused a baseline result")
        arm["terminal"] = {**result, "privateProof": private, "step": arm["step"], "editor": arm["editor"]}
        write_reply(directory, target, f"completion-{arm['step']}.json",
                    {**prefix, "status": "EXECUTED_PASS", **arm["terminal"]})
    elif phase == "migration-chain-read":
        arm = case["armed"]
        require(arm is not None and arm.get("terminal") is not None
                and request.get("step") == arm["step"], "The real native terminal must precede Show Result")
        require(lists.json_equal(request.get("renderedResult"), arm["terminal"]["result"])
                and request.get("builtInChain") == ["Get Text from Input", "Show Result"],
                "Actual Get Text/Show Result readback differs from this invocation")
        require(request.get("shortcutsForeground") is True and request.get("miniAppsForeground") is False,
                "The actual completed saved action changed its background presentation")
        case["steps"].append(arm["terminal"]); case["armed"] = None
        if arm["step"] == 0:
            write_reply(directory, target, "baseline.json",
                        {**prefix, "status": "BASELINE_VERIFIED", "terminal": arm["terminal"]})
        else:
            require(len(case["steps"]) == 2
                    and len({row["invocationID"] for row in case["steps"]}) == 2
                    and case["upgrade"] is not None, "Both genuine old/current executions are required")
            write_reply(directory, target, "completion.json",
                        {**prefix, "status": "EXECUTED_PASS", "nativeExecutions": 2,
                         "steps": case["steps"], "actualUpgrade": case["upgrade"],
                         "sameInstalledIdentity": identity,
                         "scope": "One saved legacy JSON-array Shortcut across a genuine old-five/current-nine upgrade on " + engine})
            case["finished"] = True
    elif phase == "migration-upgrade-requested":
        require(len(case["steps"]) == 1 and case["armed"] is None and case["upgrade"] is None
                and request.get("step") == 0,
                "A complete baseline and real termination must precede the one upgrade")
        termination = contract.terminated_apps(request)
        baseline = case["steps"][0]
        require(shared._epoch_milliseconds(request.get("observedAt")) >= baseline["command"]["value"]["createdAt"],
                "The upgrade request predates its native baseline")
        request_document = shared.read_document(directory / "request.json", directory)
        require(request_document["value"] == request, "The actual UI upgrade request changed")
        authorization = {**prefix, "status": "BASELINE_AND_UI_TERMINATION_VERIFIED",
            "device": args.device, "engine": engine, "inputsSHA256": inputs["sha256"],
            "requestSHA256": request_document["sha256"], "identity": identity,
            "termination": termination, "containers": case["containers"], "shortcutsData": case["shortcutsData"],
            "baselineInvocationID": baseline["invocationID"], "baselineCommand": baseline["command"],
            "baselinePrivate": baseline["privateProof"], "at": time.time()}
        path = evidence.parent / "migration-upgrade-authorization.json"
        require(not path.exists() and not path.is_symlink(), "An upgrade authorization already exists")
        temporary = path.with_name(path.name + ".observer-tmp")
        with temporary.open("x", encoding="utf-8") as stream:
            json.dump(authorization, stream, ensure_ascii=False, sort_keys=True, indent=2, allow_nan=False)
            stream.write("\n")
        # Publish a complete authorization atomically, as the original XCTest
        # exchange does. The sole reader must never see a partially written JSON.
        os.replace(temporary, path)
    else:
        raise shared.ObservationError("Unexpected genuine migration phase")
    case["phase"] = phase
