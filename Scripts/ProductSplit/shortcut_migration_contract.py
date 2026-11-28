"""Source/product and saved-value admission for the two genuine upgrade pilots.

This module only reads real source, products and XCTest exchanges. It never
installs an app, imports a fixture, creates a Shortcut or changes app storage.
The separately named upgrade_shortcut_migration process owns the one upgrade.
"""
from pathlib import Path
from collections import Counter
import copy
import json
import os
import plistlib
import re
import subprocess
import uuid
import zipfile

import observe_shortcut_surfaces as shared
import observe_shortcut_native_lists as lists
import observe_shortcut_long_running as products

require = shared.require
OLD_CODE_SOURCE = "445e2cb514012110cd865bdd33a3dbb8e6b8143d"
OLD_SOURCE = "f45d6edcf20ab18f31fb7b25e33358754e3602d0"
OLD_DOC_DELTA = (
    "docs/miniapp-sdk/MANIFEST_REFERENCE.md",
    "docs/miniapp-sdk/extension-reachability.json",
    "docs/miniapp-sdk/extension-reachability.md",
    "docs/miniapp-sdk/source-inventory.json",
)
OLD_INTENT = "b1ed3e326e5fe968671a15900c18cffb3606641674aafa9c47dd36fd49b6b5bd"
APP = "com.itorah.hanlinminiapps"
AI = "com.itorah.chavrusachat"
PARAMETERS = ("action", "inputType", "input", "jsonFile", "allowLongRunning")
MODE = "Dictionary or List (JSON)"
SURFACE = "shortcutMigration"
METHODS = {
    "nativescript": "testNativeScriptSavedJSONListSurvivesFiveToNineParameterAppUpgrade",
    "expo": "testExpoSavedJSONListSurvivesFiveToNineParameterAppUpgrade",
}
SCOPES = {"miniapp_shortcut_migration_" + engine + "_os": engine for engine in METHODS}
OLD_SOURCE_FILES = (
    "HanlinMiniAppsApp/MiniAppsShortcutIntent.swift",
    "HanlinMiniAppsApp/HanlinMiniApps.entitlements",
    "Packages/HanlinPlatform/Sources/HanlinPlatformContracts/HanlinShortcutValueCodec.swift",
    "RuntimeDependencies.lock.json",
    "Scripts/NativeScript/dependency-lock.json",
    "Scripts/Expo/dependency-lock.json",
    "AI_HLY.xcodeproj/xcshareddata/xcschemes/HanlinMiniApps.xcscheme",
    "Scripts/ProductSplit/run_native_acceptance.py",
)
DESCRIPTOR_PRODUCTS = (
    "AI_HLYUITests-Runner.app",
    "AI_HLYUITests-Runner.app/PlugIns/AI_HLYUITests.xctest",
    "AI_Hanlin.app",
    "AI_Hanlin.app/PlugIns/AI_HLYTests.xctest",
    "ChavrusaChatNotificationService.appex",
    "ChavrusaChatShare.appex",
    "ChavrusaChatTranslationProvider.appex",
    "HanlinScriptingWidgets.appex",
)


def file_record(path):
    return products.file_record(path)


def source_files(engine):
    lists.engine_contract(engine)
    return tuple(dict.fromkeys(lists.source_files(engine) + (
        "Scripts/ProductSplit/shortcut_migration_contract.py",
        "Scripts/ProductSplit/observe_shortcut_migration.py",
        "Scripts/ProductSplit/upgrade_shortcut_migration.py",
        "Scripts/ProductSplit/simulator_entitlements.py",
        "Scripts/CI/Tests/test_shortcut_migration.py",
    )))


def expected_values(run_id):
    require(type(run_id) is str and str(uuid.UUID(run_id)) == run_id,
            "A migration requires its actual lowercase XCTest UUID")
    return ["שלום", run_id, 7, 2.5, True, False]


def native_values(encoded, run_id):
    require(type(encoded) is dict and set(encoded) == {"type", "value"}
            and encoded["type"] == "array" and type(encoded["value"]) is list,
            "The saved legacy JSON action did not send a native canonical array")
    require([row.get("type") if type(row) is dict else None for row in encoded["value"]]
            == ["string", "string", "integer", "number", "bool", "bool"],
            "Legacy JSON scalar tags/order changed")
    decoded = shared.decode_value(encoded)
    require(shared.equal_typed_json(decoded, expected_values(run_id)),
            "Legacy JSON scalar values changed")
    return decoded


def metadata_contract(document, stage):
    require(stage in ("old", "current"), "Unknown migration product stage")
    actions = document.get("actions")
    require(type(actions) is dict, "Actual AppIntents metadata is absent")
    name = "HanlinRunMiniAppShortcutIntent"
    row = actions.get(name)
    require(type(row) is dict and row.get("identifier") == name,
            "The original saved-action identifier changed")
    parameters = row.get("parameters")
    require(type(parameters) is list and all(type(value) is dict for value in parameters),
            "The original parameter records are absent")
    by_name = {value.get("name"): value for value in parameters}
    expected = set(PARAMETERS) if stage == "old" else set(PARAMETERS) | {
        "textItems", "integerItems", "numberItems", "booleanItems"}
    require(len(parameters) == len(by_name) == len(expected) and set(by_name) == expected,
            "The actual product is not the required five/nine-parameter action")
    if stage == "current":
        lists.metadata_contract(document)
    return {"identifier": name, "parameters": parameters,
            "originalParameters": {name: by_name[name] for name in PARAMETERS}}


def original_parameters_equal(current, old):
    """Ignore order only for the original input's complete type alternatives."""
    projections = []
    for parameters in (current, old):
        require(type(parameters) is dict and set(parameters) == set(PARAMETERS)
                and type(parameters.get("input")) is dict,
                "The original five parameter records are absent")
        value = copy.deepcopy(parameters)
        alternatives = value["input"].pop("resolvableInputTypes", None)
        require(type(alternatives) is list
                and all(type(item) is dict for item in alternatives),
                "The original input's complete type alternatives are absent")
        canonical = lambda item: json.dumps(
            item, ensure_ascii=False, sort_keys=True, separators=(",", ":"), allow_nan=False)
        projections.append((canonical(value), Counter(canonical(item) for item in alternatives)))
    return projections[0] == projections[1]


def runtime_archive_contract(path):
    """Retain actual SDK identity; old and hosted versions are not equated."""
    path = Path(path)
    record = file_record(path)
    require(record["bytes"] <= 256 * 1024 * 1024, "The actual Host archive exceeds its original read bound")
    with zipfile.ZipFile(path) as packed:
        entries = [info for info in packed.infolist() if info.filename == "MiniAppSDK/miniapp-sdk.json"]
        require(len(entries) == 1, "The actual bundled SDK manifest is missing or duplicated")
        info = entries[0]
        require(info.file_size <= 16 * 1024 * 1024, "The actual SDK manifest exceeds its read bound")
        raw = packed.read(info)
        manifest = shared.parse_json(raw)
    require(manifest.get("schemaVersion") == 1 and type(manifest.get("engines")) is dict
            and {"expo", "nativescript"}.issubset(manifest["engines"]),
            "The actual bundled SDK engine contract is absent")
    return {"archive": {"path": str(path), **record},
            "manifest": {"bytes": len(raw), "sha256": shared.digest(raw), "crc32": f"{info.CRC:08x}"},
            "declaredInputSHA256": manifest["inputSHA256"],
            "engines": {name: {"packageVersions": value["packageVersions"],
                               "hostContract": value.get("hostContract"),
                               "typescript": value.get("typescript")}
                        for name, value in manifest["engines"].items()},
            "scope": "Actual retained SDK bytes; no old/current runtime version equality is inferred"}


def product(path, stage):
    path = Path(path)
    require(path.is_absolute() and path.is_dir() and not path.is_symlink(),
            "The admitted app product is absent or linked")
    info = plistlib.loads((path / "Info.plist").read_bytes())
    require(info.get("CFBundleIdentifier") == APP
            and info.get("CFBundleDisplayName") == "Hanlin MiniApps",
            "The old/current product is not the standalone app")
    metadata = path / "Metadata.appintents/extract.actionsdata"
    document = shared.read_document(metadata, path)
    archives = list(path.rglob("RuntimeHostResources.zip"))
    require(len(archives) == 1, "The actual app-bundled Host archive is absent or ambiguous")
    relative = archives[0].relative_to(path)
    cursor = path
    for part in relative.parts:
        cursor /= part
        require(not cursor.is_symlink(), "The actual app-bundled Host archive path is linked")
    runtime = runtime_archive_contract(archives[0])
    runtime["archive"].pop("path")
    runtime["relativePath"] = relative.as_posix()
    return {"path": str(path), "records": products.product_records(path),
            "metadataFile": file_record(metadata),
            "metadata": metadata_contract(document["value"], stage),
            "runtimeArchive": runtime, "configuration": info.get("HanlinExtensionHost")}


def same_product(actual, expected):
    return {key: value for key, value in actual.items() if key != "path"} == {
        key: value for key, value in expected.items() if key != "path"}


def checked_file(row):
    require(type(row) is dict and type(row.get("path")) is str,
            "A retained evidence file is not bound")
    path = Path(row["path"])
    require(path.is_absolute() and file_record(path) == {
        "bytes": row.get("bytes"), "sha256": row.get("sha256")}, "A retained evidence file changed")
    return path


def git(root, *argv):
    return subprocess.check_output(["git", *argv], cwd=root,
        env=dict(os.environ, GIT_NO_LAZY_FETCH="1", GIT_TERMINAL_PROMPT="0"))


def admit_old(path, expected_sha, engine, current_root):
    """Read the separately executed original old-build producer's pinned receipt.

    A missing old product/receipt is an admission failure, never a substitute
    current build. The producer and its native execution remain separately owned.
    """
    path = Path(path)
    require(path.is_absolute() and re.fullmatch(r"[0-9a-f]{64}", expected_sha or ""),
            "An explicit old-build admission path and SHA256 are required")
    document = shared.read_document(path, path.parent)
    require(document["sha256"] == expected_sha, "Old-build admission changed")
    value = document["value"]
    require(value.get("schema") == 1 and value.get("status") == "EXECUTED_PASS_OLD_APP_BUILD_ONLY"
            and value.get("sourceSHA") == OLD_SOURCE
            and value.get("productCodeSourceSHA") == OLD_CODE_SOURCE,
            "No genuine old-five app build is admitted")
    source_root = Path(value["sourceRoot"])
    require(source_root.is_absolute() and source_root != Path(current_root)
            and git(source_root, "rev-parse", "HEAD").decode().strip() == OLD_SOURCE,
            "Old/current source roots are not independently bound")
    require(tuple(git(source_root, "diff", "--name-only", OLD_CODE_SOURCE, OLD_SOURCE)
                  .decode().splitlines()) == OLD_DOC_DELTA,
            "The historical build no longer differs only by four canonical documents")
    require(git(source_root, "diff", "--name-only", "HEAD") == b"",
            "The old tracked build source has changed")
    source = value.get("sourceFiles")
    require(type(source) is dict and set(source) == set(OLD_SOURCE_FILES),
            "The old source/pin admission is incomplete")
    for name, row in source.items():
        raw = git(source_root, "show", OLD_SOURCE + ":" + name)
        require(raw == git(source_root, "show", OLD_CODE_SOURCE + ":" + name),
                "The historical build changed original product code or pins")
        require(file_record(source_root / name) == row
                and shared.digest(raw) == row["sha256"] and len(raw) == row["bytes"],
                "An actual old source/pin differs from its Git authority")
    require(source[OLD_SOURCE_FILES[0]]["sha256"] == OLD_INTENT,
            "The baseline intent is not the original five-parameter source")
    build = value.get("build")
    require(type(build) is dict and build.get("exitCode") == 0
            and build.get("timeoutSeconds") == 2400 and build.get("cwd") == str(source_root)
            and build.get("stopReason") is None, "The original old standalone build did not pass")
    argv = build.get("argv")
    require(type(argv) is list and argv[0] == "xcodebuild"
            and argv.count("build-for-testing") == 1 and "test-without-building" not in argv
            and argv[argv.index("-scheme") + 1] == "HanlinMiniApps"
            and argv[argv.index("-project") + 1] == "AI_HLY.xcodeproj",
            "The old product did not use the original standalone build")
    checked_file(build["log"])
    checked_file(value["producerReceipt"])
    checked_file(value["preparedSourceAdmission"])
    actual = product(value["app"]["path"], "old")
    require(actual == value["app"], "Old built product/metadata changed after its producer receipt")
    fixture = value.get("fixture")
    contract = lists.engine_contract(engine)
    require(type(fixture) is dict and fixture.get("engine") == engine
            and set(fixture.get("sourceFiles", {})) == {
                contract["fixture"] + "/" + name for name in contract["fixtureFiles"]},
            "The old-compatible fixture source admission differs")
    for name, row in fixture["sourceFiles"].items():
        require(file_record(Path(current_root) / name) == row,
                "The unchanged array fixture differs from old compatibility admission")
    archive = checked_file(fixture["archive"])
    require(archive.name == contract["archive"], "The old-compatible engine archive differs")
    for operation, cap in (("validate", 300), ("build", 600)):
        phase = fixture["originalCLI"][operation]
        report = shared.read_document(checked_file(phase["report"]), Path(phase["report"]["path"]).parent)["value"]
        require(phase["exitCode"] == 0 and phase["timeoutSeconds"] == cap
                and report.get("succeeded") is True,
                "The unchanged archive lacks actual original CLI qualification")
    checked_file(value["sdkManifest"])
    require(actual["runtimeArchive"]["manifest"]["sha256"] == value["sdkManifest"]["sha256"]
            and actual["runtimeArchive"]["manifest"]["bytes"] == value["sdkManifest"]["bytes"],
            "The actual old app does not bundle its admitted SDK manifest")
    return document


def descriptor_targets(document):
    require(type(document) is dict, "Malformed actual xctestrun")
    if "TestConfigurations" in document:
        configurations = document["TestConfigurations"]
        require(type(configurations) is list, "Malformed xctestrun configurations")
        found = [(i, j, target) for i, config in enumerate(configurations)
                 for j, target in enumerate(config.get("TestTargets", []))
                 if type(target) is dict and target.get("BlueprintName") == "AI_HLYUITests"]
        require(len(found) == 1, "The current AI UI descriptor is missing or ambiguous")
        i, j, target = found[0]
        selected = copy.deepcopy(document)
        selected["TestConfigurations"] = [copy.deepcopy(configurations[i])]
        selected["TestConfigurations"][0]["TestTargets"] = [copy.deepcopy(target)]
        return target, selected
    target = document.get("AI_HLYUITests")
    require(type(target) is dict and target.get("TestBundlePath"),
            "The current AI UI descriptor is missing")
    selected = {key: copy.deepcopy(value) for key, value in document.items()
                if key == "AI_HLYUITests" or not (
                    type(value) is dict and "TestBundlePath" in value)}
    return target, selected


def descriptor_installation(document, products_root):
    target, selected = descriptor_targets(document)
    root = Path(products_root)
    require(root.is_absolute() and root.is_dir() and not root.is_symlink(),
            "Descriptor products must be owned")
    require(target.get("IsUITestBundle") is True and not target.get("UseDestinationArtifacts"),
            "Unexpected UI descriptor installation mode")
    for key in ("OnlyTestIdentifiers", "SkipTestIdentifiers"):
        require(key not in target or target[key] == [],
                "The current build descriptor already changes test selection")

    def expand(value, host=None):
        require(type(value) is str and value, "Missing descriptor installation path")
        text = value.replace("__TESTROOT__", str(root))
        if host is not None:
            text = text.replace("__TESTHOST__", str(host))
        path = Path(text)
        require("__" not in text and path.is_absolute() and ".." not in path.parts
                and path.is_relative_to(root), "Descriptor installation escaped the owned products")
        cursor = root
        for part in path.relative_to(root).parts:
            cursor /= part
            require(cursor.is_dir() and not cursor.is_symlink(),
                    "Descriptor installation contains a missing/linked product")
        return path

    host = expand(target.get("TestHostPath"))
    test = expand(target.get("TestBundlePath"), host)
    app = expand(target.get("UITargetAppPath"))
    debug = root / "Debug-iphonesimulator"
    require(host == debug / DESCRIPTOR_PRODUCTS[0]
            and test == debug / DESCRIPTOR_PRODUCTS[1]
            and app == debug / "AI_Hanlin.app",
            "Migration requires the actual AI runner and AI target app")
    paths = target.get("DependentProductPaths")
    require(type(paths) is list and len(paths) == len(set(paths)),
            "The complete descriptor dependency closure is missing or duplicated")
    expanded = [expand(path, host) for path in paths]
    require(set(expanded) == {debug / name for name in DESCRIPTOR_PRODUCTS},
            "The AI installation closure changed or includes an unreviewed product")
    records = {}
    for path in expanded:
        info = plistlib.loads((path / "Info.plist").read_bytes())
        identifier = info.get("CFBundleIdentifier")
        require(type(identifier) is str and identifier
                and identifier != APP and not identifier.startswith(APP + "."),
                "The test runner would implicitly install MiniApps before baseline")
        records[path.relative_to(root).as_posix()] = {
            "bundleIdentifier": identifier, "records": products.product_records(path)}
    require(records[app.relative_to(root).as_posix()]["bundleIdentifier"] == AI,
            "The UI target is not the existing AI product")
    return selected, {"host": str(host), "test": str(test), "app": str(app), "products": records}


def descriptor_copy(derived, evidence):
    root = Path(derived) / "Build/Products"
    candidates = []
    for path in sorted(root.glob("*.xctestrun")):
        require(not path.is_symlink(), "An original build descriptor is linked")
        raw = path.read_bytes()
        require(len(raw) <= 4 * 1024 * 1024, "The actual descriptor is unexpectedly large")
        document = plistlib.loads(raw)
        if "AI_HLYUITests" in document or any(
                target.get("BlueprintName") == "AI_HLYUITests"
                for config in document.get("TestConfigurations", [])
                for target in config.get("TestTargets", [])):
            candidates.append((path, raw, document))
    require(len(candidates) == 1, "The actual current AI descriptor is absent or ambiguous")
    path, raw, document = candidates[0]
    selected, closure = descriptor_installation(document, root)
    # Same directory keeps the public __TESTROOT__ meaning unchanged.
    copy_path = root / "HanlinShortcutMigration.xctestrun"
    require(not copy_path.exists() and not copy_path.is_symlink(),
            "The scoped descriptor must be newly owned")
    with copy_path.open("xb") as stream:
        stream.write(plistlib.dumps(selected, fmt=plistlib.FMT_XML, sort_keys=False))
    retained = Path(evidence) / "migration-original-ai.xctestrun"
    with retained.open("xb") as stream:
        stream.write(raw)
    require(descriptor_installation(plistlib.loads(copy_path.read_bytes()), root)[1] == closure,
            "The scoped descriptor changed its original installation closure")
    return {"original": {"path": str(path), **file_record(path)},
            "retainedOriginal": {"path": str(retained), **file_record(retained)},
            "copy": {"path": str(copy_path), **file_record(copy_path)},
            "installation": closure}


def descriptor_current(binding):
    original = checked_file(binding["original"])
    checked_file(binding["retainedOriginal"])
    copy_path = checked_file(binding["copy"])
    require(original.read_bytes() == Path(binding["retainedOriginal"]["path"]).read_bytes(),
            "Original descriptor retention differs")
    selected, closure = descriptor_installation(plistlib.loads(original.read_bytes()), original.parent)
    actual = plistlib.loads(copy_path.read_bytes())
    require(actual == selected and descriptor_installation(actual, original.parent)[1] == closure
            and closure == binding["installation"], "Actual test installation closure changed")
    return str(copy_path)


def terminated_apps(request):
    """Require the actual XCTest .notRunning comparisons, retaining raw states."""
    require(request.get("miniAppsNotRunning") is True
            and request.get("shortcutsNotRunning") is True
            and type(request.get("miniAppsStateBeforeUpgrade")) is int
            and type(request.get("shortcutsStateBeforeUpgrade")) is int,
            "Both real apps must be observed not running before upgrade")
    return {key: request[key] for key in (
        "miniAppsNotRunning", "shortcutsNotRunning",
        "miniAppsStateBeforeUpgrade", "shortcutsStateBeforeUpgrade")}


def saved_editor(request):
    expected = expected_values(request["runID"])
    name = "Hanlin-migration-" + request["engine"] + "-" + request["runID"][:8]
    editor = request.get("editor")
    require(request.get("savedShortcutName") == name and type(editor) is dict
            and editor.get("savedShortcutName") == name
            and editor.get("savedAndReopened") is True and editor.get("processRestarted") is True
            and editor.get("inputMode") == MODE and editor.get("openWhenRun") is False
            and editor.get("inputParameter") == "input",
            "Actual saved legacy Shortcut mode/background/readback is absent")
    require(shared.equal_typed_json(editor.get("values"), expected)
            and type(editor.get("rawInput")) is str
            and shared.equal_typed_json(shared.parse_json(editor["rawInput"]), expected),
            "The reopened legacy JSON input changed")
    require(request.get("builtInChain") == ["Get Text from Input", "Show Result"]
            and editor.get("builtInChain") == request["builtInChain"],
            "The saved real built-in result chain changed")
    for key in ("savedElement", "actionElement", "modeElement", "inputElement"):
        row = editor.get(key)
        require(type(row) is dict and type(row.get("label")) is str
                and type(row.get("identifier")) is str and type(row.get("elementType")) is int,
                "An actual saved-editor element observation is missing")
    require(editor["savedElement"]["label"] == name,
            "The real saved Shortcut name is not the admitted unique name")
    return editor
