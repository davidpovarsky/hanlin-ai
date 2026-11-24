import copy
import json
from pathlib import Path
import tempfile
import unittest

from extract_target import extract
from project_graph import parse_project, validate_graph, validate_agent_sdk_linkage
from verify_results import EXPECTED, verify

ROOT = Path(__file__).resolve().parents[3]


class ProjectGraphTests(unittest.TestCase):
    def setUp(self):
        self.project = parse_project((ROOT / "AI_HLY.xcodeproj/project.pbxproj").read_text(encoding="utf-8"))
        self.objects = self.project["objects"]
        manifest = ROOT / "Scripts/CI/IntegrationValidation/miniapps_provider_sources.json"
        self.manifest = json.loads(manifest.read_text()) if manifest.exists() else None
        self.mini = next(value for value in self.objects.values()
                         if value.get("isa") == "PBXNativeTarget" and value.get("name") == "HanlinMiniApps")

    def test_registered_graph(self):
        validate_graph(self.project, self.manifest)

    def test_agent_sdk_actual_linkage(self):
        validate_agent_sdk_linkage(self.project, ROOT)

    def test_agent_sdk_requires_framework_link_not_just_declaration(self):
        ai = next(value for value in self.objects.values() if value.get("name") == "HanlinApp"
                  and value.get("isa") == "PBXNativeTarget")
        phase = next(self.objects[key] for key in ai["buildPhases"]
                     if self.objects[key]["isa"] == "PBXFrameworksBuildPhase")
        phase["files"] = [key for key in phase["files"]
                          if self.objects.get(self.objects[key].get("productRef"), {}).get("productName") != "HanlinApplication"]
        with self.assertRaisesRegex(AssertionError, "SDK image ownership mismatch"):
            validate_agent_sdk_linkage(self.project, ROOT)

    def test_agent_sdk_does_not_leak_into_miniapps(self):
        core = next(key for key, value in self.objects.items()
                    if value.get("isa") == "XCSwiftPackageProductDependency" and value.get("productName") == "HanlinAgentCore")
        self.mini["packageProductDependencies"].append(core)
        with self.assertRaisesRegex(AssertionError, "unexpected SDK dependency"):
            validate_agent_sdk_linkage(self.project, ROOT)

    def test_agent_sdk_requires_canonical_sibling_package(self):
        package = next(value for value in self.objects.values()
                       if value.get("relativePath") == ".")
        package["relativePath"] = "../OtherSDK"
        with self.assertRaisesRegex(AssertionError, "canonical local SDK"):
            validate_agent_sdk_linkage(self.project, ROOT)

    def test_shared_native_adapter_must_not_compile_again_in_executable(self):
        exception = next(value for value in self.objects.values()
                         if value.get("isa") == "PBXFileSystemSynchronizedBuildFileExceptionSet"
                         and value.get("target") == "D7B6C3C02D50A55D004E3AD6")
        exception["membershipExceptions"].remove("Model/HanlinAppleModelCatalogAdapter.swift")
        with self.assertRaisesRegex(AssertionError, "Shared sources must compile only once"):
            validate_agent_sdk_linkage(self.project, ROOT)

    def test_agent_sdk_test_import_requires_owning_application_product(self):
        unit = next(value for value in self.objects.values() if value.get("name") == "AI_HLYTests"
                    and value.get("isa") == "PBXNativeTarget")
        self.assertIn("HanlinApplication",
                      [self.objects[key]["productName"] for key in unit["packageProductDependencies"]])
        unit["packageProductDependencies"] = [key for key in unit["packageProductDependencies"]
                                               if self.objects[key].get("productName") != "HanlinApplication"]
        with self.assertRaisesRegex(AssertionError, "unexpected SDK dependency"):
            validate_agent_sdk_linkage(self.project, ROOT)

    def test_reject_app_dependency(self):
        self.mini["dependencies"] = ["D7B6C3C02D50A55D004E3AD6"]
        with self.assertRaises(AssertionError):
            validate_graph(self.project, self.manifest)

    def test_miniapps_extensions_do_not_alias_ai_targets(self):
        dependency = self.objects[self.mini["dependencies"][0]]
        dependency["target"] = next(key for key, value in self.objects.items()
                                    if value.get("name") == "HanlinScriptingWidgets"
                                    and value.get("isa") == "PBXNativeTarget")
        with self.assertRaisesRegex(AssertionError, "only on its own"):
            validate_graph(self.project, self.manifest)

    def test_miniapps_extensions_are_actually_embedded(self):
        phase = next(self.objects[key] for key in self.mini["buildPhases"]
                     if self.objects[key].get("name") == "Embed MiniApps App Extensions")
        phase["files"].pop()
        with self.assertRaisesRegex(AssertionError, "embed each own extension"):
            validate_graph(self.project, self.manifest)

    def test_miniapps_extensions_link_original_shared_sdk(self):
        target = next(value for value in self.objects.values()
                      if value.get("name") == "HanlinMiniAppsWidgets" and value.get("isa") == "PBXNativeTarget")
        phase = next(self.objects[key] for key in target["buildPhases"]
                     if self.objects[key]["isa"] == "PBXFrameworksBuildPhase")
        phase["files"].pop()
        with self.assertRaisesRegex(AssertionError, "original SDK closure"):
            validate_graph(self.project, self.manifest)

    def test_native_surfaces_share_only_miniapps_namespace(self):
        import plistlib
        for info in [ROOT / "HanlinMiniAppsApp/Info.plist",
                     *sorted((ROOT / "HanlinMiniAppsExtensions").glob("*/Info.plist"))]:
            config = plistlib.loads(info.read_bytes())["HanlinExtensionHost"]
            self.assertEqual(config["AppGroupIdentifier"], "group.com.itorah.chavrusachat")
            self.assertEqual(config["StorageNamespace"], "HanlinMiniApps/v1")
        self.assertEqual(len(list((ROOT / "HanlinMiniAppsExtensions").glob("*/Info.plist"))), 3)
        for entitlements in (ROOT / "HanlinMiniAppsExtensions").glob("*/*.entitlements"):
            self.assertIn("group.com.itorah.chavrusachat",
                          plistlib.loads(entitlements.read_bytes())["com.apple.security.application-groups"])

    def test_reject_whole_app_source_membership(self):
        self.mini["fileSystemSynchronizedGroups"].append("D7B6C3C32D50A55D004E3AD6")
        with self.assertRaises(AssertionError):
            validate_graph(self.project, self.manifest)

    def test_reject_runtime_build_phase(self):
        self.objects["A10000000000000000000051"] = {"isa": "PBXShellScriptBuildPhase"}
        self.mini["buildPhases"].append("A10000000000000000000051")
        with self.assertRaises(AssertionError):
            validate_graph(self.project, self.manifest)

    def test_reject_invalid_signing_or_lower_deployment(self):
        for field, value in [("CODE_SIGN_ENTITLEMENTS", "production.entitlements"),
                             ("CODE_SIGNING_ALLOWED", "NO"), ("CODE_SIGNING_REQUIRED", "NO"),
                             ("DEVELOPMENT_TEAM", "OTHERTEAM"), ("IPHONEOS_DEPLOYMENT_TARGET", "26.0")]:
            for key in self.objects[self.mini["buildConfigurationList"]]["buildConfigurations"]:
                with self.subTest(field=field, configuration=key):
                    mutated = copy.deepcopy(self.project)
                    mutated["objects"][key]["buildSettings"][field] = value
                    with self.assertRaises(AssertionError):
                        validate_graph(mutated, self.manifest)

    def test_reject_declared_but_unlinked_product(self):
        phase = next(self.objects[key] for key in self.mini["buildPhases"]
                     if self.objects[key]["isa"] == "PBXFrameworksBuildPhase")
        phase["files"].pop()
        with self.assertRaises(AssertionError):
            validate_graph(self.project, self.manifest)

    def test_reject_duplicate_project_key(self):
        with self.assertRaises(ValueError):
            parse_project("{ objects = {}; objects = {}; }")

    def test_extraction_keeps_target_and_real_source(self):
        with tempfile.TemporaryDirectory(prefix="hanlin-integration-graph-") as scratch:
            output = Path(scratch) / "AI_HLY.xcodeproj"
            if self.manifest:
                with self.assertRaisesRegex(ValueError, "real project"):
                    extract(ROOT, output)
                return
            result = extract(ROOT, output)
            extracted = parse_project((output / "project.pbxproj").read_text(encoding="utf-8"))
            target_id = result["target_id"]
            self.assertEqual(extracted["objects"][target_id], self.mini)
            root = extracted["objects"][extracted["rootObject"]]
            self.assertEqual(root["targets"], [target_id])
            for key in self.mini["fileSystemSynchronizedGroups"]:
                self.assertEqual(Path(extracted["objects"][key]["path"]), ROOT / "HanlinMiniAppsApp")
            self.assertFalse(any(obj["isa"] == "PBXShellScriptBuildPhase" for obj in extracted["objects"].values()))
            config = (output.parent / "Config.xcconfig").read_text(encoding="utf-8")
            self.assertIn("SWIFT_OBJC_INTEROP_MODE = objcxx", config)
            self.assertIn("CLANG_CXX_LANGUAGE_STANDARD = gnu++20", config)
            self.assertIn("HANLIN_API_KEY =\n", config)
            self.assertNotIn("$repo_root", config)

    def test_result_verifier_requires_all_actual_passing_nodes(self):
        nodes = [{"nodeType": "Test Case", "name": name + "()", "result": "Passed"} for name in EXPECTED]
        self.assertEqual(set(verify({"children": nodes})), EXPECTED)
        for invalid in [[], nodes[:-1], nodes + [nodes[0]],
                        nodes[:-1] + [{**nodes[-1], "result": "Skipped"}],
                        [{"name": name, "result": "Passed"} for name in EXPECTED]]:
            with self.assertRaises(ValueError):
                verify({"children": invalid})


if __name__ == "__main__":
    unittest.main()
