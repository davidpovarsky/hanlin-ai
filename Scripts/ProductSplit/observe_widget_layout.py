"""Observe one real Medium WidgetKit control layout through actions and rotation.

This reader never changes application/extension state or manufactures AX/PNG
evidence. It joins the original Matrix producer, installed variant and native
nonce/revision/cache observations to the separate real XCTest exchange.
"""
from pathlib import Path
import copy
import json
import plistlib
import subprocess
import time
import uuid

import observe_widget_families as family

widget = family.widget
original = widget.original
require = original.require
ROOT = Path(__file__).resolve().parents[2]
EXTRA_SOURCES = ("Scripts/ProductSplit/observe_widget_layout.py",
                 "Scripts/CI/Tests/test_widget_layout_observer.py")
SELECTOR = "testMiniAppsMediumWidgetNativeControlsStayVisibleAcrossStateAndRotation"
OBSERVATIONS = (("portrait", 0, False), ("portrait", 1, True),
                ("portrait", 2, True), ("portrait", 2, True),
                ("landscapeLeft", 2, True), ("portrait", 2, True))
ACTIONS = (("toggle", True), ("add", None), ("refresh", None))
CONTROL_LABELS = {"count": ("staticText", None), "toggle": ("switch", "Widget notifications"),
                  "add": ("button", "Add"), "refresh": ("button", "Refresh")}


def source_identity(root, source):
    # Reuse the original current-run 25-output producer admission. Neither the
    # Matrix bytes nor its original source map receives a special exemption.
    result = family.source_identity(root, source)
    for name in EXTRA_SOURCES:
        expected = subprocess.check_output(["git", "-C", str(root), "show", source + ":" + name], timeout=15)
        actual = widget.file_identity(Path(root) / name, root)
        require(actual["sha256"] == original.digest(expected), "Modified layout acceptance source: " + name)
        result[name] = actual
    return result


def create_inputs(root, derived, evidence, runner, test, state, device):
    root, evidence, runner, test = (Path(value).resolve(strict=True) for value in (root, evidence, runner, test))
    app = Path(derived) / "Build/Products/Debug-iphonesimulator/HanlinMiniApps.app"
    value = {"schema": 1, "kind": "widget-layout-inputs", "sourceSHA": state["sha"],
             "attemptID": str(uuid.uuid4()), "createdAt": time.time(), "device": device,
             "sourceFiles": source_identity(root, state["sha"]), "product": widget.product_code(app),
             "test": widget.bundle_code(test), "testRelativePath": str(test.relative_to(runner)),
             "runnerBundleIdentifier": plistlib.loads((runner / "Info.plist").read_bytes())["CFBundleIdentifier"],
             "fixture": state["widget_recovery_input"]}
    path = evidence / "widget-layout-inputs.json"
    require(not path.exists(), "The layout attempt manifest already exists")
    path.write_text(json.dumps(value, sort_keys=True, indent=2) + "\n")
    return {"path": str(path), "sha256": original.digest(path.read_bytes()), "value": value}


def load_inputs(args, evidence, fixture):
    path = Path(args.widget_layout_inputs)
    require(path.is_absolute() and path == evidence.parent / "widget-layout-inputs.json",
            "The original runner's owned layout manifest is required")
    document = original.read_document(path, evidence.parent)
    value = document["value"]
    require(type(value.get("schema")) is int and value["schema"] == 1
            and value.get("kind") == "widget-layout-inputs" and widget.uuid_string(value.get("attemptID"))
            and value.get("device") == args.device and value.get("runnerBundleIdentifier") == args.runner_bundle_id,
            "The source, simulator and original UI runner must belong to this layout attempt")
    family.finite(value.get("createdAt"))
    require(value["createdAt"] <= time.time() and fixture is not None
            and value["fixture"]["status"] == "STAGED_INPUT_ONLY"
            and value["fixture"]["archiveSHA256"] == fixture["archiveSHA256"]
            and value["fixture"]["sourceSHA256"] == fixture["sourceSHA256"],
            "The actual staged original Matrix archive changed")
    require(value["sourceFiles"] == source_identity(ROOT, value["sourceSHA"]),
            "Current layout source/producer/fixture inputs differ from admission")
    return document


def request_identity(request):
    require(type(request.get("schema")) is int and request["schema"] == 1
            and request.get("surface") == "widgetLayout" and request.get("engine") == "expo"
            and widget.uuid_string(request.get("runID")) and request.get("expectedFamily") == "systemMedium",
            "Unknown actual layout case or family")
    require(request.get("instanceName") == "Layout-systemMedium-" + request["runID"]
            and request.get("fixtureTitle") == "Interactive Widget Matrix" and request.get("sizeLabel") == "Medium"
            and request.get("priorOrientation") in ("portrait", "portraitUpsideDown", "landscapeLeft", "landscapeRight")
            and type(request.get("test")) is str and request["test"].endswith(SELECTOR + "]"),
            "The fresh named variant, actual family, prior orientation and exact selector must agree")
    require(original._epoch_milliseconds(request["startedAt"]) <= time.time() * 1000, "The UI start time is in the future")
    return {key: copy.deepcopy(request[key]) for key in family.IDENTITY_FIELDS}


def require_attempt(request, identity, directory, roots, case):
    require(str(directory) == case["directory"] and original.equal_typed_json(identity, case["identity"]),
            "The immutable layout identity or exchange directory changed")
    require(all(roots[key] == case["roots"][key] for key in widget.ROOT_FIELDS),
            "Current product containers/configuration changed")
    require(request.get("attemptID") == case["inputs"]["value"]["attemptID"]
            and request.get("sourceSHA") == case["inputs"]["value"]["sourceSHA"],
            "The UI left its admitted source/attempt")


def require_variant(facts, initial):
    for key in ("identity", "instance", "installedRecord"):
        require(original.equal_typed_json(facts[key], initial[key]), "The admitted native variant changed: " + key)
    require(facts["program"]["sha256"] == initial["program"]["sha256"]
            and facts["catalog"]["sha256"] == initial["catalog"]["sha256"]
            and facts["otherStatesSHA256"] == initial["otherStatesSHA256"],
            "The original program/catalog or an untouched instance's state changed")


def require_controls(row, facts):
    count, enabled = widget.count_and_value(facts)
    require(isinstance(row, dict) and type(row.get("visibleMatrixCount")) is int and row["visibleMatrixCount"] == 1
            and row.get("hostTerminated") is True, "One unique visible Matrix and a terminated host are required")
    family.orientation_geometry(row.get("orientation"), row.get("screenFrame"))
    bounds = widget.frame(row.get("widgetFrame"))
    require(bounds != row["screenFrame"] and family.contained(bounds, row["screenFrame"]),
            "The observed widget is not a finite contained physical container")
    window = row.get("window")
    require(isinstance(window, dict) and window.get("owner") == "com.apple.springboard"
            and window.get("kind") == "window" and window.get("exists") is True and window.get("hittable") is True
            and type(window.get("matchingWindowCount")) is int and window["matchingWindowCount"] == 1
            and type(window.get("identifier")) is str and len(window["identifier"]) <= 1024
            and family.contained(window.get("frame"), row["screenFrame"]) and family.contained(bounds, window["frame"]),
            "The controls are not bound to one actual SpringBoard window containing this widget")
    controls = row.get("controls")
    require(isinstance(controls, dict) and set(controls) == set(CONTROL_LABELS),
            "All four actual marker/Toggle/Add/Refresh observations are required")
    frames = []
    for name, (kind, label) in CONTROL_LABELS.items():
        control = controls[name]
        expected = "Matrix count: " + str(count) if name == "count" else label
        require(isinstance(control, dict) and control.get("kind") == kind and control.get("label") == expected
                and control.get("exists") is True and control.get("hittable") is True,
                "An actual labelled native control is missing, hidden or belongs to another state")
        if name != "count":
            require(control.get("enabled") is True, "A required interactive control is disabled")
        if name == "toggle":
            require(control.get("value") == ("1" if enabled else "0"),
                    "The actual native Toggle value differs from the committed Boolean state")
        frame = widget.frame(control.get("frame"))
        require(family.contained(frame, bounds) and family.contained(frame, window["frame"]),
                "A measured control extends outside the actual widget/window")
        frames.append(frame)
    for index, a in enumerate(frames):
        for b in frames[index + 1:]:
            require(a[0] + a[2] <= b[0] or b[0] + b[2] <= a[0]
                    or a[1] + a[3] <= b[1] or b[1] + b[3] <= a[1],
                    "Actual count/Toggle/Add/Refresh frames overlap")


def require_observation(row, request, facts, index, after, previous=None):
    require(type(index) is int and 0 <= index < len(OBSERVATIONS) and isinstance(row, dict)
            and type(row.get("index")) is int and row["index"] == index,
            "The finite observation sequence was reordered")
    orientation, count, enabled = OBSERVATIONS[index]
    require(row.get("requestedOrientation") == orientation and row.get("orientation") == orientation
            and row.get("attachmentLabel") == "widget-layout-observation-" + str(index)
            and widget.count_and_value(facts) == (count, enabled),
            "The real action/rotation state does not match this observation")
    require_controls(row, facts)
    start, end = original._epoch_milliseconds(row["requestedAt"]), original._epoch_milliseconds(row["capturedAt"])
    a, b = family.finite(row["requestedUptime"]), family.finite(row["capturedUptime"])
    verified, uptime = family.require_configuration(row.get("configuration"), request, row["widgetFrame"],
                                                    "widget-layout-configuration-" + str(index), start)
    require(after <= start <= verified <= end <= time.time() * 1000 and a <= uptime <= b,
            "The actual layout/configuration/capture times are stale or out of order")
    if previous is not None:
        require(start >= original._epoch_milliseconds(previous["capturedAt"]) and a >= previous["capturedUptime"],
                "The new observation precedes the previous actual capture")
        expected_screen = (list(reversed(previous["screenFrame"][2:])) if index >= 4 else previous["screenFrame"][2:])
        require(row["screenFrame"][2:] == expected_screen,
                "Actual screen geometry did not preserve or change orientation as required")
    return copy.deepcopy(row)


def require_step(step, index):
    require(type(index) is int and 1 <= index <= len(ACTIONS) and isinstance(step, dict)
            and type(step.get("index")) is int and step["index"] == index and widget.uuid_string(step.get("actionID")),
            "A fresh bounded sequential UI action identity is required")
    action, desired = ACTIONS[index - 1]
    require(step.get("action") == action and original.equal_typed_json(step.get("desiredValue"), desired),
            "The actual control plan changed")
    return action, desired


def require_transition(before, current, step):
    action, desired = require_step(step, step["index"])
    require_variant(current, before)
    expected = copy.deepcopy(before["values"])
    count, _ = widget.count_and_value(before)
    if action == "toggle":
        expected.update(count=float(count + 1), enabled=desired)
    elif action == "add":
        expected.update(count=float(count + 1))
    require(type(current["state"].get("revision")) is int
            and current["state"]["revision"] == before["state"]["revision"] + 1
            and original.equal_typed_json(current["values"], expected),
            "The original native action did not commit exactly the intended typed state transition")
    old, new = before["state"]["committedNonces"], current["state"]["committedNonces"]
    require(len(new) == len(old) + 1 and new[:-1] == old and isinstance(new[-1], str)
            and str(uuid.UUID(new[-1])).lower() == new[-1].lower()
            and new[-1].lower() not in {value.lower() for value in old},
            "One real native action must append exactly one fresh invocation nonce")
    return new[-1]


def freeze_placement(request, case, phase):
    require(case["placement"] is not None and request.get("hostTerminated") is True,
            "The physical placement was not armed or its host is running")
    require(original.equal_typed_json(family.require_gallery(request, case["admittedAt"]), case["placement"]["gallery"]),
            "The selected actual gallery or empty-page evidence changed")
    tap = original._epoch_milliseconds(request["addWidgetTappedAt"])
    require(case["placement"]["at"] <= tap <= time.time() * 1000,
            "Actual Add Widget predates its original admission")
    if case["addWidgetTappedAt"] is None:
        require(phase == "widget-layout-placed" and not case["observations"], "Placement must be admitted first")
        case["addWidgetTappedAt"] = request["addWidgetTappedAt"]
    require(request["addWidgetTappedAt"] == case["addWidgetTappedAt"],
            "Actual Add Widget time changed after first admission")
    return tap


def retain_observation(directory, target, row, request, facts):
    label = row["attachmentLabel"]
    count, _ = widget.count_and_value(facts)
    result = widget.retain_ui_artifacts(directory, target, label, expected_text="Matrix count: " + str(count))
    ax = (target / (label + "-accessibility.txt")).read_text()
    require(all(text in ax for text in ("Widget notifications", "Add", "Refresh")),
            "The actual retained AX does not contain the observed controls")
    pixels = family.png_geometry((target / (label + ".png")).read_bytes(), row["orientation"], row["screenFrame"])
    result.update(widget.retain_ui_artifacts(directory, target, row["configuration"]["attachmentLabel"],
                                            expected_text=request["instanceName"]))
    return {"artifacts": result, "screenshotPixels": pixels}


def observe_case(args, request, directory, evidence, seen, fixture):
    identity = request_identity(request)
    run_id, phase = request["runID"], request.get("phase")
    roots = original.product_roots(args.device, args.bundle_id)
    facts = family.read_native(request, roots, fixture)
    case = seen.get(run_id)
    if case is None:
        require(phase == "widget-layout-instance-created" and not any(row.get("kind") == "widgetLayout" for row in seen.values()),
                "This attempt requires exactly one fresh layout case before placement")
        inputs = load_inputs(args, evidence, fixture)
        require(original._epoch_milliseconds(request["startedAt"]) >= inputs["value"]["createdAt"] * 1000,
                "This UI case predates the source-bound attempt")
        widget.current_code(args, roots, inputs)
        require(facts["state"]["revision"] == 0 and not facts["state"]["committedNonces"]
                and widget.count_and_value(facts) == (0, False), "The UI-created variant is not fresh and uninvoked")
        target = evidence / run_id; target.mkdir(exist_ok=False)
        case = {"kind": "widgetLayout", "finished": False, "identity": identity, "directory": str(directory),
                "roots": roots, "initial": facts, "previous": facts, "inputs": inputs, "admittedAt": time.time() * 1000,
                "placement": None, "addWidgetTappedAt": None, "observations": [], "artifacts": [],
                "actions": [], "armedAction": None, "extension": original.widget_extension_executable(roots)}
        seen[run_id] = case
        widget.retain_response(directory, target, "identity.json", {"schema": 1, "runID": run_id, "status": "READY",
            "attemptID": inputs["value"]["attemptID"], "sourceSHA": inputs["value"]["sourceSHA"], "native": facts,
            "inputManifest": inputs, "actualContainers": {key: str(roots[key]) for key in ("app", "data", "group")}})
        return
    require_attempt(request, identity, directory, roots, case)
    require_variant(facts, case["initial"])
    target = evidence / run_id
    if phase == "widget-layout-arm-placement":
        family.require_same_native(facts, case["initial"])
        gallery = family.require_gallery(request, case["admittedAt"])
        if case["placement"] is not None:
            require(original.equal_typed_json(gallery, case["placement"]["gallery"]), "The armed gallery changed")
            return
        artifacts = widget.retain_ui_artifacts(directory, target, "widget-family-before-placement")
        for page in gallery["galleryPages"]:
            artifacts.update(widget.retain_ui_artifacts(directory, target, page["attachmentLabel"]))
        ax = (target / (gallery["galleryPages"][-1]["attachmentLabel"] + "-accessibility.txt")).read_text().lower()
        require("hanlin script" in ax and "medium" in ax, "The actual selected gallery AX lacks the named configuration/size")
        case["placement"] = {"at": time.time() * 1000, "gallery": gallery, "artifacts": artifacts}
        widget.retain_response(directory, target, "placement-armed.json", {"schema": 1, "runID": run_id,
            "status": "READY", "armedAt": case["placement"]["at"], "nativeBeforePlacement": facts, **gallery})
        return
    placement_tap = freeze_placement(request, case, phase)
    if phase == "widget-layout-arm-action":
        step = request["step"]
        index = len(case["actions"]) + 1
        require_step(step, index)
        require(len(case["observations"]) == index and index <= 3, "The preceding actual layout is not admitted")
        armed = case["armedAction"]
        admission = {"step": step, "ui": request["armUI"], "configuration": request["armConfiguration"]}
        if armed is not None:
            require(original.equal_typed_json(admission, armed["admission"]), "An armed action or physical association changed")
            return
        family.require_same_native(facts, case["previous"])
        require(step["actionID"] not in [row["step"]["actionID"] for row in case["actions"]],
                "A prior UI action identity was replayed")
        require_controls(request["armUI"], facts)
        require(request["armUI"]["orientation"] == "portrait", "Actions must precede the two rotations")
        family.require_configuration(request["armConfiguration"], request, request["armUI"]["widgetFrame"],
                                     "widget-layout-arm-configuration-" + str(index), case["lastObservedAt"])
        artifacts = widget.retain_ui_artifacts(directory, target, request["armConfiguration"]["attachmentLabel"],
                                               expected_text=request["instanceName"])
        case["armedAction"] = {"admission": copy.deepcopy(admission), "before": facts, "at": time.time() * 1000,
                               "artifacts": artifacts}
        widget.retain_response(directory, target, "armed-" + str(index) + ".json", {"schema": 1, "runID": run_id,
            "status": "READY", "armedAt": case["armedAction"]["at"], "step": step, "native": facts})
        return
    if phase in ("widget-layout-placed", "widget-layout-applied", "widget-layout-rotated"):
        rows = request.get("observations")
        require(isinstance(rows, list) and 1 <= len(rows) <= len(OBSERVATIONS)
                and original.equal_typed_json(rows[:len(case["observations"])], case["observations"]),
                "An acknowledged actual observation was changed")
        if len(rows) == len(case["observations"]):
            return
        index = len(case["observations"])
        require(len(rows) == index + 1 and phase == ("widget-layout-placed" if index == 0 else
                "widget-layout-applied" if index <= 3 else "widget-layout-rotated"),
                "An actual action/rotation was omitted or reordered")
        after = placement_tap if index == 0 else case["lastObservedAt"]
        fresh_after = placement_tap if index == 0 else None
        action_result = None
        if 1 <= index <= 3:
            armed = case["armedAction"]
            require(armed is not None and original.equal_typed_json(request.get("step"), armed["admission"]["step"]),
                    "The actual tap has no immutable admitted preparation")
            tap = request.get("tap")
            require(isinstance(tap, dict) and tap.get("actionID") == request["step"]["actionID"],
                    "The actual UI action identity changed")
            began = original._epoch_milliseconds(tap["beganAt"])
            returned = original._epoch_milliseconds(tap["returnedAt"])
            began_uptime, returned_uptime = family.finite(tap["beganUptime"]), family.finite(tap["returnedUptime"])
            require(armed["at"] <= began <= returned <= time.time() * 1000 and began_uptime <= returned_uptime,
                    "The real UI tap predates admission or has an invalid observed interval")
            if "tap" not in armed:
                armed["tap"] = copy.deepcopy(tap)
            require(original.equal_typed_json(tap, armed["tap"]), "The observed tap interval changed")
            after, fresh_after = returned, began
            if facts["state"]["revision"] == armed["before"]["state"]["revision"]:
                return
            nonce = require_transition(armed["before"], facts, request["step"])
            action_result = {"step": copy.deepcopy(request["step"]), "tap": copy.deepcopy(tap), "nativeNonce": nonce,
                             "armedAt": armed["at"], "beforeRevision": armed["before"]["state"]["revision"],
                             "afterRevision": facts["state"]["revision"], "armArtifacts": armed["artifacts"]}
        else:
            require(case["armedAction"] is None and (index == 0 or len(case["actions"]) == 3),
                    "A pending or missing real action cannot qualify rotation")
            family.require_same_native(facts, case["previous"])
        row = require_observation(rows[-1], request, facts, index, after,
                                  case["observations"][-1] if index else None)
        if action_result:
            require(row["requestedUptime"] >= action_result["tap"]["returnedUptime"],
                    "The action layout was captured before the actual tap")
        if index >= 4:
            fresh_after = original._epoch_milliseconds(case["actions"][-1]["tap"]["beganAt"])
        if not family.fresh_family_cache(facts, request["expectedFamily"], fresh_after):
            return
        artifacts = retain_observation(directory, target, row, request, facts)
        if index:
            expected = (list(reversed(case["artifacts"][-1]["screenshotPixels"])) if index >= 4
                        else case["artifacts"][-1]["screenshotPixels"])
            require(artifacts["screenshotPixels"] == expected, "Actual PNG dimensions do not follow the measured orientation")
        observed = time.time() * 1000
        if action_result:
            action_result["observedAt"] = observed
            case["actions"].append(action_result); case["armedAction"] = None
        case["observations"].append(row); case["artifacts"].append(artifacts)
        case["previous"], case["lastObservedAt"] = facts, observed
        widget.retain_response(directory, target, "observation-" + str(index) + ".json", {"schema": 1, "runID": run_id,
            "status": "READY", "index": index, "native": facts, "action": action_result, "actualObservation": row,
            "actualAttachments": artifacts, "observedAt": observed})
    elif phase == "widget-layout-complete" and not case["finished"]:
        require(len(case["observations"]) == 6 and len(case["actions"]) == 3 and case["armedAction"] is None
                and original.equal_typed_json(request.get("observations"), case["observations"])
                and request.get("completedActionIDs") == [row["step"]["actionID"] for row in case["actions"]],
                "All six actual layouts and three individually acknowledged native actions are required")
        family.require_same_native(facts, case["previous"])
        family.require_cleanup_and_restoration(request, case["observations"][-1], case["lastObservedAt"])
        artifacts = widget.retain_ui_artifacts(directory, target, "widget-family-cleanup-configuration",
                                               expected_text=request["instanceName"])
        for label in ("widget-family-remove-confirmation", "widget-family-removed", "widget-layout-restored"):
            artifacts.update(widget.retain_ui_artifacts(directory, target, label))
        restored = request["orientationRestoration"]
        family.png_geometry((target / "widget-layout-restored.png").read_bytes(), restored["orientation"], restored["screenFrame"])
        current = load_inputs(args, evidence, fixture)
        require(current == case["inputs"], "The original source/producer/input manifest changed")
        widget.current_code(args, roots, current)
        final_roots = original.product_roots(args.device, args.bundle_id)
        require(all(final_roots[key] == roots[key] for key in widget.ROOT_FIELDS), "Final MCM identity changed")
        final = family.read_native(request, final_roots, fixture)
        family.require_same_native(final, case["previous"])
        require(family.fresh_family_cache(final, request["expectedFamily"],
                    original._epoch_milliseconds(case["actions"][-1]["tap"]["beganAt"])),
                "The last actual native render is no longer available")
        terminal = original.product_roots(args.device, args.bundle_id)
        require(all(terminal[key] == case["roots"][key] for key in widget.ROOT_FIELDS)
                and original.widget_extension_executable(terminal) == case["extension"],
                "The installed product or extension changed before final evidence")
        widget.retain_response(directory, target, "completion.json", {"schema": 1, "runID": run_id,
            "status": "EXECUTED_PASS", "attemptID": request["attemptID"], "sourceSHA": request["sourceSHA"],
            "inputManifestSHA256": current["sha256"], "native": final, "placement": case["placement"],
            "observations": case["observations"], "observationArtifacts": case["artifacts"], "actions": case["actions"],
            "cleanup": request["cleanup"], "orientationRestoration": restored, "actualAttachments": artifacts,
            "scope": "One actual Medium iPad Home Screen widget, native Toggle/Add/Refresh, measured visible nonoverlapping controls and portrait/landscape/portrait",
            "limitations": "No RTL, appearance, Today View, Lock Screen accessory, other family, full control inventory or physical-device claim"})
        case["finished"] = True
