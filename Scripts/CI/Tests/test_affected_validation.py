from __future__ import annotations

import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

SCRIPT_PATH = Path(__file__).parents[1] / "plan_affected_validation.py"
MAP_PATH = Path(__file__).parents[1] / "affected-validation-map.json"

SPEC = importlib.util.spec_from_file_location("plan_affected_validation", SCRIPT_PATH)
assert SPEC is not None and SPEC.loader is not None
planner = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(planner)


class AffectedValidationPlannerTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        with open(MAP_PATH, "r", encoding="utf-8") as f:
            cls.mapping_config = json.load(f)

    def plan_files(
        self,
        files: list[str],
        full_validation: bool = False,
        target_group: str | None = None,
        manual_modes: dict[str, bool] | None = None,
    ):
        return planner.plan_affected_validation(
            mapping_config=self.mapping_config,
            changed_files=files,
            base_sha="abc1234567890",
            head_sha="def9876543210",
            event_name="workflow_dispatch",
            full_validation=full_validation,
            target_group=target_group,
            manual_modes=manual_modes,
        )

    # 1. docs-only change -> no simulator/device/IPA
    def test_docs_only_change_skips_all_expensive_validations(self) -> None:
        changed = ["README.md", "docs/architecture.md", ".gitignore"]
        plan = self.plan_files(changed)

        self.assertFalse(plan.is_full_validation)
        self.assertEqual(len(plan.selected_groups), 0)
        self.assertFalse(plan.step_outputs["run_phase1"])
        self.assertFalse(plan.step_outputs["run_device_build"])
        self.assertFalse(plan.step_outputs["run_ipa_packaging"])
        self.assertFalse(plan.step_outputs["run_simulator_job"])
        self.assertFalse(plan.step_outputs["run_runtimecore_bundle"])

        summary = plan.render_markdown_summary()
        self.assertIn("SKIPPED", summary)
        self.assertIn("iPad Simulator downstream unit tests", summary)
        self.assertIn("Device Release IPA build & packaging", summary)

    # 2. Scripting compiler source -> Scripting validation only plus real dependencies
    def test_scripting_compiler_only_change(self) -> None:
        changed = [
            "Scripts/ScriptingCompiler/compile-scripting-fixtures.mjs",
            "Scripts/ScriptingCompiler/package.json",
        ]
        plan = self.plan_files(changed)

        self.assertIn("scripting_compiler", plan.selected_groups)
        self.assertIn("simulator_scripting_acceptance", plan.selected_groups)
        self.assertTrue(plan.step_outputs["run_scripting_compiler"])
        self.assertTrue(plan.step_outputs["run_phase1"])
        self.assertTrue(plan.step_outputs["run_simulator_scripting_acceptance"])
        self.assertTrue(plan.step_outputs["run_simulator_job"])

        # Unrelated suites must NOT run
        self.assertNotIn("nativescript_runtime", plan.selected_groups)
        self.assertNotIn("nativescript_dependencies", plan.selected_groups)
        self.assertNotIn("python_runtime", plan.selected_groups)
        self.assertNotIn("node_runtime", plan.selected_groups)
        self.assertNotIn("device_build", plan.selected_groups)
        self.assertNotIn("ipa_packaging", plan.selected_groups)
        self.assertFalse(plan.step_outputs["run_device_build"])
        self.assertFalse(plan.step_outputs["run_runtimecore_bundle"])

    # 3. NativeScript fixture -> targeted NativeScript validation
    def test_nativescript_fixture_change(self) -> None:
        changed = [
            "Scripts/NativeScript/Fixtures/Source/app.ts",
            "Scripts/NativeScript/Fixtures/Source/swiftui-app.ts",
        ]
        plan = self.plan_files(changed)

        self.assertIn("nativescript_dependencies", plan.selected_groups)
        self.assertIn("simulator_targeted_ui", plan.selected_groups)
        self.assertTrue(plan.step_outputs["run_simulator_targeted_ui"])
        self.assertTrue(plan.step_outputs["run_simulator_job"])

        # Fixture changes do NOT build release IPA or run phase 1 Swift packages
        self.assertFalse(plan.step_outputs["run_device_build"])
        self.assertFalse(plan.step_outputs["run_ipa_packaging"])
        self.assertFalse(plan.step_outputs["run_platform_contracts"])
        self.assertFalse(plan.step_outputs["run_scripting_compiler"])

    # 4. NativeScript native provider -> required native/link validation
    def test_nativescript_native_provider_change(self) -> None:
        changed = [
            "Packages/HanlinNativeScriptRuntime/Sources/HanlinNativeScriptCoreSupport/HanlinNativeScriptCoreSupport.mm",
            "Packages/HanlinNativeScriptRuntime/Sources/HanlinNativeScriptRuntime/FixtureSupport/HanlinNativeScriptSwiftUIFixtureProvider.swift",
        ]
        plan = self.plan_files(changed)

        self.assertIn("nativescript_runtime", plan.selected_groups)
        self.assertIn("simulator_targeted_ui", plan.selected_groups)
        self.assertIn("device_build", plan.selected_groups)
        self.assertIn("nativescript_dependencies", plan.selected_groups)
        self.assertTrue(plan.step_outputs["run_nativescript_runtime"])
        self.assertTrue(plan.step_outputs["run_phase1"])
        self.assertTrue(plan.step_outputs["run_simulator_targeted_ui"])
        self.assertTrue(plan.step_outputs["run_device_build"])

        # Does not run unrelated suites
        self.assertNotIn("scripting_reference", plan.selected_groups)
        self.assertNotIn("python_runtime", plan.selected_groups)
        self.assertNotIn("node_runtime", plan.selected_groups)
        self.assertFalse(plan.step_outputs["run_scripting_reference"])

    # 5. UI-flow source -> corresponding UI/unit validation only
    def test_ui_flow_source_change(self) -> None:
        changed = [
            "AI_HLY/Views/ChatView.swift",
            "AI_HLY/MainTabView.swift",
        ]
        plan = self.plan_files(changed)

        self.assertIn("app_unit_tests", plan.selected_groups)
        self.assertIn("simulator_smoke_launch", plan.selected_groups)
        self.assertTrue(plan.step_outputs["run_simulator_unit"])
        self.assertTrue(plan.step_outputs["run_simulator_job"])

        # Must not package IPA or run phase 1 or run NativeScript E2E UI
        self.assertFalse(plan.step_outputs["run_device_build"])
        self.assertFalse(plan.step_outputs["run_ipa_packaging"])
        self.assertFalse(plan.step_outputs["run_phase1"])
        self.assertFalse(plan.step_outputs["run_simulator_targeted_ui"])

    # 6. Device packaging input -> device/IPA validation only where appropriate
    def test_device_packaging_change(self) -> None:
        changed = [
            "AI_HLY.xcodeproj/project.pbxproj",
            "AI-HLY-Info.plist",
        ]
        plan = self.plan_files(changed)

        self.assertIn("device_build", plan.selected_groups)
        self.assertIn("ipa_packaging", plan.selected_groups)
        self.assertTrue(plan.step_outputs["run_device_build"])
        self.assertTrue(plan.step_outputs["run_ipa_packaging"])

        # Packaging changes do not boot iPad simulator
        self.assertFalse(plan.step_outputs["run_simulator_job"])
        self.assertFalse(plan.step_outputs["run_simulator_unit"])
        self.assertFalse(plan.step_outputs["run_simulator_targeted_ui"])

    # 7. Shared dependency -> correct downstream union
    def test_shared_dependency_expands_to_consumers(self) -> None:
        changed = [
            "Packages/HanlinPlatform/Sources/HanlinPlatformContracts/HanlinPlatformContracts.swift",
        ]
        plan = self.plan_files(changed)

        self.assertIn("platform_contracts", plan.selected_groups)
        self.assertIn("app_unit_tests", plan.selected_groups)
        self.assertTrue(plan.step_outputs["run_platform_contracts"])
        self.assertTrue(plan.step_outputs["run_phase1"])
        self.assertTrue(plan.step_outputs["run_simulator_unit"])
        self.assertTrue(plan.step_outputs["run_simulator_job"])

        # Unrelated runtimes must NOT run
        self.assertNotIn("nativescript_runtime", plan.selected_groups)
        self.assertNotIn("python_runtime", plan.selected_groups)
        self.assertNotIn("node_runtime", plan.selected_groups)
        self.assertFalse(plan.step_outputs["run_nativescript_runtime"])

    # 8. Test-only change -> owning target
    def test_test_only_change_targets_owning_suite(self) -> None:
        changed = [
            "AI_HLYTests/CanonicalAdapterTests.swift",
        ]
        plan = self.plan_files(changed)

        self.assertIn("app_unit_tests", plan.selected_groups)
        self.assertTrue(plan.step_outputs["run_simulator_unit"])
        self.assertTrue(plan.step_outputs["run_simulator_job"])

        # Must not run broad unrelated suites
        self.assertFalse(plan.step_outputs["run_phase1"])
        self.assertFalse(plan.step_outputs["run_device_build"])
        self.assertFalse(plan.step_outputs["run_simulator_targeted_ui"])
        self.assertFalse(plan.step_outputs["run_simulator_scripting_acceptance"])

    # 9. Unknown path -> planner fails with UnmappedPathsError, NOT full
    def test_unknown_path_fails_planner_without_full_fallback(self) -> None:
        changed = [
            "UnexpectedModule/NewFeature.swift",
            "RandomDirectory/data.csv",
        ]
        with self.assertRaises(planner.UnmappedPathsError) as ctx:
            self.plan_files(changed)

        self.assertIn("UnexpectedModule/NewFeature.swift", ctx.exception.unmapped_paths)
        self.assertIn("RandomDirectory/data.csv", ctx.exception.unmapped_paths)

    # 10. Explicit full validation -> all groups
    def test_explicit_full_validation_selects_all_groups(self) -> None:
        changed = ["README.md"]
        plan = self.plan_files(changed, full_validation=True)

        self.assertTrue(plan.is_full_validation)
        self.assertTrue(plan.step_outputs["run_full_validation"])
        self.assertTrue(plan.step_outputs["run_phase1"])
        self.assertTrue(plan.step_outputs["run_device_build"])
        self.assertTrue(plan.step_outputs["run_ipa_packaging"])
        self.assertTrue(plan.step_outputs["run_simulator_job"])
        self.assertTrue(plan.step_outputs["run_simulator_unit"])
        self.assertTrue(plan.step_outputs["run_simulator_targeted_ui"])
        self.assertTrue(plan.step_outputs["run_simulator_shell_acceptance"])
        self.assertTrue(plan.step_outputs["run_simulator_mcp_acceptance"])
        self.assertEqual(len(plan.skipped_expensive_groups), 0)

    # 11. Default invocation -> full_validation=false
    def test_default_invocation_has_full_validation_false(self) -> None:
        changed = ["Scripts/CI/xcode_cache_inputs.py"]
        plan = self.plan_files(changed)

        self.assertFalse(plan.is_full_validation)
        self.assertFalse(plan.step_outputs["run_full_validation"])
        self.assertIn("ci_router", plan.selected_groups)
        self.assertFalse(plan.step_outputs["run_device_build"])
        self.assertFalse(plan.step_outputs["run_simulator_job"])

    # 12. Explicit targeted rerun -> only requested group plus prerequisites
    def test_explicit_targeted_rerun_with_prerequisites(self) -> None:
        changed = []  # No changed files
        plan = self.plan_files(
            changed,
            target_group="simulator_targeted_ui",
        )

        self.assertFalse(plan.is_full_validation)
        self.assertIn("simulator_targeted_ui", plan.selected_groups)
        self.assertIn("nativescript_dependencies", plan.selected_groups)
        self.assertTrue(plan.step_outputs["run_simulator_targeted_ui"])
        self.assertTrue(plan.step_outputs["run_simulator_job"])

        # Unrelated groups remain skipped
        self.assertNotIn("scripting_compiler", plan.selected_groups)
        self.assertNotIn("platform_contracts", plan.selected_groups)
        self.assertNotIn("device_build", plan.selected_groups)
        self.assertFalse(plan.step_outputs["run_device_build"])

    # 13. Base SHA resolution failure throws actionable BaseSHAResolutionError
    def test_base_sha_resolution_error_diagnostic(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            repo_path = Path(temp_dir)
            with self.assertRaises(planner.BaseSHAResolutionError) as ctx:
                planner.resolve_comparison_range(
                    repo_root=repo_path,
                    event_name="workflow_dispatch",
                    event_payload={},
                    compare_base_sha_input="non_existent_sha_00000",
                    head_sha_input="head_sha_12345",
                )

            err = ctx.exception
            self.assertEqual(err.head_sha, "head_sha_12345")
            self.assertIn("non_existent_sha_00000", err.candidate_shas)
            self.assertIn("does not exist", err.reason)

    # 14. Manual modes integration
    def test_manual_mode_runtime_bundle_only(self) -> None:
        plan = self.plan_files(
            ["README.md"],
            manual_modes={"runtime_bundle_only": True},
        )
        self.assertTrue(plan.step_outputs["run_runtimecore_bundle"])
        self.assertFalse(plan.step_outputs["run_device_build"])
        self.assertFalse(plan.step_outputs["run_simulator_job"])

    def test_manual_mode_fast_validation_only(self) -> None:
        plan = self.plan_files(
            ["README.md"],
            manual_modes={"fast_validation_only": True},
        )
        self.assertTrue(plan.step_outputs["run_simulator_unit"])
        self.assertTrue(plan.step_outputs["run_simulator_smoke_launch"])
        self.assertFalse(plan.step_outputs["run_device_build"])


if __name__ == "__main__":
    unittest.main()
