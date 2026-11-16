"""Source-wiring regressions that stop the exact observed pre-build failures early."""
import json
from pathlib import Path
import re
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[3]


class Phase2WiringTests(unittest.TestCase):
    def test_exact_app_tests_rebuild_affected_host_without_enabling_unrelated_groups(self):
        from Scripts.CI.plan_affected_validation import plan_affected_validation
        mapping = json.loads((ROOT / "Scripts/CI/affected-validation-map.json").read_text())
        plan = plan_affected_validation(mapping,
            ["AI_HLY/Downstream/RuntimeCore/Node/Host/runtime-capabilities.mjs"], "base", "head", "workflow_dispatch",
            exact_test_selector="AI_HLYTests/SkillRuntimeProductTests")
        self.assertTrue(plan.step_outputs["run_runtimecore_host"])
        self.assertFalse(plan.step_outputs["run_full_validation"])
        self.assertFalse(plan.step_outputs["run_runtimecore_bundle"])
        self.assertFalse(plan.step_outputs["run_device_build"])
        self.assertEqual(plan.step_outputs["simulator_unit_filter"], "AI_HLYTests/SkillRuntimeProductTests")

    def test_every_new_exact_package_is_an_active_project_reference(self):
        source = (ROOT / "AI_HLY.xcodeproj/project.pbxproj").read_text(encoding="utf-8")
        references = re.search(r'"?packageReferences"?\s*=\s*\((.*?)\);', source, re.S).group(1)
        for identity in ["AC1700000000000000000001", "AC170000000000000000000E", "AC1700000000000000000012", "AC1700000000000000000016"]:
            self.assertIn(identity, references)
            self.assertRegex(source, identity + r' = \{isa = XCRemoteSwiftPackageReference;')
        definitions = re.findall(r'^\s*(\w{24})\s+(?:/\*.*?\*/\s*)?=\s*\{', source, re.M)
        self.assertEqual(len(definitions), len(set(definitions)), "Project object identity was reused")

    def test_each_required_product_has_both_target_membership_and_a_link_entry(self):
        source = (ROOT / "AI_HLY.xcodeproj/project.pbxproj").read_text(encoding="utf-8")
        for product in ["A2UISwiftCore", "A2UISwiftUI", "BasicCatalog", "BasicCatalogSwiftUI", "SwiftTreeSitter", "TreeSitter", "TreeSitterBash"]:
            identity = re.search(r'(AC17\w+) = \{isa = XCSwiftPackageProductDependency;[^\n]+productName = ' + product + ';', source).group(1)
            links = re.findall(r'(AC17\w+) = \{isa = PBXBuildFile; productRef = ' + identity + ';', source)
            self.assertEqual(len(links), 2, product)
            for link in links:
                self.assertGreaterEqual(source.count(link), 2, product)
            self.assertGreaterEqual(source.count(identity), 5, product)

    def test_native_boot_has_one_owner_on_each_workflow_branch(self):
        source = (ROOT / ".github/workflows/build-ios26-unsigned-ipa.yml").read_text(encoding="utf-8")
        stage = source.split("- name: Boot iPad Simulator and stage fixtures", 1)[1].split("if [ \"$STAGE_SCRIPTUI_FIXTURES\"", 1)[0]
        native, other = stage.split('          else\n', 1)
        self.assertIn("stage_simulator_fixtures.py", native)
        self.assertNotIn('"bootstatus"', native)
        self.assertEqual(other.count('"bootstatus"'), 1)


if __name__ == "__main__":
    unittest.main()
