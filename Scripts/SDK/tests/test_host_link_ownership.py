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
import generate_manifest
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
        targets = {obj["name"]: obj for obj in objects.values() if obj.get("isa") == "PBXNativeTarget"}
        for name, phase in phases.items():
            declared = [objects[key]["productName"] for key in targets[name]["packageProductDependencies"]]
            self.assertEqual(declared, ["HanlinApplication"], name)
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
        # Xcode uses both product declarations and framework phase membership.
        # Reintroduce both edges without changing the SDK implementation seed.
        text = self.text
        objects = self.project["objects"]
        phases = self.host_phases(self.project)
        host_targets = {obj["name"]: key for key, obj in objects.items()
                        if obj.get("isa") == "PBXNativeTarget" and obj.get("name") in phases}
        for host, product in [("HanlinApp", "HanlinChatUI"), ("HanlinApp", "HanlinScriptStore"),
                              ("HanlinApp", "HanlinScriptDeviceServices"),
                              ("AI_HLYTests", "HanlinExpoWidgetNative")]:
            build = next(key for key, obj in objects.items()
                         if obj.get("isa") == "PBXBuildFile" and
                         objects.get(obj.get("productRef"), {}).get("productName") == product)
            reference = objects[build]["productRef"]
            declared = parse_project(text)["objects"][host_targets[host]]["packageProductDependencies"]
            if reference not in declared:
                text = update_project.edit_object(text, host_targets[host],
                    lambda block: update_project.replace_list(block, "packageProductDependencies", declared + [reference]))
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
            if key in host_targets.values():
                old = {k: v for k, v in obj.items() if k != "packageProductDependencies"}
                new = {k: v for k, v in after["objects"][key].items() if k != "packageProductDependencies"}
                self.assertEqual(old, new, key)
            elif key not in phases.values():
                self.assertEqual(after["objects"][key], obj, key)
            else:
                # Preserve every native/system file reference in the two phases.
                old = [f for f in obj["files"] if "productRef" not in objects[f]]
                new = [f for f in after["objects"][key]["files"] if "productRef" not in objects[f]]
                self.assertEqual(old, new)

    def test_every_declared_host_product_remains_reachable_and_unknown_products_are_kept(self):
        manifest = json.loads(subprocess.check_output(
            ["swift", "package", "--package-path", str(ROOT), "dump-package"], text=True))
        self.assertEqual(len(manifest["products"]), 47)
        self.assertEqual(len(manifest["targets"]), 113)
        target_names = {target["name"] for target in manifest["targets"]}
        self.assertIn("AI_Hanlin", target_names)
        self.assertNotIn("HanlinApp", target_names)
        closure = update_project.application_product_closure(manifest)
        objects = self.project["objects"]
        definition = json.loads(generate_manifest.APPLICATION_PRODUCTS.read_text())
        self.assertEqual(definition["module"], "AI_Hanlin")
        self.assertEqual(len(definition["products"]), 51)
        app_packages = {item["url"].rstrip("/").removesuffix(".git").rsplit("/", 1)[-1].lower()
                        for item in definition.get("externalPackages", [])}
        app_target = next(target for target in manifest["targets"] if target["name"] == "AI_Hanlin")
        for entry in definition["products"]:
            if entry["package"].lower() in app_packages:
                # New app-owned libraries are linked by the canonical SDK target,
                # never duplicated on the thin Xcode host.
                self.assertTrue(any("product" in dependency
                                    and dependency["product"][0] == entry["product"]
                                    and dependency["product"][1].lower() == entry["package"].lower()
                                    for dependency in app_target["dependencies"]), entry)
                continue
            matches = [obj for obj in objects.values()
                       if obj.get("isa") == "XCSwiftPackageProductDependency"
                       and obj["productName"] == entry["product"]
                       and (entry["package"] == "HanlinSDK"
                            or objects[obj["package"]].get("repositoryURL", "").rstrip("/").removesuffix(".git").rsplit("/", 1)[-1] == entry["package"])]
            self.assertTrue(matches, entry)
            self.assertTrue(all(update_project.product_is_covered(obj, objects, closure) for obj in matches), entry)
        self.assertFalse(update_project.product_is_covered(
            {"productName": "IndependentHostLibrary", "package": "separate"},
            {"separate": {"isa": "XCRemoteSwiftPackageReference",
                          "repositoryURL": "https://example.invalid/independent.git"}}, closure))
        self.assertIn("HanlinScriptStore", closure[0])
        self.assertIn("HanlinScriptDeviceServices", closure[0])
        self.assertIn("HanlinExpoWidgetNative", closure[0])
        self.assertIn("HanlinTranslationUI", closure[0])
        self.assertIn("HanlinExpoWidgetsOriginal", closure[0])
        self.assertTrue({"HanlinMiniAppsBridge", "HanlinMiniAppsPicker"} <= target_names)


    def test_unknown_independent_host_product_is_preserved_in_both_link_surfaces(self):
        text = self.text
        root = self.project["rootObject"]
        package, product, build = "FA0000000000000000000001", "FA0000000000000000000002", "FA0000000000000000000003"
        text = update_project.insert_object(text, "XCRemoteSwiftPackageReference", package,
            '\t\t\tisa = XCRemoteSwiftPackageReference;\n\t\t\trepositoryURL = "https://example.invalid/independent.git";\n')
        text = update_project.insert_object(text, "XCSwiftPackageProductDependency", product,
            f'\t\t\tisa = XCSwiftPackageProductDependency;\n\t\t\tpackage = {package};\n\t\t\tproductName = IndependentHostLibrary;\n')
        text = update_project.insert_object(text, "PBXBuildFile", build,
            f'\t\t\tisa = PBXBuildFile;\n\t\t\tproductRef = {product};\n')
        text = update_project.edit_object(text, root, lambda block: update_project.replace_list(
            block, "packageReferences", self.project["objects"][root]["packageReferences"] + [package]))
        app_id = next(key for key, obj in self.project["objects"].items()
                      if obj.get("isa") == "PBXNativeTarget" and obj.get("name") == "HanlinApp")
        app = self.project["objects"][app_id]
        phase = self.host_phases(self.project)["HanlinApp"]
        text = update_project.edit_object(text, app_id, lambda block: update_project.replace_list(
            block, "packageProductDependencies", app["packageProductDependencies"] + [product]))
        text = update_project.edit_object(text, phase, lambda block: update_project.replace_list(
            block, "files", self.project["objects"][phase]["files"] + [build]))
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / "project.pbxproj"
            path.write_text(text)
            with patch.object(update_project, "FILE", path):
                after = parse_project(update_project.update())["objects"]
        self.assertIn(product, after[app_id]["packageProductDependencies"])
        self.assertIn(build, after[phase]["files"])

    def test_canonical_seed_rejects_missing_ambiguous_recursive_and_duplicate_dependencies(self):
        valid = [{"product": "SharedUI", "package": "HanlinSDK"},
                 {"product": "RemoteUI", "package": "remote"}]
        local = {"shared": {"SharedUI": ["OriginalUI"]}}
        invalid = [[], valid + [valid[0]], [{"product": "HanlinApplication", "package": "HanlinSDK"}],
                   [{"product": "Missing", "package": "HanlinSDK"}],
                   [{"product": "RemoteUI", "package": "absent"}], [{"product": "SharedUI"}]]
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / "application_products.json"
            def write(entries):
                path.write_text(json.dumps({"schemaVersion": 1, "module": "AI_Hanlin", "products": entries}))
            with patch.object(generate_manifest, "APPLICATION_PRODUCTS", path):
                write(valid)
                self.assertEqual(generate_manifest.application_dependencies(local, {"remote": None}),
                    ['"OriginalUI"', '.product(name: "RemoteUI", package: "remote")'])
                with self.assertRaises(ValueError):
                    generate_manifest.application_dependencies({**local, "duplicate": local["shared"]}, {"remote": None})
                for entries in invalid:
                    with self.subTest(entries=entries):
                        write(entries)
                        with self.assertRaises(ValueError):
                            generate_manifest.application_dependencies(local, {"remote": None})


if __name__ == "__main__":
    unittest.main()
