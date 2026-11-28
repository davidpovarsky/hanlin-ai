"""Read genuine two-instance WidgetKit state; write only XCTest/evidence replies.

The existing Matrix, installer, renderer, AppIntents and stores are unchanged.
This leaf proves sequential UI actions, not parallel delivery, cold start,
VoiceOver, a physical device, or the other widget-family/appearance obligations.
"""
from pathlib import Path
import copy
import hashlib
import json
import math
import plistlib
import re
import subprocess
import time
import uuid

import observe_shortcut_surfaces as original
import prepare_widget_fixtures as widget_producer

require = original.require
ROOT = Path(__file__).resolve().parents[2]
SOURCE_PATHS = (
    "AI_HLYUITests/HanlinEntrypointSystemSurfaceUITests.swift",
    "Scripts/ProductSplit/run_paired_acceptance.py",
    "Scripts/ProductSplit/observe_shortcut_surfaces.py",
    "Scripts/ProductSplit/observe_widget_state.py",
    "Scripts/CI/Tests/test_widget_state_observer.py",
    "Fixtures/Widgets/Hanlin-Expo-Widget-Interactive-Matrix.hanlinExpo",
    "Fixtures/Widgets/SHA256.json",
)
ROOT_FIELDS = ("app", "data", "group", "extensions", "configuration", "infoSHA256")
IDENTITY_FIELDS = ("schema", "runID", "surface", "engine", "fixtureTitle",
                   "instanceNames", "expectedFamily", "startedAt", "test")
# Each row is an actual, separately acknowledged Home Screen action. There is
# no replay/concurrency claim: WidgetKit supplies the intended Boolean value.
STEPS = (
    ("A", "toggle", True), ("A", "toggle", False), ("A", "add", None),
    ("B", "toggle", True), ("B", "toggle", False), ("B", "refresh", None),
)


def uuid_string(value):
    return isinstance(value, str) and str(uuid.UUID(value)) == value


def file_identity(path, root):
    root, path = Path(root).resolve(strict=True), Path(path)
    require(path.is_absolute() and path.is_relative_to(root), "Code path left its admitted bundle")
    current = root
    for part in path.relative_to(root).parts:
        require(part not in ("", ".", ".."), "Invalid code path")
        current /= part
        require(not current.is_symlink(), "Code identity cannot follow a symbolic link")
    require(path.is_file() and path.stat().st_nlink == 1 and path.stat().st_size <= 1024**3,
            "Expected one bounded regular code file")
    with path.open("rb") as stream:
        checksum = hashlib.file_digest(stream, "sha256").hexdigest()
    return {"sha256": checksum, "bytes": path.stat().st_size}


def bundle_code(bundle):
    bundle = Path(bundle).resolve(strict=True)
    raw = (bundle / "Info.plist").read_bytes()
    require(len(raw) < 1024**2, "Bundle metadata exceeded its bound")
    info = plistlib.loads(raw)
    executable = info.get("CFBundleExecutable")
    require(isinstance(executable, str) and Path(executable).name == executable and executable,
            "Invalid actual bundle executable")
    names = ["Info.plist", executable]
    debug = executable + ".debug.dylib"
    if (bundle / debug).exists():
        names.append(debug)
    return {"bundleIdentifier": info.get("CFBundleIdentifier"),
            "files": {name: file_identity(bundle / name, bundle) for name in names}}


def product_code(app):
    app = Path(app).resolve(strict=True)
    info = plistlib.loads((app / "Info.plist").read_bytes())
    require(info.get("CFBundleIdentifier") == "com.itorah.hanlinminiapps",
            "Only the actual standalone MiniApps product is admitted")
    configuration = info.get("HanlinExtensionHost", {})
    require(configuration.get("StorageNamespace") == "HanlinMiniApps/v1",
            "The standalone namespace must be explicit")
    extension = original.widget_extension_executable({"app": app, "configuration": configuration})
    extension_bundle = Path(extension["path"]).parent
    return {"app": bundle_code(app), "widgetRelativePath": str(extension_bundle.relative_to(app)),
            "widget": bundle_code(extension_bundle), "configuration": configuration}


def source_identity(root, source):
    require(isinstance(source, str) and re.fullmatch(r"[0-9a-f]{40}", source),
            "The original runner must bind an exact source commit")
    actual = subprocess.check_output(["git", "-C", str(root), "rev-parse", "HEAD"], timeout=15).decode().strip()
    require(actual == source, "Source checkout changed during this attempt")
    result = {}
    derived = {"Fixtures/Widgets/Hanlin-Expo-Widget-Interactive-Matrix.hanlinExpo",
               "Fixtures/Widgets/SHA256.json"}
    for name in SOURCE_PATHS:
        expected = subprocess.check_output(["git", "-C", str(root), "show", source + ":" + name], timeout=15)
        current = file_identity(Path(root) / name, root)
        if name not in derived:
            require(current["sha256"] == original.digest(expected), "Modified acceptance/fixture source: " + name)
        result[name] = current
    try:
        produced = widget_producer.validate_receipt(root, source)
    except widget_producer.FixturePreparationError as error:
        raise original.ObservationError(str(error)) from error
    for name in derived:
        require(result[name] == produced[name], "Modified original producer output: " + name)
    return result


def create_inputs(root, derived, evidence, runner, test, state, device):
    """Called only by the original runner after its real products are built."""
    root, evidence, runner, test = (Path(value).resolve(strict=True) for value in (root, evidence, runner, test))
    app = Path(derived) / "Build/Products/Debug-iphonesimulator/HanlinMiniApps.app"
    value = {"schema": 1, "kind": "widget-state-inputs", "sourceSHA": state["sha"],
             "attemptID": str(uuid.uuid4()), "createdAt": time.time(), "device": device,
             "sourceFiles": source_identity(root, state["sha"]),
             "product": product_code(app), "test": bundle_code(test),
             "testRelativePath": str(test.relative_to(runner)),
             "runnerBundleIdentifier": plistlib.loads((runner / "Info.plist").read_bytes())["CFBundleIdentifier"],
             "fixture": state["widget_recovery_input"]}
    path = evidence / "widget-state-inputs.json"
    require(not path.exists(), "A widget-state attempt manifest already exists")
    path.write_text(json.dumps(value, sort_keys=True, indent=2) + "\n")
    return {"path": str(path), "sha256": original.digest(path.read_bytes()), "value": value}


def load_inputs(args, evidence, fixture):
    path = Path(args.widget_state_inputs)
    require(path.is_absolute() and path == evidence.parent / "widget-state-inputs.json",
            "The original runner's owned input manifest is required")
    document = original.read_document(path, evidence.parent)
    value = document["value"]
    require(type(value.get("schema")) is int and value["schema"] == 1
            and value.get("kind") == "widget-state-inputs" and uuid_string(value.get("attemptID"))
            and value.get("device") == args.device
            and value.get("runnerBundleIdentifier") == args.runner_bundle_id,
            "Source, device and runner must belong to this original attempt")
    require(type(value.get("createdAt")) in (int, float) and math.isfinite(value["createdAt"])
            and value["createdAt"] <= time.time(), "Invalid original attempt time")
    require(fixture is not None and value["fixture"]["status"] == "STAGED_INPUT_ONLY"
            and value["fixture"]["archiveSHA256"] == fixture["archiveSHA256"]
            and value["fixture"]["sourceSHA256"] == fixture["sourceSHA256"],
            "The exact original Matrix archive must remain the installed input")
    require(value["sourceFiles"] == source_identity(ROOT, value["sourceSHA"]),
            "The qualified source inputs changed")
    return document


def current_code(args, roots, inputs):
    value = inputs["value"]
    require(product_code(roots["app"]) == value["product"],
            "Installed MiniApps/widget code differs from the actual original build")
    runner = original.os_container(args.device, args.runner_bundle_id, "app")
    relative = Path(value["testRelativePath"])
    require(not relative.is_absolute() and len(relative.parts) == 2
            and relative.parts[0] == "PlugIns" and relative.name == "AI_HLYUITests.xctest",
            "The actual original UI test bundle is required")
    require(bundle_code(runner / relative) == value["test"],
            "Installed XCTest code differs from the original built test bundle")


def request_identity(request):
    require(type(request.get("schema")) is int and request["schema"] == 1
            and request.get("surface") == "widgetState" and request.get("engine") == "expo"
            and uuid_string(request.get("runID")), "Unknown widget-state request")
    run_id = request["runID"]
    require(request.get("instanceNames") == {key: "State-" + key + "-" + run_id for key in ("A", "B")}
            and request.get("fixtureTitle") == "Interactive Widget Matrix"
            and request.get("expectedFamily") == "systemMedium",
            "Two fresh named Matrix variants and the exact medium-family scope are required")
    require(isinstance(request.get("test"), str) and request["test"].endswith(
        "testMiniAppsPlacedWidgetToggleKeepsIndependentInstanceState]"),
        "Unexpected real XCTest selector")
    original._epoch_milliseconds(request["startedAt"])
    return {key: copy.deepcopy(request[key]) for key in IDENTITY_FIELDS}


def read_pair(request, roots, fixture):
    require(fixture is not None, "The original Matrix archive is required")
    pair = {key: original.widget_facts({"instanceName": request["instanceNames"][key],
                "expectedFamily": request["expectedFamily"]}, roots, fixture) for key in ("A", "B")}
    # The original store uses immutable revisions. Do not join two different
    # snapshots if a real render publication raced this read; poll it again.
    if pair["A"]["snapshotSHA256"] != pair["B"]["snapshotSHA256"]:
        return None
    first, second = (pair[key] for key in ("A", "B"))
    for facts in pair.values():
        require(facts["installedRecord"].get("sourceDigest") == fixture["archiveSHA256"],
                "The installed source archive differs from the admitted Matrix input")
    require(first["identity"]["variantID"] != second["identity"]["variantID"]
            and all(first["identity"][key] == second["identity"][key] for key in
                    ("installedPackageID", "packageID", "generation", "entrypointID"))
            and first["program"]["sha256"] == second["program"]["sha256"],
            "The two real independent variants must belong to one exact installed program")
    return pair


def require_same_variants(pair, initial):
    for key in ("A", "B"):
        for field in ("identity", "instance", "installedRecord"):
            require(original.equal_typed_json(pair[key][field], initial[key][field]),
                    "An admitted widget variant/generation/settings record changed")
        require(pair[key]["program"]["sha256"] == initial[key]["program"]["sha256"],
                "An admitted widget program changed")


def count_and_value(facts):
    values = facts["values"]
    count, enabled = values.get("count", 0.0), values.get("enabled", False)
    require(type(count) in (int, float) and math.isfinite(count) and count >= 0 and count == int(count)
            and type(enabled) is bool, "Widget state must retain actual numeric count and Boolean value")
    return int(count), enabled


def nodes(value):
    if isinstance(value, dict):
        yield value
        for child in value.values():
            yield from nodes(child)
    elif isinstance(value, list):
        for child in value:
            yield from nodes(child)


def cache_matches(facts, after=None):
    cache = facts["cache"]
    if cache is None:
        return False
    count, enabled = count_and_value(facts)
    toggles = [node for node in nodes(cache["node"]) if node.get("type") == "ToggleView"
               and isinstance(node.get("props"), dict) and node["props"].get("target") == "enabled"]
    if not (len(toggles) == 1 and toggles[0]["props"].get("isOn") is enabled
            and original.widget_node_contains(cache["node"], "Matrix count: " + str(count))):
        return False
    rendered = cache["record"].get("renderedAt")
    require(type(rendered) in (int, float) and math.isfinite(rendered), "Invalid native render timestamp")
    return after is None or rendered >= after


def frame(value):
    require(isinstance(value, list) and len(value) == 4
            and all(type(x) in (int, float) and math.isfinite(x) for x in value)
            and value[2] > 0 and value[3] > 0, "A real finite positive AX frame is required")
    return value


def require_ui(ui, pair, placed, frozen_frames=None):
    require(isinstance(ui, dict) and set(ui) == set(placed), "The actual placed-widget UI set differs")
    for key in placed:
        row = ui[key]
        require(isinstance(row, dict), "Missing actual widget AX observations")
        count, enabled = count_and_value(pair[key])
        require(type(row.get("count")) is int and row["count"] == count
                and row.get("switchValue") == ("1" if enabled else "0")
                and row.get("switchEnabled") is True and row.get("switchHittable") is True
                and row.get("addHittable") is True and row.get("refreshHittable") is True,
                "The observed native Toggle and original controls do not match actual state")
        bounds = frame(row.get("frame"))
        if frozen_frames:
            require(bounds == frozen_frames[key], "A physical widget association changed after both placements")
        for child in ("switchFrame", "addFrame", "refreshFrame"):
            child_frame = frame(row.get(child))
            require(bounds[0] <= child_frame[0] and bounds[1] <= child_frame[1]
                    and child_frame[0] + child_frame[2] <= bounds[0] + bounds[2]
                    and child_frame[1] + child_frame[3] <= bounds[1] + bounds[3],
                    "An observed control is outside its uniquely grouped widget")
    if len(placed) == 2:
        a, b = (ui[key]["frame"] for key in ("A", "B"))
        require(a[0] + a[2] <= b[0] or b[0] + b[2] <= a[0]
                or a[1] + a[3] <= b[1] or b[1] + b[3] <= a[1],
                "Both visible widgets must have distinct nonoverlapping physical containers")


def require_step(step, index):
    require(type(index) is int and 1 <= index <= len(STEPS)
            and isinstance(step, dict) and type(step.get("index")) is int and step["index"] == index
            and uuid_string(step.get("actionID")), "Missing fresh sequential UI action identity")
    target, action, desired = STEPS[index - 1]
    require(step.get("instance") == target and step.get("action") == action
            and original.equal_typed_json(step.get("desiredValue"), desired),
            "The action differs from the exact original sequential control plan")
    return target, action, desired


def require_transition(before, current, step):
    target, action, desired = require_step(step, step["index"])
    require_same_variants(current, before)
    old, new = before[target], current[target]
    other = "B" if target == "A" else "A"
    require(original.equal_typed_json(current[other]["state"], before[other]["state"])
            and new["otherStatesSHA256"] == old["otherStatesSHA256"],
            "An untouched widget instance changed during the selected UI action")
    expected = copy.deepcopy(old["values"])
    old_count, _ = count_and_value(old)
    if action == "toggle":
        expected.update(enabled=desired, count=float(old_count + 1))
    elif action == "add":
        expected.update(count=float(old_count + 1))
    require(type(new["state"].get("revision")) is int
            and new["state"]["revision"] == old["state"]["revision"] + 1
            and original.equal_typed_json(new["values"], expected),
            "The actual AppIntent did not commit exactly the intended typed state transition")
    old_nonces, nonces = old["state"]["committedNonces"], new["state"]["committedNonces"]
    require(len(nonces) == len(old_nonces) + 1 and nonces[:-1] == old_nonces,
            "One actual native invocation must append exactly one nonce")
    nonce = nonces[-1]
    require(isinstance(nonce, str) and str(uuid.UUID(nonce)).lower() == nonce.lower()
            and nonce.lower() not in {value.lower() for value in old_nonces
                                     + current[other]["state"]["committedNonces"]},
            "A stale, invalid or shared native invocation nonce cannot qualify")
    return nonce


def configuration_bindings(request, pair, placed, *, after, frozen_frames=None):
    """Bind actual Edit Widget selection to each physical AX container.

    Count labels locate the current container; they are not variant identities.
    Only the actual saved fresh name, current native identity and frame together
    admit that association. Both panels are read again at the final boundary.
    """
    bindings = request.get("configurationBindings")
    require(isinstance(bindings, dict) and set(bindings) == set(placed),
            "Read the actual configuration of every placed widget")
    for key in placed:
        row = bindings[key]
        expected = request["instanceNames"][key]
        other = request["instanceNames"]["B" if key == "A" else "A"]
        require(isinstance(row, dict) and row.get("instanceName") == expected
                and type(row.get("count")) is int and row["count"] == count_and_value(pair[key])[0],
                "The configuration readback belongs to a different named instance/state")
        label, value = row.get("label"), row.get("value")
        require(type(label) is str and type(value) is str and len(label) <= 4096 and len(value) <= 4096
                and (expected in label or expected in value) and other not in label and other not in value,
                "The real saved WidgetKit entity selection is absent or ambiguous")
        actual_frame = frame(row.get("frame"))
        require(actual_frame == request["ui"][key]["frame"]
                and (frozen_frames is None or actual_frame == frozen_frames[key]),
                "The named selection was read from a different physical widget")
        verified = original._epoch_milliseconds(row.get("verifiedAt"))
        require(after <= verified <= time.time() * 1000,
                "The actual saved selection was not freshly reread in this case phase")
    return copy.deepcopy(bindings)


def retain_ui_artifacts(directory, evidence, label, *, expected_text=None):
    """Retain exact XCTest AX/PNG bytes, never create a system observation."""
    retained = {}
    for suffix in ("-accessibility.txt", ".png"):
        name = label + suffix
        path = directory / name
        identity = file_identity(path, directory)
        require(0 < identity["bytes"] <= 16 * 1024**2, "Missing or oversized actual XCTest attachment")
        data = path.read_bytes()
        require(original.digest(data) == identity["sha256"] and len(data) == identity["bytes"],
                "The actual XCTest attachment changed during retention")
        if suffix == ".png":
            require(data.startswith(b"\x89PNG\r\n\x1a\n"), "The actual screenshot is not a PNG")
        else:
            text = data.decode("utf-8")
            require(expected_text is None or expected_text in text,
                    "The original configuration AX attachment does not contain its actual saved name")
        (evidence / name).write_bytes(data)
        retained[name] = identity
    return retained


def retain_configurations(directory, evidence, bindings):
    retained = {}
    for key, row in bindings.items():
        label = "widget-state-" + key + "-configuration-" + str(row["count"])
        retained[key] = retain_ui_artifacts(directory, evidence, label, expected_text=row["instanceName"])
    return retained


def retain_response(directory, evidence, name, response):
    original.write_response(directory, name, response)
    (evidence / name).write_text(json.dumps(response, ensure_ascii=False, sort_keys=True, indent=2) + "\n")


def observe_case(args, request, directory, evidence, seen, fixture):
    identity = request_identity(request)
    run_id, phase = request["runID"], request.get("phase")
    case = seen.get(run_id)
    roots = original.product_roots(args.device, args.bundle_id)
    pair = read_pair(request, roots, fixture)
    if pair is None:
        return
    if case is None:
        require(phase == "widget-instances-created", "Bind both fresh variants before any system action")
        inputs = load_inputs(args, evidence, fixture)
        require(original._epoch_milliseconds(request["startedAt"]) >= inputs["value"]["createdAt"] * 1000,
                "The actual UI run predates this admitted original attempt")
        current_code(args, roots, inputs)
        require(all(facts["state"]["revision"] == 0 and not facts["state"]["committedNonces"]
                    and count_and_value(facts) == (0, False) for facts in pair.values()),
                "Both UI-created variants must start with zero uninvoked state")
        case_evidence = evidence / run_id
        case_evidence.mkdir(exist_ok=False)
        case = {"kind": "widgetState", "finished": False, "identity": identity,
                "directory": str(directory), "roots": roots, "initial": pair, "previous": pair,
                "inputs": inputs, "steps": [], "placed": [], "armed": None, "frames": None,
                "bindings": {}, "admittedAt": time.time() * 1000,
                "extension": original.widget_extension_executable(roots)}
        seen[run_id] = case
        retain_response(directory, case_evidence, "identity.json", {
            "schema": 1, "runID": run_id, "status": "READY", "attemptID": inputs["value"]["attemptID"],
            "sourceSHA": inputs["value"]["sourceSHA"], "inputManifest": inputs,
            "variants": pair, "actualContainers": {key: str(roots[key]) for key in ("app", "data", "group")}})
        return
    require(str(directory) == case["directory"] and original.equal_typed_json(identity, case["identity"]),
            "The original UI request or exchange directory changed")
    require(all(roots[key] == case["roots"][key] for key in ROOT_FIELDS),
            "Current product configuration or MCM containers changed")
    require(request.get("attemptID") == case["inputs"]["value"]["attemptID"]
            and request.get("sourceSHA") == case["inputs"]["value"]["sourceSHA"],
            "UI evidence left the original source/attempt binding")
    require_same_variants(pair, case["initial"])
    require(request.get("hostTerminated") is True, "Actual XCTest must observe the host terminated")
    target_evidence = evidence / run_id
    if phase == "widget-state-placement":
        placed = request.get("placed")
        expected = ["A"] if not case["placed"] else ["A", "B"]
        if placed == case["placed"]:
            return
        require(placed == expected and len(case["steps"]) == (0 if len(placed) == 1 else 1),
                "Real placements must follow the exact fresh-case sequence")
        require(all(original.equal_typed_json(pair[key]["state"], case["previous"][key]["state"])
                    for key in ("A", "B")), "Placing the second widget changed existing state")
        require_ui(request["ui"], pair, placed)
        if not all(cache_matches(pair[key]) for key in placed):
            return
        bindings = configuration_bindings(request, pair, placed,
            after=case["steps"][-1]["observedAt"] if case["steps"] else case["admittedAt"])
        artifacts = retain_configurations(directory, target_evidence, bindings)
        case["placed"] = placed
        case["frames"] = {key: request["ui"][key]["frame"] for key in placed}
        case["bindings"] = bindings
        case["previous"] = pair
        retain_response(directory, target_evidence, "placement-" + placed[-1] + ".json",
                        {"schema": 1, "runID": run_id, "status": "READY", "placed": placed,
                         "ui": request["ui"], "variants": pair, "configurationBindings": bindings,
                         "actualAttachments": artifacts})
    elif phase == "widget-state-arm":
        step = request["step"]
        require_step(step, len(case["steps"]) + 1)
        require(request.get("placed") == case["placed"]
                and case["placed"] == (["A"] if step["index"] == 1 else ["A", "B"]),
                "The action's real placements are not admitted")
        if case["armed"] is not None:
            require(original.equal_typed_json(step, case["armed"]["step"]), "An armed UI action changed")
            return
        require(step["actionID"] not in [row["step"]["actionID"] for row in case["steps"]],
                "A previous UI action identity was replayed")
        require(all(original.equal_typed_json(pair[key]["state"], case["previous"][key]["state"])
                    for key in ("A", "B")), "Unacknowledged state changed before the actual tap")
        require_ui(request["ui"], pair, case["placed"], case["frames"])
        require(original.equal_typed_json(request.get("configurationBindings"), case["bindings"]),
                "A saved physical-instance association changed before the actual tap")
        case["armed"] = {"step": copy.deepcopy(step), "before": pair, "armedAt": time.time() * 1000}
        retain_response(directory, target_evidence, "armed-" + str(step["index"]) + ".json",
                        {"schema": 1, "runID": run_id, "status": "READY", **case["armed"]})
    elif phase == "widget-state-applied":
        step = request["step"]
        if case["armed"] is None and case["steps"] and original.equal_typed_json(step, case["steps"][-1]["step"]):
            return
        require(case["armed"] is not None and original.equal_typed_json(step, case["armed"]["step"])
                and request.get("tapObserved") is True, "The actual UI tap has no admitted preparation")
        armed = case["armed"]
        target = step["instance"]
        if pair[target]["state"]["revision"] == armed["before"][target]["state"]["revision"]:
            return
        nonce = require_transition(armed["before"], pair, step)
        require_ui(request["ui"], pair, case["placed"], case["frames"])
        require(original.equal_typed_json(request.get("configurationBindings"), case["bindings"]),
                "A saved physical-instance association changed during the actual tap")
        if not cache_matches(pair[target], armed["armedAt"]):
            return
        artifacts = retain_ui_artifacts(directory, target_evidence, "widget-state-step-" + str(step["index"]))
        result = {"schema": 1, "runID": run_id, "status": "APPLIED", "step": step,
                  "nativeNonce": nonce, "armedAt": armed["armedAt"], "observedAt": time.time() * 1000,
                  "variants": pair, "ui": request["ui"], "configurationBindings": case["bindings"],
                  "actualAttachments": artifacts}
        case["steps"].append(result)
        case["previous"], case["armed"] = pair, None
        retain_response(directory, target_evidence, "applied-" + str(step["index"]) + ".json", result)
    elif phase == "widget-state-complete" and not case["finished"]:
        require(len(case["steps"]) == len(STEPS) and case["armed"] is None and case["placed"] == ["A", "B"],
                "All six actual sequential actions and both placements are required")
        require(all(original.equal_typed_json(pair[key]["state"], case["previous"][key]["state"])
                    and cache_matches(pair[key]) for key in ("A", "B")),
                "Final state or cached layout changed after the actual control sequence")
        require_ui(request["ui"], pair, ["A", "B"], case["frames"])
        bindings = configuration_bindings(request, pair, ["A", "B"],
            after=case["steps"][-1]["observedAt"], frozen_frames=case["frames"])
        artifacts = retain_configurations(directory, target_evidence, bindings)
        current = load_inputs(args, evidence, fixture)
        require(current == case["inputs"], "The original input/source manifest changed")
        current_code(args, roots, current)
        final_roots = original.product_roots(args.device, args.bundle_id)
        require(all(final_roots[key] == roots[key] for key in ROOT_FIELDS),
                "Product containers/configuration changed at the final observation boundary")
        final_pair = read_pair(request, final_roots, fixture)
        require(final_pair is not None, "A final immutable snapshot was not available")
        require_same_variants(final_pair, pair)
        require(all(original.equal_typed_json(final_pair[key]["state"], pair[key]["state"])
                    and cache_matches(final_pair[key]) for key in ("A", "B")),
                "Both current variant states must remain unchanged at completion")
        require_ui(request["ui"], final_pair, ["A", "B"], case["frames"])
        configuration_bindings(request, final_pair, ["A", "B"],
            after=case["steps"][-1]["observedAt"], frozen_frames=case["frames"])
        terminal_roots = original.product_roots(args.device, args.bundle_id)
        require(all(terminal_roots[key] == case["roots"][key] for key in ROOT_FIELDS)
                and original.widget_extension_executable(terminal_roots) == case["extension"],
                "Current product containers, configuration or installed widget extension changed before completion")
        retain_response(directory, target_evidence, "completion.json", {
            "schema": 1, "runID": run_id, "status": "EXECUTED_PASS", "attemptID": request["attemptID"],
            "sourceSHA": request["sourceSHA"], "inputManifestSHA256": current["sha256"],
            "steps": case["steps"], "variants": final_pair, "ui": request["ui"],
            "configurationBindings": bindings, "actualAttachments": artifacts,
            "scope": "Two independent medium widgets; six actual sequential Toggle/Add/Refresh actions only"})
        case["finished"] = True
