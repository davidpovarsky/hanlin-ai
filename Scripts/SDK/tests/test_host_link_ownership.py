import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
import xml.etree.ElementTree as ET
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "Scripts/SDK"))
import update_project
from project_graph import parse_project


class HostLinkOwnershipTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.text = update_project.FILE.read_text()
        cls.project = parse_project(cls.text)

    def host_phases(self, project):
        objects = project["objects"]
        return {target["name"]: next(key for key in target["buildPhases"]
                    if objects[key]["isa"] == "PBXFrameworksBuildPhase")
                for target in objects.values() if target.get("isa") == "PBXNativeTarget"
                and target.get("name") in {"HanlinApp", "AI_HLYTests"}}

    def assert_single_owner(self, project):
        objects = project["objects"]
        phases = self.host_phases(project)
        self.assertEqual(set(phases), {"HanlinApp", "AI_HLYTests"})
        for name, phase in phases.items():
            products = [objects[objects[key]["productRef"]]["productName"]
                        for key in objects[phase]["files"] if "productRef" in objects[key]]
            self.assertEqual(products, ["HanlinApplication"], name)

    def test_host_target_name_disambiguates_the_sdk_and_preserves_the_app_product(self):
        objects = self.project["objects"]
        app_id = "D7B6C3C02D50A55D004E3AD6"
        app = objects[app_id]
        self.assertEqual(app["name"], "HanlinApp")
        self.assertEqual(app["productReference"], "D7B6C3C12D50A55D004E3AD6")
        self.assertEqual(objects[app["productReference"]]["path"], "AI_Hanlin.app")
        for key in objects[app["buildConfigurationList"]]["buildConfigurations"]:
            settings = objects[key]["buildSettings"]
            self.assertEqual(settings["PRODUCT_NAME"], "AI_Hanlin")
            self.assertEqual(settings["PRODUCT_MODULE_NAME"], "HanlinApp")
            self.assertEqual(settings["PRODUCT_BUNDLE_IDENTIFIER"], "com.itorah.chavrusachat")
        ui = next(target for target in objects.values()
                  if target.get("productType") == "com.apple.product-type.bundle.ui-testing")
        for key in objects[ui["buildConfigurationList"]]["buildConfigurations"]:
            self.assertEqual(objects[key]["buildSettings"]["TEST_TARGET_NAME"], app["name"])
        proxies = [obj for obj in objects.values()
                   if obj.get("isa") == "PBXContainerItemProxy"
                   and obj.get("remoteGlobalIDString") == app_id]
        self.assertEqual(len(proxies), 2)
        self.assertTrue(all(obj["remoteInfo"] == app["name"] for obj in proxies))
        references = []
        for scheme in (ROOT / "AI_HLY.xcodeproj/xcshareddata/xcschemes").glob("*.xcscheme"):
            references += [ref for ref in ET.parse(scheme).iter("BuildableReference")
                           if ref.get("BlueprintIdentifier") == app_id]
        self.assertEqual(len(references), 6)
        for ref in references:
            self.assertEqual(ref.get("BlueprintName"), app["name"])
            self.assertEqual(ref.get("BuildableName"), "AI_Hanlin.app")

    def test_checked_in_hosts_link_only_the_shared_application_image(self):
        self.assert_single_owner(self.project)

    def test_generator_preserves_declared_source_closure_and_all_unrelated_objects(self):
        # Reintroduce the actual duplicate products observed in the native log.
        # The retained PBXBuildFile objects are source declarations, not extra
        # linked implementations once their phase membership is removed.
        text = self.text
        objects = self.project["objects"]
        phases = self.host_phases(self.project)
        for host, product in [("HanlinApp", "HanlinScriptStore"),
                              ("HanlinApp", "HanlinScriptDeviceServices"),
                              ("AI_HLYTests", "HanlinExpoWidgetNative")]:
            build = next(key for key, obj in objects.items()
                         if obj.get("isa") == "PBXBuildFile" and
                         objects.get(obj.get("productRef"), {}).get("productName") == product)
            current = parse_project(text)["objects"][phases[host]]["files"]
            if build not in current:
                text = update_project.edit_object(text, phases[host],
                    lambda block: update_project.replace_list(block, "files", current + [build]))
        before = parse_project(text)
        with tempfile.TemporaryDirectory() as folder:
            project_path = Path(folder) / "project.pbxproj"
            project_path.write_text(text)
            with patch.object(update_project, "FILE", project_path):
                rendered = update_project.update()
                project_path.write_text(rendered)
                self.assertEqual(update_project.update(), rendered)
        after = parse_project(rendered)
        self.assert_single_owner(after)
        self.assertEqual(set(before["objects"]), set(after["objects"]))
        for key, obj in before["objects"].items():
            if key not in phases.values():
                self.assertEqual(after["objects"][key], obj, key)
            else:
                # Preserve every native/system file reference in the two phases.
                old = [f for f in obj["files"] if "productRef" not in objects[f]]
                new = [f for f in after["objects"][key]["files"] if "productRef" not in objects[f]]
                self.assertEqual(old, new)

    def test_every_declared_host_product_remains_reachable_and_unknown_products_are_kept(self):
        manifest = json.loads(subprocess.check_output(
            ["swift", "package", "--package-path", str(ROOT), "dump-package"], text=True))
        self.assertEqual(len(manifest["products"]), 44)
        self.assertEqual(len(manifest["targets"]), 108)
        target_names = {target["name"] for target in manifest["targets"]}
        self.assertIn("AI_Hanlin", target_names)
        self.assertNotIn("HanlinApp", target_names)
        closure = update_project.application_product_closure(manifest)
        objects = self.project["objects"]
        for obj in objects.values():
            if obj.get("isa") != "PBXNativeTarget" or obj.get("name") not in {"HanlinApp", "AI_HLYTests"}:
                continue
            for key in obj["packageProductDependencies"]:
                self.assertTrue(update_project.product_is_covered(objects[key], objects, closure),
                                obj["name"] + ": " + objects[key]["productName"])
        self.assertFalse(update_project.product_is_covered(
            {"productName": "IndependentHostLibrary", "package": "separate"},
            {"separate": {"isa": "XCRemoteSwiftPackageReference",
                          "repositoryURL": "https://example.invalid/independent.git"}}, closure))
        self.assertIn("HanlinScriptStore", closure[0])
        self.assertIn("HanlinScriptDeviceServices", closure[0])
        self.assertIn("HanlinExpoWidgetNative", closure[0])


if __name__ == "__main__":
    unittest.main()
