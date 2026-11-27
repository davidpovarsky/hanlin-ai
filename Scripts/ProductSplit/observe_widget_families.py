"""Correlate four genuine named Home Screen placements with native family renders.

Only the XCTest exchange and owned evidence directory are written. Family is
never inferred from a swipe ordinal, a declared template or a screenshot alone.
Rotation may reuse a verified timeline; no second native render is invented.
"""
from pathlib import Path
import copy
import json
import math
import plistlib
import struct
import subprocess
import time
import uuid

import observe_widget_state as widget

original = widget.original
require = original.require
ROOT = Path(__file__).resolve().parents[2]
EXTRA_SOURCES = ("Scripts/ProductSplit/observe_widget_families.py",
                 "Scripts/CI/Tests/test_widget_families_observer.py")
FAMILIES = {
    "systemSmall": ("Small", "testMiniAppsSmallWidgetRetainsFamilyAndInstanceAcrossRotation"),
    "systemMedium": ("Medium", "testMiniAppsMediumWidgetRetainsFamilyAndInstanceAcrossRotation"),
    "systemLarge": ("Large", "testMiniAppsLargeWidgetRetainsFamilyAndInstanceAcrossRotation"),
    "systemExtraLarge": ("Extra Large", "testMiniAppsExtraLargeWidgetRetainsFamilyAndInstanceAcrossRotation"),
}
ORIENTATIONS = ("portrait", "landscapeLeft", "portrait")
IDENTITY_FIELDS = ("schema", "runID", "surface", "engine", "fixtureTitle", "instanceName",
                   "expectedFamily", "sizeLabel", "priorOrientation", "startedAt", "test")


def source_identity(root, source):
    # The separately qualified original Widget reader admits the current-run
    # original producer's derived Matrix files; do not duplicate that protocol.
    result = widget.source_identity(root, source)
    for name in EXTRA_SOURCES:
        expected = subprocess.check_output(["git", "-C", str(root), "show", source + ":" + name], timeout=15)
        actual = widget.file_identity(Path(root) / name, root)
        require(actual["sha256"] == original.digest(expected), "Modified family acceptance source: " + name)
        result[name] = actual
    return result


def create_inputs(root, derived, evidence, runner, test, state, device):
    root, evidence, runner, test = (Path(value).resolve(strict=True) for value in (root, evidence, runner, test))
    app = Path(derived) / "Build/Products/Debug-iphonesimulator/HanlinMiniApps.app"
    value = {"schema": 1, "kind": "widget-families-inputs", "sourceSHA": state["sha"],
             "attemptID": str(uuid.uuid4()), "createdAt": time.time(), "device": device,
             "sourceFiles": source_identity(root, state["sha"]), "product": widget.product_code(app),
             "test": widget.bundle_code(test), "testRelativePath": str(test.relative_to(runner)),
             "runnerBundleIdentifier": plistlib.loads((runner / "Info.plist").read_bytes())["CFBundleIdentifier"],
             "fixture": state["widget_recovery_input"]}
    path = evidence / "widget-families-inputs.json"
    require(not path.exists(), "The family attempt manifest already exists")
    path.write_text(json.dumps(value, sort_keys=True, indent=2) + "\n")
    return {"path": str(path), "sha256": original.digest(path.read_bytes()), "value": value}


def load_inputs(args, evidence, fixture):
    path = Path(args.widget_families_inputs)
    require(path.is_absolute() and path == evidence.parent / "widget-families-inputs.json",
            "The original runner's owned family manifest is required")
    document = original.read_document(path, evidence.parent)
    value = document["value"]
    require(type(value.get("schema")) is int and value["schema"] == 1
            and value.get("kind") == "widget-families-inputs" and widget.uuid_string(value.get("attemptID"))
            and value.get("device") == args.device and value.get("runnerBundleIdentifier") == args.runner_bundle_id,
            "The source, simulator and original UI runner must belong to this attempt")
    finite(value.get("createdAt"))
    require(value["createdAt"] <= time.time() and fixture is not None
            and value["fixture"]["status"] == "STAGED_INPUT_ONLY"
            and value["fixture"]["archiveSHA256"] == fixture["archiveSHA256"]
            and value["fixture"]["sourceSHA256"] == fixture["sourceSHA256"],
            "The actual staged original Matrix archive changed")
    require(value["sourceFiles"] == source_identity(ROOT, value["sourceSHA"]),
            "Current source/producer/fixture inputs differ from admission")
    return document


def finite(value):
    require(type(value) in (int, float) and math.isfinite(value) and value >= 0,
            "A finite actual observation time is required")
    return value


def request_identity(request):
    family = request.get("expectedFamily")
    require(type(request.get("schema")) is int and request["schema"] == 1
            and request.get("surface") == "widgetFamilies" and request.get("engine") == "expo"
            and widget.uuid_string(request.get("runID")) and family in FAMILIES,
            "Unknown actual Home Screen family case")
    label, selector = FAMILIES[family]
    require(request.get("instanceName") == "Family-" + family + "-" + request["runID"]
            and request.get("fixtureTitle") == "Interactive Widget Matrix" and request.get("sizeLabel") == label
            and request.get("priorOrientation") in ("portrait", "portraitUpsideDown", "landscapeLeft", "landscapeRight")
            and type(request.get("test")) is str and request["test"].endswith(selector + "]"),
            "Family, fresh named variant, prior orientation and exact original selector must agree")
    original._epoch_milliseconds(request["startedAt"])
    return {key: copy.deepcopy(request[key]) for key in IDENTITY_FIELDS}


def read_native(request, roots, fixture):
    require(fixture is not None, "The exact original Matrix archive is required")
    facts = original.widget_facts(request, roots, fixture)
    require(facts["installedRecord"].get("sourceDigest") == fixture["archiveSHA256"],
            "The current installed archive differs from this actual producer input")
    return facts


def require_same_native(facts, initial):
    for key in ("identity", "instance", "installedRecord", "state"):
        require(original.equal_typed_json(facts[key], initial[key]),
                "The named variant/generation/settings/native state changed: " + key)
    require(facts["program"]["sha256"] == initial["program"]["sha256"]
            and facts["catalog"]["sha256"] == initial["catalog"]["sha256"]
            and facts["otherStatesSHA256"] == initial["otherStatesSHA256"],
            "Program/catalog or another instance's state changed during the family case")


def fresh_family_cache(facts, family, after):
    cache = facts["cache"]
    if cache is None:
        return False
    row = cache["record"]
    require(original.equal_typed_json(row.get("identity"), facts["identity"])
            and row.get("engine") == "expo" and row.get("family") == family
            and row.get("programSHA256") == facts["program"]["sha256"]
            and original.equal_typed_json(row.get("settings"), facts["instance"]["settings"])
            and row.get("renderSHA256") == cache["artifact"]["sha256"],
            "The verified native render belongs to another family, instance, program or settings")
    require(finite(row.get("renderedAt")) <= time.time() * 1000, "The native render time is in the future")
    return widget.cache_matches(facts, after)


def contained(inner, outer):
    a, b = widget.frame(inner), widget.frame(outer)
    return a[0] >= b[0] and a[1] >= b[1] and a[0] + a[2] <= b[0] + b[2] and a[1] + a[3] <= b[1] + b[3]


def orientation_geometry(orientation, bounds):
    bounds = widget.frame(bounds)
    require(orientation in ("portrait", "portraitUpsideDown", "landscapeLeft", "landscapeRight"),
            "An unknown orientation cannot qualify a physical layout")
    portrait = orientation.startswith("portrait")
    require((bounds[3] > bounds[2]) if portrait else (bounds[2] > bounds[3]),
            "Assigned orientation did not produce effective screen geometry")
    return portrait


def require_gallery(request, after):
    before = request.get("prePlacement")
    require(isinstance(before, dict) and type(before.get("visibleMatrixCount")) is int
            and before["visibleMatrixCount"] == 0 and type(before.get("visiblePlaceholderCount")) is int
            and before["visiblePlaceholderCount"] == 0 and before.get("orientation") == "portrait",
            "The placement page already contains an unowned Matrix/placeholder or is not portrait")
    orientation_geometry("portrait", before["screenFrame"])
    previous = original._epoch_milliseconds(before["at"])
    uptime = finite(before["uptime"])
    require(previous >= after, "The empty placement page predates this actual native admission")
    pages = request.get("galleryPages")
    require(isinstance(pages, list) and 1 <= len(pages) <= 12, "Missing bounded actual gallery page evidence")
    seen = set()
    for index, page in enumerate(pages):
        require(type(page.get("index")) is int and page["index"] == index
                and type(page.get("selected")) is bool and page["selected"] is (index == len(pages) - 1)
                and page.get("attachmentLabel") == "widget-family-gallery-" + str(index),
                "The actual gallery page sequence or selected page was substituted")
        rows = page.get("rows")
        require(isinstance(rows, list) and 1 <= len(rows) <= 128, "Missing actual visible gallery labels")
        texts = []
        for row in rows:
            require(isinstance(row, dict) and all(type(row.get(key)) is str and len(row[key]) <= 1024 for key in ("label", "value")),
                    "Actual page label/value is missing or oversized")
            widget.frame(row.get("frame")); texts.extend((row["label"].strip().lower(), row["value"].strip().lower()))
        signature = json.dumps(rows, sort_keys=True)
        require(signature not in seen, "A repeated gallery page cannot prove another offered family")
        seen.add(signature)
        current, current_uptime = original._epoch_milliseconds(page["observedAt"]), finite(page["uptime"])
        require(previous <= current <= time.time() * 1000 and uptime <= current_uptime,
                "Gallery evidence is stale or out of order")
        previous, uptime = current, current_uptime
        if page["selected"]:
            label = FAMILIES[request["expectedFamily"]][0].lower()
            require("hanlin script" in texts and (label in texts or label + " widget" in texts),
                    "The actual selected page must expose Hanlin Script and the requested size; ordinal is insufficient")
    return {"prePlacement": copy.deepcopy(before), "galleryPages": copy.deepcopy(pages)}


def require_configuration(value, request, bounds, label, after):
    require(isinstance(value, dict) and value.get("instanceName") == request["instanceName"]
            and value.get("attachmentLabel") == label and value.get("frame") == bounds
            and type(value.get("label")) is str and type(value.get("value")) is str
            and (request["instanceName"] in value["label"] or request["instanceName"] in value["value"]),
            "This physical frame is not the actual saved fresh named configuration")
    verified = original._epoch_milliseconds(value["verifiedAt"])
    require(after <= verified <= time.time() * 1000, "The saved configuration was not freshly re-read for this phase")
    return verified, finite(value["verifiedUptime"])


def require_rotation(row, request, index, after, previous=None):
    require(type(index) is int and 0 <= index < 3 and isinstance(row, dict)
            and type(row.get("index")) is int and row["index"] == index
            and row.get("requestedOrientation") == ORIENTATIONS[index] and row.get("orientation") == ORIENTATIONS[index]
            and row.get("attachmentLabel") == "widget-family-rotation-" + str(index)
            and type(row.get("visibleMatrixCount")) is int and row["visibleMatrixCount"] == 1
            and row.get("markerLabel") == "Matrix count: 0" and row.get("markerHittable") is True
            and row.get("hostTerminated") is True, "The actual unique Matrix/host/orientation observation is incomplete")
    orientation_geometry(row["orientation"], row["screenFrame"])
    require(contained(row["widgetFrame"], row["screenFrame"]) and row["widgetFrame"] != row["screenFrame"]
            and contained(row["markerFrame"], row["widgetFrame"]), "Actual Matrix content is outside its bound screen/container")
    start, end = original._epoch_milliseconds(row["requestedAt"]), original._epoch_milliseconds(row["capturedAt"])
    a, b = finite(row["requestedUptime"]), finite(row["capturedUptime"])
    verified, uptime = require_configuration(row.get("configuration"), request, row["widgetFrame"],
                                            "widget-family-configuration-" + str(index), start)
    require(after <= start <= verified <= end <= time.time() * 1000 and a <= uptime <= b,
            "The actual rotation/configuration/capture events are out of order")
    if previous is not None:
        require(start >= original._epoch_milliseconds(previous["capturedAt"]) and a >= previous["capturedUptime"]
                and row["screenFrame"][2:] == list(reversed(previous["screenFrame"][2:])),
                "The screen did not effectively rotate between actual observations")
    return copy.deepcopy(row)


def png_geometry(raw, orientation, screen):
    require(len(raw) >= 24 and raw.startswith(b"\x89PNG\r\n\x1a\n") and raw[12:16] == b"IHDR",
            "The actual screenshot lacks its PNG dimensions")
    width, height = struct.unpack(">II", raw[16:24])
    orientation_geometry(orientation, [0, 0, width, height])
    screen = widget.frame(screen)
    require(math.isclose(width / screen[2], height / screen[3], rel_tol=1e-6),
            "The actual full-screen PNG aspect does not match the observed AX screen")
    return [width, height]


def retain_rotation(directory, target, row, request):
    result = widget.retain_ui_artifacts(directory, target, row["attachmentLabel"], expected_text="Matrix count: 0")
    raw = (target / (row["attachmentLabel"] + ".png")).read_bytes()
    pixels = png_geometry(raw, row["orientation"], row["screenFrame"])
    result.update(widget.retain_ui_artifacts(directory, target, row["configuration"]["attachmentLabel"],
                                           expected_text=request["instanceName"]))
    return {"artifacts": result, "screenshotPixels": pixels}


def require_cleanup_and_restoration(request, last, after):
    cleanup = request.get("cleanup")
    require(isinstance(cleanup, dict) and cleanup.get("instanceName") == request["instanceName"]
            and cleanup.get("action") == "Remove Widget" and cleanup.get("confirmationLabel") in ("Remove", "Remove Widget")
            and type(cleanup.get("visibleMatrixCountAfter")) is int and cleanup["visibleMatrixCountAfter"] == 0
            and cleanup.get("hostTerminated") is True and "cleanupFailure" not in request
            and request.get("unboundPlacementCreated") is False,
            "The exact bound widget was not actually removed through its system confirmation")
    verified, uptime = require_configuration(cleanup.get("configuration"), request, last["widgetFrame"],
                                            "widget-family-cleanup-configuration", after)
    removed = original._epoch_milliseconds(cleanup["removedAt"])
    removal_uptime = finite(cleanup["removedUptime"])
    require(verified <= removed <= time.time() * 1000 and uptime <= removal_uptime,
            "The actual removal is stale or precedes its named configuration check")
    restoration = request.get("orientationRestoration")
    require(isinstance(restoration, dict) and restoration.get("priorOrientation") == request["priorOrientation"]
            and restoration.get("orientation") == request["priorOrientation"] and "restorationFailure" not in request,
            "The actual initial device orientation was not restored")
    orientation_geometry(restoration["orientation"], restoration["screenFrame"])
    require(removed <= original._epoch_milliseconds(restoration["restoredAt"]) <= time.time() * 1000
            and removal_uptime <= finite(restoration["restoredUptime"]),
            "Restoration must follow actual owned-widget cleanup")


def observe_case(args, request, directory, evidence, seen, fixture):
    identity = request_identity(request)
    run_id, phase = request["runID"], request.get("phase")
    case = seen.get(run_id)
    roots = original.product_roots(args.device, args.bundle_id)
    facts = read_native(request, roots, fixture)
    if case is None:
        require(phase == "widget-family-instance-created", "Native admission must precede placement")
        require(not any(row.get("kind") == "widgetFamilies" and (not row["finished"] or
                    row["identity"]["expectedFamily"] == request["expectedFamily"]) for row in seen.values()),
                "A previous family case is unfinished or this family already has a case in this attempt")
        inputs = load_inputs(args, evidence, fixture)
        require(original._epoch_milliseconds(request["startedAt"]) >= inputs["value"]["createdAt"] * 1000,
                "The UI case predates this source-bound attempt")
        widget.current_code(args, roots, inputs)
        require(facts["state"]["revision"] == 0 and not facts["state"]["committedNonces"]
                and widget.count_and_value(facts) == (0, False), "The UI-created variant is not a fresh uninvoked zero/false state")
        target = evidence / run_id; target.mkdir(exist_ok=False)
        case = {"kind": "widgetFamilies", "finished": False, "identity": identity, "directory": str(directory),
                "roots": roots, "initial": facts, "inputs": inputs, "admittedAt": time.time() * 1000,
                "armed": None, "addWidgetTappedAt": None, "rotations": [], "rotationArtifacts": [],
                "extension": original.widget_extension_executable(roots)}
        seen[run_id] = case
        widget.retain_response(directory, target, "identity.json", {"schema": 1, "runID": run_id, "status": "READY",
            "attemptID": inputs["value"]["attemptID"], "sourceSHA": inputs["value"]["sourceSHA"], "native": facts,
            "inputManifest": inputs, "actualContainers": {key: str(roots[key]) for key in ("app", "data", "group")}})
        return
    require(str(directory) == case["directory"] and original.equal_typed_json(identity, case["identity"]),
            "The immutable family case identity or exchange directory changed")
    require(all(roots[key] == case["roots"][key] for key in widget.ROOT_FIELDS), "Current product containers/configuration changed")
    require(request.get("attemptID") == case["inputs"]["value"]["attemptID"]
            and request.get("sourceSHA") == case["inputs"]["value"]["sourceSHA"], "The UI left its original source/attempt")
    require_same_native(facts, case["initial"])
    target = evidence / run_id
    if phase == "widget-family-arm":
        gallery = require_gallery(request, case["admittedAt"])
        if case["armed"] is not None:
            require(original.equal_typed_json(gallery, case["armed"]["gallery"]), "The armed page evidence changed")
            return
        artifacts = widget.retain_ui_artifacts(directory, target, "widget-family-before-placement")
        for page in gallery["galleryPages"]:
            artifacts.update(widget.retain_ui_artifacts(directory, target, page["attachmentLabel"]))
        selected = gallery["galleryPages"][-1]
        selected_ax = (target / (selected["attachmentLabel"] + "-accessibility.txt")).read_text().lower()
        require("hanlin script" in selected_ax and request["sizeLabel"].lower() in selected_ax,
                "The retained actual selected gallery AX does not contain its reported configuration and size")
        case["armed"] = {"at": time.time() * 1000, "gallery": gallery, "artifacts": artifacts}
        widget.retain_response(directory, target, "placement-armed.json", {"schema": 1, "runID": run_id,
            "status": "READY", "armedAt": case["armed"]["at"], "nativeBeforePlacement": facts, **gallery})
        return
    require(case["armed"] is not None and request.get("hostTerminated") is True,
            "The actual physical placement was not armed or its host is running")
    require(original.equal_typed_json(require_gallery(request, case["admittedAt"]), case["armed"]["gallery"]),
            "The actual selected page or pre-placement association changed")
    tap = original._epoch_milliseconds(request["addWidgetTappedAt"])
    require(case["armed"]["at"] <= tap <= time.time() * 1000, "The genuine Add Widget action predates its admission")
    if case["addWidgetTappedAt"] is None:
        require(phase == "widget-family-placed" and not case["rotations"],
                "The actual Add Widget timestamp must be admitted with the first placement")
        case["addWidgetTappedAt"] = request["addWidgetTappedAt"]
    require(request["addWidgetTappedAt"] == case["addWidgetTappedAt"],
            "The actual Add Widget timestamp changed after its first admission")
    if phase in ("widget-family-placed", "widget-family-rotated"):
        rows = request.get("rotations")
        require(isinstance(rows, list) and 1 <= len(rows) <= 3
                and original.equal_typed_json(rows[:len(case["rotations"])], case["rotations"]),
                "An already observed rotation changed")
        if len(rows) == len(case["rotations"]):
            return
        index = len(case["rotations"])
        require(len(rows) == index + 1 and phase == ("widget-family-placed" if index == 0 else "widget-family-rotated"),
                "Actual rotation phases were omitted or reordered")
        row = require_rotation(rows[-1], request, index, tap if index == 0 else case["lastObservedAt"],
                               case["rotations"][-1] if index else None)
        if not fresh_family_cache(facts, request["expectedFamily"], tap):
            return
        artifacts = retain_rotation(directory, target, row, request)
        if index:
            require(artifacts["screenshotPixels"] == list(reversed(case["rotationArtifacts"][-1]["screenshotPixels"])),
                    "Actual screenshot dimensions did not rotate with the observed screen")
        case["rotations"].append(row); case["rotationArtifacts"].append(artifacts)
        case["lastObservedAt"] = time.time() * 1000
        widget.retain_response(directory, target, "placement.json" if index == 0 else "rotation-" + str(index) + ".json",
            {"schema": 1, "runID": run_id, "status": "READY", "index": index, "native": facts,
             "actualRotation": row, "actualAttachments": artifacts, "observedAt": case["lastObservedAt"]})
    elif phase == "widget-family-complete" and not case["finished"]:
        require(len(case["rotations"]) == 3 and original.equal_typed_json(request.get("rotations"), case["rotations"]),
                "All three acknowledged physical orientations are required")
        require_cleanup_and_restoration(request, case["rotations"][-1], case["lastObservedAt"])
        artifacts = widget.retain_ui_artifacts(directory, target, "widget-family-cleanup-configuration",
                                               expected_text=request["instanceName"])
        for label in ("widget-family-remove-confirmation", "widget-family-removed", "widget-family-restored"):
            artifacts.update(widget.retain_ui_artifacts(directory, target, label))
        restoration = request["orientationRestoration"]
        png_geometry((target / "widget-family-restored.png").read_bytes(),
                     restoration["orientation"], restoration["screenFrame"])
        current = load_inputs(args, evidence, fixture)
        require(current == case["inputs"], "The original input/source/producer manifest changed at completion")
        widget.current_code(args, roots, current)
        final_roots = original.product_roots(args.device, args.bundle_id)
        require(all(final_roots[key] == roots[key] for key in widget.ROOT_FIELDS), "Current MCM identity changed at the final readback")
        final = read_native(request, final_roots, fixture)
        require_same_native(final, case["initial"])
        require(fresh_family_cache(final, request["expectedFamily"], tap),
                "The exact actual post-placement family render is no longer available")
        terminal = original.product_roots(args.device, args.bundle_id)
        require(all(terminal[key] == case["roots"][key] for key in widget.ROOT_FIELDS)
                and original.widget_extension_executable(terminal) == case["extension"],
                "The installed product/extension changed before terminal evidence")
        widget.retain_response(directory, target, "completion.json", {"schema": 1, "runID": run_id,
            "status": "EXECUTED_PASS", "attemptID": request["attemptID"], "sourceSHA": request["sourceSHA"],
            "inputManifestSHA256": current["sha256"], "native": final, "placement": case["armed"],
            "rotations": case["rotations"], "rotationArtifacts": case["rotationArtifacts"],
            "cleanup": request["cleanup"], "orientationRestoration": request["orientationRestoration"],
            "actualAttachments": artifacts,
            "scope": "One actually offered iPad Home Screen family, fresh named native render and portrait/landscape/portrait geometry; timeline reuse on rotation is allowed",
            "limitations": "No Today View portrait family, Lock Screen accessory, VoiceOver, appearance/RTL or physical-device claim"})
        case["finished"] = True
