"""Read-only source binding for genuine MiniApps Studio gallery XCTest cases.

The existing UI companion creates both copies, types edits, validates, builds,
installs and taps the original runtime controls. This leaf only observes the
app-bundled SDK, its actual unpacked files, the two project copies, original
authoring output and current installed source. It writes only test exchange
responses and evidence. It does not author, compile or install a project.
"""
from pathlib import Path
import io
import json
import os
import re
import stat
import time
import zipfile

import observe_shortcut_surfaces as shared
from observe_share_translation_surfaces import (
    INSTALLED, ROOT_KEYS, document_bytes, normalized_relative, raw_file,
    verify_installed_fixture_archive,
)

require = shared.require
equal = shared.equal_typed_json
UUID = r"[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}"
RUNTIME = Path("Library/Application Support/HanlinRuntime/v1")
STEPS = ("gallery-ready", "copy-one", "copy-two", "source-edited", "build-preview", "runtime-observed")
FIXED = ("schema", "runID", "surface", "engine", "exampleID", "marker", "packageTitle", "startedAt")
EXAMPLES = {
    "expo-hello-world": ("expo", "App.tsx", "Hello from Expo!", "Button taps: 0", "Button taps: 1"),
    "sdk-only-departure-budget": ("expo", "App.tsx", "Departure Budget", "55 minutes reserved before the target", "35 minutes reserved before the target"),
    "nativescript-hello-world": ("nativescript", "index.ts", "Hello from NativeScript!", "Button taps: 0", "Button taps: 1"),
    "sdk-only-table-share": ("nativescript", "index.ts", "Table Share", "3 people pay $35.42 each.", "2 pay $26.57; 2 pay $26.56."),
    "nativescript-image-drawing": ("nativescript", "index.ts", "Native image drawing", "0° clockwise • 8 invalid inputs rejected", "180° clockwise • 8 invalid inputs rejected"),
}


def validate_request(request):
    require(type(request.get("schema")) is int and request["schema"] == 1
            and request.get("surface") == "studioGallery", "Unknown Studio gallery exchange")
    run_id = request.get("runID")
    require(isinstance(run_id, str) and re.fullmatch(UUID, run_id), "Invalid Studio UI run UUID")
    example = request.get("exampleID")
    require(example in EXAMPLES and request.get("engine") == EXAMPLES[example][0],
            "The UI must select one of the five actual shipped gallery examples")
    require(request.get("marker") == "שלום Studio " + run_id[:8]
            and request.get("packageTitle") == "Studio " + example + " " + run_id[:8],
            "The editor and installed card must use this fresh case's exact text")
    require(request.get("phase") in STEPS, "Unknown Studio UI checkpoint")
    started = shared._epoch_milliseconds(request.get("startedAt"))
    observed = shared._epoch_milliseconds(request.get("observedAt"))
    require(started <= observed <= time.time() * 1000 + 5000, "Invalid actual Studio UI timestamp")
    return run_id


def source_tree(root, trusted_root, exclude=(), limit=32 * 1024 * 1024):
    root = Path(root)
    require(root.is_dir() and not root.is_symlink(), "The actual project directory is absent or a link")
    files = {}
    total = 0
    for directory, folders, names in os.walk(root, followlinks=False):
        base = Path(directory)
        for name in folders:
            require(not (base / name).is_symlink(), "An actual project directory is a symbolic link")
        if base == root:
            folders[:] = [name for name in folders if name not in exclude]
        for name in sorted(names):
            path = base / name
            relative = normalized_relative(path.relative_to(root).as_posix())
            document = raw_file(path, trusted_root, limit)
            total += document["bytes"]
            require(len(files) < 4096 and total <= limit, "Observed source exceeds the bounded gallery project")
            files[relative] = document
    require(files, "The actual project contains no source")
    return files


def hashes(files):
    return {path: document["sha256"] for path, document in sorted(files.items())}


def read_zip_members(document, limit=128 * 1024 * 1024):
    result = {}
    with zipfile.ZipFile(io.BytesIO(document["raw"])) as archive:
        entries = archive.infolist()
        require(len(entries) <= 4096 and len({item.filename for item in entries}) == len(entries),
                "The built archive has duplicate or excessive members")
        require(sum(item.file_size for item in entries) <= limit, "The built archive exceeds the source bound")
        for entry in entries:
            normalized_relative(entry.filename.rstrip("/"))
            require(not stat.S_ISLNK(entry.external_attr >> 16), "The built archive contains a symbolic link")
            if not entry.is_dir():
                result[entry.filename] = archive.read(entry)
    return result


def original_typecheck(base, project):
    require(isinstance(project, dict) and project.get("extends") is None,
            "This original gallery project must retain its direct shipped TypeScript configuration")
    override = project.get("compilerOptions", {})
    require(isinstance(override, dict), "Invalid original project compiler options")
    options = {"strict": True, "checkJs": False, "skipLibCheck": False,
               **base["compilerOptions"], **override}
    require(all(type(options.get(key)) is bool for key in ("strict", "checkJs", "skipLibCheck"))
            and options["strict"] is True, "The shipped gallery source must retain original strict checking")
    return {"strict": options["strict"], "checkJs": options["checkJs"],
            "skipLibCheck": options["skipLibCheck"],
            "dependencyDeclarationsChecked": not options["skipLibCheck"]}


def verify_tooling(sdk, descriptor, manifest, archive, data_root):
    """Verify selected compiler/declarations/tools against their bundled hashes.

    readMiniAppSDK returns manifest metadata, so report.version alone cannot
    establish these actual files. The original producer lists every SDK file.
    Unlisted executable input under the selected tooling root also fails.
    """
    tooling = normalized_relative(descriptor["toolingRoot"])
    require("/" not in tooling and tooling in ("expo", "nativescript"), "Unexpected original tooling root")
    entries = manifest.get("files")
    require(isinstance(entries, list) and len(entries) <= 100000, "The original SDK file manifest is absent or excessive")
    listed = {}
    for item in entries:
        path = normalized_relative(item.get("path"))
        require(path not in listed and re.fullmatch(r"[0-9a-f]{64}", item.get("sha256", ""))
                and type(item.get("bytes")) is int and 0 <= item["bytes"] <= 64 * 1024 * 1024,
                "Invalid or duplicate original SDK file identity")
        listed[path] = item
    selected = {path: item for path, item in listed.items() if path.startswith(tooling + "/")}
    require(descriptor["typescriptPath"] in selected and descriptor["tsconfigPath"] in selected
            and sum(item["bytes"] for item in selected.values()) <= 768 * 1024 * 1024,
            "The actual selected compiler/configuration closure is absent or excessive")
    actual_paths = set()
    for directory, folders, names in os.walk(sdk / tooling, followlinks=False):
        base = Path(directory)
        require(not base.is_symlink() and all(not (base / name).is_symlink() for name in folders),
                "The actual selected tooling has a symbolic directory link")
        actual_paths.update((base / name).relative_to(sdk).as_posix() for name in names)
    require(actual_paths == set(selected), "The actual compiler/tooling inventory differs from the bundled SDK closure")
    prefix = "MiniAppSDK/"
    packaged = {item.filename[len(prefix):]: item for item in archive.infolist()
                if item.filename.startswith(prefix + tooling + "/") and not item.is_dir()}
    require(set(packaged) == set(selected), "The bundled compiler/tooling inventory differs from its original file manifest")
    total = 0
    for path, item in selected.items():
        entry = packaged[path]
        require(not stat.S_ISLNK(entry.external_attr >> 16) and entry.file_size == item["bytes"],
                "The bundled original tooling member has an invalid size or link")
        original = archive.read(entry)
        actual = raw_file(sdk / path, data_root, 64 * 1024 * 1024)
        require(shared.digest(original) == item["sha256"] and actual["bytes"] == item["bytes"]
                and actual["sha256"] == item["sha256"],
                "Actual compiler/declaration/tooling bytes differ from the app-bundled original")
        total += actual["bytes"]
    fingerprint = shared.digest("\n".join(path + ":" + selected[path]["sha256"] for path in sorted(selected)).encode())
    return {"root": tooling, "compilerPath": descriptor["typescriptPath"],
            "fileCount": len(selected), "bytes": total, "filesSHA256": fingerprint,
            "basis": "Every selected original compiler/declaration/tooling file matches bundled ZIP and SDK manifest"}


def bind_sdk(roots, request):
    candidates = list(roots["app"].rglob("RuntimeHostResources.zip"))
    require(len(candidates) == 1, "The installed app's original Host archive is absent or ambiguous")
    archive = raw_file(candidates[0], roots["app"], 256 * 1024 * 1024)
    host = roots["data"] / RUNTIME / "runtime/node" / ("host-" + archive["sha256"])
    ready = raw_file(host / ".ready", roots["data"])
    require(ready["raw"] == archive["sha256"].encode(), "The original Host unpack stamp differs from bundled bytes")
    sdk = host / "MiniAppSDK"
    manifest = shared.read_document(sdk / "miniapp-sdk.json", roots["data"])
    value = manifest["value"]
    require(type(value.get("schemaVersion")) is int and value["schemaVersion"] == 1,
            "Unknown actual shipped SDK schema")
    descriptor = value["engines"][request["engine"]]
    examples = [item for item in descriptor.get("examples", []) if item.get("id") == request["exampleID"]]
    require(len(examples) == 1 and examples[0].get("engine") == request["engine"]
            and examples[0].get("path") == "examples/" + request["exampleID"]
            and examples[0].get("entry") == "index.ts", "The selected gallery row is not the original SDK example")
    example = examples[0]
    template = source_tree(sdk / example["path"], roots["data"])
    config_path = normalized_relative(descriptor["tsconfigPath"])
    config = shared.read_document(sdk / config_path, roots["data"])
    options = config["value"].get("compilerOptions", {})
    policy = descriptor.get("typeCheckingPolicy", {})
    require(options.get("strict") is True and policy.get("strictSource") is True
            and type(options.get("skipLibCheck")) is bool
            and type(policy.get("checkOriginalDeclarationBodies")) is bool
            and options["skipLibCheck"] is not policy["checkOriginalDeclarationBodies"],
            "The actual engine's source/declaration policy differs from its original SDK descriptor")
    with zipfile.ZipFile(io.BytesIO(archive["raw"])) as bundle:
        entries = bundle.infolist()
        require(len(entries) <= 100000 and len({item.filename for item in entries}) == len(entries),
                "The actual bundled Host archive has duplicate or excessive members")
        require(bundle.read("MiniAppSDK/miniapp-sdk.json") == raw_file(sdk / "miniapp-sdk.json", roots["data"])["raw"]
                and bundle.read("MiniAppSDK/" + config_path) == raw_file(sdk / config_path, roots["data"])["raw"],
                "The unpacked SDK manifest/config differs from the app-bundled original")
        tooling = verify_tooling(sdk, descriptor, value, bundle, roots["data"])
        prefix = "MiniAppSDK/" + example["path"] + "/"
        selected = [item for item in entries if item.filename.startswith(prefix) and not item.is_dir()]
        require({item.filename[len(prefix):] for item in selected} == set(template),
                "The unpacked gallery project differs from the app-bundled source members")
        for item in selected:
            require(not stat.S_ISLNK(item.external_attr >> 16)
                    and item.file_size <= 32 * 1024 * 1024
                    and bundle.read(item) == template[item.filename[len(prefix):]]["raw"],
                    "The actual gallery source is not the original app-bundled bytes")
    edited_file = EXAMPLES[request["exampleID"]][1]
    require(edited_file in template and "script.json" in template and "hanlin.authoring.json" in template,
            "The original editable project inputs are absent")
    author = shared.parse_json(template["hanlin.authoring.json"]["raw"])
    require(type(author.get("schemaVersion")) is int and author["schemaVersion"] == 1
            and author.get("engine") == request["engine"] and author.get("entry") == "index.ts"
            and author.get("tsconfig") == "tsconfig.json" and author.get("sourceRoot") is None,
            "The selected example is not the original editable gallery project")
    policy = original_typecheck(config["value"], shared.parse_json(template["tsconfig.json"]["raw"]))
    return {"archive": document_bytes(archive), "root": str(sdk), "manifest": manifest,
            "config": config, "ready": document_bytes(ready), "descriptor": descriptor,
            "example": example, "template": template, "tooling": tooling, "effectiveTypecheck": policy}


def sdk_summary(sdk):
    return {key: sdk[key] for key in ("archive", "root", "config", "ready", "example", "tooling", "effectiveTypecheck")} | {
        "manifest": document_bytes(sdk["manifest"]), "templateHashes": hashes(sdk["template"])}


def verify_sdk_unchanged(case, roots, full=False):
    sdk = case["sdk"]
    current = bind_sdk(roots, case["fixed"]) if full else None
    if current is not None:
        require(equal(sdk_summary(current), sdk_summary(sdk)), "The current app-bundled SDK changed during this UI case")
        return
    require(shared.read_document(Path(sdk["manifest"]["path"]), roots["data"])["sha256"] == sdk["manifest"]["sha256"]
            and shared.read_document(Path(sdk["config"]["path"]), roots["data"])["sha256"] == sdk["config"]["sha256"]
            and raw_file(Path(sdk["ready"]["path"]), roots["data"])["sha256"] == sdk["ready"]["sha256"],
            "The current SDK manifest/config/unpack identity changed")
    actual = source_tree(Path(sdk["root"]) / sdk["example"]["path"], roots["data"])
    require(hashes(actual) == hashes(sdk["template"]), "Editing a copy changed the shipped SDK example")


def matching_projects(workspace, example):
    require(workspace.is_dir() and not workspace.is_symlink(), "The actual local Studio library is unavailable")
    found = set()
    for path in workspace.iterdir():
        if re.fullmatch(re.escape(example) + r"-[0-9A-F]{8}", path.name):
            require(path.is_dir() and not path.is_symlink(), "A copied gallery project is not an independent directory")
            found.add(path.name)
    return found


def edited_source(request, template, actual):
    require(set(actual) == set(template), "Editor changes added or removed original project inputs")
    edited_file, original_heading = EXAMPLES[request["exampleID"]][1:3]
    original = template[edited_file]["raw"].decode("utf-8")
    require(original.count(original_heading) == 1, "The original example heading is absent or ambiguous")
    expected = original.replace(original_heading, request["marker"], 1).encode("utf-8")
    require(actual[edited_file]["raw"] == expected, "The actual editor source does not contain exactly the observed heading edit")
    manifest = shared.parse_json(template["script.json"]["raw"])
    manifest["name"] = request["packageTitle"]
    require(equal(shared.parse_json(actual["script.json"]["raw"]), manifest),
            "The editor changed manifest fields beyond this fresh installed name")
    require(all(actual[path]["raw"] == original["raw"] for path, original in template.items()
                if path not in (edited_file, "script.json")),
            "The editor changed original runtime logic, compiler configuration or other source")
    return actual


def verify_copies(case, roots, edited=False):
    workspace = case["workspace"]
    expected = set(case["baselineProjects"]) | set(case["copies"])
    require(matching_projects(workspace, case["fixed"]["exampleID"]) == expected,
            "The observed gallery copies were replaced or another copy appeared")
    first = source_tree(workspace / case["copies"][0], roots["data"], exclude=(".hanlin-build",))
    if edited:
        edited_source(case["fixed"], case["sdk"]["template"], first)
    else:
        require(hashes(first) == hashes(case["sdk"]["template"]), "The first copy differs from the real SDK source")
    if len(case["copies"]) == 2:
        second = source_tree(workspace / case["copies"][1], roots["data"])
        require(hashes(second) == hashes(case["sdk"]["template"]), "Editing the first copy changed the independent second copy")
    verify_sdk_unchanged(case, roots)
    return first


def build_facts(case, roots):
    request, sdk = case["fixed"], case["sdk"]
    actual = verify_copies(case, roots, edited=True)
    require(hashes(actual) == case["editedHashes"], "Source changed after the actual editor checkpoint")
    folder = case["workspace"] / case["copies"][0] / ".hanlin-build"
    require(folder.is_dir() and not folder.is_symlink(), "The original UI authoring output is absent")
    stages = list(folder.iterdir())
    require(len(stages) == 1 and re.fullmatch(UUID, stages[0].name)
            and stages[0].is_dir() and not stages[0].is_symlink(),
            "Exactly one fresh original authoring stage is required")
    stage = stages[0]
    suffix = "hanlinExpo" if request["engine"] == "expo" else "hanlinNativeScript"
    archive = raw_file(stage / ("MiniApp." + suffix), roots["data"], 128 * 1024 * 1024)
    package = source_tree(stage / "package", roots["data"], limit=128 * 1024 * 1024)
    members = read_zip_members(archive)
    require(set(members) == set(package) and all(members[path] == document["raw"] for path, document in package.items()),
            "The real Studio output ZIP differs from its original prepared package")
    author = shared.parse_json(package["hanlin.authoring.json"]["raw"])
    report = shared.parse_json(package["hanlin.validation.json"]["raw"])
    expected_sdk = {"packageVersions": sdk["descriptor"]["packageVersions"],
                    "manifestSHA256": sdk["manifest"]["sha256"],
                    "compilerVersion": sdk["descriptor"]["typescript"]["compilerVersion"]}
    require(type(author.get("schemaVersion")) is int and author["schemaVersion"] == 1
            and author.get("engine") == request["engine"] and author.get("entry") == "index.ts"
            and author.get("tsconfig") == "tsconfig.json" and author.get("sourceRoot") == "source"
            and equal(author.get("sdk"), expected_sdk) and equal(author.get("sourceHashes"), hashes(actual)),
            "The original build is not bound to this edited source and shipped compiler")
    retained = {path[7:]: document for path, document in package.items() if path.startswith("source/")}
    require(set(retained) == set(actual) and all(retained[path]["raw"] == actual[path]["raw"] for path in actual),
            "The original authoring output did not retain exactly the edited project")
    compiled = {path: document["sha256"] for path, document in package.items()
                if not path.startswith("source/") and path not in ("hanlin.authoring.json", "hanlin.validation.json")}
    require(equal(author.get("compiledHashes"), compiled), "The compiled-output identity differs from actual prepared bytes")
    expected_typecheck = original_typecheck(sdk["config"]["value"],
                                            shared.parse_json(actual["tsconfig.json"]["raw"]))
    require(equal(expected_typecheck, sdk["effectiveTypecheck"]), "The current source changed the original project compiler policy")
    require(type(report.get("schemaVersion")) is int and report["schemaVersion"] == 1
            and report.get("engine") == request["engine"] and report.get("operation") == "build"
            and report.get("succeeded") is True and report.get("sourceRoot") == "source"
            and equal(report.get("sdk"), expected_sdk) and equal(report.get("typecheck"), expected_typecheck)
            and isinstance(report.get("diagnostics"), list)
            and not any(item.get("category") == "error" for item in report["diagnostics"]),
            "The real build did not succeed with the original engine's exact compiler policy")
    manifest = shared.parse_json(package["script.json"]["raw"])
    expected_manifest = shared.parse_json(actual["script.json"]["raw"])
    expected_manifest.update(entry="bundle.js" if request["engine"] == "expo" else "nativescript/app/bundle.mjs",
                             runInApp=True, hanlinRuntime="hanlin-" + request["engine"])
    require(equal(manifest, expected_manifest) and manifest["entry"] in compiled,
            "The original compiled app entry or fresh manifest differs")
    return {"archive": document_bytes(archive), "stage": str(stage), "authoring": author,
            "validation": report, "packageHashes": hashes(package), "manifest": manifest}


def installed_ids(data_root):
    path = data_root / INSTALLED / "registry/catalog.json"
    if not path.exists():
        return set()
    document = shared.read_document(path, data_root)
    require(type(document["value"].get("schemaVersion")) is int and document["value"]["schemaVersion"] == 1
            and isinstance(document["value"].get("packages"), dict), "Unknown actual primary catalog")
    return set(document["value"]["packages"])


def installed_build(case, roots):
    catalog = shared.read_document(roots["data"] / INSTALLED / "registry/catalog.json", roots["data"])
    require(type(catalog["value"].get("schemaVersion")) is int and catalog["value"]["schemaVersion"] == 1
            and type(catalog["value"].get("revision")) is int, "Unknown actual primary catalog revision")
    matches = [(key, entry) for key, entry in catalog["value"]["packages"].items()
               if entry.get("record", {}).get("sourceDigest") == case["build"]["archive"]["sha256"]]
    require(len(matches) == 1, "The real Studio archive is not exactly one current installed package")
    installed_id, entry = matches[0]
    record = entry["record"]
    require(installed_id not in case["baselineInstalledIDs"] and entry.get("enabled") is True
            and record.get("installedPackageID") == installed_id
            and type(record.get("activeGeneration")) is int and record["activeGeneration"] > 0,
            "The gallery UI must install a fresh enabled package, not an old catalog record")
    app_entries = [item for item in entry.get("entrypoints", []) if item.get("kind") == "app"]
    require(len(app_entries) == 1 and app_entries[0].get("compatibility") in ("supported", "partial")
            and app_entries[0].get("runtimeProfile") == "hanlin-" + case["fixed"]["engine"]
            and "mainApplication" in app_entries[0].get("supportedContexts", [])
            and app_entries[0].get("sourcePath") == "source/" + case["build"]["manifest"]["entry"],
            "The installed package has no current supported original foreground app entry")
    identity = {"installedPackageID": installed_id, "packageID": record["packageID"],
                "generation": record["activeGeneration"], "entrypointID": app_entries[0]["id"], "variantID": "default"}
    binding = verify_installed_fixture_archive(roots["data"], identity, catalog,
                                               case["build"]["archive"], roots["data"])
    require(equal(binding["authorManifest"], case["build"]["manifest"]),
            "The current installed source no longer names the edited gallery app")
    return {"identity": identity, "record": record, "entrypoint": app_entries[0], "source": binding}


def runtime_observation(request, directory):
    example = request["exampleID"]
    expected_before, expected_after = EXAMPLES[example][3:5]
    require(all(request.get(key) is True for key in
                ("installPressed", "catalogCardObserved", "runtimeHeadingObserved", "runtimeActionObserved"))
            and request.get("runtimeBefore") == expected_before and request.get("runtimeAfter") == expected_after
            and type(request.get("runtimeProcessID")) is int and request["runtimeProcessID"] > 0,
            "The real UI did not observe the installed heading and original runtime callback")
    labels = ["studio-runtime-before", "studio-runtime-after"]
    if example == "nativescript-image-drawing":
        require(equal(request.get("drawingAnglesObserved"), [0, 45, 90, 180])
                and request.get("nativeImageObserved") is True,
                "The original native image and all four actual angle states are required")
        labels = ["studio-drawing-" + str(angle) for angle in (0, 45, 90, 180)]
    attachments = {}
    for index, label in enumerate(labels):
        screenshot = raw_file(directory / (label + ".png"), directory)
        tree = raw_file(directory / (label + "-accessibility.txt"), directory)
        text = tree["raw"].decode("utf-8")
        expected = (str((0, 45, 90, 180)[index]) + "° clockwise • 8 invalid inputs rejected"
                    if example == "nativescript-image-drawing" else (expected_before, expected_after)[index])
        require(screenshot["raw"].startswith(b"\x89PNG\r\n\x1a\n")
                and expected in text and request["marker"] in text
                and re.search(r"^Attributes: Application, .*?, pid: " + str(request["runtimeProcessID"]) + r",", text),
                "The actual retained runtime screenshot/accessibility observation differs")
        attachments[label] = {"image": document_bytes(screenshot), "accessibility": document_bytes(tree)}
    return {"before": expected_before, "after": expected_after, "processID": request["runtimeProcessID"],
            "attachments": attachments,
            "drawingPixelReview": "NOT_CLAIMED; actual screenshots are retained for review" if len(labels) == 4 else None}


def current_roots(args, expected):
    roots = shared.product_roots(args.device, args.bundle_id)
    require(all(equal(roots[key], expected[key]) if key == "configuration" else roots[key] == expected[key]
                for key in ROOT_KEYS), "The actual MiniApps containers or product configuration changed")
    return roots


def publish(directory, output, filename, value):
    require(filename in ("identity.json", "studio-copy-one.json", "studio-copy-two.json",
                         "studio-source.json", "studio-build.json", "completion.json"),
            "Unexpected Studio test response")
    require(directory.is_dir() and not directory.is_symlink(), "The actual XCTest exchange directory changed")
    target = directory / filename
    require(not target.exists(), "A Studio test response must not be overwritten")
    data = (json.dumps(value, ensure_ascii=False, sort_keys=True, indent=2) + "\n").encode()
    temporary = directory / (filename + ".observer-tmp")
    with temporary.open("xb") as stream:
        stream.write(data)
    temporary.replace(target)
    (output / filename).write_bytes(data)


def observe_case(args, request, directory, evidence, seen):
    run_id = validate_request(request)
    phase = request["phase"]
    case = seen.get(run_id)
    if case is None:
        require(phase == "gallery-ready" and request.get("galleryLoaded") is True,
                "The real Studio gallery must load before the observer admits a case")
        roots = shared.product_roots(args.device, args.bundle_id)
        require(all(not evidence.is_relative_to(roots[key]) for key in ("app", "data", "group")),
                "Studio observation evidence must stay outside production containers")
        sdk = bind_sdk(roots, request)
        workspace = roots["data"] / RUNTIME / "clients/tools/miniapp-studio"
        baseline_projects = matching_projects(workspace, request["exampleID"])
        baseline_installed = installed_ids(roots["data"])
        # Retain the actual 25k-file manifest once per unique SDK, without
        # expanding every response/Swift request by several megabytes.
        manifests = evidence / "studio-sdk-manifests"
        manifests.mkdir(exist_ok=True)
        require(not manifests.is_symlink(), "The owned SDK evidence directory changed")
        manifest_copy = manifests / (sdk["manifest"]["sha256"] + ".json")
        manifest_bytes = raw_file(Path(sdk["manifest"]["path"]), roots["data"])["raw"]
        if manifest_copy.exists():
            require(raw_file(manifest_copy, evidence)["raw"] == manifest_bytes, "Retained SDK manifest bytes changed")
        else:
            with manifest_copy.open("xb") as stream:
                stream.write(manifest_bytes)
        output = evidence / run_id
        output.mkdir(exist_ok=False)
        case = {"kind": "studioGallery", "fixed": {key: request[key] for key in FIXED},
                "directory": str(directory), "roots": roots, "sdk": sdk, "workspace": workspace,
                "baselineProjects": baseline_projects,
                "baselineInstalledIDs": baseline_installed, "copies": [],
                "done": [], "output": output, "finished": False}
        seen[run_id] = case
    require(case.get("kind") == "studioGallery" and case["directory"] == str(directory)
            and equal({key: request.get(key) for key in FIXED}, case["fixed"]),
            "The prepared Studio run, source edit or actual XCTest exchange changed")
    if case["finished"] or phase in case["done"]:
        return
    require(phase == STEPS[len(case["done"])], "The real Studio UI skipped an admitted copy/edit/build step")
    roots = current_roots(args, case["roots"])
    updates = {}
    response = {"schema": 1, "runID": run_id, "status": "READY", "exampleID": request["exampleID"]}
    if phase == "gallery-ready":
        response.update(sdk=sdk_summary(case["sdk"]), workspace=str(case["workspace"]))
        filename = "identity.json"
    elif phase in ("copy-one", "copy-two"):
        require(request.get("copyOneObserved" if phase == "copy-one" else "copyTwoObserved") is True,
                "The real gallery did not display its completed independent copy")
        fresh = matching_projects(case["workspace"], request["exampleID"]) - case["baselineProjects"] - set(case["copies"])
        require(len(fresh) == 1, "Exactly one newly copied gallery project is required at this UI step")
        copies = case["copies"] + [next(iter(fresh))]
        first = verify_copies({**case, "copies": copies}, roots)
        require(not (case["workspace"] / copies[0] / ".hanlin-build").exists(),
                "The fresh gallery copy already contains a previous build")
        updates["copies"] = copies
        response.update(projectNames=copies, sourceHashes=hashes(first))
        filename = "studio-" + phase + ".json"
    elif phase == "source-edited":
        require(request.get("editorReplacementObserved") is True and len(case["copies"]) == 2,
                "The original editor must change only the first of two actual copies")
        actual = verify_copies(case, roots, edited=True)
        require(not (case["workspace"] / case["copies"][0] / ".hanlin-build").exists(),
                "The real editor checkpoint must precede the first build")
        updates["editedHashes"] = hashes(actual)
        response.update(projectNames=list(case["copies"]), editedHashes=updates["editedHashes"])
        filename = "studio-source.json"
    elif phase == "build-preview":
        require(all(request.get(key) is True for key in
                    ("validatePressed", "validationSucceededObserved", "buildPressed", "importPreviewObserved")),
                "The original Validate/Build buttons and real import preview were not observed")
        updates["build"] = build_facts(case, roots)
        response.update(build=updates["build"], independentCopyUnchanged=True, shippedExampleUnchanged=True)
        filename = "studio-build.json"
    else:
        require(equal(build_facts(case, roots), case["build"]), "The actual Studio build changed before completion")
        installed = installed_build(case, roots)
        runtime = runtime_observation(request, directory)
        verify_sdk_unchanged(case, roots, full=True)
        require(equal(installed_build(case, roots), installed), "The installed source changed during final observation")
        response.update(status="EXECUTED_PASS", sdk=sdk_summary(case["sdk"]), projectNames=list(case["copies"]),
                        build=case["build"], installed=installed, runtime=runtime,
                        independentCopyUnchanged=True, shippedExampleUnchanged=True,
                        scope="Real local Gallery copies, UI edits, original compiler/importer and actual runtime callback",
                        iCloud="NOT_RUN", physicalDevice="NOT_RUN")
        filename = "completion.json"
    current_roots(args, roots)
    publish(directory, case["output"], filename, response)
    case.update(updates)
    case["done"].append(phase)
    case["finished"] = phase == "runtime-observed"
