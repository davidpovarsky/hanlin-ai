"""Observe one actual Large WidgetKit component fixture and one real Add action.

The archive uses the original Widget deterministic ZIP/package recipe. This
reader writes only input staging and XCTest/evidence exchanges. Prepared nodes
bind source and freshness; only the actual native AX/value/frame/PNG observations
qualify component exposure. No Gauge or Chart accessibility type is assumed.
"""
from pathlib import Path
import base64
import copy
import io
import json
import plistlib
import subprocess
import time
import uuid
import zipfile

import observe_widget_layout as layout
import prepare_widget_fixtures as producer

family = layout.family
widget = family.widget
original = widget.original
require = original.require
ROOT = Path(__file__).resolve().parents[2]
SELECTOR = "testMiniAppsLargeWidgetComponentsTrackActualNativeState"
TITLE = "Widget Components Pilot"
ARCHIVE = "Hanlin-Expo-Widget-Components.hanlinExpo"
FIXTURE_FILES = ("Fixtures/WidgetComponents/script.json", "Fixtures/WidgetComponents/widget.jsx")
SOURCE_PATHS = (
    "AI_HLYUITests/HanlinEntrypointSystemSurfaceUITests.swift",
    "Scripts/ProductSplit/run_paired_acceptance.py",
    "Scripts/ProductSplit/observe_shortcut_surfaces.py",
    "Scripts/ProductSplit/observe_widget_state.py",
    "Scripts/ProductSplit/observe_widget_families.py",
    "Scripts/ProductSplit/observe_widget_layout.py",
    "Scripts/ProductSplit/observe_widget_components.py",
    "Scripts/CI/Tests/test_widget_components_observer.py",
    *FIXTURE_FILES,
)
COMPONENTS = ("count", "add", "progress", "gauge", "chart", "symbol", "link")
# Original exports own the current resolved package versions and ZIP algorithm.
# This new fixture never changes or writes any of the original 25 outputs.
RECIPE = r"""
import {readFileSync} from 'node:fs';
import {createHash} from 'node:crypto';
import {widgetSamples} from './Scripts/Widgets/samples.mjs';
import {deterministicZip} from './Scripts/Widgets/deterministic-zip.mjs';
const samples = widgetSamples.filter(row => row.name === 'Hanlin-Expo-Widget-Interactive-Matrix');
if (samples.length !== 1) throw Error('Original package recipe is ambiguous');
const pkg = {...JSON.parse(samples[0].files['package.json']), name:'hanlin-expo-widget-components'};
const files = {
  'script.json':readFileSync('Fixtures/WidgetComponents/script.json'),
  'package.json':Buffer.from(JSON.stringify(pkg,null,2)+'\n'),
  'widget.jsx':readFileSync('Fixtures/WidgetComponents/widget.jsx'),
};
const bytes = deterministicZip(files);
const sha = raw => createHash('sha256').update(raw).digest('hex');
console.log(JSON.stringify({nodeVersion:process.version, archive:bytes.toString('base64'),
  sha256:sha(bytes), sources:Object.fromEntries(Object.entries(files).map(([name,raw])=>[name,sha(raw)]))}));
"""


def source_identity(root, source):
    root = Path(root).resolve(strict=True)
    producer.source_head(root, source)
    result = {}
    for name in SOURCE_PATHS:
        expected = producer.git_bytes(root, source, name)
        current = widget.file_identity(root / name, root)
        require(current["sha256"] == original.digest(expected), "Modified component acceptance input: " + name)
        result[name] = current
    return result


def fixture_recipe(root, source):
    root = Path(root).resolve(strict=True)
    before = producer.input_identity(root, source)
    result = subprocess.run([before["node"]["path"], "--input-type=module", "-e", RECIPE], cwd=root,
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=30)
    require(result.returncode == 0 and len(result.stdout) <= 1024**2,
            "The unchanged original Widget ZIP/package exports did not prepare this fixture")
    value = original.parse_json(result.stdout)
    require(value.get("nodeVersion") == before["node"]["version"], "The original pinned Node changed")
    raw = base64.b64decode(value["archive"], validate=True)
    require(0 < len(raw) < 1024**2 and original.digest(raw) == value.get("sha256"),
            "The source-only component archive digest is invalid")
    after = producer.input_identity(root, source)
    require(original.equal_typed_json(before, after), "Original producer/resolver inputs changed during the recipe")
    with zipfile.ZipFile(io.BytesIO(raw)) as archive:
        require(archive.namelist() == sorted(["script.json", "package.json", "widget.jsx"]),
                "Unexpected component archive membership or ordering")
        members = {name: archive.read(name) for name in archive.namelist()}
    require(value["sources"] == {name: original.digest(data) for name, data in members.items()},
            "The actual component archive member hashes disagree")
    require(members["script.json"] == (root / FIXTURE_FILES[0]).read_bytes()
            and members["widget.jsx"] == (root / FIXTURE_FILES[1]).read_bytes(),
            "The archive must preserve both complete authored files")
    manifest = original.parse_json(members["script.json"])
    require(manifest.get("name") == TITLE and manifest.get("kind") == "widget"
            and manifest.get("widgetEngine") == "expo" and manifest.get("hanlinRuntime") == "hanlin-expo"
            and manifest.get("entry") == "widget.jsx", "The separate widget-only fixture contract changed")
    return raw, {"archiveSHA256": original.digest(raw), "sourceSHA256": value["sources"]["widget.jsx"],
                 "metadata": manifest["hanlinWidget"], "entry": manifest["entry"],
                 "memberSHA256": value["sources"], "producerInputs": before}


def stage_fixture(root, source, evidence, documents):
    root, evidence, documents = (Path(p).resolve(strict=True) for p in (root, evidence, documents))
    github = producer.context(root, source)
    sources = source_identity(root, source)
    raw, facts = fixture_recipe(root, source)
    target = evidence / "widget-components-fixture"
    require(not target.exists() and not (documents / ARCHIVE).exists(), "A component input already exists in this attempt")
    target.mkdir()
    (target / ARCHIVE).write_bytes(raw)
    (documents / ARCHIVE).write_bytes(raw)
    require(widget.file_identity(documents / ARCHIVE, documents)["sha256"] == facts["archiveSHA256"],
            "The source input changed during original document staging")
    receipt = {"status": "STAGED_INPUT_ONLY", "sourceSHA": source, "github": github, "archive": ARCHIVE,
               "sourceFiles": sources, **facts,
               "scope": "Source archive only; the original UI importer/compiler, installation and native widget produce acceptance"}
    (target / "receipt.json").write_text(json.dumps(receipt, sort_keys=True, indent=2) + "\n")
    return receipt


def create_inputs(root, derived, evidence, runner, test, state, device):
    root, evidence, runner, test = (Path(p).resolve(strict=True) for p in (root, evidence, runner, test))
    app = Path(derived) / "Build/Products/Debug-iphonesimulator/HanlinMiniApps.app"
    value = {"schema": 1, "kind": "widget-components-inputs", "sourceSHA": state["sha"],
             "attemptID": str(uuid.uuid4()), "createdAt": time.time(), "device": device,
             "sourceFiles": source_identity(root, state["sha"]), "product": widget.product_code(app),
             "test": widget.bundle_code(test), "testRelativePath": str(test.relative_to(runner)),
             "runnerBundleIdentifier": plistlib.loads((runner / "Info.plist").read_bytes())["CFBundleIdentifier"],
             "fixture": state["widget_components_input"]}
    path = evidence / "widget-components-inputs.json"
    require(not path.exists(), "A component attempt manifest already exists")
    path.write_text(json.dumps(value, sort_keys=True, indent=2) + "\n")
    return {"path": str(path), "sha256": original.digest(path.read_bytes()), "value": value}


def load_inputs(args, evidence):
    path = Path(args.widget_components_inputs)
    require(path.is_absolute() and path == evidence.parent / "widget-components-inputs.json",
            "The current original runner's component manifest is required")
    document = original.read_document(path, evidence.parent)
    value = document["value"]
    require(type(value.get("schema")) is int and value["schema"] == 1
            and value.get("kind") == "widget-components-inputs" and widget.uuid_string(value.get("attemptID"))
            and value.get("device") == args.device and value.get("runnerBundleIdentifier") == args.runner_bundle_id,
            "The source, owned simulator and actual runner must belong to this component attempt")
    family.finite(value.get("createdAt"))
    require(value["createdAt"] <= time.time(), "The component attempt begins in the future")
    sources = source_identity(ROOT, value["sourceSHA"])
    require(original.equal_typed_json(sources, value["sourceFiles"]), "Current component source differs from admission")
    archive, facts = fixture_recipe(ROOT, value["sourceSHA"])
    fixture = value["fixture"]
    require(fixture.get("status") == "STAGED_INPUT_ONLY" and fixture.get("sourceSHA") == value["sourceSHA"]
            and original.equal_typed_json(fixture.get("github"), producer.context(ROOT, value["sourceSHA"]))
            and original.equal_typed_json(fixture.get("sourceFiles"), sources)
            and all(original.equal_typed_json(fixture.get(key), row) for key, row in facts.items()),
            "The original recipe/source/current-run fixture admission changed")
    staged = evidence.parent / "widget-components-fixture" / ARCHIVE
    require(widget.file_identity(staged, evidence.parent)["sha256"] == original.digest(archive),
            "The retained actual staged component archive changed")
    return document


def request_identity(request):
    require(type(request.get("schema")) is int and request["schema"] == 1
            and request.get("surface") == "widgetComponents" and request.get("engine") == "expo"
            and widget.uuid_string(request.get("runID")) and request.get("expectedFamily") == "systemLarge",
            "Unknown component case, engine or actual family")
    require(request.get("instanceName") == "Components-systemLarge-" + request["runID"]
            and request.get("fixtureTitle") == TITLE and request.get("sizeLabel") == "Large"
            and request.get("priorOrientation") in ("portrait", "portraitUpsideDown", "landscapeLeft", "landscapeRight")
            and type(request.get("test")) is str and request["test"].endswith(SELECTOR + "]"),
            "The fresh named component variant, prior orientation and exact selector must agree")
    require(original._epoch_milliseconds(request["startedAt"]) <= time.time() * 1000, "The UI start is in the future")
    return {key: copy.deepcopy(request[key]) for key in family.IDENTITY_FIELDS}


def component_values(count):
    require(type(count) is int and count in (0, 1), "Only the actual zero-to-one component action is selected")
    text = str(count)
    return {"count": ("Components count: " + text, text), "add": ("Add", "Count " + text),
            "progress": ("Progress count " + text, text + " of 10"),
            "gauge": ("Gauge count " + text, text + " of 10"),
            "chart": ("Chart count " + text, "Count " + text + "; Reference 10"),
            "symbol": ("Book count " + text, "Outline book" if count == 0 else "Filled book"),
            "link": ("Details count " + text, "Count " + text)}


def require_components(row, facts):
    count, _ = widget.count_and_value(facts)
    expected = component_values(count)
    require(isinstance(row, dict) and type(row.get("visibleComponentCount")) is int
            and row["visibleComponentCount"] == 1 and row.get("hostTerminated") is True,
            "One actual uniquely marked component widget and a terminated host are required")
    require(row.get("orientation") == "portrait", "This component pilot observes actual portrait only")
    family.orientation_geometry(row["orientation"], row.get("screenFrame"))
    bounds = widget.frame(row.get("widgetFrame"))
    require(bounds != row["screenFrame"] and family.contained(bounds, row["screenFrame"]),
            "The actual component widget must be a contained physical frame")
    window = row.get("window")
    require(isinstance(window, dict) and window.get("owner") == "com.apple.springboard"
            and window.get("exists") is True and window.get("hittable") is True
            and type(window.get("matchingWindowCount")) is int and window["matchingWindowCount"] == 1
            and type(window.get("identifier")) is str and len(window["identifier"]) <= 1024
            and family.contained(window.get("frame"), row["screenFrame"]) and family.contained(bounds, window["frame"]),
            "The real component widget must belong to one actual SpringBoard window")
    rows = row.get("components")
    require(isinstance(rows, dict) and set(rows) == set(COMPONENTS), "Every individually identified native component is required")
    frames = []
    for name, (label, value) in expected.items():
        element = rows[name]
        require(isinstance(element, dict) and element.get("identifier") == "hanlin-component-" + name
                and element.get("label") == label and element.get("value") == value
                and element.get("exists") is True and element.get("hittable") is True,
                "An actual component identifier, label, value or visibility is missing or stale")
        require(type(element.get("elementType")) is str and 0 < len(element["elementType"]) <= 128
                and type(element.get("elementTypeRaw")) is int and element["elementTypeRaw"] > 0,
                "The actual native accessibility type must be recorded, not inferred from authored JSX")
        if name in ("add", "link"):
            require(element.get("enabled") is True, "A required actual interactive component is disabled")
        bounds2 = widget.frame(element.get("frame"))
        require(family.contained(bounds2, bounds) and family.contained(bounds2, window["frame"]),
                "An actual component lies outside its owned widget/window")
        frames.append(bounds2)
    for index, a in enumerate(frames):
        for b in frames[index + 1:]:
            require(a[0] + a[2] <= b[0] or b[0] + b[2] <= a[0]
                    or a[1] + a[3] <= b[1] or b[1] + b[3] <= a[1],
                    "Actual component frames overlap")


def _strings(value):
    if isinstance(value, str):
        yield value
    elif isinstance(value, dict):
        for child in value.values():
            yield from _strings(child)
    elif isinstance(value, list):
        for child in value:
            yield from _strings(child)


def fresh_component_cache(facts, after):
    cache = facts["cache"]
    if cache is None:
        return False
    row = cache["record"]
    require(original.equal_typed_json(row.get("identity"), facts["identity"])
            and row.get("engine") == "expo" and row.get("family") == "systemLarge"
            and row.get("programSHA256") == facts["program"]["sha256"]
            and original.equal_typed_json(row.get("settings"), facts["instance"]["settings"])
            and row.get("renderSHA256") == cache["artifact"]["sha256"],
            "The native render belongs to another family, instance, program or configuration")
    rendered = family.finite(row.get("renderedAt"))
    require(rendered <= time.time() * 1000, "The native component render time is in the future")
    count, _ = widget.count_and_value(facts)
    strings = set(_strings(cache["node"]))
    expected = component_values(count)
    return rendered >= after and all("hanlin-component-" + name in strings
        and label in strings and value in strings for name, (label, value) in expected.items())


def require_observation(row, request, facts, index, after, previous=None):
    require(type(index) is int and index in (0, 1) and isinstance(row, dict)
            and type(row.get("index")) is int and row["index"] == index
            and row.get("attachmentLabel") == "widget-components-observation-" + str(index)
            and widget.count_and_value(facts)[0] == index,
            "The actual zero/one component observation was omitted, reordered or substituted")
    require_components(row, facts)
    start, end = original._epoch_milliseconds(row["requestedAt"]), original._epoch_milliseconds(row["capturedAt"])
    a, b = family.finite(row["requestedUptime"]), family.finite(row["capturedUptime"])
    verified, uptime = family.require_configuration(row.get("configuration"), request, row["widgetFrame"],
                                                    "widget-components-configuration-" + str(index), start)
    require(after <= start <= verified <= end <= time.time() * 1000 and a <= uptime <= b,
            "The component configuration/capture does not follow its actual placement/action")
    if previous is not None:
        require(start >= original._epoch_milliseconds(previous["capturedAt"]) and a >= previous["capturedUptime"]
                and row["screenFrame"] == previous["screenFrame"] and row["widgetFrame"] == previous["widgetFrame"]
                and row["window"] == previous["window"],
                "The actual widget/window/geometry changed across the single state action")
    return copy.deepcopy(row)


def require_transition(before, current):
    layout.require_variant(current, before)
    expected = copy.deepcopy(before["values"]); expected["count"] = 1.0
    require(before["state"]["revision"] == 0 and widget.count_and_value(before)[0] == 0
            and current["state"]["revision"] == 1 and widget.count_and_value(current)[0] == 1
            and original.equal_typed_json(current["values"], expected),
            "The actual Add must commit only the original zero-to-one native state transition")
    old, new = before["state"]["committedNonces"], current["state"]["committedNonces"]
    require(old == [] and len(new) == 1 and widget.uuid_string(new[0]),
            "The actual Add must commit exactly one fresh native invocation nonce")
    return new[0]


def retain_observation(directory, target, row, request):
    label = row["attachmentLabel"]
    result = widget.retain_ui_artifacts(directory, target, label, expected_text="Components count: " + str(row["index"]))
    ax = (target / (label + "-accessibility.txt")).read_text()
    require(all("hanlin-component-" + name in ax for name in COMPONENTS),
            "The real retained AX must expose every individually observed component identifier")
    pixels = family.png_geometry((target / (label + ".png")).read_bytes(), row["orientation"], row["screenFrame"])
    result.update(widget.retain_ui_artifacts(directory, target, row["configuration"]["attachmentLabel"],
                                            expected_text=request["instanceName"]))
    return {"artifacts": result, "screenshotPixels": pixels}


def require_cleanup(request, last, after):
    cleanup = request.get("cleanup")
    require(isinstance(cleanup, dict) and cleanup.get("instanceName") == request["instanceName"]
            and cleanup.get("action") == "Remove Widget" and cleanup.get("confirmationLabel") in ("Remove", "Remove Widget")
            and type(cleanup.get("visibleComponentCountAfter")) is int and cleanup["visibleComponentCountAfter"] == 0
            and cleanup.get("hostTerminated") is True and "cleanupFailure" not in request
            and request.get("unboundPlacementCreated") is False,
            "The exact owned component widget was not removed through its actual system confirmation")
    verified, uptime = family.require_configuration(cleanup.get("configuration"), request, last["widgetFrame"],
                                                     "widget-components-cleanup-configuration", after)
    removed = original._epoch_milliseconds(cleanup["removedAt"])
    removal_uptime = family.finite(cleanup["removedUptime"])
    require(verified <= removed <= time.time() * 1000 and uptime <= removal_uptime,
            "The actual component removal predates its fresh named configuration")
    restored = request.get("orientationRestoration")
    require(isinstance(restored, dict) and restored.get("priorOrientation") == request["priorOrientation"]
            and restored.get("orientation") == request["priorOrientation"] and "restorationFailure" not in request,
            "The actual initial orientation was not restored")
    family.orientation_geometry(restored["orientation"], restored["screenFrame"])
    require(removed <= original._epoch_milliseconds(restored["restoredAt"]) <= time.time() * 1000
            and removal_uptime <= family.finite(restored["restoredUptime"]),
            "Actual orientation restoration must follow owned cleanup")


def observe_case(args, request, directory, evidence, seen):
    identity = request_identity(request)
    run_id, phase = request["runID"], request.get("phase")
    roots = original.product_roots(args.device, args.bundle_id)
    case = seen.get(run_id)
    if case is None:
        require(phase == "widget-components-instance-created"
                and not any(row.get("kind") == "widgetComponents" for row in seen.values()),
                "Exactly one new component case must precede actual placement")
        inputs = load_inputs(args, evidence)
        require(original._epoch_milliseconds(request["startedAt"]) >= inputs["value"]["createdAt"] * 1000,
                "The UI case predates the source-bound component attempt")
        widget.current_code(args, roots, inputs)
        fixture = inputs["value"]["fixture"]
        facts = family.read_native(request, roots, fixture)
        require(facts["state"]["revision"] == 0 and not facts["state"]["committedNonces"]
                and widget.count_and_value(facts)[0] == 0, "The named component variant is not fresh and uninvoked")
        target = evidence / run_id; target.mkdir(exist_ok=False)
        case = {"kind": "widgetComponents", "finished": False, "identity": identity, "directory": str(directory),
                "roots": roots, "initial": facts, "previous": facts, "inputs": inputs, "admittedAt": time.time() * 1000,
                "placement": None, "addWidgetTappedAt": None, "observations": [], "artifacts": [],
                "armedAction": None, "action": None, "extension": original.widget_extension_executable(roots)}
        seen[run_id] = case
        widget.retain_response(directory, target, "identity.json", {"schema": 1, "runID": run_id, "status": "READY",
            "attemptID": inputs["value"]["attemptID"], "sourceSHA": inputs["value"]["sourceSHA"], "native": facts,
            "inputManifest": inputs, "actualContainers": {key: str(roots[key]) for key in ("app", "data", "group")}})
        return
    require(str(directory) == case["directory"] and original.equal_typed_json(identity, case["identity"])
            and all(roots[key] == case["roots"][key] for key in widget.ROOT_FIELDS)
            and request.get("attemptID") == case["inputs"]["value"]["attemptID"]
            and request.get("sourceSHA") == case["inputs"]["value"]["sourceSHA"],
            "The admitted component request/source/attempt/container identity changed")
    facts = family.read_native(request, roots, case["inputs"]["value"]["fixture"])
    layout.require_variant(facts, case["initial"])
    target = evidence / run_id
    if phase == "widget-components-arm-placement":
        family.require_same_native(facts, case["initial"])
        gallery = family.require_gallery(request, case["admittedAt"])
        before = request.get("preComponentPlacement")
        require(isinstance(before, dict) and type(before.get("visibleComponentCount")) is int
                and before["visibleComponentCount"] == 0 and before.get("orientation") == "portrait"
                and before.get("screenFrame") == gallery["prePlacement"]["screenFrame"]
                and case["admittedAt"] <= original._epoch_milliseconds(before["at"])
                <= original._epoch_milliseconds(gallery["prePlacement"]["at"])
                and family.finite(before["uptime"]) <= family.finite(gallery["prePlacement"]["uptime"]),
                "The actual placement page did not establish an absent component widget before opening the gallery")
        admission = {"gallery": gallery, "componentsBefore": before}
        if case["placement"] is not None:
            require(original.equal_typed_json(admission, case["placement"]["admission"]), "The armed actual gallery changed")
            return
        artifacts = {}
        for label in ("widget-components-before-placement", "widget-family-before-placement"):
            artifacts.update(widget.retain_ui_artifacts(directory, target, label))
        for page in gallery["galleryPages"]:
            artifacts.update(widget.retain_ui_artifacts(directory, target, page["attachmentLabel"]))
        ax = (target / (gallery["galleryPages"][-1]["attachmentLabel"] + "-accessibility.txt")).read_text().lower()
        require("hanlin script" in ax and "large" in ax, "The actual selected gallery AX lacks the offered Large page")
        case["placement"] = {"at": time.time() * 1000, "admission": copy.deepcopy(admission), "artifacts": artifacts}
        widget.retain_response(directory, target, "placement-armed.json", {"schema": 1, "runID": run_id,
            "status": "READY", "armedAt": case["placement"]["at"], "nativeBeforePlacement": facts, **admission})
        return
    require(case["placement"] is not None and request.get("hostTerminated") is True, "Placement was not armed or its host is running")
    require(original.equal_typed_json(family.require_gallery(request, case["admittedAt"]), case["placement"]["admission"]["gallery"])
            and original.equal_typed_json(request.get("preComponentPlacement"), case["placement"]["admission"]["componentsBefore"]),
            "Actual placement admission changed")
    placement_tap = original._epoch_milliseconds(request["addWidgetTappedAt"])
    require(case["placement"]["at"] <= placement_tap <= time.time() * 1000, "Actual Add Widget predates admission")
    if case["addWidgetTappedAt"] is None:
        require(phase == "widget-components-placed", "The physical placement must be observed first")
        case["addWidgetTappedAt"] = request["addWidgetTappedAt"]
    require(request["addWidgetTappedAt"] == case["addWidgetTappedAt"], "The actual placement time changed")
    if phase == "widget-components-arm-action":
        require(len(case["observations"]) == 1 and case["action"] is None and widget.uuid_string(request.get("actionID")),
                "One admitted placement and a fresh real Add identity must precede the action")
        admission = {key: copy.deepcopy(request[key]) for key in ("actionID", "armUI", "armConfiguration")}
        if case["armedAction"] is not None:
            require(original.equal_typed_json(admission, case["armedAction"]["admission"]), "The armed real action changed")
            return
        family.require_same_native(facts, case["previous"])
        require_components(request["armUI"], facts)
        family.require_configuration(request["armConfiguration"], request, request["armUI"]["widgetFrame"],
                                     "widget-components-arm-configuration", case["lastObservedAt"])
        require(request["armUI"]["widgetFrame"] == case["observations"][0]["widgetFrame"]
                and request["armUI"]["window"] == case["observations"][0]["window"],
                "The physical widget/window changed before the actual Add")
        artifacts = widget.retain_ui_artifacts(directory, target, "widget-components-arm-configuration",
                                               expected_text=request["instanceName"])
        case["armedAction"] = {"admission": admission, "before": facts, "at": time.time() * 1000, "artifacts": artifacts}
        widget.retain_response(directory, target, "action-armed.json", {"schema": 1, "runID": run_id,
            "status": "READY", "actionID": request["actionID"], "armedAt": case["armedAction"]["at"], "native": facts})
        return
    if phase in ("widget-components-placed", "widget-components-applied"):
        rows = request.get("observations")
        require(isinstance(rows, list) and 1 <= len(rows) <= 2
                and original.equal_typed_json(rows[:len(case["observations"])], case["observations"]),
                "An acknowledged native component observation changed")
        if len(rows) == len(case["observations"]):
            return
        index = len(case["observations"])
        require(len(rows) == index + 1 and phase == ("widget-components-placed" if index == 0 else "widget-components-applied"),
                "The actual component sequence was omitted or reordered")
        after, fresh_after, action = placement_tap, placement_tap, None
        if index == 0:
            family.require_same_native(facts, case["initial"])
        else:
            armed = case["armedAction"]
            require(armed is not None and request.get("actionID") == armed["admission"]["actionID"], "Actual Add has no immutable admission")
            tap = request.get("tap")
            require(isinstance(tap, dict) and tap.get("actionID") == request["actionID"], "The actual tap identity changed")
            began, returned = original._epoch_milliseconds(tap["beganAt"]), original._epoch_milliseconds(tap["returnedAt"])
            a, b = family.finite(tap["beganUptime"]), family.finite(tap["returnedUptime"])
            require(armed["at"] <= began <= returned <= time.time() * 1000 and a <= b, "The real Add tap predates admission")
            if "tap" not in armed:
                armed["tap"] = copy.deepcopy(tap)
            require(original.equal_typed_json(tap, armed["tap"]), "The real tap interval changed")
            if facts["state"]["revision"] == 0:
                return
            nonce = require_transition(armed["before"], facts)
            after, fresh_after = returned, began
            action = {"actionID": request["actionID"], "tap": copy.deepcopy(tap), "nativeNonce": nonce,
                      "beforeRevision": 0, "afterRevision": 1, "armedAt": armed["at"], "armArtifacts": armed["artifacts"]}
        row = require_observation(rows[-1], request, facts, index, after, case["observations"][-1] if index else None)
        if action:
            require(row["requestedUptime"] >= action["tap"]["returnedUptime"], "The updated component capture predates the real Add")
        if not fresh_component_cache(facts, fresh_after):
            return
        artifacts = retain_observation(directory, target, row, request)
        if index:
            require(artifacts["screenshotPixels"] == case["artifacts"][0]["screenshotPixels"], "Actual component PNG geometry changed")
        case["observations"].append(row); case["artifacts"].append(artifacts)
        case["previous"], case["lastObservedAt"] = facts, time.time() * 1000
        if action:
            case["action"] = action; case["armedAction"] = None
        widget.retain_response(directory, target, "observation-" + str(index) + ".json", {"schema": 1, "runID": run_id,
            "status": "READY", "native": facts, "actualObservation": row, "actualAttachments": artifacts,
            "action": action, "observedAt": case["lastObservedAt"]})
    elif phase == "widget-components-complete" and not case["finished"]:
        require(len(case["observations"]) == 2 and case["action"] is not None and case["armedAction"] is None
                and original.equal_typed_json(request.get("observations"), case["observations"])
                and request.get("actionID") == case["action"]["actionID"],
                "Both actual component observations and the real native Add are required")
        family.require_same_native(facts, case["previous"])
        require_cleanup(request, case["observations"][-1], case["lastObservedAt"])
        artifacts = widget.retain_ui_artifacts(directory, target, "widget-components-cleanup-configuration",
                                               expected_text=request["instanceName"])
        for label in ("widget-components-remove-confirmation", "widget-components-removed", "widget-components-restored"):
            artifacts.update(widget.retain_ui_artifacts(directory, target, label))
        restoration = request["orientationRestoration"]
        family.png_geometry((target / "widget-components-restored.png").read_bytes(), restoration["orientation"], restoration["screenFrame"])
        current = load_inputs(args, evidence)
        require(current == case["inputs"], "The current source/recipe/input manifest changed")
        widget.current_code(args, roots, current)
        final_roots = original.product_roots(args.device, args.bundle_id)
        require(all(final_roots[key] == roots[key] for key in widget.ROOT_FIELDS), "Final actual product containers changed")
        final = family.read_native(request, final_roots, current["value"]["fixture"])
        family.require_same_native(final, case["previous"])
        require(fresh_component_cache(final, original._epoch_milliseconds(case["action"]["tap"]["beganAt"])),
                "The actual current component render is no longer available")
        require(original.widget_extension_executable(final_roots) == case["extension"], "The actual widget extension changed")
        widget.retain_response(directory, target, "completion.json", {"schema": 1, "runID": run_id, "status": "EXECUTED_PASS",
            "attemptID": request["attemptID"], "sourceSHA": request["sourceSHA"], "inputManifestSHA256": current["sha256"],
            "native": final, "placement": case["placement"], "observations": case["observations"],
            "observationArtifacts": case["artifacts"], "action": case["action"], "cleanup": request["cleanup"],
            "orientationRestoration": restoration, "actualAttachments": artifacts,
            "scope": "One actual Large iPad Home Screen component fixture, native AX identities/labels/values/types/frames/PNGs and one real Add zero-to-one nonce/revision",
            "limitations": "No other family, appearance, RTL, VoiceOver speech, preview, asset image, Link navigation, Live Activity or physical-device acceptance"})
        case["finished"] = True
