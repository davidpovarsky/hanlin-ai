"""Source-wiring regressions that stop the exact observed pre-build failures early."""
import json
from pathlib import Path
import re
import subprocess
import unittest
import yaml

ROOT = Path(__file__).resolve().parents[3]


class Phase2WiringTests(unittest.TestCase):
    def test_device_mcp_verifies_the_canonical_patched_archive(self):
        workflow = yaml.safe_load((ROOT / ".github/workflows/build-ios26-unsigned-ipa.yml").read_text(encoding="utf-8"))
        job = next(job for job in workflow["jobs"].values() if job.get("name") == "Build unsigned IPA with Xcode 26")
        step = next(step for step in job["steps"] if step.get("name") == "Verify MCP host on pinned Node 24.5.0")
        command = step["run"]
        self.assertLess(command.index("prepare-runtime-host.sh"), command.index("python3 -m zipfile -e"))
        self.assertIn("build/runtime-host/RuntimeHostResources.zip", command)
        self.assertIn("HANLIN_RUNTIME_TEST_FIXTURES", command)
        self.assertIn("npm run test:integration", command)
        self.assertNotIn("npm ci", command, "A clean second install would discard the audited runtime patches")
        self.assertNotIn("npm test --prefix", command, "The original preparer already executes the same Host test gate")

    def test_motion_reuses_prepared_simulator_only_by_explicit_manual_group(self):
        from Scripts.CI.plan_affected_validation import plan_affected_validation, RoutingError
        mapping = json.loads((ROOT / "Scripts/CI/affected-validation-map.json").read_text())
        with self.assertRaises(RoutingError):
            plan_affected_validation(mapping, ["README.md"], "base", "head", "workflow_dispatch",
                target_group="phase2_app_with_motion")
        plan = plan_affected_validation(mapping, ["README.md"], "base", "head", "workflow_dispatch",
            target_group="phase2_app_with_motion",
            exact_test_selector="AI_HLYUITests/HanlinNativeScriptProductionE2ETests/testDirectUIKitTabBarBridge")
        self.assertEqual(plan.step_outputs["simulator_configuration"], "Release")
        self.assertTrue(plan.step_outputs["run_simulator_job"])
        self.assertFalse(plan.step_outputs["run_runtimecore_bundle"])
        workflow = yaml.safe_load((ROOT / ".github/workflows/build-ios26-unsigned-ipa.yml").read_text(encoding="utf-8"))
        triggers = workflow.get("on", workflow.get(True))
        self.assertLessEqual(len(triggers["workflow_dispatch"]["inputs"]), 25)
        self.assertEqual(triggers["workflow_dispatch"]["inputs"]["target_validation_group"]["default"], "")
        simulator = next(job for job in workflow["jobs"].values() if job.get("name") == "Launch full app on iPad Simulator")
        steps = simulator["steps"]
        motion = next(step for step in steps if step.get("name") == "Verify affected Motion on the prepared app simulator")
        self.assertIn("inputs.target_validation_group == 'phase2_app_with_motion'", motion["if"])
        self.assertIn("!cancelled()", motion["if"])
        self.assertNotIn("continue-on-error", motion)
        self.assertEqual(motion["env"]["HANLIN_MOTION_SCOPE"], "affected")
        self.assertEqual(motion["env"]["HANLIN_MOTION_DEVICE_STRATEGY"], "ready")
        self.assertGreater(steps.index(motion), next(i for i, step in enumerate(steps) if step.get("name") == "Run simulator test suite"))

    def test_skill_exposure_does_not_stage_unrelated_expo_fixtures(self):
        from Scripts.CI.plan_affected_validation import plan_affected_validation
        mapping = json.loads((ROOT / "Scripts/CI/affected-validation-map.json").read_text())
        for selector, required in [("AI_HLYTests/AgentSkillsExposureTests", False),
            ("AI_HLYUITests/HanlinExpoProductionE2ETests/testProductionExpoSwiftUIProbeEndToEnd", True)]:
            plan = plan_affected_validation(mapping, ["README.md"], "base", "head", "workflow_dispatch",
                exact_test_selector=selector)
            self.assertEqual(plan.step_outputs["stage_scriptui_fixtures"], required)

    def test_optional_progress_cannot_block_focused_native_acceptance(self):
        workflow = yaml.safe_load((ROOT / ".github/workflows/build-ios26-unsigned-ipa.yml").read_text(encoding="utf-8"))
        notifications = [step for job in workflow["jobs"].values() for step in job.get("steps", [])
            if step.get("uses") == "davidpovarsky/github-automation/live-refresh@main"]
        self.assertTrue(notifications)
        for step in notifications:
            for scope in ["exact_test_selector", "device_build", "chat_motion_product", "project_packaging", "phase2_app_with_motion"]:
                self.assertIn("inputs.target_validation_group != '" + scope + "'", step["if"])
        simulator = next(job for job in workflow["jobs"].values() if job.get("name") == "Launch full app on iPad Simulator")
        for name in ["Build full arm64 simulator app", "Boot iPad Simulator and stage fixtures", "Run simulator test suite"]:
            step = next(step for step in simulator["steps"] if step.get("name") == name)
            self.assertNotIn("continue-on-error", step)
            self.assertNotIn("if", step, "Product validation remains mandatory after skipping optional progress")

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
