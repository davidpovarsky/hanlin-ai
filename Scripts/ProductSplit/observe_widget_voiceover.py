"""Read one actual VoiceOver-operated widget and an untouched native variant.

Speech and gestures come from the public XCTest service in the real UI case.
This reader never enables a service, invokes an intent, or writes product state.
The second variant is a native-state control, not a second physical placement.
"""
from pathlib import Path
import copy
import json
import math
import plistlib
import re
import subprocess
import time
import uuid

import observe_widget_state as widget

original = widget.original
require = original.require
ROOT = Path(__file__).resolve().parents[2]
EXTRA_SOURCES = (
    "Scripts/ProductSplit/observe_widget_voiceover.py",
    "Scripts/CI/Tests/test_widget_voiceover_observer.py",
)
IDENTITY_FIELDS = widget.IDENTITY_FIELDS + ("requestedSpeechLocale", "priorVoiceOverEnabled")
SELECTOR = "testMiniAppsPlacedWidgetToggleVoiceOverAnnouncesAndSetsBothValues"


def source_identity(root, source):
    result = widget.source_identity(root, source)
    for name in EXTRA_SOURCES:
        expected = subprocess.check_output(["git", "-C", str(root), "show", source + ":" + name], timeout=15)
        actual = widget.file_identity(Path(root) / name, root)
        require(actual["sha256"] == original.digest(expected), "Modified VoiceOver acceptance source: " + name)
        result[name] = actual
    return result


def create_inputs(root, derived, evidence, runner, test, state, device):
    root, evidence, runner, test = (Path(value).resolve(strict=True) for value in (root, evidence, runner, test))
    app = Path(derived) / "Build/Products/Debug-iphonesimulator/HanlinMiniApps.app"
    value = {"schema": 1, "kind": "widget-voiceover-inputs", "sourceSHA": state["sha"],
             "attemptID": str(uuid.uuid4()), "createdAt": time.time(), "device": device,
             "sourceFiles": source_identity(root, state["sha"]),
             "product": widget.product_code(app), "test": widget.bundle_code(test),
             "testRelativePath": str(test.relative_to(runner)),
             "runnerBundleIdentifier": plistlib.loads((runner / "Info.plist").read_bytes())["CFBundleIdentifier"],
             "fixture": state["widget_recovery_input"]}
    path = evidence / "widget-voiceover-inputs.json"
    require(not path.exists(), "The VoiceOver attempt manifest already exists")
    path.write_text(json.dumps(value, sort_keys=True, indent=2) + "\n")
    return {"path": str(path), "sha256": original.digest(path.read_bytes()), "value": value}


def load_inputs(args, evidence, fixture):
    path = Path(args.widget_voiceover_inputs)
    require(path.is_absolute() and path == evidence.parent / "widget-voiceover-inputs.json",
            "The original runner's owned VoiceOver manifest is required")
    document = original.read_document(path, evidence.parent)
    value = document["value"]
    require(type(value.get("schema")) is int and value["schema"] == 1
            and value.get("kind") == "widget-voiceover-inputs" and widget.uuid_string(value.get("attemptID"))
            and value.get("device") == args.device
            and value.get("runnerBundleIdentifier") == args.runner_bundle_id,
            "The source, simulator and test runner must belong to this original attempt")
    require(type(value.get("createdAt")) in (int, float) and math.isfinite(value["createdAt"])
            and value["createdAt"] <= time.time(), "Invalid actual attempt time")
    require(fixture is not None and value["fixture"]["status"] == "STAGED_INPUT_ONLY"
            and value["fixture"]["archiveSHA256"] == fixture["archiveSHA256"]
            and value["fixture"]["sourceSHA256"] == fixture["sourceSHA256"],
            "The unchanged original Matrix archive must be the actual staged input")
    require(value["sourceFiles"] == source_identity(ROOT, value["sourceSHA"]),
            "The qualified VoiceOver/source/fixture inputs changed")
    return document


def request_identity(request):
    require(type(request.get("schema")) is int and request["schema"] == 1
            and request.get("surface") == "widgetVoiceOver" and request.get("engine") == "expo"
            and widget.uuid_string(request.get("runID")), "Unknown actual VoiceOver case")
    require(request.get("instanceNames") == {key: "VoiceOver-" + key + "-" + request["runID"] for key in ("A", "B")}
            and request.get("fixtureTitle") == "Interactive Widget Matrix"
            and request.get("expectedFamily") == "systemMedium"
            and request.get("requestedSpeechLocale") == "en_US"
            and type(request.get("priorVoiceOverEnabled")) is bool,
            "This pilot requires fresh named variants, the original medium Matrix and an observed prior service state")
    require(isinstance(request.get("test"), str) and request["test"].endswith(SELECTOR + "]"),
            "Unexpected real XCTest selector")
    original._epoch_milliseconds(request["startedAt"])
    return {key: copy.deepcopy(request[key]) for key in IDENTITY_FIELDS}


def spoken_value(utterance):
    require(type(utterance) is str and len(utterance) <= 4096, "Missing or oversized actual public speech")
    words = re.findall(r"[^\W_]+", utterance.lower(), flags=re.UNICODE)
    labels = sum(a == "widget" and b == "notifications" for a, b in zip(words, words[1:]))
    require(labels == 1 and (("on" in words) != ("off" in words)),
            "Actual English speech must name this unique switch and exactly one on/off state")
    return "on" in words


def bounded_uptime(value):
    require(type(value) in (int, float) and math.isfinite(value) and value >= 0,
            "Missing finite actual monotonic time")
    return value


def event_times(row):
    start, end = (original._epoch_milliseconds(row[key]) for key in ("startedAt", "finishedAt"))
    a, b = (bounded_uptime(row[key]) for key in ("startedUptime", "finishedUptime"))
    require(start <= end <= time.time() * 1000 and a <= b, "Actual service/gesture times are out of order")
    return start, end, a, b


def require_events(request, count, prefix=()):
    events = request.get("voiceOverEvents")
    prior = request["priorVoiceOverEnabled"]
    expected = [("setup", False), ("exercise", True), ("final-configuration", False), ("restore-prior", prior)]
    require(isinstance(events, list) and len(events) == count and count in (1, 2, 4),
            "The real service lifecycle must match this exact phase")
    require(original.equal_typed_json(events[:len(prefix)], list(prefix)),
            "An already observed service operation changed")
    previous_state, previous_time, previous_uptime = prior, original._epoch_milliseconds(request["startedAt"]), 0
    for row, (reason, requested) in zip(events, expected):
        require(isinstance(row, dict) and row.get("reason") == reason and row.get("status") == "OK"
                and "error" not in row and type(row.get("requestedEnabled")) is bool
                and row["requestedEnabled"] is requested and row.get("beforeEnabled") is previous_state
                and row.get("afterEnabled") is requested,
                "Actual public enable/disable results or their prior-state chain differ")
        operation = "unchanged" if previous_state is requested else ("enable" if requested else "disable")
        require(row.get("operation") == operation, "A public service operation was substituted")
        start, end, a, b = event_times(row)
        require(start >= previous_time and a >= previous_uptime, "Service operations were reordered or replayed")
        previous_state, previous_time, previous_uptime = requested, end, b
    return copy.deepcopy(events)


def retain_json(directory, evidence, name, value):
    document = original.read_document(directory / name, directory)
    require(original.equal_typed_json(document["value"], value),
            "The actual XCTest JSON attachment differs from its published case: " + name)
    raw = (directory / name).read_bytes()
    require(original.digest(raw) == document["sha256"], "An actual XCTest JSON attachment changed during retention")
    (evidence / name).write_bytes(raw)
    return {key: document[key] for key in ("path", "sha256", "bytes")}


def require_speech(value, request, pair, frames, phase, after):
    require(isinstance(value, dict) and type(value.get("schema")) is int and value["schema"] == 1
            and all(value.get(key) == request.get(key) for key in ("runID", "attemptID", "sourceSHA"))
            and value.get("phase") == phase and value.get("label") == "Widget notifications"
            and type(value.get("visibleMatchingSwitchCount")) is int and value["visibleMatchingSwitchCount"] == 1,
            "Speech is not bound to the one actual named physical switch in this source attempt")
    widget.require_ui(value.get("ui"), pair, ["A"], frames)
    start = original._epoch_milliseconds(value["startedAt"])
    uptime = bounded_uptime(value["startedUptime"])
    require(start >= after, "The public speech observation predates its actual case phase")
    trace = value.get("trace")
    require(isinstance(trace, list) and 1 <= len(trace) <= 128, "The actual bounded speech traversal is absent")
    at = start
    for index, row in enumerate(trace):
        require(isinstance(row, dict) and type(row.get("index")) is int and row["index"] == index
                and row.get("operation") == ("currentSpeech" if index == 0 else "moveForward")
                and row.get("serviceEnabled") is True and row.get("hostTerminated") is True
                and type(row.get("utterance")) is str and len(row["utterance"]) <= 4096,
                "The real public speech trace or its active service/terminated host is incomplete")
        current = original._epoch_milliseconds(row["at"])
        next_uptime = bounded_uptime(row["uptime"])
        require(at <= current <= time.time() * 1000 and uptime <= next_uptime,
                "A speech observation was replayed or reordered")
        at, uptime = current, next_uptime
    expected = widget.count_and_value(pair["A"])[1]
    require(spoken_value(trace[-1]["utterance"]) is expected,
            "Actual public speech does not announce the independently observed native Boolean state")
    return at, uptime


def require_step(step, index):
    require(type(index) is int and index in (1, 2), "Only two actual sequential VoiceOver toggles are admitted")
    widget.require_step(step, index)
    return step


def require_gesture(gesture, request, armed, after_speech):
    step = armed["step"]
    require(isinstance(gesture, dict) and type(gesture.get("schema")) is int and gesture["schema"] == 1
            and all(gesture.get(key) == request.get(key) for key in ("runID", "attemptID", "sourceSHA"))
            and type(gesture.get("index")) is int and gesture["index"] == step["index"]
            and gesture.get("actionID") == step["actionID"] and gesture.get("method") == "XCUIElement.doubleTap"
            and gesture.get("label") == "Widget notifications"
            and type(gesture.get("visibleMatchingSwitchCount")) is int and gesture["visibleMatchingSwitchCount"] == 1
            and all(gesture.get(key) is True for key in ("serviceEnabledBefore", "serviceEnabledAfter",
                                                       "hostTerminatedBefore", "hostTerminatedAfter")),
            "The actual VoiceOver gesture, enabled service and terminated host are not bound")
    widget.require_ui(gesture.get("beforeUI"), armed["before"], ["A"], armed["frames"])
    speech = gesture.get("currentSpeech")
    require(isinstance(speech, dict) and spoken_value(speech.get("utterance")) is not step["desiredValue"],
            "The immediate real current speech does not identify the intended pre-gesture value")
    at, uptime = original._epoch_milliseconds(speech["at"]), bounded_uptime(speech["uptime"])
    start, end, a, b = event_times(gesture)
    prior = armed["speech"]["trace"][-1]
    require(armed["armedAt"] <= at <= start <= end <= original._epoch_milliseconds(after_speech["startedAt"])
            and bounded_uptime(prior["uptime"]) <= uptime <= a <= b <= bounded_uptime(after_speech["startedUptime"]),
            "The actual current speech/gesture/post-state chain is stale or reordered")
    return end


def require_restoration(request, events, after):
    row = request.get("voiceOverRestoration")
    prior = request["priorVoiceOverEnabled"]
    require(isinstance(row, dict) and row.get("priorEnabled") is prior and row.get("afterEnabled") is prior
            and "restorationFailure" not in request,
            "The actual prior VoiceOver state was not restored successfully")
    restored = original._epoch_milliseconds(row["restoredAt"])
    uptime = bounded_uptime(row["restoredUptime"])
    require(original._epoch_milliseconds(events[-2]["finishedAt"]) <= after
            <= original._epoch_milliseconds(events[-1]["startedAt"]),
            "The final physical configuration must be read between disabling and restoring the service")
    require(restored >= max(after, original._epoch_milliseconds(events[-1]["finishedAt"]))
            and restored <= time.time() * 1000 and uptime >= bounded_uptime(events[-1]["finishedUptime"]),
            "Prior-state restoration was not freshly observed after the final action/configuration")


def observe_case(args, request, directory, evidence, seen, fixture):
    identity = request_identity(request)
    run_id, phase = request["runID"], request.get("phase")
    case = seen.get(run_id)
    roots = original.product_roots(args.device, args.bundle_id)
    pair = widget.read_pair(request, roots, fixture)
    if pair is None:
        return
    if case is None:
        require(phase == "widget-voiceover-instances-created", "Bind both fresh native variants before a system action")
        inputs = load_inputs(args, evidence, fixture)
        require(original._epoch_milliseconds(request["startedAt"]) >= inputs["value"]["createdAt"] * 1000,
                "The actual UI run predates this admitted source attempt")
        widget.current_code(args, roots, inputs)
        events = require_events(request, 1)
        require(all(facts["state"]["revision"] == 0 and not facts["state"]["committedNonces"]
                    and widget.count_and_value(facts) == (0, False) for facts in pair.values()),
                "Both UI-created native variants must start uninvoked at zero/false")
        target = evidence / run_id
        target.mkdir(exist_ok=False)
        retain_json(directory, target, "voiceover-service-events.json",
                    {"schema": 1, "runID": run_id, "events": events})
        case = {"kind": "widgetVoiceOver", "finished": False, "identity": identity,
                "directory": str(directory), "roots": roots, "initial": pair, "previous": pair,
                "inputs": inputs, "steps": [], "placed": False, "armed": None, "frames": None,
                "bindings": {}, "events": events, "admittedAt": time.time() * 1000,
                "extension": original.widget_extension_executable(roots)}
        seen[run_id] = case
        widget.retain_response(directory, target, "identity.json", {
            "schema": 1, "runID": run_id, "status": "READY", "attemptID": inputs["value"]["attemptID"],
            "sourceSHA": inputs["value"]["sourceSHA"], "inputManifest": inputs, "variants": pair,
            "actualContainers": {key: str(roots[key]) for key in ("app", "data", "group")}})
        return
    require(str(directory) == case["directory"] and original.equal_typed_json(identity, case["identity"]),
            "The prepared UI identity, prior service state or exchange directory changed")
    require(all(roots[key] == case["roots"][key] for key in widget.ROOT_FIELDS),
            "Current product configuration or MCM containers changed")
    require(request.get("attemptID") == case["inputs"]["value"]["attemptID"]
            and request.get("sourceSHA") == case["inputs"]["value"]["sourceSHA"],
            "The UI evidence left its original source/attempt binding")
    widget.require_same_variants(pair, case["initial"])
    require(request.get("hostTerminated") is True and request.get("placed") == ["A"],
            "Only named A is physically placed; the actual host must be terminated")
    target = evidence / run_id
    if phase == "widget-voiceover-placement":
        if case["placed"]:
            return
        require_events(request, 1, case["events"])
        require(all(original.equal_typed_json(pair[key]["state"], case["initial"][key]["state"]) for key in ("A", "B")),
                "A native state changed during placement")
        widget.require_ui(request["ui"], pair, ["A"])
        if not widget.cache_matches(pair["A"]):
            return
        bindings = widget.configuration_bindings(request, pair, ["A"], after=case["admittedAt"])
        artifacts = widget.retain_configurations(directory, target, bindings)
        case.update(placed=True, previous=pair, frames={"A": request["ui"]["A"]["frame"]}, bindings=bindings)
        widget.retain_response(directory, target, "placement-A.json", {
            "schema": 1, "runID": run_id, "status": "READY", "placed": ["A"],
            "ui": request["ui"], "variants": pair, "configurationBindings": bindings, "actualAttachments": artifacts})
    elif phase == "widget-voiceover-arm":
        step = require_step(request["step"], len(case["steps"]) + 1)
        require(case["placed"], "The one actual physical placement has not been admitted")
        if case["armed"] is not None:
            require(original.equal_typed_json(step, case["armed"]["step"])
                    and original.equal_typed_json(request.get("voiceOverBefore"), case["armed"]["speech"]),
                    "The armed action or actual pre-gesture speech changed")
            return
        require(step["actionID"] not in [row["step"]["actionID"] for row in case["steps"]], "A UI action was replayed")
        require(all(original.equal_typed_json(pair[key]["state"], case["previous"][key]["state"]) for key in ("A", "B")),
                "Unacknowledged native state changed before the actual gesture")
        widget.require_ui(request["ui"], pair, ["A"], case["frames"])
        require(original.equal_typed_json(request.get("configurationBindings"), case["bindings"]),
                "The admitted named physical association changed before the gesture")
        events = require_events(request, 2, case["events"])
        speech = request.get("voiceOverBefore")
        require_speech(speech, request, pair, case["frames"], "before-" + str(step["index"]),
                       max(case["steps"][-1]["observedAt"] if case["steps"] else case["admittedAt"],
                           original._epoch_milliseconds(events[-1]["finishedAt"])))
        speech_artifact = retain_json(directory, target, "voiceover-before-" + str(step["index"]) + ".json", speech)
        retain_json(directory, target, "voiceover-service-events.json", {"schema": 1, "runID": run_id, "events": events})
        case["events"] = events
        case["armed"] = {"step": copy.deepcopy(step), "before": pair, "speech": copy.deepcopy(speech),
                         "frames": case["frames"], "armedAt": time.time() * 1000, "speechArtifact": speech_artifact}
        widget.retain_response(directory, target, "armed-" + str(step["index"]) + ".json", {
            "schema": 1, "runID": run_id, "status": "READY", **case["armed"]})
    elif phase == "widget-voiceover-applied":
        step = request["step"]
        if case["armed"] is None and case["steps"] and original.equal_typed_json(step, case["steps"][-1]["step"]):
            return
        require(case["armed"] is not None and original.equal_typed_json(step, case["armed"]["step"])
                and original.equal_typed_json(request.get("voiceOverBefore"), case["armed"]["speech"]),
                "The actual gesture has no unchanged admitted preparation")
        armed = case["armed"]
        require_events(request, 2, case["events"])
        if pair["A"]["state"]["revision"] == armed["before"]["A"]["state"]["revision"]:
            return
        nonce = widget.require_transition(armed["before"], pair, step)
        widget.require_ui(request["ui"], pair, ["A"], case["frames"])
        require(original.equal_typed_json(request.get("configurationBindings"), case["bindings"]),
                "The named physical association changed during the gesture")
        speech = request.get("voiceOverAfter")
        require_speech(speech, request, pair, case["frames"], "after-" + str(step["index"]), armed["armedAt"])
        require_gesture(request.get("voiceOverGesture"), request, armed, speech)
        if not widget.cache_matches(pair["A"], armed["armedAt"]):
            return
        artifacts = widget.retain_ui_artifacts(directory, target, "widget-voiceover-step-" + str(step["index"]))
        for name, value in (("voiceover-after-", speech), ("voiceover-gesture-", request["voiceOverGesture"])):
            artifacts.update({name: retain_json(directory, target, name + str(step["index"]) + ".json", value)})
        result = {"schema": 1, "runID": run_id, "status": "APPLIED", "step": step, "nativeNonce": nonce,
                  "armedAt": armed["armedAt"], "observedAt": time.time() * 1000, "variants": pair,
                  "ui": request["ui"], "speechBefore": armed["speech"], "speechAfter": speech,
                  "gesture": request["voiceOverGesture"], "actualAttachments": artifacts}
        case["steps"].append(result)
        case["previous"], case["armed"] = pair, None
        widget.retain_response(directory, target, "applied-" + str(step["index"]) + ".json", result)
    elif phase == "widget-voiceover-complete" and not case["finished"]:
        require(case["placed"] and len(case["steps"]) == 2 and case["armed"] is None,
                "Both actual VoiceOver gestures and independently observed transitions are required")
        require(all(original.equal_typed_json(pair[key]["state"], case["previous"][key]["state"])
                    and pair[key]["otherStatesSHA256"] == case["previous"][key]["otherStatesSHA256"] for key in ("A", "B"))
                and widget.cache_matches(pair["A"]), "Final native state or the actual placed layout changed")
        widget.require_ui(request["ui"], pair, ["A"], case["frames"])
        bindings = widget.configuration_bindings(request, pair, ["A"],
            after=case["steps"][-1]["observedAt"], frozen_frames=case["frames"])
        events = require_events(request, 4, case["events"])
        require_restoration(request, events, original._epoch_milliseconds(bindings["A"]["verifiedAt"]))
        artifacts = widget.retain_configurations(directory, target, bindings)
        artifacts["serviceEvents"] = retain_json(directory, target, "voiceover-service-events.json",
            {"schema": 1, "runID": run_id, "events": events})
        current = load_inputs(args, evidence, fixture)
        require(current == case["inputs"], "The exact source/product/input manifest changed")
        widget.current_code(args, roots, current)
        final_roots = original.product_roots(args.device, args.bundle_id)
        require(all(final_roots[key] == roots[key] for key in widget.ROOT_FIELDS),
                "Product containers/configuration changed at the final readback")
        final_pair = widget.read_pair(request, final_roots, fixture)
        require(final_pair is not None, "The final immutable native snapshot was unavailable")
        widget.require_same_variants(final_pair, case["initial"])
        require(all(original.equal_typed_json(final_pair[key]["state"], pair[key]["state"])
                    and final_pair[key]["otherStatesSHA256"] == pair[key]["otherStatesSHA256"] for key in ("A", "B"))
                and original.equal_typed_json(final_pair["B"]["state"], case["initial"]["B"]["state"])
                and widget.cache_matches(final_pair["A"]),
                "The placed A or untouched native B changed at completion")
        widget.require_ui(request["ui"], final_pair, ["A"], case["frames"])
        widget.configuration_bindings(request, final_pair, ["A"],
            after=case["steps"][-1]["observedAt"], frozen_frames=case["frames"])
        terminal = original.product_roots(args.device, args.bundle_id)
        require(all(terminal[key] == case["roots"][key] for key in widget.ROOT_FIELDS)
                and original.widget_extension_executable(terminal) == case["extension"],
                "The actual current product/extension changed before terminal evidence")
        widget.retain_response(directory, target, "completion.json", {
            "schema": 1, "runID": run_id, "status": "EXECUTED_PASS", "attemptID": request["attemptID"],
            "sourceSHA": request["sourceSHA"], "inputManifestSHA256": current["sha256"],
            "steps": case["steps"], "variants": final_pair, "ui": request["ui"],
            "configurationBindings": bindings, "voiceOverEvents": events,
            "voiceOverRestoration": request["voiceOverRestoration"], "actualAttachments": artifacts,
            "scope": "One actual medium WidgetKit placement, English public VoiceOver off/on/off and two native toggles; B is an untouched native-state control",
            "focusAssociation": "Inference from public current speech, one visible matching switch and its reread named physical configuration"})
        case["finished"] = True
