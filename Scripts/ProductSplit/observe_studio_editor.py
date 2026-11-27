"""Read actual Studio files and UI evidence for the original paired runner.

All workspace, editor, preference, conflict and recovery writes belong to the
shipping UI. This observer writes only XCTest replies and its evidence. The
runner's separate input producer may create ordinary Documents import inputs;
it cannot create a Studio project, draft, preference, grant or acceptance result.
"""
from pathlib import Path
import base64
import datetime
import json
import math
import plistlib
import re
import time
import uuid
from urllib.parse import urlsplit

import observe_shortcut_surfaces as shared
import observe_studio_gallery as gallery
from observe_share_translation_surfaces import ROOT_KEYS, document_bytes, normalized_relative, raw_file

require = shared.require
equal = shared.equal_typed_json
RUNTIME = gallery.RUNTIME
FIXED = ("schema", "runID", "surface", "scenario", "engine", "exampleID", "marker", "startedAt", "processID")
STEPS = {
    "files": ("gallery-ready", "copy-ready", "file-created", "file-moved", "folders-created",
              "style-saved", "project-moved", "reopened"),
    "assistance": ("gallery-ready", "copy-ready", "assistance-observed", "preferences-saved",
                   "logs-ready", "log-exported", "reopened"),
    "conflict": ("gallery-ready", "copy-ready", "document-ready", "two-editors-ready", "first-save",
                 "conflict-visible", "reload-observed", "second-save", "second-conflict",
                 "recovered-draft", "copy-saved", "reopened"),
    "import": ("gallery-ready", "import-input-ready", "copy-ready", "source-edited", "reopened"),
}
FONT = "CourierNewPSMT"
STYLE = {"schemaVersion": 1, "symbol": "star.fill", "color": "purple"}


def validate_request(request):
    require(type(request.get("schema")) is int and request["schema"] == 1
            and request.get("surface") == "studioEditor", "Unknown actual Studio editor exchange")
    run_id = request.get("runID")
    require(isinstance(run_id, str) and re.fullmatch(gallery.UUID, run_id), "Invalid Studio editor run")
    scenario = request.get("scenario")
    require(scenario in STEPS and request.get("phase") in STEPS[scenario], "Unknown Studio editor scenario/phase")
    engine = request.get("engine")
    require(engine in ("expo", "nativescript")
            and request.get("exampleID") == ("expo-hello-world" if engine == "expo" else "nativescript-hello-world"),
            "Use the actual original hello-world source for the selected engine")
    require(scenario == "files" or engine == ("nativescript" if scenario == "conflict" else "expo"),
            "This scenario differs from its original-runner selector")
    require(request.get("marker") == "שלום Editor " + run_id[:8]
            and type(request.get("processID")) is int and request["processID"] > 0,
            "The editor must bind the fresh UI marker and actual application PID")
    start = shared._epoch_milliseconds(request.get("startedAt"))
    observed = shared._epoch_milliseconds(request.get("observedAt"))
    require(start <= observed <= time.time() * 1000 + 5000, "Invalid actual editor UI timestamps")
    require(type(request.get("currentProcessID")) is int and request["currentProcessID"] > 0,
            "Every phase must observe the actual current application PID")
    return run_id


def paths(request):
    suffix = request["runID"][:8]
    return {"created": "notes/first-" + suffix + ".ts", "moved": "notes/nested/moved-" + suffix + ".ts",
            "folder": "Libraries-" + suffix + "/Nested", "assistance": "notes/assistance-" + suffix + ".ts",
            "conflict": "notes/conflict-" + suffix + ".ts", "export": "studio-log-" + suffix + ".log"}


def text_for(request, version):
    value = json.dumps(request["marker"] + " " + version, ensure_ascii=False)
    return "export const marker = " + value + ";\n"


def assistance_source(request):
    return ("const greeting = " + json.dumps(request["marker"], ensure_ascii=False)
            + ";\ngreeting.toUpperCase();\ngreeting.substring(0, 2);\n")


def expected_source(case, additions=None):
    return {key: value["raw"] for key, value in case["sdk"]["template"].items()} | (additions or {})


def project_snapshot(case, roots, relative=None, additions=None):
    relative = normalized_relative(relative or case["project"])
    actual = gallery.source_tree(case["workspace"] / relative, roots["data"])
    expected = expected_source(case, additions)
    require(set(actual) == set(expected)
            and all(actual[name]["raw"] == value for name, value in expected.items()),
            "The real project lost, changed or added source outside the admitted UI operation")
    return gallery.hashes(actual)


def screen(directory, label, process_id, needles=()):
    require(re.fullmatch(r"studio-editor-[a-z0-9-]+", label) is not None, "Unknown actual editor screenshot")
    image = raw_file(directory / (label + ".png"), directory)
    tree = raw_file(directory / (label + "-accessibility.txt"), directory)
    text = tree["raw"].decode("utf-8")
    require(image["raw"].startswith(b"\x89PNG\r\n\x1a\n")
            and re.search(r"^Attributes: Application, .*?, pid: " + str(process_id) + r",", text)
            and all(needle in text for needle in needles),
            "The retained screenshot/accessibility observation does not bind the actual editor state")
    return {"image": document_bytes(image), "accessibility": document_bytes(tree)}


def window_observations(request, expected_texts, admitted=None):
    """Correlate real left/right UIWindow queries, never AX snapshot addresses.

    Horizontal geometry selects the independently visible editor. Its stale
    text and the native draft.original bytes establish the separate writer;
    geometry is not represented as a persistent scene/window identifier.
    """
    windows = request.get("editorWindows")
    bounds = request.get("windowingScreenFrame")
    require(isinstance(bounds, list) and len(bounds) == 4
            and all(type(x) in (int, float) and math.isfinite(x) for x in bounds)
            and bounds[2] > 500 and bounds[3] > 500,
            "Window geometry must use the actual Home Screen accessibility bounds")
    if admitted:
        require(equal(bounds, admitted["screenFrame"]), "The actual screen geometry changed during the two-writer case")
    require(type(request.get("editorWindowCount")) is int and request["editorWindowCount"] == 2
            and isinstance(windows, list) and len(windows) == 2, "Two actual editor UIWindow queries are required")
    for index, window in enumerate(windows):
        require(isinstance(window, dict) and set(window) == {"side", "windowFrame", "editorFrame", "text"}
                and window["side"] == ("left" if index == 0 else "right"),
                "Actual windows must be correlated by visible left/right order")
        for key in ("windowFrame", "editorFrame"):
            rectangle = window[key]
            require(isinstance(rectangle, list) and len(rectangle) == 4
                    and all(type(x) in (int, float) and math.isfinite(x) for x in rectangle)
                    and rectangle[2] >= 100 and rectangle[3] > 20, "Invalid actual window/editor geometry")
        x, y, width, height = window["windowFrame"]
        ex, ey, ew, eh = window["editorFrame"]
        require(x >= bounds[0] - 2 and y >= bounds[1] - 2 and x + width <= bounds[0] + bounds[2] + 2
                and y + height <= bounds[1] + bounds[3] + 2
                and ex >= x - 2 and ey >= y - 2 and ex + ew <= x + width + 2 and ey + eh <= y + height + 2
                and window["text"] == expected_texts[index], "A distinct window must contain its exact independently observed editor")
        if admitted:
            old = admitted["windows"][index]["windowFrame"]
            require(abs(old[0] - x) <= 3 and abs(old[2] - width) <= 3,
                    "The actual tiled window's horizontal ownership changed")
    a, b = [window["windowFrame"] for window in windows]
    require(a[0] + a[2] <= b[0] + 2, "Both source editors must be visible in nonoverlapping tiled windows")
    return windows


def two_windows(request, directory):
    windows = window_observations(request, [text_for(request, "original")] * 2)
    require(request.get("windowingEnabledObserved") is True and request.get("newWindowCreatedObserved") is True
            and type(request.get("windowingSettingsProcessID")) is int
            and type(request.get("windowingSystemProcessID")) is int
            and request["windowingSettingsProcessID"] > 0 and request["windowingSystemProcessID"] > 0
            and len({request["processID"], request["windowingSettingsProcessID"], request["windowingSystemProcessID"]}) == 3,
            "The two-writer setup must use actual system settings and New Window UI")
    settings = screen(directory, "studio-editor-windowing-settings", request["windowingSettingsProcessID"], ("Windowed Apps",))
    system = screen(directory, "studio-editor-new-window-menu", request["windowingSystemProcessID"], ("New Window", "Hanlin MiniApps"))
    proof = screen(directory, "studio-editor-two-windows", request["processID"],
                   ("miniapps-studio-editor", request["marker"]))
    tree = Path(proof["accessibility"]["path"]).read_text()
    require(tree.count("miniapps-studio-editor'") >= 2 or tree.count('miniapps-studio-editor"') >= 2,
            "The actual accessibility tree contains fewer than two source editors")
    return {"windows": windows, "screenFrame": request["windowingScreenFrame"], "proof": proof,
            "settings": settings, "system": system}


def matching_drafts(case, roots):
    directory = roots["data"] / RUNTIME / "clients/tools/miniapp-studio-drafts"
    if not directory.exists():
        return []
    require(directory.is_dir() and not directory.is_symlink(), "The actual recovery journal directory changed")
    found = []
    for file in directory.glob("*.json"):
        document = shared.read_document(file, roots["data"])
        value = document["value"]
        if value.get("projectPath") == str(case["workspace"] / case["project"]):
            require(re.fullmatch(r"[0-9A-F-]{36}", value.get("id", ""))
                    and str(uuid.UUID(value["id"])).upper() == value["id"]
                    and file.name == value["id"] + ".json", "The actual draft identity is invalid")
            found.append(document)
    return found


def conflict_draft(case, roots, original, edited):
    drafts = matching_drafts(case, roots)
    require(len(drafts) == 1, "Exactly one actual draft from the stale editor is required")
    document = drafts[0]
    value = document["value"]
    require(value.get("path") == paths(case["fixed"])["conflict"]
            and value.get("text") == text_for(case["fixed"], edited)
            and isinstance(value.get("original"), str)
            and base64.b64decode(value["original"], validate=True) == text_for(case["fixed"], original).encode(),
            "The real conflict journal must preserve both stale original bytes and the user's changed draft")
    saved = value.get("savedAt")
    require(type(saved) in (int, float) and math.isfinite(saved)
            and shared._epoch_milliseconds(case["fixed"]["startedAt"]) / 1000 - 978307200 - 5 <= saved
            <= time.time() - 978307200 + 5, "The conflict draft is stale or has an invalid native Date encoding")
    return document_bytes(document) | {"id": value["id"], "text": value["text"], "original": value["original"]}


def preferences(roots, bundle_id):
    document = raw_file(roots["data"] / "Library/Preferences" / (bundle_id + ".plist"), roots["data"])
    value = plistlib.loads(document["raw"])
    actual = {key: value.get("miniapps.studio." + key) for key in ("fontName", "fontSize", "theme")}
    require(actual["fontName"] == FONT and type(actual["fontSize"]) in (int, float)
            and actual["fontSize"] == 22 and actual["theme"] == "dark",
            "The actual persisted font, size and theme differ from the real UI choices")
    return {"document": document_bytes(document), "values": actual}


def actual_log(case, roots):
    document = raw_file(roots["data"] / RUNTIME / "logs/node-runtime.log", roots["data"], 64 * 1024 * 1024)
    text = document["raw"].decode("utf-8")
    matches = []
    for line in text.splitlines():
        try:
            value = shared.parse_json(line.encode())
        except (ValueError, TypeError):
            continue
        if not isinstance(value, dict) or value.get("event") != "runtime_paths_configured":
            continue
        timestamp = value.get("timestamp")
        require(isinstance(timestamp, str), "The actual runtime diagnostic has no timestamp")
        try:
            moment = datetime.datetime.fromisoformat(timestamp.replace("Z", "+00:00"))
            require(moment.utcoffset() is not None, "The actual log timestamp has no time zone")
            observed = moment.timestamp()
        except ValueError as error:
            raise ValueError("The actual runtime timestamp is invalid") from error
        if observed < shared._epoch_milliseconds(case["fixed"]["startedAt"]) / 1000 - 5:
            continue
        require(observed <= time.time() + 5, "A future log event cannot prove this run")
        root = roots["data"] / RUNTIME
        require(equal(value.get("fields"), {"home": str(root / "runtime/home"), "npmCache": str(root / "cache/npm"),
                "npmPrefix": str(root / "runtime/npm-prefix"), "npmTemp": str(root / "staging/tmp")}),
                "The real log belongs to another runtime container")
        matches.append((line, timestamp))
    require(matches, "The actual original Node runtime has no fresh startup diagnostic for this UI run")
    return document, matches[-1]


def input_request(case):
    fixed = case["fixed"]
    return {"schema": 1, "runID": fixed["runID"], "engine": fixed["engine"],
            "exampleID": fixed["exampleID"], "marker": fixed["marker"], "startedAt": fixed["startedAt"],
            "dataContainer": str(case["roots"]["data"]), "appContainer": str(case["roots"]["app"]),
            "hostArchiveSHA256": case["sdk"]["archive"]["sha256"],
            "templateHashes": gallery.hashes(case["sdk"]["template"])}


def input_manifest(args, evidence):
    require(getattr(args, "studio_inputs", None) is not None, "The original source input producer was not admitted")
    path = Path(args.studio_inputs).resolve(strict=True)
    require(path.parent == evidence.parent and path.name == "studio-source-inputs.json",
            "The original runner must explicitly admit its normal source-input manifest")
    document = shared.read_document(path, evidence.parent)
    require(equal(document["value"], {"schema": 1, "kind": "studio-source-input-v1",
            "requestRoot": str(evidence), "responseRoot": str(evidence.parent / "studio-source-inputs")}),
            "The source input producer paths differ from the original owned runner")
    return document


def verify_input(case, args, roots, evidence):
    manifest = input_manifest(args, evidence)
    require(manifest["sha256"] == case["inputManifest"]["sha256"], "The input producer manifest changed")
    request = input_request(case)
    response_path = Path(manifest["value"]["responseRoot"]) / (request["runID"] + ".json")
    response = shared.read_document(response_path, evidence.parent)
    value = response["value"]
    require(set(value) == set(request) | {"status", "producerRequestSHA256", "inputFolder", "projectFolder"}
            and equal({key: value.get(key) for key in request}, request)
            and value.get("status") == "STAGED_INPUTS_ONLY"
            and value.get("producerRequestSHA256") == shared.read_document(
                case["output"] / "studio-import-input-request.json", evidence)["sha256"],
            "The normal Files input response does not bind this exact source request")
    name = "HanlinStudioImport-" + request["runID"]
    require(value.get("inputFolder") == name and value.get("projectFolder") == request["exampleID"],
            "The ordinary import input changed its assigned directory")
    source = roots["data"] / "Documents" / name / request["exampleID"]
    actual = gallery.source_tree(source, roots["data"])
    require(gallery.hashes(actual) == request["templateHashes"], "The normal imported source differs from the shipped original")
    return {"response": document_bytes(response), "folder": name, "projectFolder": request["exampleID"],
            "sourceHashes": gallery.hashes(actual)}


def publish(directory, output, name, value):
    require(name == "identity.json" or name == "completion.json"
            or re.fullmatch(r"editor-[a-z-]+\.json", name), "Unknown actual editor response")
    require(directory.is_dir() and not directory.is_symlink(), "The actual XCTest exchange changed")
    target = directory / name
    require(not target.exists(), "An editor observation response cannot be replaced")
    data = (json.dumps(value, ensure_ascii=False, sort_keys=True, indent=2) + "\n").encode()
    temporary = directory / (name + ".observer-tmp")
    with temporary.open("xb") as stream:
        stream.write(data)
    temporary.replace(target)
    (output / name).write_bytes(data)


def observe_case(args, request, directory, evidence, seen):
    run_id = validate_request(request)
    phase, scenario = request["phase"], request["scenario"]
    case = seen.get(run_id)
    if case is None:
        require(phase == "gallery-ready" and request.get("galleryLoaded") is True,
                "The actual shipped Gallery must load before an editor case")
        roots = shared.product_roots(args.device, args.bundle_id)
        require(all(not evidence.is_relative_to(roots[key]) for key in ("app", "data", "group")),
                "Editor observer evidence must be outside production containers")
        sdk = gallery.bind_sdk(roots, request)
        workspace = roots["data"] / RUNTIME / "clients/tools/miniapp-studio"
        wanted = paths(request)
        require(not (roots["data"] / "Documents" / wanted["export"]).exists()
                and not (workspace / wanted["folder"].split("/")[0]).exists()
                and not (roots["data"] / "Documents" / ("HanlinStudioImport-" + run_id)).exists(),
                "The fresh run's export, library folder or ordinary import input already exists")
        require(request["currentProcessID"] == request["processID"], "Initial Studio PID changed before admission")
        output = evidence / run_id
        output.mkdir(exist_ok=False)
        case = {"kind": "studioEditor", "fixed": {key: request[key] for key in FIXED}, "roots": roots,
                "directory": str(directory), "sdk": sdk, "workspace": workspace, "output": output,
                "baselineProjects": gallery.matching_projects(workspace, request["exampleID"]),
                "done": [], "finished": False}
        if scenario == "import":
            case["inputManifest"] = input_manifest(args, evidence)
            temporary = output / "studio-import-input-request.tmp"
            temporary.write_text(json.dumps(input_request(case), ensure_ascii=False, sort_keys=True, indent=2) + "\n")
            temporary.replace(output / "studio-import-input-request.json")
        seen[run_id] = case
    require(case["kind"] == "studioEditor" and case["directory"] == str(directory)
            and equal({key: request.get(key) for key in FIXED}, case["fixed"]),
            "The prepared editor scenario, source, process or exchange identity changed")
    if case["finished"] or phase in case["done"]:
        return
    require(phase == STEPS[scenario][len(case["done"])], "The actual UI skipped an admitted editor operation")
    observed_at = shared._epoch_milliseconds(request["observedAt"])
    # The preserved original XCTest timestamp helper records whole seconds.
    # Strict ordered phase admission prevents replay; equal seconds are valid.
    require(observed_at >= case.get("lastObservedAt", 0), "An editor phase regressed its UI observation time")
    restarting = phase in ("recovered-draft", "reopened")
    current_pid = request["currentProcessID"]
    if not restarting:
        require(current_pid == case.get("recoveredProcessID", request["processID"]),
                "The actual editor process changed between admitted operations")
    else:
        require(current_pid != request["processID"], "The editor recovery/reopen did not actually restart its process")
        if scenario == "conflict" and phase == "reopened":
            require(current_pid != case["recoveredProcessID"], "The saved recovery copy must survive a second real restart")
    roots = gallery.current_roots(args, case["roots"])
    gallery.verify_sdk_unchanged(case, roots)
    result = {"schema": 1, "runID": run_id, "scenario": scenario, "status": "READY"}
    updates = {}
    wanted = paths(request)
    additions = dict(case.get("additions", {}))
    if phase == "gallery-ready":
        result.update(sdk=gallery.sdk_summary(case["sdk"]), workspace=str(case["workspace"]))
    elif phase == "import-input-ready":
        result.update(verify_input(case, args, roots, evidence))
    elif phase == "copy-ready":
        require(request.get("copyObserved") is True, "The real Gallery/Files copy did not finish")
        fresh = gallery.matching_projects(case["workspace"], request["exampleID"]) - case["baselineProjects"]
        require(len(fresh) == 1, "Exactly one fresh independent original project is required")
        project = next(iter(fresh))
        result.update(projectName=project, sourceHashes=project_snapshot({**case, "project": project}, roots))
        updates["project"] = project
        if scenario == "import":
            result["ordinaryInput"] = verify_input(case, args, roots, evidence)
    elif scenario == "files":
        if phase == "file-created":
            additions[wanted["created"]] = text_for(request, "created").encode()
            require(request.get("createdPath") == wanted["created"] and request.get("fileCreateObserved") is True,
                    "The original editor did not create the configured nested source")
        elif phase == "file-moved":
            additions.pop(wanted["created"])
            additions[wanted["moved"]] = text_for(request, "after move").encode()
            require(request.get("movedPath") == wanted["moved"] and request.get("fileMoveObserved") is True,
                    "The original editor did not move and continue editing its actual open file")
        elif phase == "folders-created":
            folder = case["workspace"] / wanted["folder"]
            require(request.get("folderCreateObserved") is True and folder.is_dir() and not folder.is_symlink()
                    and not list(folder.iterdir()), "The real UI did not create the fresh nested library folders")
        elif phase == "style-saved":
            style = shared.read_document(case["workspace"] / case["project"] / ".miniapps-folder.json", roots["data"])
            require(request.get("styleSaveObserved") is True and equal(style["value"], STYLE),
                    "The actual saved project symbol/color differs from its real UI selection")
            additions[".miniapps-folder.json"] = raw_file(Path(style["path"]), roots["data"])["raw"]
        elif phase == "project-moved":
            destination = wanted["folder"] + "/" + case["project"]
            require(request.get("projectMoveObserved") is True and request.get("movedProject") == destination
                    and not (case["workspace"] / case["project"]).exists(), "The real project move left its old source behind")
            project_snapshot(case, roots, destination, additions)
            updates["movedFrom"] = case["project"]
            updates["project"] = destination
        if "movedFrom" in case:
            require(not (case["workspace"] / case["movedFrom"]).exists(),
                    "The moved project's old library path reappeared")
        if phase != "project-moved":
            result["sourceHashes"] = project_snapshot(case, roots, additions=additions)
        updates["additions"] = additions
    elif scenario == "assistance":
        additions[wanted["assistance"]] = assistance_source(request).encode()
        result["sourceHashes"] = project_snapshot(case, roots, additions=additions)
        updates["additions"] = additions
        if phase == "assistance-observed":
            require(all(request.get(k) is True for k in ("completionApplied", "inlineDocumentationObserved", "parameterHintObserved", "referenceOpened"))
                    and request.get("referenceURL") == "https://docs.expo.dev/", "The actual editor assistance/reference controls were not observed")
            prefix = "const greeting = " + json.dumps(request["marker"], ensure_ascii=False) + ";\ngreeting.toUpperCase"
            reference = urlsplit(request.get("referenceAddressObserved", ""))
            require(request.get("completionIntermediateSource") == prefix
                    and request.get("parameterIntermediateSource") == prefix + "();\ngreeting.substring("
                    and reference.scheme == "https" and reference.hostname == "docs.expo.dev"
                    and reference.username is None and reference.password is None,
                    "The real completion/cursor/reference observations differ from the authored source route")
            result["completion"] = screen(directory, "studio-editor-completion", request["processID"], ("toUpperCase", "miniapps-studio-editor"))
            result["documentation"] = screen(directory, "studio-editor-documentation", request["processID"], ("toUpperCase", "Open API reference"))
            result["parameterHint"] = screen(directory, "studio-editor-parameter-hint", request["processID"], ("substring", "start", "number"))
            safari_pid = request.get("referenceProcessID")
            require(type(safari_pid) is int and safari_pid > 0 and safari_pid != request["processID"], "Reference must open in the actual system browser")
            result["reference"] = screen(directory, "studio-editor-reference", safari_pid, ("docs.expo.dev",))
        elif phase == "preferences-saved":
            require(request.get("fontPickerObserved") is True and request.get("fontFamilySelected") == "Courier New"
                    and request.get("fontFaceSelected") == "Regular"
                    and type(request.get("fontSizeSelected")) is int and request["fontSizeSelected"] == 22
                    and request.get("themeSelected") == "dark", "The actual font/theme controls were not used")
            result["fontPicker"] = screen(directory, "studio-editor-font-picker", current_pid, ("Courier New",))
            result["fontFace"] = screen(directory, "studio-editor-font-face", current_pid, ("Regular",))
            result["themePicker"] = screen(directory, "studio-editor-theme", current_pid, ("Dark",))
            updates["preferences"] = preferences(roots, args.bundle_id)
            result["preferences"] = updates["preferences"]
        elif phase == "logs-ready":
            require(request.get("logSearchQuery") == "runtime_paths_configured" and request.get("logSearchObserved") is True,
                    "The actual Live logs search was not used")
            log, (line, timestamp) = actual_log(case, roots)
            updates["logBeforeExport"] = log["raw"]
            result["log"] = document_bytes(log)
            result["observedLine"] = line
            result["ui"] = screen(directory, "studio-editor-logs", current_pid,
                                  ("runtime_paths_configured", "Live logs", timestamp))
        elif phase == "log-exported":
            require(request.get("logExportObserved") is True and request.get("logExportName") == wanted["export"],
                    "The real log export must use this fresh run's assigned Files name")
            exported = raw_file(roots["data"] / "Documents" / wanted["export"], roots["data"], 64 * 1024 * 1024)
            log, _ = actual_log(case, roots)
            require(exported["raw"].startswith(case["logBeforeExport"]) and log["raw"].startswith(exported["raw"]),
                    "The actual exported file is not a complete observed prefix of the real append-only runtime log")
            updates["export"] = document_bytes(exported)
            result["export"] = updates["export"]
    elif scenario == "conflict":
        path = wanted["conflict"]
        if phase == "document-ready":
            additions[path] = text_for(request, "original").encode()
            require(request.get("documentCreateObserved") is True, "Create the conflict input through the original source editor")
        elif phase == "two-editors-ready":
            updates["twoWindows"] = two_windows(request, directory)
        elif phase in ("first-save", "second-save"):
            original, newer = ("original", "writer A") if phase == "first-save" else ("writer A", "writer A again")
            windows = window_observations(request, [text_for(request, newer), text_for(request, original)],
                                          case["twoWindows"])
            require(request.get("writerAObserved") == text_for(request, newer)
                    and request.get("staleWriterBObserved") == text_for(request, original),
                    "The actual first writer and independently stale second editor must remain distinct")
            result["windowObservations"] = windows
            additions[path] = text_for(request, newer).encode()
        elif phase in ("conflict-visible", "second-conflict", "recovered-draft"):
            original, edited = ("original", "writer B draft") if phase == "conflict-visible" else ("writer A", "writer B recovered")
            require(request.get("conflictObserved") is True and request.get("draftTextObserved") == text_for(request, edited),
                    "The real conflict UI and unchanged stale draft were not observed")
            draft = conflict_draft(case, roots, original, edited)
            if phase == "recovered-draft":
                require(request.get("recoveredDraftOpened") is True and draft == case["draft"],
                        "The original recovery UI must reopen the same real journal after application restart")
                result["recoveryUI"] = screen(directory, "studio-editor-recovery-list", current_pid,
                                               ("Recovered drafts", wanted["conflict"]))
                result["conflictUI"] = screen(directory, "studio-editor-recovered-conflict", current_pid,
                                               ("Your draft is preserved", "Save a copy", request["marker"]))
                updates["recoveredProcessID"] = current_pid
            else:
                winner = "writer A" if phase == "conflict-visible" else "writer A again"
                result["windowObservations"] = window_observations(request,
                    [text_for(request, winner), text_for(request, edited)], case["twoWindows"])
                result["conflictUI"] = screen(directory, "studio-editor-" + phase, current_pid,
                                               ("Your draft is preserved", "Reload file", "Save a copy"))
            updates["draft"] = draft
            result["draft"] = draft
        elif phase == "reload-observed":
            require(request.get("reloadPressed") is True and request.get("reloadedText") == text_for(request, "writer A")
                    and not matching_drafts(case, roots), "Reload must adopt the real winning file and clear the stale draft")
        elif phase == "copy-saved":
            require(request.get("saveCopyPressed") is True, "The original Save a copy action was not used")
            actual = gallery.source_tree(case["workspace"] / case["project"], roots["data"])
            extra = set(actual) - set(expected_source(case, additions))
            require(len(extra) == 1, "Conflict recovery must create exactly one separate original copy")
            copied = next(iter(extra))
            require(re.fullmatch(re.escape(path[:-3]) + r"-copy-[0-9A-F]{8}\.ts", copied)
                    and actual[copied]["raw"] == text_for(request, "writer B recovered").encode()
                    and not matching_drafts(case, roots), "Saving a conflict copy changed bytes or retained an already saved draft")
            additions[copied] = actual[copied]["raw"]
            updates["conflictCopy"] = copied
            result["copyPath"] = copied
        result["sourceHashes"] = project_snapshot(case, roots, additions=additions)
        updates["additions"] = additions
    elif scenario == "import":
        result["ordinaryInput"] = verify_input(case, args, roots, evidence)
        if phase == "source-edited":
            require(request.get("importEditObserved") is True, "Edit the imported copy using the real source editor")
            file = gallery.EXAMPLES[request["exampleID"]][1]
            original = case["sdk"]["template"][file]["raw"].decode()
            heading = gallery.EXAMPLES[request["exampleID"]][2]
            require(original.count(heading) == 1, "Unexpected original imported heading")
            additions[file] = original.replace(heading, request["marker"]).encode()
        result["sourceHashes"] = project_snapshot(case, roots, additions=additions)
        updates["additions"] = additions
    if phase == "reopened":
        require(request.get("reopenedSourceObserved") is True and type(request.get("reopenedProcessID")) is int
                and request["reopenedProcessID"] == current_pid,
                "The original UI must reopen the saved source after actual restart")
        result["reopened"] = screen(directory, "studio-editor-reopened", request["reopenedProcessID"],
                                    (request["marker"], "miniapps-studio-editor"))
        if scenario == "assistance":
            result["preferences"] = preferences(roots, args.bundle_id)
            require(equal(result["preferences"]["values"], case["preferences"]["values"]), "Saved editor preferences did not survive restart")
            actual_export = raw_file(Path(case["export"]["path"]), roots["data"], 64 * 1024 * 1024)
            require(actual_export["sha256"] == case["export"]["sha256"], "The actual exported log changed")
        if scenario == "files":
            require(request.get("reopenedSymbolObserved") == STYLE["symbol"]
                    and request.get("reopenedColorObserved") == STYLE["color"],
                    "The real folder appearance UI must display its persisted choices after restart")
            result["appearanceUI"] = screen(directory, "studio-editor-reopened-appearance", current_pid,
                                              ("Folder appearance", "star.fill", "Purple"))
        if scenario == "conflict":
            require(request.get("winningTextObserved") == text_for(request, "writer A again")
                    and request.get("copyTextObserved") == text_for(request, "writer B recovered")
                    and request.get("conflictCopyPath") == case["conflictCopy"]
                    and not matching_drafts(case, roots), "The actual winning file and recovered copy did not both survive")
        gallery.verify_sdk_unchanged(case, roots, full=True)
        result.update(status="EXECUTED_PASS", sdk=gallery.sdk_summary(case["sdk"]),
                      scope="Actual local Studio UI/files/editor operations for " + scenario,
                      iCloudAccountAndRemoteConflict="NOT_RUN", physicalDevice="NOT_RUN")
    result["actualUI"] = screen(directory, "studio-editor-phase-" + phase, current_pid,
                                ("miniapps-gallery-" + request["exampleID"],) if phase == "gallery-ready" else ())
    gallery.current_roots(args, roots)
    name = "identity.json" if phase == "gallery-ready" else "completion.json" if phase == "reopened" else "editor-" + phase + ".json"
    publish(directory, case["output"], name, result)
    case.update(updates)
    case["done"].append(phase)
    case["lastObservedAt"] = observed_at
    case["finished"] = phase == "reopened"
