"""Portable graph and signed-bundle ownership checks for real extension targets."""
from copy import deepcopy
import json
import re
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
from extension_inventory import ROLES, SIGNING_TARGETS, signing_targets_for_owner, embedded_product_bundles
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
                         {"applications": 2, "extensions": 11, "shippingTargets": 13})
        validate_miniapps_extension_targets(self.project)
        self.assertEqual(validate_system_extension_sources(ROOT),
                         {"newExtensionEntryPoints": 3, "signingTargets": 13})
        self.assertEqual(len({row.bundle for row in SIGNING_TARGETS}), 13)
        self.assertEqual(len({row.profile_environment for row in SIGNING_TARGETS}), 13)

    def test_original_ten_signing_roles_and_profile_names_are_unchanged(self):
        self.assertEqual(ROLES[:10], [
            ("ai", "com.itorah.chavrusachat", "APPLE_MAIN_PROVISIONING_PROFILE_B64", "AI_HLY/AI_HLY.entitlements"),
            ("miniapps", "com.itorah.hanlinminiapps", "APPLE_MINIAPPS_PROVISIONING_PROFILE_B64", "HanlinMiniAppsApp/HanlinMiniApps.entitlements"),
            ("share", "com.itorah.chavrusachat.share", "APPLE_SHARE_PROVISIONING_PROFILE_B64", "ChavrusaChatShare/ChavrusaChatShare.entitlements"),
            ("widgets", "com.itorah.chavrusachat.widgets", "APPLE_WIDGETS_PROVISIONING_PROFILE_B64", "HanlinScriptingWidgets/HanlinScriptingWidgets.entitlements"),
            ("translation", "com.itorah.chavrusachat.translation-provider", "APPLE_TRANSLATION_PROVISIONING_PROFILE_B64", "ChavrusaChatTranslationProvider/ChavrusaChatTranslationProvider.entitlements"),
            ("notification", "com.itorah.chavrusachat.notification-service", "APPLE_NOTIFICATION_SERVICE_PROVISIONING_PROFILE_B64", "ChavrusaChatNotificationService/ChavrusaChatNotificationService.entitlements"),
            ("miniapps_widgets", "com.itorah.hanlinminiapps.widgets", "APPLE_MINIAPPS_WIDGETS_PROVISIONING_PROFILE_B64", "HanlinMiniAppsExtensions/Widgets/HanlinMiniAppsWidgets.entitlements"),
            ("miniapps_share", "com.itorah.hanlinminiapps.share", "APPLE_MINIAPPS_SHARE_PROVISIONING_PROFILE_B64", "HanlinMiniAppsExtensions/Share/HanlinMiniAppsShare.entitlements"),
            ("miniapps_translation_provider", "com.itorah.hanlinminiapps.translation-provider", "APPLE_MINIAPPS_TRANSLATION_PROVIDER_PROVISIONING_PROFILE_B64", "HanlinMiniAppsExtensions/Translation/HanlinMiniAppsTranslationProvider.entitlements"),
            ("miniapps_notification_service", "com.itorah.hanlinminiapps.notification-service", "APPLE_MINIAPPS_NOTIFICATION_SERVICE_PROVISIONING_PROFILE_B64", "HanlinMiniAppsExtensions/Notification/HanlinMiniAppsNotificationService.entitlements"),
        ])

    def test_new_system_surfaces_do_not_acquire_hanlin_shipping_or_registration(self):
        names = {value["name"] for value in self.project["objects"].values()
                 if value.get("isa") == "PBXNativeTarget"}
        self.assertFalse(names & {"ChavrusaChatKeyboard", "ChavrusaChatNotificationContent", "ChavrusaChatCameraCapture"})
        scene = (ROOT / "AI_HLY/Downstream/SDK/HanlinApplicationScene.swift").read_text()
        intents = (ROOT / "AI_HLY/Downstream/SystemIntegrations/ChavrusaSystemIntegrations.swift").read_text()
        widget = (ROOT / "HanlinScriptingWidgets/HanlinScriptingWidgets.swift").read_text()
        self.assertNotIn(".hanlinMiniAppSystemEntrypoints(", scene)
        self.assertNotIn("HanlinMiniAppSystemIntentsPackage.self", intents)
        self.assertNotIn("HanlinCameraCaptureIntentsPackage.self", intents)
        self.assertNotIn("HanlinCameraCaptureControl", widget)
        mini = (ROOT / "HanlinMiniAppsApp/HanlinMiniAppsApp.swift").read_text()
        self.assertIn(".hanlinMiniAppSystemEntrypoints(", mini)
        package_pattern = r"\b(?:struct|class|enum|extension)\s+(\w+)\s*:\s*AppIntentsPackage\b"
        self.assertEqual(re.findall(package_pattern, mini), ["HanlinMiniAppsIntents"])
        self.assertEqual(re.findall(package_pattern, intents), ["HanlinApplicationIntentsPackage"])
        self.assertNotIn("HanlinMiniAppSystemIntentsPackage.self", mini)
        objects = self.project["objects"]
        mini_sources = {
            objects[objects[file]["fileRef"]].get("path")
            for phase in self.target(self.project, "HanlinMiniApps")["buildPhases"]
            if objects[phase]["isa"] == "PBXSourcesBuildPhase"
            for file in objects[phase]["files"] if "fileRef" in objects[file]
        }
        entity_path = "AI_HLY/Downstream/ScriptingPlatform/HanlinInstalledMiniAppEntity.swift"
        self.assertIn(entity_path, mini_sources)
        entity = (ROOT / entity_path).read_text()
        self.assertIn("public struct HanlinInstalledMiniAppEntity: IndexedEntity", entity)
        self.assertIn("public struct HanlinInstalledMiniAppQuery: EnumerableEntityQuery, EntityStringQuery, IndexedEntityQuery", entity)
        self.assertIn("public struct HanlinOpenInstalledMiniAppIntent: OpenIntent", entity)
        self.assertEqual(re.findall(package_pattern, entity), [])
        app = (ROOT / "AI_HLY/AI_HLY.swift").read_text()
        self.assertIn("HanlinApplicationIntentsPackage.self", app)
        self.assertIn("HanlinCameraCaptureIntentsPackage.self", mini)
        project = deepcopy(self.project)
        objects = project["objects"]
        original = self.target(project, "HanlinMiniAppsKeyboard")
        unexpected = deepcopy(original)
        unexpected["name"] = "ChavrusaChatKeyboard"
        objects["UNEXPECTED_AI_KEYBOARD"] = unexpected
        objects[project["rootObject"]]["targets"].append("UNEXPECTED_AI_KEYBOARD")
        with self.assertRaisesRegex(AssertionError, "Shipping bundle inventory"):
            validate_shipping_extension_inventory(project)
        project = deepcopy(self.project)
        objects = project["objects"]
        camera = next(key for key, value in objects.items()
                      if value.get("productName") == "HanlinCameraCaptureUI")
        self.target(project, "HanlinScriptingWidgets")["packageProductDependencies"].append(camera)
        with self.assertRaisesRegex(AssertionError, "remain in MiniApps"):
            validate_shipping_extension_inventory(project)

    def test_shared_publication_and_camera_ui_are_gated_to_standalone_miniapps(self):
        directory = ROOT / "AI_HLY/Downstream/ScriptingPlatform"
        index = (directory / "HanlinMiniAppSpotlightIndex.swift").read_text()
        self.assertIn("identifier == SplitAppStorageLayout.miniAppsBundleIdentifier", index)
        self.assertIn("supportsProduct(identifier: productIdentifier)", index)
        reconcile = index.split("    func reconcile(", 1)[1].split("    func claimPresentation(", 1)[0]
        self.assertLess(reconcile.index("guard Self.isAvailableForCurrentProduct else { return }"),
                        reconcile.index("records = HanlinMiniAppSystemCatalog.records"))
        for name in ("reindexSpotlight()", "openSpotlightEntity(id: String)"):
            method = index.split("    func " + name, 1)[1].split("\n    }", 1)[0]
            self.assertIn("guard Self.isAvailableForCurrentProduct else { throw", method)
        platform = (directory / "HanlinScriptingPlatform.swift").read_text()
        publication = platform.split("        await HanlinMiniAppSystemEntrypoints.shared.reconcile(", 1)[0]
        self.assertTrue(publication.rstrip().endswith(
            "if HanlinMiniAppSystemEntrypoints.isAvailableForCurrentProduct {"))
        self.assertIn("WidgetCenter.shared.reloadTimelines", publication)
        detail = (directory / "ScriptingPackageCenterViews.swift").read_text()
        before_camera = detail.split("HanlinMiniAppCaptureSection(package:", 1)[0]
        self.assertTrue(before_camera.rstrip().endswith(
            "if HanlinMiniAppSystemEntrypoints.isAvailableForCurrentProduct {"))
        views = (directory / "HanlinMiniAppSystemEntrypointsView.swift").read_text()
        section = views.split("struct HanlinMiniAppCaptureSection: View", 1)[1]
        self.assertIn("if HanlinMiniAppSystemEntrypoints.isAvailableForCurrentProduct, !records.isEmpty", section)

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
        source = self.target(project, "HanlinScriptingWidgets")["productReference"]
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
        app = self.target(project, "HanlinMiniApps")
        extensionkit = next(objects[key] for key in app["buildPhases"]
                            if objects[key].get("name") == "Embed MiniApps ExtensionKit Extensions")
        plugins = next(objects[key] for key in app["buildPhases"]
                       if objects[key].get("name") == "Embed MiniApps App Extensions")
        capture = self.target(project, "HanlinMiniAppsCameraCapture")["productReference"]
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
        widget = self.target(project, "HanlinMiniAppsWidgets")
        widget["packageProductDependencies"] = [
            key for key in widget["packageProductDependencies"]
            if project["objects"][key]["productName"] != "HanlinCameraCaptureUI"]
        with self.assertRaises(AssertionError):
            validate_shipping_extension_inventory(project)

    def test_each_export_selects_exactly_its_five_or_eight_owned_bundles(self):
        ai = signing_targets_for_owner("ai")
        mini = signing_targets_for_owner("miniapps")
        self.assertEqual((len(ai), len(mini)), (5, 8))
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
            "miniapps", "miniapps_keyboard", "miniapps_notification_content", "miniapps_camera_capture"})
        for role in REGISTRATION_ROLES:
            target, name, capabilities, source = registration_target(role, ROOT)
            self.assertTrue(name)
            self.assertTrue(source.is_file())
            if target.bundle.endswith(".camera-capture"):
                self.assertEqual(capabilities, ())
            elif role != "miniapps":
                self.assertEqual(capabilities, ("APP_GROUPS",))
            self.assertIn(target, SIGNING_TARGETS)
        for role in ["ai", "keyboard", "notification-content", "camera-capture"]:
            with self.assertRaises(ValueError):
                registration_target(role, ROOT)
