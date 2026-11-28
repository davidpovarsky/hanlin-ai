import copy
import json
import os
import re
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "Scripts/SDK"))
import generate_manifest
import update_project
from project_graph import parse_project


def dump(package):
    return json.loads(subprocess.check_output(
        ["swift", "package", "--package-path", str(package), "dump-package"],
        text=True, timeout=30))


def target(manifest, name):
    return next(value for value in manifest["targets"] if value["name"] == name)


def swift_import_contract(value):
    settings = [item["kind"] for item in value["settings"] if item["tool"] == "swift"]
    modes = [item["interoperabilityMode"]["_0"] for item in settings if "interoperabilityMode" in item]
    flags = [flag for item in settings if "unsafeFlags" in item for flag in item["unsafeFlags"]["_0"]]
    normalized = [flag[:2] + os.path.normpath(flag[2:])
                  if flag.startswith(("-I/", "-F/")) else flag for flag in flags]
    return modes, normalized


class WidgetCxxImportTests(unittest.TestCase):
    def test_real_widget_consumers_preserve_original_expo_cpp_import_contract(self):
        original = dump(ROOT / "Packages/HanlinExpoRuntime")
        widgets = dump(ROOT / "Packages/HanlinWidgetSDK")
        unified = dump(ROOT)
        producer = target(original, "ExpoWidgetsHost")
        expected = swift_import_contract(producer)
        self.assertEqual(expected[0], ["Cxx"])
        self.assertIn("-std=gnu++20", expected[1])
        self.assertIn("-DREACT_NATIVE_PRODUCTION=1", expected[1])
        self.assertIn("-DRN_DEBUG_STRING_CONVERTIBLE=0", expected[1])
        self.assertTrue(any("ReactModularHeaders" in flag for flag in expected[1]))
        self.assertTrue(any("ModularFrameworks" in flag for flag in expected[1]))
        products = {value["name"]: value["targets"] for value in unified["products"]}
        owners = {dependency["product"][1].lower()
                  for value in widgets["targets"] for dependency in value["dependencies"]
                  if "product" in dependency}
        local_products = {owner: products for owner in owners}
        text = (ROOT / "Package.swift").read_text()
        for name in ["HanlinScriptingWidgets", "HanlinWidgetUI"]:
            with self.subTest(target=name):
                source = target(widgets, name)
                extension_contract = ([], ["-application-extension"])
                self.assertEqual(swift_import_contract(source), extension_contract)
                self.assertEqual(swift_import_contract(target(unified, name)), extension_contract)
                self.assertFalse(any("swiftLanguageMode" in item["kind"] for item in source["settings"]),
                                 "Consumer must retain package Swift6, not inherit original ExpoWidgets Swift5.")
                self.assertIn(generate_manifest.target(source, "Packages/HanlinWidgetSDK", local_products), text)
        project_text = update_project.FILE.read_text()
        objects = parse_project(project_text)["objects"]
        expected_flags = ["$(inherited)"] + [
            flag.replace(str(ROOT), "$(SRCROOT)") for flag in expected[1]]
        consumers = {"HanlinApp", "HanlinMiniApps", "AI_HLYTests", "HanlinMiniAppsTests",
                     "HanlinScriptingWidgets", "HanlinMiniAppsWidgets"}
        hosts = {value["name"]: value for value in objects.values()
                 if value.get("isa") == "PBXNativeTarget" and value.get("name") in consumers}
        self.assertEqual(set(hosts), consumers)
        for name, value in hosts.items():
            configs = objects[value["buildConfigurationList"]]["buildConfigurations"]
            self.assertEqual({objects[key]["name"] for key in configs}, {"Debug", "Release"})
            for key in configs:
                settings = objects[key]["buildSettings"]
                with self.subTest(host=name, config=objects[key]["name"]):
                    self.assertEqual(settings["SWIFT_ENABLE_EXPLICIT_MODULES"], "YES")
                    flags = settings["OTHER_SWIFT_FLAGS"]
                    self.assertIn("$(inherited)", flags)
                    if name in {"HanlinScriptingWidgets", "HanlinMiniAppsWidgets"}:
                        self.assertNotIn("SWIFT_OBJC_INTEROP_MODE", settings)
                        self.assertEqual(settings["APPLICATION_EXTENSION_API_ONLY"], "YES")
                        self.assertEqual(flags, ["$(inherited)"])
                    else:
                        self.assertEqual(settings["SWIFT_OBJC_INTEROP_MODE"], "objcxx")
                        for index in range(1, len(expected_flags), 2):
                            pair = expected_flags[index:index + 2]
                            self.assertTrue(any(flags[offset:offset + 2] == pair
                                                for offset in range(len(flags) - 1)), pair)
        # Preserve an existing scalar flags setting, including app-specific
        # definitions, without modifying any other project object or setting.
        app_key = objects[hosts["HanlinApp"]["buildConfigurationList"]]["buildConfigurations"][0]
        seeded = update_project.edit_object(project_text, app_key, lambda block: re.sub(
            r'"?OTHER_SWIFT_FLAGS"? = [^;]+;',
            'OTHER_SWIFT_FLAGS = "$(inherited) -D HANLIN_IMPORT_PARITY_PROBE";', block, count=1))
        expected_project = parse_project(seeded)
        expected_project["objects"][app_key]["buildSettings"]["OTHER_SWIFT_FLAGS"] = [
            "$(inherited)", "-D", "HANLIN_IMPORT_PARITY_PROBE", *expected_flags[1:]]
        self.assertEqual(parse_project(update_project.wire_widget_cxx_imports(seeded, unified)),
                         expected_project)
        # Use the actual project producer, including the real MiniApps extension
        # cloning path. Neither this source contract nor dump-package runs Xcode.
        with tempfile.TemporaryDirectory(prefix="hanlin-widget-cxx-project-") as folder:
            path = Path(folder) / "project.pbxproj"
            path.write_text(project_text)
            with patch.object(update_project, "FILE", path):
                rendered = update_project.update(package=unified)
                self.assertEqual(parse_project(rendered), parse_project(project_text))
                path.write_text(rendered)
                self.assertEqual(update_project.update(package=unified), rendered)


    def test_original_widget_extension_keeps_one_shared_module_and_rejects_app_runtime_edges(self):
        unified = dump(ROOT)
        products = {value["name"]: value["targets"] for value in unified["products"]}
        self.assertEqual(products["HanlinExpoWidgetsExtension"], ["ExpoWidgets"])
        self.assertEqual(products["HanlinExpoWidgetsOriginal"], ["ExpoWidgets", "ExpoWidgetsHost"])
        reachable = update_project.validate_widget_extension_boundary(unified)
        self.assertIn("ExpoWidgets", reachable)
        self.assertIn("HanlinExpoWidgetSubset", reachable)
        self.assertNotIn("ExpoWidgetsHost", reachable)
        self.assertNotIn("ExpoModulesCore", reachable)
        for forbidden in ("ExpoWidgetsHost", "ExpoModulesCore", "React", "hermesvm"):
            changed = copy.deepcopy(unified)
            target(changed, "ExpoWidgets")["dependencies"].append({"byName": [forbidden, None]})
            with self.subTest(forbidden=forbidden), self.assertRaisesRegex(ValueError, "app-only target"):
                update_project.validate_widget_extension_boundary(changed)
        changed = copy.deepcopy(unified)
        target(changed, "ExpoWidgets")["settings"] = []
        with self.assertRaisesRegex(ValueError, "extension-safe native imports"):
            update_project.validate_widget_extension_boundary(changed)
        original = dump(ROOT / "Packages/HanlinExpoRuntime")
        shared, host = target(original, "ExpoWidgets"), target(original, "ExpoWidgetsHost")
        self.assertEqual(shared["path"], host["path"])
        expected_host = {"Original/LiveActivity.swift", "Original/LiveActivityFactory.swift",
                         "Original/WidgetObject.swift", "Original/WidgetsExceptions.swift",
                         "Original/WidgetsModule.swift", "Original/WidgetsRecords.swift"}
        self.assertEqual(set(host["sources"]), expected_host)
        self.assertEqual(set(shared["exclude"]), expected_host)
        self.assertEqual(shared["resources"], [{"path": "Resources/ExpoWidgets.bundle", "rule": {"copy": {}}}])
        root = ROOT / "Packages/HanlinExpoRuntime" / shared["path"]
        self.assertTrue(expected_host <= {path.relative_to(root).as_posix() for path in root.rglob("*.swift")})
        for path in root.rglob("*.swift"):
            if path.relative_to(root).as_posix() not in expected_host:
                self.assertNotRegex(path.read_text(), r"(?m)^import (ExpoModulesCore|ExpoUI|React)\b", path)
        host_settings = swift_import_contract(host)
        self.assertEqual(host_settings[0], ["Cxx"])
        self.assertIn("-DREACT_NATIVE_PRODUCTION=1", host_settings[1])
        project = parse_project(update_project.FILE.read_text())["objects"]
        for value in project.values():
            if value.get("isa") != "PBXNativeTarget" or value.get("name") not in {"HanlinScriptingWidgets", "HanlinMiniAppsWidgets"}:
                continue
            declared = {project[ref]["productName"] for ref in value["packageProductDependencies"]}
            self.assertIn("HanlinExpoWidgetsExtension", declared)
            self.assertNotIn("HanlinExpoWidgetsOriginal", declared)
            phase = next(project[ref] for ref in value["buildPhases"] if project[ref]["isa"] == "PBXFrameworksBuildPhase")
            linked = {project[project[ref]["productRef"]]["productName"] for ref in phase["files"] if "productRef" in project[ref]}
            self.assertIn("HanlinExpoWidgetsExtension", linked)
            self.assertNotIn("HanlinExpoWidgetsOriginal", linked)

    def test_original_modifier_vocabulary_does_not_expand_prepared_widget_admission(self):
        native = ROOT / "Packages/HanlinExpoWidgetSubset/Sources/HanlinExpoWidgetSubset"
        registry = (native / "ExpoUI/Modifiers/ViewModifierRegistry.swift").read_text()
        keys = set(re.findall(r'register\("([^"]+)"', registry))
        self.assertEqual(len(keys), 164)
        self.assertTrue({"glassEffect", "toggleStyle", "onScrollGeometryChange", "onHingeChange", "searchable"} <= keys)
        context = (native / "DictionaryContext.swift").read_text()
        block = context.split("static let preparedModifierTypes: Set<String> = [", 1)[1].split("]", 1)[0]
        prepared = set(re.findall(r'"([^"]+)"', block))
        self.assertEqual(len(prepared), 101)
        self.assertEqual(len(prepared & keys), 97)
        self.assertEqual(prepared - keys, {"widgetURL", "activityBackgroundTint", "resizable", "widgetAccentedRenderingMode"})
        self.assertIn("AppContext.preparedModifierTypes.contains(name)", context)
        self.assertIn("context.resources.values.contains(url)", context)
        self.assertIn("properties: Properties = .preparedResources", context)
        self.assertIn("if context.properties == .originalWidgets", context)
        self.assertIn("guard appContext.properties == .preparedResources", context)
        for filename in ("HingeObservationModifiers.swift", "ScrollObservationModifiers.swift"):
            text = (native / "ExpoUI/Modifiers" / filename).read_text()
            self.assertIn('guard params["workletCallback"] == nil || params["workletCallback"] is NSNull else', text)
            self.assertNotIn("WorkletCallback?", text)
            self.assertNotIn("workletCallback.invoke", text)
        source = (ROOT / "Packages/HanlinExpoRuntime/Sources/ExpoWidgets/Original/Widgets/ViewRenderer.swift").read_text()
        self.assertIn("WidgetButtonView.self", source)
        self.assertIn("LiveActivityButtonView.self", source)
        self.assertIn("WidgetToggleView.self", source)
        self.assertNotIn("HanlinExpoNativeWidgetView", source)


if __name__ == "__main__":
    unittest.main()
