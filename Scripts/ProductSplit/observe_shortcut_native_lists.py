"""Read-only correlation for four real native-list Shortcuts, twice per case.

XCTest alone edits, saves, reopens, clears and runs the real system Shortcut.
This reader writes only attempt evidence and the XCTest-owned exchange. Native
integer/number tags are inspected in the original command; JS typeof/JSON alone
cannot establish that distinction. Each engine is a separate four-case scope;
pre-change saved-action migration remains a separate obligation.
"""
from pathlib import Path
import hashlib
import json
import math
import os
import re
import subprocess
import time
import uuid

import observe_shortcut_surfaces as shared
import observe_shortcut_long_running as products
import observe_share_translation_surfaces as archive_binding
from observe_shortcut_concurrency import same_private_path

require = shared.require
equal = shared.equal_typed_json
APP_ID = "hanlin.shortcutlists.nativescript"
ACTION = "native-lists.echo"
ENTRYPOINT = "native-lists-intent"
SCOPE = "miniapp_native_lists_nativescript_os"
FIXTURE = "Fixtures/ShortcutNativeLists/nativescript"
ARCHIVE = "NativeListsNativeScript.hanlinNativeScript"
FIXTURE_FILES = ("package.json", "script.json", "tsconfig.json", "hanlin.authoring.json", "index.ts", "proof.ts")
KINDS = {
    "text": ("textList", "Text List", "textItems", "string", 0),
    "integer": ("integerList", "Integer List", "integerItems", "integer", 2),
    "number": ("numberList", "Number List", "numberItems", "number", 7),
    "boolean": ("booleanList", "Boolean List", "booleanItems", "bool", 1),
}
METHODS = {
    kind: "testNativeScriptSaved" + kind.title() + "ListReopensThenClearsToEmpty"
    for kind in KINDS
}
SOURCE_FILES = tuple(FIXTURE + "/" + name for name in FIXTURE_FILES) + (
    "AI_HLYUITests/HanlinEntrypointSystemSurfaceUITests.swift",
    "HanlinMiniAppsApp/MiniAppsShortcutIntent.swift",
    "Packages/HanlinPlatform/Sources/HanlinPlatformContracts/HanlinValue.swift",
    "Packages/HanlinPlatform/Sources/HanlinPlatformContracts/HanlinShortcutValueCodec.swift",
    "Scripts/MiniApps/miniapp.mjs",
    "AI_HLY/Downstream/RuntimeCore/Node/Host/miniapp-authoring.mjs",
    "Scripts/ProductSplit/run_paired_acceptance.py",
    "Scripts/ProductSplit/observe_shortcut_native_lists.py",
    "Scripts/ProductSplit/observe_shortcut_surfaces.py",
    "Scripts/ProductSplit/observe_shortcut_long_running.py",
    "Scripts/ProductSplit/observe_share_translation_surfaces.py",
    "Scripts/CI/Tests/test_shortcut_native_lists.py",
    "Scripts/CI/Tests/fixtures/native_lists_actionsdata.json",
)


# Keep the original NativeScript scope/fixtures independently selectable.
# Host storage and channel sources bind the different engine-owned evidence.
SHARED_SOURCE_FILES = SOURCE_FILES[len(FIXTURE_FILES):] + (
    "Scripts/ProductSplit/observe_shortcut_concurrency.py",
)
SOURCE_FILES = tuple(FIXTURE + "/" + name for name in FIXTURE_FILES) + SHARED_SOURCE_FILES + (
    "AI_HLY/Downstream/HostServices/Adapters/NativeScriptHostServicesAdapter.swift",
    "Packages/HanlinNativeScriptRuntime/Sources/HanlinNativeScriptRuntime/HanlinNativeScriptWindowSession.swift",
    "Packages/HanlinNativeScriptRuntime/Sources/HanlinNativeScriptRuntime/Resources/NativeScriptSharedRuntime/@hanlin/window-factory/index.mjs",
)
EXPO_FIXTURE_FILES = ("package.json", "script.json", "tsconfig.json", "hanlin.authoring.json",
                      "index.ts", "proof.ts", "App.tsx")
EXPO_METHODS = {
    kind: "testExpoSaved" + kind.title() + "ListReopensThenClearsToEmpty"
    for kind in KINDS
}
ENGINE_CONTRACTS = {
    "nativescript": {"scope": SCOPE, "appID": APP_ID, "fixture": FIXTURE, "archive": ARCHIVE,
                     "fixtureFiles": FIXTURE_FILES, "methods": METHODS,
                     "handler": "nativescript/app/bundle.mjs"},
    "expo": {"scope": "miniapp_native_lists_expo_os", "appID": "hanlin.shortcutlists.expo",
             "fixture": "Fixtures/ShortcutNativeLists/expo", "archive": "NativeListsExpo.hanlinExpo",
             "fixtureFiles": EXPO_FIXTURE_FILES, "methods": EXPO_METHODS, "handler": "bundle.js"},
}


def engine_contract(engine):
    require(type(engine) is str and engine in ENGINE_CONTRACTS, "Unknown native-list engine")
    return ENGINE_CONTRACTS[engine]


def source_files(engine):
    contract = engine_contract(engine)
    if engine == "nativescript":
        return SOURCE_FILES
    return tuple(contract["fixture"] + "/" + name for name in contract["fixtureFiles"]) + SHARED_SOURCE_FILES + (
        "Packages/HanlinExpoUI/src/miniapp-actions.ts",
        "Packages/HanlinExpoUI/src/host-services.ts",
        "AI_HLY/Downstream/HostServices/Adapters/ExpoHostServicesAdapter.swift",
        "AI_HLY/Downstream/HostServices/Core/HanlinHostCallContext.swift",
        "AI_HLY/Downstream/HostServices/Data/HanlinFileService.swift",
        "Packages/HanlinPlatform/Sources/HanlinMiniAppCore/HanlinMiniAppActionChannel.swift",
        "AI_HLY/Downstream/ScriptingPlatform/HanlinScriptingPlatform.swift",
        "AI_HLY/Downstream/MiniApps/HanlinMiniAppHost.swift",
    )


def expected_values(kind, run_id, step):
    require(kind in KINDS and type(step) is int and step in (0, 1), "Unknown native list case/step")
    require(isinstance(run_id, str) and str(uuid.UUID(run_id)) == run_id, "Invalid case UUID")
    if step == 1:
        return []
    return {"text": ["שלום", "汉字", run_id], "integer": [-7, 0, 42],
            "number": [-1.25, 0.5, 42.125], "boolean": [True, False]}[kind]


def native_input(encoded, kind, expected):
    require(isinstance(encoded, dict) and encoded.get("type") == "array"
            and set(encoded) == {"type", "value"} and type(encoded["value"]) is list,
            "The original command must carry an actual canonical array")
    require(all(isinstance(item, dict) and item.get("type") == KINDS[kind][3]
                for item in encoded["value"]), "The native array's canonical element tag differs")
    actual = shared.decode_value(encoded)
    require(equal(actual, expected), "Native list values/order or empty clearing differ")
    return actual


def result_values(actual, expected):
    # JSON/JS has one numeric domain. Input native tags are checked separately.
    require(type(actual) is list and len(actual) == len(expected), "Result list count differs")
    for left, right in zip(actual, expected):
        if type(right) in (int, float):
            require(type(left) in (int, float) and math.isfinite(left) and left == right,
                    "Returned numeric value differs")
        else:
            require(type(left) is type(right) and left == right, "Returned scalar type/value differs")


def json_equal(left, right):
    # JSON result readback has one numeric domain; never coerce booleans.
    if type(left) in (int, float) and type(right) in (int, float):
        return math.isfinite(left) and math.isfinite(right) and left == right
    if type(left) is not type(right):
        return False
    if type(left) is dict:
        return left.keys() == right.keys() and all(json_equal(left[k], right[k]) for k in left)
    if type(left) is list:
        return len(left) == len(right) and all(json_equal(a, b) for a, b in zip(left, right))
    return left == right


def metadata_contract(document):
    actions = document.get("actions")
    require(type(actions) is dict, "Actual compiled AppIntents action dictionary is absent")
    rows = [row for name, row in actions.items() if name == "HanlinRunMiniAppShortcutIntent"
            and isinstance(row, dict) and row.get("identifier") == name]
    require(len(rows) == 1, "Exactly one actual Run MiniApp Action metadata entry is required")
    action = rows[0]
    parameters = action.get("parameters", [])
    by_name = {row.get("name"): row for row in parameters}
    require(len(parameters) == len(by_name) == 9 and set(by_name) == {
        "action", "inputType", "input", "jsonFile", "allowLongRunning",
        "textItems", "integerItems", "numberItems", "booleanItems"}, "Shipping parameter set changed")
    cases = action["actionConfiguration"]["switchStatement"]["wrapper"]
    require(cases["parameterIdentifier"] == "inputType", "The actual list Switch selects another parameter")
    for mode, label, name, _, primitive in KINDS.values():
        row = by_name[name]
        require(row.get("isOptional") is True and row["title"]["key"] == label
                and row["valueType"]["array"]["wrapper"]["memberValueType"]
                ["primitive"]["wrapper"]["typeIdentifier"] == primitive, "Native array metadata differs")
        matches = [case for case in cases["cases"] if not case.get("isDefaultCase") and
                   case["value"]["array"]["values"] == [
                       {"enumeration": {"identifier": "MiniAppsShortcutInputType", "value": mode}}]]
        require(len(matches) == 1 and matches[0]["configuration"]["actionSummary"]["wrapper"]
                ["summaryString"]["parameterIdentifiers"] == ["action", name], "Actual list summary differs")
    require(sum(case.get("isDefaultCase") is True for case in cases["cases"]) == 1,
            "The original default summary is missing")
    return {"identifier": action["identifier"], "parameters": parameters, "switch": cases}


def file_record(path):
    return products.file_record(path)


def create_inputs(root, evidence, runner, test, state, simulator, engine="nativescript"):
    contract = engine_contract(engine)
    root, evidence, runner, test = (Path(p).resolve(strict=True) for p in (root, evidence, runner, test))
    require(subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=root, text=True).strip() == state["sha"],
            "Current source HEAD differs from original runner")
    source_rows = {name: file_record(root / name) for name in source_files(engine)}
    for name, row in source_rows.items():
        raw = subprocess.check_output(["git", "show", state["sha"] + ":" + name], cwd=root)
        require(shared.digest(raw) == row["sha256"], "A native-list source differs from admitted Git")
    built = state["native_list_fixtures"]
    require(built["status"] == "BUILT_AND_STAGED_INPUTS_ONLY" and len(built["archives"]) == 1
            and built["archives"][0]["engine"] == engine
            and built["archives"][0]["archive"] == contract["archive"],
            "The original single-fixture CLI did not succeed")
    archive = evidence / "shortcut-native-list-fixture" / contract["archive"]
    require(file_record(archive)["sha256"] == built["archives"][0]["archiveSHA256"],
            "Produced native-list archive changed")
    app = runner.parent / "HanlinMiniApps.app"
    metadata = list(app.glob("Metadata.appintents/extract.actionsdata"))
    require(len(metadata) == 1, "The actual standalone product metadata is missing")
    meta = shared.read_document(metadata[0], app)
    value = {
        "schema": 1, "scope": contract["scope"], "engine": engine, "device": simulator, "sourceSHA": state["sha"],
        "root": str(root), "sourceFiles": source_rows,
        "archive": {"path": str(archive), **file_record(archive)},
        "fixture": built, "app": products.product_records(app),
        "runner": products.product_records(runner), "test": products.product_records(test),
        "testRelativePath": test.relative_to(runner).as_posix(),
        "metadataRelativePath": metadata[0].relative_to(app).as_posix(),
        "metadataFile": file_record(metadata[0]), "metadataContract": metadata_contract(meta["value"]),
        "expectedCases": contract["methods"],
    }
    path = evidence / "shortcut-native-lists-inputs.json"
    with path.open("x") as stream:
        json.dump(value, stream, ensure_ascii=False, indent=2, sort_keys=True); stream.write("\n")
    return {"path": str(path), **file_record(path)}


def current_inputs(args, evidence, roots, engine="nativescript"):
    contract = engine_contract(engine)
    path = Path(args.native_list_inputs)
    require(path == evidence.parent / "shortcut-native-lists-inputs.json", "Manifest is outside owned attempt")
    document = shared.read_document(path, evidence.parent)
    value = document["value"]
    require(value.get("schema") == 1 and value.get("scope") == contract["scope"]
            and value.get("engine") == engine and value.get("device") == args.device
            and value.get("expectedCases") == contract["methods"], "Native-list input manifest differs")
    root = Path(value["root"]).resolve(strict=True)
    require(set(value["sourceFiles"]) == set(source_files(engine)), "Incomplete source closure")
    require(subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=root, text=True).strip() == value["sourceSHA"],
            "Source HEAD changed during acceptance")
    require(all(file_record(root / name) == row for name, row in value["sourceFiles"].items()),
            "Actual native-list source changed")
    require(value["archive"]["path"] == str(evidence.parent / "shortcut-native-list-fixture" / contract["archive"])
            and file_record(Path(value["archive"]["path"]))["sha256"] == value["archive"]["sha256"],
            "Original archive binding changed")
    runner = shared.os_container(args.device, args.runner_bundle_id, "app")
    relative = Path(value["testRelativePath"])
    require(len(relative.parts) == 2 and relative.parts[0] == "PlugIns"
            and relative.name == "AI_HLYUITests.xctest", "Unexpected test bundle")
    require(products.product_records(roots["app"]) == value["app"]
            and products.product_records(runner) == value["runner"]
            and products.product_records(runner / relative) == value["test"], "Installed product/test bytes changed")
    metadata = roots["app"] / "Metadata.appintents/extract.actionsdata"
    require(value["metadataRelativePath"] == "Metadata.appintents/extract.actionsdata"
            and file_record(metadata) == value["metadataFile"], "Installed intent metadata changed")
    require(metadata_contract(shared.read_document(metadata, roots["app"])["value"]) == value["metadataContract"],
            "Installed native parameter metadata changed")
    return document


def _identity_rejection_details(row, snapshot, contract):
    # Only failed admission reaches this bounded, identity-only observation.
    # Unknown row values and the user's display text are never serialized.
    def field(value):
        result = {"type": type(value).__name__}
        if type(value) is str:
            result.update(value=value[:64], characters=len(value), truncated=len(value) > 64)
        elif type(value) is int:
            result["isUInt64"] = 0 <= value <= 18446744073709551615
            if result["isUInt64"]:
                result["value"] = value
        elif type(value) is bool:
            result["value"] = value
        return result

    keys = ("installedPackageID", "packageID", "generation", "entrypointID", "variantID")
    identity = row["identity"]
    details = {
        "schema": 1, "snapshotSHA256": snapshot["sha256"],
        "expected": {"appID": contract["appID"], "actionID": ACTION, "entrypointID": ENTRYPOINT,
                     "hostActionHandler": "source/" + contract["handler"]},
        "actual": {
            "identityFieldCount": len(identity),
            "unexpectedIdentityFieldCount": sum(key not in keys for key in identity),
            "identity": {key: {"present": key in identity, **field(identity.get(key))} for key in keys},
            "hostActionHandler": field(row.get("hostActionHandler")),
            "displayName": {"type": type(row.get("displayName")).__name__,
                            "nonempty": type(row.get("displayName")) is str and bool(row["displayName"])},
        },
    }
    # Six actual string values, each at most 64 Unicode characters, keep this
    # complete ASCII JSON below 8 KiB even for escaped non-BMP code points.
    return json.dumps(details, ensure_ascii=True, separators=(",", ":"), sort_keys=True)


def current_identity(roots, engine="nativescript"):
    contract = engine_contract(engine)
    snapshot = shared.snapshot_document(roots["extensions"])
    rows = [row for row in snapshot["value"]["snapshot"].get("intentEntities", [])
            if row.get("appID") == contract["appID"] and row.get("id") == ACTION
            and row.get("identity", {}).get("entrypointID") == ENTRYPOINT]
    require(len(rows) == 1, "The actual installed native-list action is missing or ambiguous")
    row = rows[0]
    identity = row["identity"]
    try:
        require(set(identity) == {"installedPackageID", "packageID", "generation", "entrypointID", "variantID"}
                and all(type(identity[k]) is str and identity[k] for k in identity if k != "generation")
                and type(identity["generation"]) is int and identity["generation"] > 0
                and type(row.get("displayName")) is str and row["displayName"]
                and row.get("hostActionHandler") == "source/" + contract["handler"], "Invalid action identity")
    except shared.ObservationError as error:
        raise shared.ObservationError(str(error) + "; " + _identity_rejection_details(row, snapshot, contract)) from error
    result = {"identity": identity, "appID": contract["appID"], "actionID": ACTION,
              "actionDisplayName": row["displayName"], "hostActionHandler": row["hostActionHandler"]}
    catalog = shared.installed_catalog(roots["data"], result)
    return result, catalog


def validate_editor(request, step):
    kind = request["listKind"]
    mode, label, parameter, _, _ = KINDS[kind]
    editor = request.get("editor")
    expected = expected_values(kind, request["runID"], step)
    require(type(editor) is dict and editor.get("inputMode") == mode and editor.get("parameter") == parameter
            and editor.get("label") == label and editor.get("savedAndReopened") is True
            and editor.get("processRestarted") is True and editor.get("openWhenRun") is False,
            "A real saved/reopened native array and background mode are required")
    require(equal(editor.get("values"), expected) and editor.get("rowCount") == len(expected),
            "Actual reopened native editor values differ")
    require(type(editor.get("rawRows")) is list and len(editor["rawRows"]) == len(expected),
            "Actual editor row readback is absent")
    raw_values = []
    for row in editor["rawRows"]:
        require(type(row) is dict and type(row.get("value")) is str
                and type(row.get("label")) is str and type(row.get("identifier")) is str,
                "Public native editor row readback is malformed")
        raw = row["value"]
        if kind == "text":
            raw_values.append(raw)
        elif kind == "integer":
            require(re.fullmatch(r"0|-?[1-9][0-9]*", raw) is not None, "Native integer readback differs")
            raw_values.append(int(raw))
        elif kind == "number":
            raw_values.append(float(raw))
        else:
            require(raw in ("0", "1"), "Actual switch readback is not boolean")
            raw_values.append(raw == "1")
    require(equal(raw_values, expected), "Public row readback differs from the native values")
    require(request.get("savedShortcutName") == "Hanlin-lists-" + kind + "-" + request["runID"][:8],
            "The owned saved Shortcut identity changed")
    require(request.get("builtInChain") == ["Get Text from Input", "Show Result"],
            "Original real built-in result chain is required")
    return expected


def terminal_result(request, identity, baseline_ids, commands, armed_at):
    engine = request.get("engine", "nativescript")
    contract = engine_contract(engine)
    kind, step = request["listKind"], request["step"]
    expected = validate_editor(request, step)
    matches = []
    for command_id, document in commands.items():
        row = document["value"]; invocation = row.get("invocation", {})
        if command_id in baseline_ids or invocation.get("identity") != identity["identity"] \
                or invocation.get("entityID") != ACTION:
            continue
        require(type(row.get("createdAt")) in (int, float) and row["createdAt"] >= armed_at,
                "Actual invocation predates the arm observation")
        native_input(invocation.get("parameters"), kind, expected)
        matches.append((command_id, document))
    require(len(matches) <= 1, "The native list executed more than once")
    if not matches:
        return None
    command_id, document = matches[0]
    row = document["value"]; receipt = row["receipt"]; invocation = row["invocation"]
    if receipt.get("status") in ("queued", "running"):
        return None
    require(receipt.get("status") == "succeeded" and receipt.get("failure") is None
            and receipt.get("cancellationRequested") is False and receipt.get("leaseID") is None
            and receipt.get("leaseExpiresAt") is None
            and type(receipt.get("attempt")) is int and receipt["attempt"] == 1,
            "The real action did not finish once without failure/cancellation/lease")
    delivery = invocation.get("delivery", {})
    require(delivery.get("schemaVersion") == 1 and delivery.get("appID") == contract["appID"]
            and delivery.get("source") == "shortcuts" and delivery.get("userGesturePresent") is True
            and delivery.get("canPresentUI") is False and invocation.get("continueInForeground") is False,
            "The real OS delivery or saved background mode differs")
    result = shared.decode_value(receipt.get("value"))
    if type(result) is str:
        result = shared.parse_json(result)
    require(type(result) is dict and result.get("schema") == 1 and result.get("appID") == contract["appID"]
            and result.get("actionID") == ACTION, "Returned fixture identity differs")
    result_values(result.get("values"), expected)
    js_type = {"text": "string", "integer": "number", "number": "number", "boolean": "boolean"}[kind]
    require(result.get("observedTypes") == [js_type] * len(expected), "Actual JS scalar observations differ")
    if engine == "nativescript":
        require(type(result.get("nonce")) is str and re.fullmatch(r"[a-z0-9]+-[a-z0-9]+", result["nonce"])
                and type(result.get("caller")) is str and result["caller"]
                and result.get("executionMode") == "headless-action" and result.get("attached") is False,
                "Actual native handler identity/presentation is missing")
        window_id = result.get("windowID")
        require(type(window_id) is str and re.fullmatch(r"[A-Za-z0-9_-]{1,128}", window_id),
                "Invalid actual window identifier")
    else:
        require(type(result.get("nonce")) is str and re.fullmatch(r"[a-z0-9]+-[a-z0-9]+", result["nonce"])
                and result.get("caller") == "hanlin.host", "Actual Expo handler identity is missing")
        invocation_id = result.get("invocationID")
        require(type(invocation_id) is str and str(uuid.UUID(invocation_id)) == command_id.lower(),
                "Expo handler invocation is not the original queued command")
        require(result.get("stateFile") == "native-list-" + result["nonce"] + ".json",
                "Expo result is not its invocation-owned state filename")
    require(shared._epoch_milliseconds(result.get("observedAt")) >= armed_at,
            "Returned handler evidence predates this run")
    return {"invocationID": command_id, "command": document, "result": result}


def result_document(roots, identity, payload, engine):
    engine_contract(engine)
    if engine == "nativescript":
        path = roots["data"] / "Library/Application Support/Hanlin/MiniApps" / APP_ID / "Windows" \
            / payload["windowID"] / "State" / ("native-list-" + payload["nonce"] + ".json")
        require(same_private_path(str(path), payload.get("statePath")),
                "Result escaped its actual native window state")
    else:
        filename = payload.get("stateFile")
        require(type(filename) is str and re.fullmatch(r"native-list-[a-z0-9]+-[a-z0-9]+\.json", filename)
                and filename == "native-list-" + payload["nonce"] + ".json",
                "Expo result is not its invocation-owned state filename")
        path = shared.expo_state_directory(roots["data"], identity["identity"]["installedPackageID"]) / filename
    return shared.read_document(path, roots["data"])


def validate_expo_presentation(request, step, armed_at):
    presentation = request.get("completionPresentation")
    require(type(presentation) is dict and type(presentation.get("step")) is int
            and presentation["step"] == step and presentation.get("shortcutsForeground") is True
            and presentation.get("miniAppsForeground") is False,
            "The actual completed Expo action must leave Shortcuts in the foreground")
    require(shared._epoch_milliseconds(presentation.get("observedAt")) >= armed_at,
            "Expo presentation evidence predates the armed execution")


def write_reply(directory, evidence, filename, value):
    require(re.fullmatch(r"identity\.json|armed-[01]\.json|chain-0\.json|completion-[01]\.json|completion\.json", filename),
            "Unexpected native-list reply")
    require(directory.is_dir() and not directory.is_symlink() and not (directory / filename).exists(),
            "Native-list replies must be fresh and owned")
    temporary = directory / (filename + ".native-list-tmp")
    with temporary.open("x") as stream:
        json.dump(value, stream, ensure_ascii=False, sort_keys=True, indent=2); stream.write("\n")
    os.replace(temporary, directory / filename)
    (evidence / filename).write_bytes((directory / filename).read_bytes())


def observe_case(args, request, directory, evidence, seen):
    run_id = request.get("runID"); kind = request.get("listKind")
    expected_values(kind, run_id, 0)
    engine = request.get("engine")
    contract = engine_contract(engine)
    require(request.get("schema") == 1
            and request.get("surface") == "nativeLists" and request.get("fixtureAppID") == contract["appID"]
            and request.get("testMethod") == contract["methods"][kind], "Unexpected native-list case")
    shared._epoch_milliseconds(request.get("startedAt"))
    case = seen.get(run_id)
    if case is not None:
        require(case["engine"] == engine, "A case cannot change its admitted native-list engine")
    phase = request.get("phase")
    if case is not None and case["phase"] == phase:
        # A pending terminal is re-read; other immutable phase replies need no polling work.
        if phase != "native-list-sent" or (case.get("armed") or {}).get("terminal") is not None:
            return
    repeated_pending = case is not None and case["phase"] == phase == "native-list-sent"
    if repeated_pending:
        roots, inputs, identity, installed = (case[key] for key in ("actualRoots", "inputs", "identity", "installed"))
    else:
        roots = shared.product_roots(args.device, args.bundle_id)
        inputs = current_inputs(args, evidence, roots, engine)
        identity, catalog = current_identity(roots, engine)
        installed = archive_binding.verify_installed_fixture_archive(
            roots["data"], identity["identity"], catalog, inputs["value"]["archive"], evidence.parent)
    commands = shared.queue_documents(roots["extensions"])
    if case is None:
        require(phase == "native-list-installed", "Bind actual installation before opening Shortcuts")
        target = evidence / run_id; target.mkdir()
        apps = shared.system_app_observation(args.device, target)
        case = {"phase": phase, "kind": kind, "engine": engine, "startedAt": request["startedAt"],
                "directory": str(directory), "identity": identity, "installed": installed,
                "roots": {k: str(roots[k]) for k in ("app", "group", "data")},
                "inputsSHA256": inputs["sha256"], "steps": [], "armed": None,
                "initialIDs": set(commands), "finished": False, "actualRoots": roots, "inputs": inputs}
        seen[run_id] = case
        write_reply(directory, target, "identity.json", {"schema": 1, "runID": run_id,
            "status": "READY", **identity, "systemApps": apps, "inputManifest": inputs,
            "installedFixture": installed})
        return
    require(case["kind"] == kind and case["startedAt"] == request["startedAt"]
            and case["directory"] == str(directory) and case["identity"] == identity
            and equal(case["installed"], installed) and case["inputsSHA256"] == inputs["sha256"]
            and case["roots"] == {k: str(roots[k]) for k in ("app", "group", "data")},
            "Admitted source/product/installation/case changed")
    target = evidence / run_id
    prefix = {"schema": 1, "runID": run_id}
    if phase == "native-list-arm":
        step = request.get("step")
        require(type(step) is int and step == len(case["steps"]) and step in (0, 1)
                and case["armed"] is None, "Steps must arm once, in order, after real result-chain readback")
        validate_editor(request, step)
        require(not [key for key, doc in commands.items() if key not in case["initialIDs"]
                     and doc["value"].get("invocation", {}).get("identity") == identity["identity"]
                     and doc["value"]["invocation"].get("entityID") == ACTION
                     and key not in {row["invocationID"] for row in case["steps"]}],
                "An extra action executed outside the armed saved Shortcut")
        arm = {"step": step, "baseline": set(commands), "at": time.time() * 1000,
               "editor": request["editor"], "savedShortcutName": request["savedShortcutName"]}
        case["armed"] = arm
        write_reply(directory, target, "armed-" + str(step) + ".json",
                    {**prefix, "status": "ARMED", "step": step, "observedAtMilliseconds": arm["at"]})
    elif phase == "native-list-sent":
        arm = case["armed"]
        require(arm is not None and request.get("step") == arm["step"]
                and equal(request.get("editor"), arm["editor"])
                and request.get("savedShortcutName") == arm["savedShortcutName"]
                and request.get("systemLaunchObserved") is True, "The actual armed UI launch differs")
        if not (target / ("completion-" + str(arm["step"]) + ".json")).exists():
            result = terminal_result(request, identity, arm["baseline"], commands, arm["at"])
            if result is None:
                case["phase"] = phase
                return
            if repeated_pending:
                fresh_roots = shared.product_roots(args.device, args.bundle_id)
                fresh_inputs = current_inputs(args, evidence, fresh_roots, engine)
                fresh_identity, fresh_catalog = current_identity(fresh_roots, engine)
                fresh_installed = archive_binding.verify_installed_fixture_archive(
                    fresh_roots["data"], fresh_identity["identity"], fresh_catalog,
                    fresh_inputs["value"]["archive"], evidence.parent)
                require(all(fresh_roots[key] == roots[key] for key in ("app", "data", "group"))
                        and fresh_inputs["sha256"] == inputs["sha256"] and fresh_identity == identity
                        and equal(fresh_installed, installed), "Live terminal product/source/installation changed")
            payload = result["result"]
            private = result_document(roots, identity, payload, engine)
            require(json_equal(private["value"], payload), "Returned JSON differs from its real private file")
            require(all(row["result"]["nonce"] != payload["nonce"] for row in case["steps"]),
                    "The cleared list reused an old handler result")
            arm["terminal"] = {**result, "privateProof": private, "editor": arm["editor"], "step": arm["step"]}
            write_reply(directory, target, "completion-" + str(arm["step"]) + ".json",
                        {**prefix, "status": "EXECUTED_PASS", **arm["terminal"]})
    elif phase == "native-list-chain-read":
        arm = case["armed"]
        require(arm is not None and "terminal" in arm and request.get("step") == arm["step"],
                "A real terminal must precede the built-in result-chain readback")
        if engine == "expo":
            validate_expo_presentation(request, arm["step"], arm["at"])
        require(json_equal(request.get("renderedResult"), arm["terminal"]["result"])
                and request.get("builtInChain") == ["Get Text from Input", "Show Result"],
                "Actual Get Text/Show Result content differs from this handler result")
        step = arm["step"]; case["steps"].append(arm["terminal"]); case["armed"] = None
        if step == 0:
            write_reply(directory, target, "chain-0.json", {**prefix, "status": "CHAIN_READ"})
        if step == 1:
            require(len({row["invocationID"] for row in case["steps"]}) == 2
                    and case["steps"][1]["result"]["values"] == [], "Empty clearing did not execute independently")
            write_reply(directory, target, "completion.json", {**prefix, "status": "EXECUTED_PASS",
                "steps": case["steps"], "caseKind": kind, "nativeExecutions": 2,
                "scope": ("Current NativeScript saved native list only; no Expo or pre-change migration claim"
                          if engine == "nativescript" else
                          "Current Expo saved native list only; no NativeScript or pre-change migration claim")})
            case["finished"] = True
    else:
        raise shared.ObservationError("Unexpected native-list exchange phase")
    case["phase"] = phase
