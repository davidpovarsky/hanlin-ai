import copy
import json
from pathlib import Path
import tempfile
import unittest

from extract_target import extract
from project_graph import parse_project, validate_graph
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

    def test_reject_app_dependency(self):
        self.mini["dependencies"] = ["D7B6C3C02D50A55D004E3AD6"]
        with self.assertRaises(AssertionError):
            validate_graph(self.project, self.manifest)

    def test_reject_whole_app_source_membership(self):
        self.mini["fileSystemSynchronizedGroups"].append("D7B6C3C32D50A55D004E3AD6")
        with self.assertRaises(AssertionError):
            validate_graph(self.project, self.manifest)

    def test_reject_runtime_build_phase(self):
        self.objects["A10000000000000000000051"] = {"isa": "PBXShellScriptBuildPhase"}
        self.mini["buildPhases"].append("A10000000000000000000051")
        with self.assertRaises(AssertionError):
            validate_graph(self.project, self.manifest)

    def test_reject_signing_or_lower_deployment(self):
        for field, value in [("CODE_SIGN_ENTITLEMENTS", "production.entitlements"),
                             ("CODE_SIGNING_ALLOWED", "YES"), ("IPHONEOS_DEPLOYMENT_TARGET", "26.0")]:
            mutated = copy.deepcopy(self.project)
            key = self.objects[self.mini["buildConfigurationList"]]["buildConfigurations"][0]
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
