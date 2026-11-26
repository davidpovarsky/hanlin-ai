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
        producer = target(original, "ExpoWidgets")
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
                self.assertEqual(swift_import_contract(source), expected)
                self.assertEqual(swift_import_contract(target(unified, name)), expected)
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
                    self.assertEqual(settings["SWIFT_OBJC_INTEROP_MODE"], "objcxx")
                    self.assertEqual(settings["SWIFT_ENABLE_EXPLICIT_MODULES"], "YES")
                    flags = settings["OTHER_SWIFT_FLAGS"]
                    self.assertIn("$(inherited)", flags)
                    for index in range(1, len(expected_flags), 2):
                        pair = expected_flags[index:index + 2]
                        self.assertTrue(any(flags[offset:offset + 2] == pair
                                            for offset in range(len(flags) - 1)), pair)
                    if name in {"HanlinScriptingWidgets", "HanlinMiniAppsWidgets"}:
                        self.assertEqual(flags, expected_flags)
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


if __name__ == "__main__":
    unittest.main()
