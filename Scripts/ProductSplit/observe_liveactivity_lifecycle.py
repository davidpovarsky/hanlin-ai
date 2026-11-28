"""Read-only correlation for original Expo/NativeScript local ActivityKit lifecycles.

Only XCTest invokes the authored controls. Native API return/private journals
bind actual IDs and ownership; public system AX/PNG captures separately bind
visible content. Prepared programs and end returns are never rendering or
dismissal acknowledgments. Physical lock/APNs/minimal display remain separate.
"""
from pathlib import Path
import copy
import hashlib
import io
import json
import math
import plistlib
import re
import subprocess
import time
import uuid
import zipfile

import observe_shortcut_surfaces as shared
import observe_shortcut_long_running as products
import observe_share_translation_surfaces as archives
import observe_widget_state as widget
import observe_widget_families as family
from observe_shortcut_concurrency import same_private_path
from simulator_entitlements import read_simulator_entitlements

require = shared.require
equal = shared.equal_typed_json
ROOT = Path(__file__).resolve().parents[2]
TYPE = "com.apple.CoreSimulator.SimDeviceType.iPhone-16-Pro"
RUNTIME = "com.apple.CoreSimulator.SimRuntime.iOS-27-2"
RUNTIME_BUILD = "24B8117"
REGIONS = ("banner", "compact-leading", "compact-trailing", "minimal",
           "expanded-leading", "expanded-trailing", "expanded-center", "expanded-bottom")
SCOPES = {
    "miniapp_liveactivity_lifecycle_expo_os": "expo",
    "miniapp_liveactivity_lifecycle_nativescript_os": "nativescript",
}
FIXTURE_FILES = {
    "expo": ("App.tsx", "hanlin.authoring.json", "index.ts", "package.json", "script.json", "tsconfig.json"),
    "nativescript": ("hanlin.authoring.json", "index.ts", "package.json", "script.json", "tsconfig.json", "widget.jsx"),
}
METHODS = {
    "expo": "testExpoLiveActivityLifecycleKeepsTwoActualIDsAndSystemViewsIndependent",
    "nativescript": "testNativeScriptLiveActivityLifecycleKeepsTwoActualIDsAndSystemViewsIndependent",
}
SOURCE_PATHS = (
    "AI_HLYUITests/HanlinEntrypointSystemSurfaceUITests.swift",
    "Scripts/ProductSplit/run_paired_acceptance.py",
    "Scripts/ProductSplit/observe_shortcut_surfaces.py",
    "Scripts/ProductSplit/observe_liveactivity_lifecycle.py",
    "Scripts/ProductSplit/observe_shortcut_long_running.py",
    "Scripts/ProductSplit/observe_shortcut_concurrency.py",
    "Scripts/ProductSplit/observe_share_translation_surfaces.py",
    "Scripts/ProductSplit/observe_widget_state.py",
    "Scripts/ProductSplit/observe_widget_families.py",
    "Scripts/ProductSplit/observe_runtime_image_origin.py",
    "Scripts/ProductSplit/simulator_entitlements.py",
    "Scripts/CI/Tests/test_liveactivity_lifecycle.py",
    "Scripts/MiniApps/miniapp.mjs",
    "AI_HLY/Downstream/RuntimeCore/Node/Host/miniapp-authoring.mjs",
    "AI_HLY/Downstream/ScriptingPlatform/HanlinScriptingPlatform.swift",
    "Packages/HanlinPlatform/Sources/HanlinScriptExtensions/HanlinScriptWidgetLiveActivity.swift",
    "Packages/HanlinPlatform/Sources/HanlinScriptExtensions/HanlinWidgetInstance.swift",
    "Packages/HanlinPlatform/Sources/HanlinScriptExtensions/HanlinScriptExtensionContracts.swift",
    "Packages/HanlinPlatform/Sources/HanlinScriptExtensions/HanlinScriptLiveActivityController.swift",
    "Packages/HanlinPlatform/Sources/HanlinScriptExtensions/HanlinLiveActivityOperationQueue.swift",
    "Packages/HanlinExpoRuntime/Sources/ExpoWidgets/HanlinExpoWidgetsIntegration.swift",
    "Packages/HanlinExpoRuntime/Sources/ExpoWidgets/Original/WidgetsModule.swift",
    "Packages/HanlinExpoRuntime/Sources/ExpoWidgets/Original/WidgetsStorage.swift",
    "Packages/HanlinExpoRuntime/Sources/ExpoWidgets/Original/LiveActivityFactory.swift",
    "Packages/HanlinExpoRuntime/Sources/ExpoWidgets/Original/LiveActivity.swift",
    "Packages/HanlinExpoRuntime/Sources/ExpoWidgets/Original/Widgets/WidgetLiveActivity.swift",
    "Packages/HanlinExpoRuntime/Sources/ExpoWidgets/Original/Widgets/LiveActivityBanner.swift",
    "Packages/HanlinWidgetSDK/Sources/HanlinScriptingWidgets/HanlinScriptingWidgets.swift",
)
# Each entry is a separate actual system capture after the indicated List.
PRESENTATIONS = (
    ("compact-a", "start-a", (("A", "compact-leading", 0), ("A", "compact-trailing", 0)), ()),
    ("expanded-a", "start-a", tuple(("A", name, 0) for name in REGIONS[4:]), ()),
    ("banner-both", "start-b", (("A", "banner", 0), ("B", "banner", 0)), ()),
    ("banner-updated-a", "update-a", (("A", "banner", 1), ("B", "banner", 0)), ()),
    ("banner-only-b", "end-a", (("B", "banner", 0),), ("A",)),
    ("home-empty", "end-b", (), ("A", "B")),
    ("banner-empty", "end-b", (), ("A", "B")),
)
ACTION_ORDER = ("prepare", "start-a", "start-b", "update-a", "end-a", "end-b")


def finite(value):
    require(type(value) in (int, float) and math.isfinite(value) and value >= 0,
            "An actual finite nonnegative observation time is required")
    return value


def segment(value):
    require(type(value) is str and 0 < len(value) <= 512 and value not in (".", "..")
            and "/" not in value and "\\" not in value and "\x00" not in value,
            "An actual owner path segment is invalid")
    return value


def actual_id(value):
    require(type(value) is str and 0 < len(value) <= 512 and "\x00" not in value,
            "The actual native activity ID is missing or unbounded")
    return value


def fixture_contract(engine):
    require(engine in FIXTURE_FILES, "Unknown lifecycle fixture engine")
    suffix = "Expo" if engine == "expo" else "NativeScript"
    return {"engine": engine, "scope": "miniapp_liveactivity_lifecycle_" + engine + "_os",
            "appID": "hanlin.activity.lifecycle." + engine,
            "title": "Live Activity Lifecycle " + suffix,
            "fixture": "Fixtures/LiveActivityLifecycle/" + engine,
            "archive": "LiveActivityLifecycle" + suffix + (".hanlinExpo" if engine == "expo" else ".hanlinNativeScript"),
            "files": FIXTURE_FILES[engine], "method": METHODS[engine]}


def admit_device(sdk, runtime, device_types, xcode):
    require(sdk in ("27.0", "27.2"), "The new lifecycle scope needs an explicitly qualified iOS 27 profile")
    expected = ("Xcode 27.0", "Build version 27A266a") if sdk == "27.0" else ("Xcode 27.2", "Build version 27B52")
    require(tuple(xcode.strip().splitlines()) == expected, "The actual lifecycle Xcode/SDK profile differs")
    require(runtime.get("identifier") == RUNTIME and runtime.get("isAvailable") is True
            and runtime.get("version") == "27.2" and runtime.get("buildversion") == RUNTIME_BUILD,
            "The actual supported 27.2 runtime/build is required; no fallback")
    supported = {row["identifier"] for row in runtime["supportedDeviceTypes"]}
    matches = [row for row in device_types if row.get("identifier") == TYPE]
    require(len(matches) == 1 and matches[0].get("productFamily") == "iPhone" and TYPE in supported,
            "The installed runtime must actually offer the exact Dynamic Island-capable iPhone 16 Pro")
    return matches[0], {"schema": 1, "runtime": RUNTIME, "runtimeVersion": "27.2",
        "runtimeBuild": RUNTIME_BUILD, "deviceType": TYPE, "device": copy.deepcopy(matches[0]),
        "buildSDK": sdk, "xcode": list(expected),
        "profile": "local-27.0-runtime-27.2" if sdk == "27.0" else "hosted-27.2",
        "scope": "Fresh owned Simulator only; model support is not an observed Island presentation"}


def source_identity(root, source, engine):
    root = Path(root)
    require(subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=root, text=True).strip() == source,
            "Current lifecycle source HEAD differs")
    fixed = fixture_contract(engine)
    names = SOURCE_PATHS + tuple(fixed["fixture"] + "/" + name for name in fixed["files"])
    result = {}
    for name in names:
        expected = subprocess.check_output(["git", "show", source + ":" + name], cwd=root)
        row = widget.file_identity(root / name, root)
        require(row["sha256"] == shared.digest(expected) and row["bytes"] == len(expected),
                "A lifecycle source input differs from current Git: " + name)
        result[name] = row
    return result


def host_archive(app, expected_sha):
    paths = list(Path(app).rglob("RuntimeHostResources.zip"))
    require(len(paths) == 1, "The actual app-bundled Host archive is missing or ambiguous")
    path = paths[0]
    row = widget.file_identity(path, app)
    require(row["bytes"] <= 256 * 1024 * 1024 and row["sha256"] == expected_sha,
            "The actual app does not contain the SDK used by the original fixture recipe")
    with zipfile.ZipFile(path) as packed:
        entries = [item for item in packed.infolist() if item.filename == "MiniAppSDK/miniapp-sdk.json"]
        require(len(entries) == 1 and entries[0].file_size <= 16 * 1024 * 1024,
                "The actual bundled SDK manifest is missing, duplicate or oversized")
        raw = packed.read(entries[0])
    manifest = shared.parse_json(raw)
    require(manifest.get("schemaVersion") == 1 and type(manifest.get("engines")) is dict,
            "Unknown actual bundled SDK manifest")
    return {"relativePath": path.relative_to(app).as_posix(), **row,
            "manifestSHA256": shared.digest(raw), "inputSHA256": manifest["inputSHA256"],
            "engines": {name: {key: row.get(key) for key in ("packageVersions", "hostContract", "typescript")}
                        for name, row in manifest["engines"].items()}}


def create_inputs(root, derived, evidence, runner, test, state, device, engine):
    root, evidence, runner, test = (Path(p).resolve(strict=True) for p in (root, evidence, runner, test))
    fixed = fixture_contract(engine)
    built = state["liveactivity_lifecycle_fixture"]
    require(built["status"] == "BUILT_AND_STAGED_INPUTS_ONLY" and len(built["archives"]) == 1
            and built["archives"][0]["engine"] == engine and built["archives"][0]["archive"] == fixed["archive"],
            "The original single-engine lifecycle validate/build did not succeed")
    archive = evidence / "liveactivity-lifecycle-fixture" / fixed["archive"]
    record = widget.file_identity(archive, evidence)
    require(record["sha256"] == built["archives"][0]["archiveSHA256"], "Actual produced lifecycle archive changed")
    app = Path(derived) / "Build/Products/Debug-iphonesimulator/HanlinMiniApps.app"
    info = plistlib.loads((app / "Info.plist").read_bytes())
    require(info.get("NSSupportsLiveActivities") is True, "The actual standalone product has not enabled Live Activities")
    product = widget.product_code(app)
    extension = app / product["widgetRelativePath"]
    group = product["configuration"]["AppGroupIdentifier"]
    signing = {}
    for name, bundle in (("app", app), ("widget", extension)):
        details = plistlib.loads((bundle / "Info.plist").read_bytes())
        actual = read_simulator_entitlements(bundle / details["CFBundleExecutable"])
        require(group in actual["entitlements"].get("com.apple.security.application-groups", []),
                "The actual app/extension does not own its declared App Group")
        signing[name] = actual
    executable = app / info["CFBundleExecutable"]
    architectures = subprocess.check_output(["lipo", "-archs", str(executable)], timeout=15, text=True).split()
    require(architectures == ["arm64"], "The actual lifecycle product must be the original arm64 Simulator build")
    value = {"schema": 1, "kind": "liveactivity-lifecycle-inputs", "engine": engine, "scope": fixed["scope"],
             "attemptID": str(uuid.uuid4()), "createdAt": time.time(), "sourceSHA": state["sha"],
             "device": device, "deviceAdmission": state["liveactivity_device_admission"],
             "sourceFiles": source_identity(root, state["sha"], engine), "product": product,
             "test": widget.bundle_code(test), "testRelativePath": test.relative_to(runner).as_posix(),
             "runnerBundleIdentifier": plistlib.loads((runner / "Info.plist").read_bytes())["CFBundleIdentifier"],
             "fixture": built, "archive": {"path": str(archive), **record},
             "actualBundledSDK": host_archive(app, built["shippingArchiveSHA256"]),
             "actualEntitlements": signing, "actualArchitectures": architectures}
    path = evidence / "liveactivity-lifecycle-inputs.json"
    with path.open("x") as stream:
        json.dump(value, stream, indent=2, sort_keys=True); stream.write("\n")
    return {"path": str(path), "sha256": shared.digest(path.read_bytes())}


def load_inputs(args, evidence):
    require(args.liveactivity_lifecycle_inputs is not None, "The original lifecycle input manifest is required")
    path = Path(args.liveactivity_lifecycle_inputs)
    require(path.is_absolute() and path == evidence.parent / "liveactivity-lifecycle-inputs.json",
            "Only this original runner's lifecycle manifest is admitted")
    document = shared.read_document(path, evidence.parent)
    value = document["value"]
    fixed = fixture_contract(value.get("engine"))
    require(value.get("schema") == 1 and value.get("kind") == "liveactivity-lifecycle-inputs"
            and value.get("scope") == fixed["scope"] and value.get("device") == args.device
            and value.get("runnerBundleIdentifier") == args.runner_bundle_id
            and widget.uuid_string(value.get("attemptID")) and finite(value.get("createdAt")) <= time.time(),
            "The source/device/runner/attempt identity is invalid")
    require(equal(source_identity(ROOT, value["sourceSHA"], fixed["engine"]), value["sourceFiles"]),
            "Current lifecycle source changed")
    profile = value["deviceAdmission"]
    require(profile["deviceType"] == TYPE and profile["runtime"] == RUNTIME
            and profile["runtimeVersion"] == "27.2" and profile["runtimeBuild"] == RUNTIME_BUILD,
            "The new iPhone runtime admission is absent")
    archive = value["archive"]
    current = widget.file_identity(Path(archive["path"]), evidence.parent)
    require(current["sha256"] == archive["sha256"] and current["bytes"] == archive["bytes"],
            "The once-staged lifecycle archive changed")
    return document


def current_package(roots, inputs):
    fixed = fixture_contract(inputs["value"]["engine"])
    catalog = shared.read_document(roots["data"] / archives.INSTALLED / "registry/catalog.json", roots["data"])
    value = catalog["value"]
    require(value.get("schemaVersion") == 1 and type(value.get("revision")) is int
            and type(value.get("packages")) is dict, "Unknown actual installed catalog")
    matches = [(key, row) for key, row in value["packages"].items()
               if row.get("record", {}).get("sourceDigest") == inputs["value"]["archive"]["sha256"]]
    require(len(matches) == 1, "The exact original lifecycle archive is missing or ambiguous")
    key, entry = matches[0]
    segment(key)
    record = entry["record"]
    require(entry.get("enabled") is True and record.get("schemaVersion") == 1
            and record.get("installedPackageID") == key and type(record.get("activeGeneration")) is int
            and record["activeGeneration"] > 0, "The actual lifecycle package is disabled or stale")
    rows = [row for row in entry.get("entrypoints", []) if row.get("kind") == "app"]
    require(len(rows) == 1 and rows[0].get("runtimeProfile") == "hanlin-" + fixed["engine"]
            and rows[0].get("compatibility") in ("supported", "partial")
            and "mainApplication" in rows[0].get("supportedContexts", []),
            "The current original native foreground entrypoint is absent")
    identity = {"installedPackageID": key, "packageID": record["packageID"],
                "generation": record["activeGeneration"], "entrypointID": rows[0]["id"], "variantID": "default"}
    binding = archives.verify_installed_fixture_archive(
        roots["data"], identity, catalog, inputs["value"]["archive"], Path(inputs["path"]).parent)
    author = binding["authorManifest"]
    require(author.get("hanlinAppID") == fixed["appID"] and author.get("name") == fixed["title"]
            and author.get("actions") == [] and author.get("hanlinRuntime") == "hanlin-" + fixed["engine"]
            and rows[0].get("sourcePath") == "source/" + author["entry"],
            "The installed archive is not the exact independent lifecycle fixture")
    return {"identity": identity, "record": record, "entrypoint": rows[0], "catalog": catalog,
            "source": binding}


def private_journal(roots, package, request):
    data = roots["data"]
    if request["engine"] == "expo":
        path = shared.expo_state_directory(data, package["identity"]["installedPackageID"]) / "activity-lifecycle.json"
        document = shared.read_document(path, data)
    else:
        base = data / "Library/Application Support/Hanlin/MiniApps" / request["fixtureAppID"] / "Windows"
        require(not base.is_symlink(), "Lifecycle window storage is linked")
        paths = sorted(base.glob("*/State/activity-lifecycle.json"))
        require(len(paths) <= 64, "Unexpected number of actual lifecycle windows")
        documents = [shared.read_document(path, data) for path in paths]
        matches = [row for row in documents if row["value"].get("runUUID") == request["runID"]
                   and row["value"].get("appID") == request["fixtureAppID"]]
        require(len(matches) == 1, "Exactly one own-window journal must match the fresh case")
        document = matches[0]
        storage = document["value"].get("storage", {})
        window = segment(storage.get("ownerWindowID"))
        expected = base / window / "State/activity-lifecycle.json"
        require(Path(document["path"]) == expected
                and same_private_path(str(expected), storage.get("literalStatePath")),
                "The real NativeScript window/private storage identity changed")
    require(document["value"].get("storage", {}).get("area") == "state"
            and document["value"]["storage"].get("filename") == "activity-lifecycle.json",
            "The original private State area differs")
    return document


def native_owner(roots, package, request, journal, previous=None):
    identity = package["identity"]
    if request["engine"] == "expo":
        app_info = plistlib.loads((roots["app"] / "Info.plist").read_bytes())
        group = app_info.get("ExpoWidgetsAppGroupIdentifier")
        require(group == roots["configuration"]["AppGroupIdentifier"], "The Expo factory uses another App Group")
        product = app_info.get("HanlinExpoWidgetsProductIdentifier", app_info["CFBundleIdentifier"])
        require(type(product) is str and product, "Missing original Expo product namespace")
        path = roots["group"] / "Library/Preferences" / (segment(group) + ".plist")
        raw = archives.raw_file(path, roots["group"], 16 * 1024 * 1024)
        values = plistlib.loads(raw["raw"])
        name = "HanlinActivityLifecycle." + request["runID"]
        key = "hanlin." + shared.digest("\0".join((product, identity["installedPackageID"], "liveActivity", name)).encode())
        def decoded(key):
            value = values.get(key)
            require(type(value) is bytes, "The actual native Expo owner registration is missing")
            return shared.parse_json(value)
        factory = decoded("__hanlin_expo_widget_registration_v1." + key)
        require(factory.get("id") == key and factory.get("name") == name
                and factory.get("kind") == "liveActivity" and factory.get("isActive") is True
                and factory.get("productIdentifier") == product
                and all(equal(factory.get(k), identity[k]) for k in ("packageID", "installedPackageID", "generation"))
                and type(factory.get("sessionID")) is str and factory["sessionID"],
                "The native Expo factory belongs to another owner/generation/session")
        generations = decoded("__hanlin_expo_widget_active_generations_v1." + shared.digest(product.encode()))
        require(equal(generations.get(identity["installedPackageID"]), identity["generation"]),
                "The Expo owner generation is no longer current")
        activity_records = {}
        for slot in journal["slots"].values():
            if slot is not None:
                activity_id = actual_id(slot["activityID"])
                record = decoded("__hanlin_expo_activity_registration_v1." + activity_id)
                require(equal(record, factory), "The actual activity ID belongs to a different native Expo owner")
                activity_records[activity_id] = record
        if previous is not None:
            require(equal(factory, previous["factory"]), "The actual foreground Expo session changed")
        return {"kind": "native-expo-registration", "factory": factory, "activities": activity_records,
                "preferencesSHA256": raw["sha256"],
                "scope": "Native owner/ID registration; not active-state, rendering or dismissal proof"}
    snapshot = shared.snapshot_document(roots["extensions"])
    current = snapshot["value"]["snapshot"]
    expected = {**identity, "entrypointID": "widget", "variantID": "default"}
    instances = [row for row in current.get("widgetInstances", [])
                 if equal(row.get("identity"), expected) and row.get("engine") == "scriptwidget"]
    templates = [row for row in current.get("widgets", [])
                 if equal(row.get("identity"), expected) and row.get("engine") == "scriptwidget"]
    require(identity["installedPackageID"] not in current.get("inactiveWidgetInstallations", [])
            and len(instances) == 1 and instances[0].get("displayName") == "Default"
            and len(templates) == 1 and templates[0].get("family") == "systemMedium"
            and templates[0].get("displayName") == request["fixtureTitle"] + " · Default"
            and finite(templates[0].get("validUntil")) > time.time() * 1000,
            "The native current default ScriptWidget owner/family is unavailable")
    payload = templates[0].get("payload", {})
    require(payload.get("kind") == "scriptwidget", "Wrong original ScriptWidget payload")
    descriptor = payload.get("scriptDescriptor", {})
    program = shared.widget_artifact(roots["extensions"], expected,
                                     descriptor.get("scriptRef"), descriptor.get("scriptSHA256"))
    value = program["value"]
    require(value.get("engine") == "scriptwidget" and value.get("abiVersion") == 1
            and value.get("families") == ["systemMedium"] and value.get("actions") == []
            and value.get("sourceSHA256") == package["source"]["installedSources"]["source/widget.jsx"]["sha256"],
            "The native ScriptWidget program differs from the authored lifecycle source")
    states = [row for row in current.get("widgetStates", [])
              if equal(row.get("identity"), expected) and row.get("engine") == "scriptwidget"]
    require(len(states) <= 1, "Ambiguous current default ScriptWidget state")
    if states:
        require(states[0].get("artifactSHA256") == program["sha256"], "Native state belongs to another program")
    if previous is not None:
        require(equal(expected, previous["identity"]) and program["sha256"] == previous["programSHA256"]
                and equal(instances[0], previous["instance"]),
                "The actual native ScriptWidget owner/program changed")
    return {"kind": "current-native-scriptwidget-owner", "identity": expected,
            "instance": copy.deepcopy(instances[0]), "programSHA256": program["sha256"],
            "program": program, "states": states, "snapshotSHA256": snapshot["sha256"],
            "scope": "Current native owner/program plus source-bound original API returns; not a rendered snapshot"}


def journal_transition(value, request, prior, operation):
    require(type(value) is dict and type(value.get("schemaVersion")) is int and value["schemaVersion"] == 1
            and value.get("engine") == request["engine"] and value.get("appID") == request["fixtureAppID"]
            and value.get("runUUID") == request["runID"], "The private lifecycle journal has a foreign identity")
    tap = request["operation"]
    require(type(tap) is dict and tap.get("name") == operation and type(tap.get("ordinal")) is int,
            "The real control operation/ordinal is absent")
    before = shared._epoch_milliseconds(tap["beganAt"])
    returned = shared._epoch_milliseconds(tap["returnedAt"])
    require(before <= returned <= time.time() * 1000
            and finite(tap["beganUptime"]) <= finite(tap["returnedUptime"]),
            "The actual tap interval is invalid")
    observations = value.get("observations")
    old = [] if prior is None else prior["observations"]
    require(type(observations) is list and len(observations) == len(old) + 1
            and len(observations) <= 64 and equal(observations[:-1], old)
            and tap["ordinal"] == len(observations), "An observed native-call prefix changed, skipped or replayed")
    row = observations[-1]
    require(row.get("ordinal") == len(observations) and row.get("operation") == operation
            and row.get("outcome") == "returned" and "error" not in row
            and before <= finite(row.get("requestedAtEpochMilliseconds"))
            <= finite(row.get("completedAtEpochMilliseconds")) <= time.time() * 1000,
            "The actual authored operation did not return after this real tap")
    if prior is not None:
        require(finite(prior["observations"][-1]["completedAtEpochMilliseconds"]) <= before
                and prior["observations"][-1]["completedAtEpochMilliseconds"] <= row["requestedAtEpochMilliseconds"],
                "A later real tap/native operation predates its admitted predecessor")
    calls = row.get("calls")
    require(type(calls) is list and calls, "The original native calls were not recorded")
    end = row["requestedAtEpochMilliseconds"]
    for call in calls:
        require(call.get("outcome") == "returned" and "error" not in call
                and end <= finite(call.get("requestedAtEpochMilliseconds"))
                <= finite(call.get("observedReturnAtEpochMilliseconds"))
                <= row["completedAtEpochMilliseconds"], "A native call failed, is pending or changed order")
        end = call["observedReturnAtEpochMilliseconds"]
    expo = request["engine"] == "expo"
    method = ("factory.getInstances/getId" if expo else "host.liveActivities.list")
    if operation == "prepare":
        names = ["host.readFile(state)", "createLiveActivity", method] if expo else ["File.exists(private State journal)", method]
        require(prior is None and [c["method"] for c in calls] == names
                and equal(calls[0].get("result"), {"exists": False} if expo else False)
                and calls[-1].get("result") == [] and value.get("slots") == {"A": None, "B": None}
                and value.get("lastObservedIDs") == []
                and row["requestedAtEpochMilliseconds"] <= finite(value.get("preparedAtEpochMilliseconds"))
                <= row["completedAtEpochMilliseconds"], "Preparation did not observe a fresh empty original owner")
        return copy.deepcopy(value)
    require(prior is not None and equal(value.get("storage"), prior["storage"])
            and value.get("preparedAtEpochMilliseconds") == prior["preparedAtEpochMilliseconds"]
            and value.get("listScope") == prior["listScope"], "The admitted foreground/private session changed")
    slots = copy.deepcopy(prior["slots"])
    listed = prior["lastObservedIDs"]
    if operation in ("start-a", "start-b"):
        slot = operation[-1].upper()
        require(slots[slot] is None and (slot == "A" or slots["A"] is not None and not slots["A"]["endRequestReturned"]),
                "A start replaced an existing or ended slot")
        names = ["factory.start", "activity.getId"] if expo else ["host.liveActivities.areEnabled", "host.liveActivities.start"]
        require([c["method"] for c in calls] == names, "The original start route changed")
        require(expo or calls[0].get("result") is True, "Actual ActivityKit authorization is disabled")
        returned_id = calls[-1].get("result") if expo else calls[-1].get("result", {}).get("activityID")
        returned_id = actual_id(returned_id)
        require(all(old_slot is None or old_slot["activityID"] != returned_id for old_slot in slots.values()),
                "Two starts reused an actual ActivityKit ID")
        slots[slot] = {"activityID": returned_id, "submittedRevision": 0, "endRequestReturned": False}
    elif operation == "list":
        require([c["method"] for c in calls] == [method], "The real owner-filtered List call is absent")
        listed = calls[0].get("result")
        require(type(listed) is list and all(type(x) is str for x in listed)
                and len(listed) == len(set(listed))
                and set(listed).issubset({r["activityID"] for r in slots.values() if r is not None}),
                "Actual List contains duplicate or foreign IDs")
    elif operation == "update-a":
        require(all(slots[k] is not None and not slots[k]["endRequestReturned"] for k in ("A", "B"))
                and slots["A"]["submittedRevision"] == 0, "Update A did not preserve both actual slots")
        names = ["activity.getId", "activity.update"] if expo else ["host.liveActivities.update"]
        require([c["method"] for c in calls] == names
                and (calls[0].get("result") == slots["A"]["activityID"] if expo else calls[0].get("result") == {"ok": True}),
                "The update did not return for actual A")
        slots["A"]["submittedRevision"] = 1
    elif operation in ("end-a", "end-b"):
        slot = operation[-1].upper()
        require(slots[slot] is not None and slots[slot]["endRequestReturned"] is False,
                "A repeated/unowned end is not admitted")
        names = ["activity.getId", "activity.end('immediate')"] if expo else ["host.liveActivities.end"]
        require([c["method"] for c in calls] == names
                and (calls[0].get("result") == slots[slot]["activityID"] if expo else calls[0].get("result") == {"ok": True}),
                "The end did not return for the exact actual slot")
        slots[slot]["endRequestReturned"] = True
    else:
        require(False, "Unknown lifecycle operation")
    require(equal(value.get("slots"), slots) and equal(value.get("lastObservedIDs"), listed),
            "The journal fabricated an ID, revision, other-slot mutation or List result")
    return copy.deepcopy(value)


def desired_ids(journal):
    return sorted(row["activityID"] for row in journal["slots"].values()
                  if row is not None and row["endRequestReturned"] is False)


def marker(run_id, slot, region, revision):
    require(slot in ("A", "B") and region in REGIONS and revision in (0, 1), "Invalid expected region marker")
    return "LA|" + run_id + "|" + slot + "|" + region + "|R" + str(revision)


def presentation(row, request, index, after):
    require(type(row) is dict and type(row.get("index")) is int and row["index"] == index
            and 0 <= index < len(PRESENTATIONS), "A system capture was omitted, replayed or reordered")
    name, _, expected, forbidden = PRESENTATIONS[index]
    require(row.get("name") == name and row.get("attachmentLabel") == "activity-lifecycle-" + name
            and row.get("systemOwner") == "com.apple.springboard"
            and row.get("systemForeground") is True and row.get("miniAppsForeground") is False,
            "The current real system surface is not observed")
    expected_context = "compact-home" if index == 0 else ("expanded-island" if index == 1 else
                       "home" if index == 5 else "notification-centre-pull-down")
    require(row.get("context") == expected_context, "The actual public presentation route changed")
    screen = widget.frame(row["screenFrame"])
    require(screen[2] < screen[3], "This bounded iPhone pilot requires observed portrait geometry")
    begin = shared._epoch_milliseconds(row["requestedAt"])
    end = shared._epoch_milliseconds(row["capturedAt"])
    require(after <= begin <= end <= time.time() * 1000
            and finite(row["requestedUptime"]) <= finite(row["capturedUptime"]),
            "The system capture predates its actual native operation/List")
    gesture = row.get("gesture", {})
    expected_gesture = ("actual-compact-marker-long-press" if index == 1 else
                        "public-home" if index in (0, 5) else "public-home-then-pull-down")
    require(type(gesture) is dict and gesture.get("kind") == expected_gesture
            and begin <= shared._epoch_milliseconds(gesture.get("returnedAt")) <= end
            and row["requestedUptime"] <= finite(gesture.get("returnedUptime")) <= row["capturedUptime"],
            "The real public gesture and its returned interval are required")
    if index == 1:
        compact = gesture.get("marker", {})
        text = marker(request["runID"], "A", "compact-leading", 0)
        require(gesture.get("durationSeconds") == 1 and compact.get("exists") is True
                and compact.get("hittable") is True and text in (compact.get("label"), compact.get("value"))
                and family.contained(widget.frame(compact["frame"]), screen),
                "Expansion requires a real long press on the observed own compact marker")
    elif index not in (0, 5):
        require(equal(gesture.get("startNormalized"), [0.2, 0.01])
                and equal(gesture.get("endNormalized"), [0.2, 0.80]),
                "The actual bounded public pull-down gesture changed")
    witnesses = row.get("emptyBannerContextWitnesses")
    require(type(witnesses) is list, "The actual system context observation is absent")
    if index == 6:
        require(1 <= len(witnesses) <= 8 and all(
            item.get("exists") is True and type(item.get("elementType")) is str
            and type(item.get("elementTypeRaw")) is int
            and item.get("label") in ("Notification Center", "No Older Notifications", "No Notifications")
            and family.contained(widget.frame(item["frame"]), screen) for item in witnesses),
            "An empty pulled-down capture needs an actual native Notification Center witness")
    else:
        require(witnesses == [], "An unrelated empty-surface witness was substituted")
    wanted = {marker(request["runID"], *parts) for parts in expected}
    elements = row.get("elements")
    require(type(elements) is dict and set(elements) == wanted, "Actual individually bound region evidence is incomplete")
    for text, element in elements.items():
        require(type(element) is dict and element.get("exists") is True
                and element.get("matchingCount") == 1 and type(element.get("elementType")) is str
                and element["elementType"] and type(element.get("elementTypeRaw")) is int
                and text in (element.get("label"), element.get("value")),
                "A visible region lacks its real native type/label/value/unique identity")
        bounds = widget.frame(element["frame"])
        window = element.get("window", {})
        require(window.get("owner") == "com.apple.springboard" and window.get("exists") is True
                and window.get("matchingWindowCount") == 1,
                "A visible region belongs to an absent or ambiguous actual window")
        window_frame = widget.frame(window["frame"])
        require(family.contained(window_frame, screen) and family.contained(bounds, window_frame)
                and family.contained(bounds, screen), "Actual region/window geometry is outside the observed screen")
    visible = row.get("visibleOwnedMarkers")
    require(type(visible) is list and len(visible) <= 64 and all(type(x) is str for x in visible)
            and all(x.startswith("LA|" + request["runID"] + "|") for x in visible),
            "The actual case-marker enumeration is not bounded or case-owned")
    for slot in forbidden:
        require(not any(text.startswith("LA|" + request["runID"] + "|" + slot + "|") for text in visible),
                "An ended slot remains visible in this actual system capture")
    require(row.get("forbiddenSlots") == list(forbidden), "The actual absence query did not cover the required own slots")
    if not wanted:
        require(visible == [] and row.get("noVisibleOwnedMarkersAtCapture") is True,
                "An empty API List cannot substitute for actual absence in the captured surface")
    return copy.deepcopy(row)


def retain_presentation(directory, target, row, request):
    retained = widget.retain_ui_artifacts(directory, target, row["attachmentLabel"])
    ax = (target / (row["attachmentLabel"] + "-accessibility.txt")).read_text()
    require("Application" in ax and "SpringBoard" in ax, "The actual AX attachment is not the system application")
    for text in row["elements"]:
        require(text in ax, "A claimed real region is missing from the retained actual AX tree")
    for slot in row["forbiddenSlots"]:
        require("LA|" + request["runID"] + "|" + slot + "|" not in ax,
                "The actual system AX still contains the ended slot")
    for witness in row["emptyBannerContextWitnesses"]:
        require(witness["label"] in ax, "The empty-surface native context witness is absent from actual AX")
    raw = (target / (row["attachmentLabel"] + ".png")).read_bytes()
    pixels = family.png_geometry(raw, "portrait", row["screenFrame"])
    return {"files": retained, "screenshotPixels": pixels,
            "scope": "Actual retained AX/PNG; no pixel-derived appearance or OS dismissal acknowledgment"}


def request_identity(request):
    fixed = fixture_contract(request.get("engine"))
    require(type(request.get("schema")) is int and request["schema"] == 1 and request.get("surface") == "liveActivityLifecycle"
            and widget.uuid_string(request.get("runID")) and request.get("fixtureAppID") == fixed["appID"]
            and request.get("fixtureTitle") == fixed["title"] and request.get("testMethod") == fixed["method"]
            and type(request.get("ownerProcessID")) is int and request["ownerProcessID"] > 0,
            "The lifecycle case/source/owner identity is invalid")
    return {key: copy.deepcopy(request[key]) for key in (
        "schema", "runID", "engine", "surface", "fixtureAppID", "fixtureTitle", "testMethod", "startedAt", "ownerProcessID")}


def observe_case(args, request, directory, evidence, seen):
    identity = request_identity(request)
    run_id, phase = request["runID"], request.get("phase")
    require(phase in ("activity-lifecycle-prepared", "activity-lifecycle-operation",
                      "activity-lifecycle-system", "activity-lifecycle-complete"),
            "Unknown actual lifecycle observation phase")
    if phase in ("activity-lifecycle-prepared", "activity-lifecycle-operation"):
        operation = request.get("operation", {})
        require(type(operation.get("ordinal")) is int and 1 <= operation["ordinal"] <= 64,
                "The actual operation ordinal is invalid")
    if phase == "activity-lifecycle-system":
        index = request.get("presentation", {}).get("index")
        require(type(index) is int and 0 <= index < len(PRESENTATIONS),
                "The actual presentation index is invalid")
    case = seen.get(run_id)
    if case is not None:
        require(equal(identity, case["identity"]) and str(directory) == case["directory"]
                and request.get("attemptID") == case["inputs"]["value"]["attemptID"]
                and request.get("sourceSHA") == case["inputs"]["value"]["sourceSHA"],
                "The admitted lifecycle owner/source/request identity changed")
        if phase == "activity-lifecycle-operation" and request["operation"]["ordinal"] <= len(case["operations"]):
            require(equal(request["operation"], case["operations"][request["operation"]["ordinal"] - 1]),
                    "An acknowledged actual control tap changed")
            return
        if phase == "activity-lifecycle-system" and request["presentation"]["index"] < len(case["presentations"]):
            require(equal(request["presentation"], case["presentations"][request["presentation"]["index"]]),
                    "An acknowledged actual system capture changed")
            return
    roots = shared.product_roots(args.device, args.bundle_id)
    inputs = load_inputs(args, evidence) if case is None else case["inputs"]
    require(inputs["value"]["engine"] == request["engine"], "The actual original archive belongs to another engine")
    widget.current_code(args, roots, inputs)
    process = products.process_observation(args, request, roots)
    package = current_package(roots, inputs)
    document = private_journal(roots, package, request)
    target = evidence / run_id
    if case is None:
        require(phase == "activity-lifecycle-prepared" and request["operation"]["name"] == "prepare"
                and not any(row.get("kind") == "liveActivityLifecycle" for row in seen.values()),
                "Exactly one fresh original lifecycle case must precede native operations")
        require(shared._epoch_milliseconds(request["startedAt"]) >= inputs["value"]["createdAt"] * 1000,
                "The UI case predates its actual source/device admission")
        if len(document["value"].get("observations", [])) < 1:
            return
        journal = journal_transition(document["value"], request, None, "prepare")
        owner = native_owner(roots, package, request, journal)
        target.mkdir(exist_ok=False)
        artifacts = widget.retain_ui_artifacts(directory, target, "activity-lifecycle-prepared")
        case = {"kind": "liveActivityLifecycle", "identity": identity, "directory": str(directory),
                "inputs": inputs, "roots": roots, "package": package, "process": process,
                "owner": owner, "journal": journal, "journalDocument": document,
                "operations": [copy.deepcopy(request["operation"])], "actions": ["prepare"],
                "presentations": [], "presentationArtifacts": [], "lastAcknowledgedAt": time.time() * 1000,
                "preparedArtifacts": artifacts, "finished": False}
        seen[run_id] = case
        widget.retain_response(directory, target, "identity.json", {"schema": 1, "runID": run_id, "status": "READY",
            "attemptID": inputs["value"]["attemptID"], "sourceSHA": inputs["value"]["sourceSHA"],
            "deviceAdmission": inputs["value"]["deviceAdmission"], "nativeOwner": owner,
            "package": package, "actualProcess": process, "journal": document, "ordinal": 1,
            "listedIDs": [], "desiredIDs": [], "actualContainers": {k: str(roots[k]) for k in ("app", "data", "group")}})
        return
    require(all(roots[k] == case["roots"][k] for k in ("app", "data", "group"))
            and equal(process, case["process"]) and equal(package["identity"], case["package"]["identity"])
            and package["record"]["sourceDigest"] == case["package"]["record"]["sourceDigest"]
            and document["path"] == case["journalDocument"]["path"],
            "The real process/package/generation/private journal changed")
    if phase == "activity-lifecycle-operation":
        operation = request["operation"]["name"]
        if len(document["value"].get("observations", [])) == len(case["journal"]["observations"]):
            return  # Actual asynchronous operation is still pending; do not acknowledge it.
        if operation != "list":
            require(len(case["actions"]) < len(ACTION_ORDER)
                    and operation == ACTION_ORDER[len(case["actions"])], "A lifecycle mutation was reordered or repeated")
            required_views = {"start-a": 0, "start-b": 2, "update-a": 3, "end-a": 4, "end-b": 5}[operation]
            require(len(case["presentations"]) == required_views,
                    "The prior actual system presentation is required before another mutation")
            require(case["actions"] == ["prepare"] or
                    case["journal"]["observations"][-1]["operation"] == "list"
                    and sorted(case["journal"]["lastObservedIDs"]) == desired_ids(case["journal"]),
                    "A genuine current owner-filtered List must precede the next mutation")
        else:
            require(case["actions"] != ["prepare"], "A mutation must precede its observed List")
        journal = journal_transition(document["value"], request, case["journal"], operation)
        owner = native_owner(roots, package, request, journal, case["owner"])
        artifacts = widget.retain_ui_artifacts(directory, target, "activity-lifecycle-operation-" + str(len(case["operations"]) + 1))
        case["operations"].append(copy.deepcopy(request["operation"]))
        if operation != "list":
            case["actions"].append(operation)
        case["journal"], case["journalDocument"], case["owner"] = journal, document, owner
        case["lastAcknowledgedAt"] = time.time() * 1000
        ordinal = len(case["operations"])
        widget.retain_response(directory, target, "operation-" + str(ordinal) + ".json",
            {"schema": 1, "runID": run_id, "status": "READY", "ordinal": ordinal, "operation": operation,
             "journal": document, "nativeOwner": owner, "actualProcess": process,
             "listedIDs": journal["lastObservedIDs"], "desiredIDs": desired_ids(journal), "artifacts": artifacts})
        return
    require(equal(document["value"], case["journal"]), "The native journal changed without an admitted actual tap")
    owner = native_owner(roots, package, request, case["journal"], case["owner"])
    if phase == "activity-lifecycle-system":
        index = len(case["presentations"])
        require(index < len(PRESENTATIONS) and case["actions"][-1] == PRESENTATIONS[index][1]
                and case["journal"]["observations"][-1]["operation"] == "list"
                and sorted(case["journal"]["lastObservedIDs"]) == desired_ids(case["journal"]),
                "The system capture has no exact current actual native operation/List")
        row = presentation(request["presentation"], request, index, case["lastAcknowledgedAt"])
        require(row.get("operationOrdinal") == len(case["operations"]),
                "The system capture is bound to another native operation")
        artifacts = retain_presentation(directory, target, row, request)
        case["presentations"].append(row); case["presentationArtifacts"].append(artifacts)
        widget.retain_response(directory, target, "presentation-" + str(index) + ".json",
            {"schema": 1, "runID": run_id, "status": "READY", "index": index,
             "actualSystemCapture": row, "actualArtifacts": artifacts,
             "actualIDs": {k: v["activityID"] for k, v in case["journal"]["slots"].items() if v is not None}})
        return
    if phase == "activity-lifecycle-complete" and not case["finished"]:
        require(case["actions"] == list(ACTION_ORDER) and len(case["presentations"]) == len(PRESENTATIONS)
                and case["journal"]["lastObservedIDs"] == []
                and all(v is not None and v["endRequestReturned"] is True for v in case["journal"]["slots"].values())
                and equal(request.get("presentations"), case["presentations"]),
                "Both actual IDs, independent update/end/list and all actual system captures are required")
        final = load_inputs(args, evidence)
        require(equal(final, case["inputs"]), "The current source/fixture attempt changed")
        widget.current_code(args, roots, final)
        require(host_archive(roots["app"], final["value"]["fixture"]["shippingArchiveSHA256"])["manifestSHA256"]
                == final["value"]["actualBundledSDK"]["manifestSHA256"], "The actual bundled SDK changed")
        widget.retain_response(directory, target, "completion.json", {"schema": 1, "runID": run_id,
            "status": "EXECUTED_PASS", "sourceSHA": final["value"]["sourceSHA"],
            "attemptID": final["value"]["attemptID"], "actualPackage": package,
            "actualProcess": process, "actualOwner": owner, "actualFinalJournal": document,
            "operations": case["operations"], "presentations": case["presentations"],
            "presentationArtifacts": case["presentationArtifacts"], "inputManifest": final,
            "scope": "One fresh iPhone Simulator engine: two actual activity IDs, List/update/end isolation, compact/expanded Island and banner AX/PNG",
            "limitations": "No forced minimal display, physical lock/APNs, restoration, stale/relevance/deep-link/button, cross-engine or full appearance/accessibility acceptance"})
        case["finished"] = True
