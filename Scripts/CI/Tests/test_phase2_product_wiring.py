"""Source-wiring regressions that stop the exact observed pre-build failures early."""
import copy
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import unittest
import yaml

from Scripts.CI.IntegrationValidation.project_graph import parse_project
from Scripts.CI.ui_viewport_cohorts import plan as viewport_plan

ROOT = Path(__file__).resolve().parents[3]


class Phase2WiringTests(unittest.TestCase):
    REQUIRED_PRODUCTS = {
        "A2UISwiftCore": "a2ui", "A2UISwiftUI": "a2ui",
        "BasicCatalog": "a2ui", "BasicCatalogSwiftUI": "a2ui",
        "SwiftTreeSitter": "swift-tree-sitter", "TreeSitter": "tree-sitter",
        "TreeSitterBash": "tree-sitter-bash",
    }

    def assert_native_staging_precedes_ui(self, run):
        start = run.index('if [ "${STAGE_NATIVESCRIPT_AFTER_UNIT:-false}"')
        end = run.index('if [ "${STAGE_SCRIPTUI_AFTER_UNIT:-false}"', start)
        staged = run[start:end]
        self.assertIn("stage_simulator_fixtures.py", staged)
        self.assertIn('--simulator-udid "$SIMULATOR_UDID"', staged)
        self.assertNotIn("--app-path", staged, "Never install a second app over the Xcode host")
        # The original UI result now belongs to a viewport cohort; it is still
        # produced after the real unit host install and deferred fixture copy.
        self.assertLess(start, run.index("python3 Scripts/CI/ui_viewport_cohorts.py rows"))
        self.assertLess(run.index("python3 Scripts/CI/ui_viewport_cohorts.py rows"),
                        run.index('-resultBundlePath "$LOG_DIR/$cohort_bundle"'))
        self.assertIn('cohort_results cohort_bundle cohort_log; do', run)
        self.assertIn('done < "$LOG_DIR/ui-viewport-cohorts.tsv"', run)
        return staged

    def required_product_inputs(self):
        return (parse_project((ROOT / "AI_HLY.xcodeproj/project.pbxproj").read_text(encoding="utf-8")),
                (ROOT / "Package.swift").read_text(encoding="utf-8"),
                json.loads((ROOT / "Scripts/SDK/application_products.json").read_text(encoding="utf-8")))

    def assert_required_product_graph(self, project, manifest, inventory):
        objects = project["objects"]
        root = objects[project["rootObject"]]
        targets = {objects[key]["name"]: objects[key] for key in root["targets"]
                   if objects[key].get("isa") == "PBXNativeTarget"}
        for name in ("HanlinApp", "AI_HLYTests"):
            self.assertIn(name, targets)
            target = targets[name]
            declared = target["packageProductDependencies"]
            self.assertEqual(len(declared), 1, name + ": one shared implementation owner")
            product_id = declared[0]
            product = objects[product_id]
            self.assertEqual(product["isa"], "XCSwiftPackageProductDependency", name)
            self.assertEqual(product["productName"], "HanlinApplication", name)
            self.assertIn(product["package"], root["packageReferences"], name)
            package = objects[product["package"]]
            self.assertEqual(package["isa"], "XCLocalSwiftPackageReference", name)
            self.assertEqual(package["relativePath"], ".", name)
            phases = [objects[key] for key in target["buildPhases"]
                      if objects[key]["isa"] == "PBXFrameworksBuildPhase"]
            self.assertEqual(len(phases), 1, name)
            builds = [objects[key] for key in phases[0]["files"] if "productRef" in objects[key]]
            self.assertTrue(all(item["isa"] == "PBXBuildFile" for item in builds), name)
            self.assertEqual([item["productRef"] for item in builds], [product_id],
                             name + ": declaration must reach the real active linker phase")

        # Inspect the generated implementation target, not orphaned old PBX
        # product objects or another module that happens to name the same library.
        manifest = re.sub(r'"(?:\\.|[^"\\])*"|//[^\n]*|/\*[\s\S]*?\*/',
                          lambda match: match[0] if match[0].startswith('"') else "", manifest)
        exports = re.findall(r'\.library\(\s*name:\s*"HanlinApplication",\s*targets:\s*(\[[^\]]*\])\s*\)', manifest)
        self.assertEqual(exports, ['["AI_Hanlin"]'], "The linked product must export the original implementation")
        dependencies = re.findall(
            r'\.target\(\s*name:\s*"AI_Hanlin",\s*dependencies:\s*\[(.*?)\],\s*path:\s*"AI_HLY"',
            manifest, re.S)
        self.assertEqual(len(dependencies), 1, "Exactly one original SDK implementation target is required")
        external = re.findall(r'\.product\(\s*name:\s*"([^"]+)",\s*package:\s*"([^"]+)"\s*\)', dependencies[0])
        self.assertEqual(inventory["schemaVersion"], 1)
        self.assertEqual(inventory["module"], "AI_Hanlin")
        authored = [(item["product"], item["package"]) for item in inventory["products"]]
        for product, package in self.REQUIRED_PRODUCTS.items():
            self.assertEqual([pair for pair in external if pair[0] == product], [(product, package)],
                             product + ": missing or duplicated real SDK target dependency")
            self.assertEqual([pair for pair in authored if pair[0] == product], [(product, package)],
                             product + ": canonical generator input differs from the linked SDK")

    def test_native_fixtures_follow_the_actual_xcode_host_install(self):
        workflow = yaml.safe_load((ROOT / ".github/workflows/build-ios26-unsigned-ipa.yml").read_text(encoding="utf-8"))
        job = next(j for j in workflow["jobs"].values() if j.get("name") == "Launch full app on iPad Simulator")
        boot = next(s["run"] for s in job["steps"] if s.get("name") == "Boot iPad Simulator and stage fixtures")
        decision = boot.split("defer_native_fixtures=false", 1)[1].split('if { [ "$RUN_NATIVESCRIPT_DEPENDENCIES"', 1)[0]
        base = dict(RUN_NATIVESCRIPT_DEPENDENCIES="true", RUN_SIMULATOR_UNIT="true", SIMULATOR_UNIT_FILTER="AI_HLYTests/SkillStoreAndImportTests",
            FAST_VALIDATION_ONLY="false", SIMULATOR_E2E_ONLY="false", NATIVESCRIPT_POC_ONLY="false", RUN_FULL_VALIDATION="false")
        shell = "bash"
        if os.name == "nt":
            # Windows' system32/bash.exe enters WSL; use the native Git shell
            # for this portable workflow decision without starting a distro.
            git = Path(shutil.which("git") or "")
            shell = str(git.parent.parent / "bin/bash.exe")
            self.assertTrue(Path(shell).is_file(), "Native Git Bash is required for this Windows check")
        with tempfile.TemporaryDirectory() as folder:
            for overrides in [{}, {"RUN_SIMULATOR_UNIT": "false"}, {"SIMULATOR_UNIT_FILTER": ""},
                {"FAST_VALIDATION_ONLY": "true"}, {"SIMULATOR_E2E_ONLY": "true"}, {"NATIVESCRIPT_POC_ONLY": "true"},
                {"RUN_FULL_VALIDATION": "true"}, {"RUN_NATIVESCRIPT_DEPENDENCIES": "false"}]:
                with self.subTest(overrides=overrides):
                    result = subprocess.run([shell, "-c", 'defer_native_fixtures=false\n' + decision + '\nprintf "%s" "$defer_native_fixtures"'],
                        env={**os.environ, **base, **overrides, "GITHUB_ENV": (Path(folder) / "environment").as_posix()},
                        capture_output=True, text=True, timeout=10)
                    self.assertEqual(result.returncode, 0, result.stderr)
                    self.assertEqual(result.stdout, "false" if overrides else "true")
        run = next(s["run"] for s in job["steps"] if s.get("name") == "Run simulator test suite")
        self.assert_native_staging_precedes_ui(run)
        profile = json.loads((ROOT / "Scripts/CI/ui_viewport_cohorts.json").read_text())
        selected = "AI_HLYUITests/HanlinNativeScriptProductionE2ETests"
        cohort = viewport_plan(selected, profile)["cohorts"][0]
        self.assertEqual(cohort["selectors"], [selected])
        self.assertEqual(cohort["result_bundle"], "NativeScriptProductionE2EResult.xcresult")

    def test_deferred_native_staging_cannot_move_after_ui_or_reinstall_the_host(self):
        workflow = yaml.safe_load((ROOT / ".github/workflows/build-ios26-unsigned-ipa.yml").read_text(encoding="utf-8"))
        job = next(j for j in workflow["jobs"].values() if j.get("name") == "Launch full app on iPad Simulator")
        run = next(s["run"] for s in job["steps"] if s.get("name") == "Run simulator test suite")
        staged = self.assert_native_staging_precedes_ui(run)
        changed = run.replace(staged, "", 1) + staged
        # Keep a following block so the mutation fails on ordering, not parsing.
        changed += 'if [ "${STAGE_SCRIPTUI_AFTER_UNIT:-false}" = "true" ]; then :; fi\n'
        with self.assertRaises(AssertionError):
            self.assert_native_staging_precedes_ui(changed)
        with self.assertRaises(AssertionError):
            self.assert_native_staging_precedes_ui(
                run.replace(staged, staged.replace("stage_simulator_fixtures.py",
                    'stage_simulator_fixtures.py --app-path "$APP_PATH"'), 1))

    def test_explicit_compact_validation_does_not_cancel_native_ipad_acceptance(self):
        workflow = yaml.safe_load((ROOT / ".github/workflows/build-ios26-unsigned-ipa.yml").read_text(encoding="utf-8"))
        group = workflow["concurrency"]["group"]
        self.assertIn("(inputs.target_validation_group == 'exact_test_selector' && contains(inputs.exact_test_selector, 'HanlinMorphComposerUITests/testCompact')) && 'explicit-compact-composer'", group)
        self.assertIn("'phase2-combined-native'", group)
        triggers = workflow.get("on", workflow.get(True))
        self.assertEqual(triggers["push"], {"branches": ["main"]})
        self.assertNotIn("pull_request", triggers)

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
        self.assert_required_product_graph(*self.required_product_inputs())

    def test_shared_application_wiring_rejects_orphaned_and_duplicate_host_edges(self):
        original, manifest, inventory = self.required_product_inputs()
        for host in ("HanlinApp", "AI_HLYTests"):
            for mutation in ("membership", "link", "package", "duplicate-product"):
                with self.subTest(host=host, mutation=mutation):
                    project = copy.deepcopy(original)
                    objects = project["objects"]
                    root = objects[project["rootObject"]]
                    target = next(objects[key] for key in root["targets"] if objects[key].get("name") == host)
                    phase = next(objects[key] for key in target["buildPhases"]
                                 if objects[key]["isa"] == "PBXFrameworksBuildPhase")
                    product_id = target["packageProductDependencies"][0]
                    if mutation == "membership":
                        target["packageProductDependencies"] = []
                    elif mutation == "link":
                        # Leave the old PBXBuildFile object present but unreachable.
                        phase["files"] = [key for key in phase["files"]
                                          if objects[key].get("productRef") != product_id]
                    elif mutation == "package":
                        root["packageReferences"].remove(objects[product_id]["package"])
                    else:
                        old = next(key for key, item in objects.items()
                                   if item.get("isa") == "XCSwiftPackageProductDependency"
                                   and item.get("productName") == "A2UISwiftCore")
                        target["packageProductDependencies"].append(old)
                        link = next(key for key, item in objects.items()
                                    if item.get("isa") == "PBXBuildFile" and item.get("productRef") == old)
                        phase["files"].append(link)
                    with self.assertRaises(AssertionError):
                        self.assert_required_product_graph(project, manifest, inventory)

    def test_required_products_must_reach_the_original_sdk_module_and_generator_input(self):
        project, manifest, original = self.required_product_inputs()
        target_start = manifest.index('.target(name: "AI_Hanlin",')
        for product, package in self.REQUIRED_PRODUCTS.items():
            with self.subTest(product=product, missing="generated-target"):
                token = '.product(name: "' + product + '", package: "' + package + '")'
                changed = manifest[:target_start] + manifest[target_start:].replace(token, "", 1)
                self.assertNotEqual(changed, manifest)
                with self.assertRaises(AssertionError):
                    self.assert_required_product_graph(project, changed, original)
            with self.subTest(product=product, missing="canonical-generator-input"):
                inventory = copy.deepcopy(original)
                inventory["products"] = [item for item in inventory["products"] if item["product"] != product]
                with self.assertRaises(AssertionError):
                    self.assert_required_product_graph(project, manifest, inventory)
        changed = manifest.replace('.library(name: "HanlinApplication", targets: ["AI_Hanlin"])',
                                   '.library(name: "HanlinApplication", targets: ["HanlinA2UI"])', 1)
        self.assertNotEqual(changed, manifest)
        with self.assertRaises(AssertionError):
            self.assert_required_product_graph(project, changed, original)

    def test_native_boot_has_one_owner_on_each_workflow_branch(self):
        source = (ROOT / ".github/workflows/build-ios26-unsigned-ipa.yml").read_text(encoding="utf-8")
        stage = source.split("- name: Boot iPad Simulator and stage fixtures", 1)[1].split("if [ \"$STAGE_SCRIPTUI_FIXTURES\"", 1)[0]
        native, other = stage.split('          else\n', 1)
        self.assertIn("stage_simulator_fixtures.py", native)
        self.assertNotIn('"bootstatus"', native)
        self.assertEqual(other.count('"bootstatus"'), 1)


if __name__ == "__main__":
    unittest.main()
