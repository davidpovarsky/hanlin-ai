"""Portable graph and signed-bundle ownership checks for real extension targets."""
from copy import deepcopy
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "Scripts/SDK"))
sys.path.insert(0, str(ROOT / "Scripts/ProductSplit"))
import update_project
from extension_inventory import SIGNING_TARGETS, signing_targets_for_owner, embedded_product_bundles
from project_graph import parse_project, validate_miniapps_extension_targets, validate_shipping_extension_inventory
from register_miniapps_bundle import registration_target, REGISTRATION_ROLES
from verify_targets import validate_system_extension_sources


class SystemExtensionTargetsTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.text = update_project.FILE.read_text()
        cls.project = parse_project(cls.text)

    def target(self, project, name):
        return next(value for value in project["objects"].values()
                    if value.get("isa") == "PBXNativeTarget" and value.get("name") == name)

    def test_complete_actual_shipping_graph_and_source_metadata(self):
        self.assertEqual(validate_shipping_extension_inventory(self.project),
                         {"applications": 2, "extensions": 14, "shippingTargets": 16})
        validate_miniapps_extension_targets(self.project)
        self.assertEqual(validate_system_extension_sources(ROOT),
                         {"newExtensionEntryPoints": 6, "signingTargets": 16})
        self.assertEqual(len({row.bundle for row in SIGNING_TARGETS}), 16)
        self.assertEqual(len({row.profile_environment for row in SIGNING_TARGETS}), 16)

    def test_generation_is_idempotent_and_preserves_native_shell_phases(self):
        package = json.loads(subprocess.check_output(
            ["swift", "package", "--package-path", str(ROOT), "dump-package"],
            text=True, timeout=120))
        before = self.project["objects"]
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / "project.pbxproj"
            path.write_text(self.text)
            with patch.object(update_project, "FILE", path):
                first = update_project.update(package=package)
                path.write_text(first)
                self.assertEqual(update_project.update(package=package), first)
        after = parse_project(first)["objects"]
        for key, value in before.items():
            if value.get("isa") == "PBXShellScriptBuildPhase":
                self.assertEqual(after[key], value, key)
        validate_shipping_extension_inventory(parse_project(first))

    def test_wrong_owner_or_duplicate_embedding_is_rejected(self):
        project = deepcopy(self.project)
        objects = project["objects"]
        ai = self.target(project, "HanlinApp")
        mini = self.target(project, "HanlinMiniApps")
        source = self.target(project, "ChavrusaChatKeyboard")["productReference"]
        phase = next(objects[key] for key in mini["buildPhases"]
                     if objects[key].get("name") == "Embed MiniApps App Extensions")
        objects[phase["files"][0]]["fileRef"] = source
        with self.assertRaises(AssertionError):
            validate_shipping_extension_inventory(project)
        project = deepcopy(self.project)
        objects = project["objects"]
        phase = next(objects[key] for key in self.target(project, "HanlinApp")["buildPhases"]
                     if objects[key].get("name") == "Embed App Extensions")
        phase["files"].append(phase["files"][0])
        with self.assertRaises(AssertionError):
            validate_shipping_extension_inventory(project)

    def test_capture_cannot_be_embedded_in_plugins(self):
        project = deepcopy(self.project)
        objects = project["objects"]
        app = self.target(project, "HanlinApp")
        extensionkit = next(objects[key] for key in app["buildPhases"]
                            if objects[key].get("name") == "Embed ExtensionKit Extensions")
        plugins = next(objects[key] for key in app["buildPhases"]
                       if objects[key].get("name") == "Embed App Extensions")
        capture = self.target(project, "ChavrusaChatCameraCapture")["productReference"]
        file_id = next(key for key in extensionkit["files"] if objects[key]["fileRef"] == capture)
        extensionkit["files"].remove(file_id)
        plugins["files"].append(file_id)
        with self.assertRaises(AssertionError):
            validate_shipping_extension_inventory(project)

    def test_missing_target_or_capture_intent_link_is_rejected(self):
        project = deepcopy(self.project)
        root = project["objects"][project["rootObject"]]
        root["targets"] = [key for key in root["targets"]
                           if project["objects"][key].get("name") != "HanlinMiniAppsCameraCapture"]
        with self.assertRaises(AssertionError):
            validate_shipping_extension_inventory(project)
        project = deepcopy(self.project)
        widget = self.target(project, "HanlinScriptingWidgets")
        widget["packageProductDependencies"] = [
            key for key in widget["packageProductDependencies"]
            if project["objects"][key]["productName"] != "HanlinCameraCaptureUI"]
        with self.assertRaises(AssertionError):
            validate_shipping_extension_inventory(project)

    def test_each_export_selects_its_own_eight_bundles(self):
        ai = signing_targets_for_owner("ai")
        mini = signing_targets_for_owner("miniapps")
        self.assertEqual((len(ai), len(mini)), (8, 8))
        self.assertFalse({row.bundle for row in ai} & {row.bundle for row in mini})
        self.assertTrue(all(row.bundle == "com.itorah.hanlinminiapps" or
                            row.bundle.startswith("com.itorah.hanlinminiapps.") for row in mini))
        with self.assertRaises(ValueError):
            signing_targets_for_owner("unknown")
        with tempfile.TemporaryDirectory() as directory:
            app = Path(directory) / "Hanlin.app"
            app.mkdir()
            for name in ("PlugIns/Keyboard.appex", "Extensions/Translation.appex", "Extensions/Capture.appex"):
                (app / name).mkdir(parents=True)
            self.assertEqual({path.relative_to(app).as_posix() for path in embedded_product_bundles(app)},
                             {".", "PlugIns/Keyboard.appex", "Extensions/Translation.appex", "Extensions/Capture.appex"})

    def test_registration_scope_and_capture_entitlements_are_exact(self):
        self.assertEqual(set(REGISTRATION_ROLES), {
            "miniapps", "keyboard", "notification-content", "camera-capture",
            "miniapps-keyboard", "miniapps-notification-content", "miniapps-camera-capture"})
        for role in REGISTRATION_ROLES:
            target, name, capabilities, source = registration_target(role, ROOT)
            self.assertTrue(name)
            self.assertTrue(source.is_file())
            if role.endswith("camera-capture"):
                self.assertEqual(capabilities, ())
            elif role != "miniapps":
                self.assertEqual(capabilities, ("APP_GROUPS",))
            self.assertIn(target, SIGNING_TARGETS)
        with self.assertRaises(ValueError):
            registration_target("ai", ROOT)
