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
        self.assertGreaterEqual(manifest["operation_count"], 58)

    def test_unmapped_shell_command_fails_validation(self) -> None:
        manifest = validator.load_manifest()
        mutated = copy.deepcopy(manifest)
        # Remove a canonical shell command entry
        mutated["operations"] = [op for op in mutated["operations"] if op["canonical_id"] != "shell.curl"]
        errors = validator.validate_coverage(mutated)
        self.assertTrue(
            any("Missing shell command coverage entry: shell.curl" in err for err in errors),
            "Validation unexpectedly succeeded when a canonical shell command was unmapped"
        )

    def test_unmapped_script_ui_command_fails_validation(self) -> None:
        manifest = validator.load_manifest()
        mutated = copy.deepcopy(manifest)
        # Remove a ScriptUI command entry
        mutated["operations"] = [op for op in mutated["operations"] if op["canonical_id"] != "script_ui.command.navigate"]
        errors = validator.validate_coverage(mutated)
        self.assertTrue(
            any("Missing ScriptUI command coverage entry: script_ui.command.navigate" in err for err in errors),
            "Validation unexpectedly succeeded when a canonical ScriptUI command was unmapped"
        )

    def test_unmapped_capability_fails_validation(self) -> None:
        manifest = validator.load_manifest()
        mutated = copy.deepcopy(manifest)
        # Remove a capability entry
        mutated["operations"] = [op for op in mutated["operations"] if op["canonical_id"] != "capability.network"]
        errors = validator.validate_coverage(mutated)
        self.assertTrue(
            any("Missing capability coverage entry: capability.network" in err for err in errors),
            "Validation unexpectedly succeeded when a canonical capability was unmapped"
        )

    def test_missing_required_field_fails_validation(self) -> None:
        manifest = validator.load_manifest()
        mutated = copy.deepcopy(manifest)
        del mutated["operations"][0]["runtime_bridge_owner"]
        errors = validator.validate_coverage(mutated)
        self.assertTrue(
            any("missing required field 'runtime_bridge_owner'" in err for err in errors)
        )


if __name__ == "__main__":
    unittest.main()
