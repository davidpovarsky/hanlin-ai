from __future__ import annotations

import copy
import importlib.util
from pathlib import Path
import unittest

VALIDATOR_PATH = Path(__file__).resolve().parents[1] / "validate_command_coverage.py"
SPEC = importlib.util.spec_from_file_location("validate_command_coverage", VALIDATOR_PATH)
assert SPEC is not None and SPEC.loader is not None
validator = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(validator)


class RuntimeCommandCoverageTests(unittest.TestCase):
    def test_canonical_coverage_manifest_is_complete(self) -> None:
        manifest = validator.load_manifest()
        errors = validator.validate_coverage(manifest)
        self.assertEqual(
            errors,
            [],
            f"Coverage manifest validation failed with errors: {errors}"
        )
        self.assertEqual(manifest["operation_count"], 58)

    def test_exact_category_breakdown(self) -> None:
        manifest = validator.load_manifest()
        ops = manifest["operations"]
        shell_ops = [op for op in ops if op["canonical_id"].startswith("shell.")]
        ui_ops = [op for op in ops if op["canonical_id"].startswith("script_ui.command.")]
        cap_ops = [op for op in ops if op["canonical_id"].startswith("capability.")]
        lifecycle_ops = [op for op in ops if op["canonical_id"].startswith("app.")]
        tool_ops = [op for op in ops if op["canonical_id"].startswith("tool_authority.")]

        self.assertEqual(len(shell_ops), 23, f"Expected 23 shell commands, got {len(shell_ops)}")
        self.assertEqual(len(ui_ops), 14, f"Expected 14 ScriptUI commands, got {len(ui_ops)}")
        self.assertEqual(len(cap_ops), 11, f"Expected 11 capabilities, got {len(cap_ops)}")
        self.assertEqual(len(lifecycle_ops), 8, f"Expected 8 app lifecycle operations, got {len(lifecycle_ops)}")
        self.assertEqual(len(tool_ops), 2, f"Expected 2 tool authority operations, got {len(tool_ops)}")
        self.assertEqual(len(ops), 58, f"Expected 58 total operations, got {len(ops)}")

    def test_unmapped_shell_command_fails_validation(self) -> None:
        manifest = validator.load_manifest()
        mutated = copy.deepcopy(manifest)
        mutated["operations"] = [op for op in mutated["operations"] if op["canonical_id"] != "shell.curl"]
        errors = validator.validate_coverage(mutated)
        self.assertTrue(
            any("Missing shell command coverage entry: shell.curl" in err for err in errors),
            "Validation unexpectedly succeeded when a canonical shell command was unmapped"
        )

    def test_unmapped_script_ui_command_fails_validation(self) -> None:
        manifest = validator.load_manifest()
        mutated = copy.deepcopy(manifest)
        mutated["operations"] = [op for op in mutated["operations"] if op["canonical_id"] != "script_ui.command.navigate"]
        errors = validator.validate_coverage(mutated)
        self.assertTrue(
            any("Missing ScriptUI command coverage entry: script_ui.command.navigate" in err for err in errors),
            "Validation unexpectedly succeeded when a canonical ScriptUI command was unmapped"
        )

    def test_unmapped_capability_fails_validation(self) -> None:
        manifest = validator.load_manifest()
        mutated = copy.deepcopy(manifest)
        mutated["operations"] = [op for op in mutated["operations"] if op["canonical_id"] != "capability.network"]
        errors = validator.validate_coverage(mutated)
        self.assertTrue(
            any("Missing capability coverage entry: capability.network" in err for err in errors),
            "Validation unexpectedly succeeded when a canonical capability was unmapped"
        )

    def test_unmapped_app_lifecycle_operation_fails_validation(self) -> None:
        manifest = validator.load_manifest()
        mutated = copy.deepcopy(manifest)
        mutated["operations"] = [op for op in mutated["operations"] if op["canonical_id"] != "app.discard_preview"]
        errors = validator.validate_coverage(mutated)
        self.assertTrue(
            any("Missing app lifecycle coverage entry: app.discard_preview" in err for err in errors),
            "Validation unexpectedly succeeded when an app lifecycle operation was unmapped"
        )

    def test_unmapped_tool_authority_operation_fails_validation(self) -> None:
        manifest = validator.load_manifest()
        mutated = copy.deepcopy(manifest)
        mutated["operations"] = [op for op in mutated["operations"] if op["canonical_id"] != "tool_authority.invoke"]
        errors = validator.validate_coverage(mutated)
        self.assertTrue(
            any("Missing tool authority coverage entry: tool_authority.invoke" in err for err in errors),
            "Validation unexpectedly succeeded when a tool authority operation was unmapped"
        )

    def test_missing_required_field_fails_validation(self) -> None:
        manifest = validator.load_manifest()
        mutated = copy.deepcopy(manifest)
        del mutated["operations"][0]["runtime_bridge_owner"]
        errors = validator.validate_coverage(mutated)
        self.assertTrue(
            any("missing required field 'runtime_bridge_owner'" in err for err in errors)
        )

    def test_missing_tests_and_justification_fails_validation(self) -> None:
        manifest = validator.load_manifest()
        mutated = copy.deepcopy(manifest)
        mutated["operations"][0]["existing_acceptance_test"] = None
        mutated["operations"][0]["new_acceptance_test"] = None
        mutated["operations"][0]["justified_exclusion"] = None
        errors = validator.validate_coverage(mutated)
        self.assertTrue(
            any("has neither test coverage nor justified exclusion" in err for err in errors)
        )


if __name__ == "__main__":
    unittest.main()
