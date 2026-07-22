from __future__ import annotations

import re
import unittest
from pathlib import Path


REPOSITORY_ROOT = Path(__file__).resolve().parents[3]
RUNNER = REPOSITORY_ROOT / "Packages/IOSSystemLite/Sources/IOSSystemLite/IOSSystemRunner.swift"


class IOSSystemRunnerSourceTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.source = RUNNER.read_text(encoding="utf-8")

    def test_initialize_environment_has_one_production_call_site(self) -> None:
        self.assertEqual(len(re.findall(r"\binitializeEnvironment\(\)", self.source)), 1)
        self.assertIn("Mutex<RegistrationState>", self.source)
        self.assertIn("case uninitialized", self.source)
        self.assertIn("case initialized(IOSSystemRegistrationReport)", self.source)
        self.assertIn("case failed(IOSSystemRegistrationError)", self.source)

    def test_legacy_add_command_list_fallback_is_removed(self) -> None:
        self.assertNotIn("addCommandList(", self.source)
        self.assertNotRegex(self.source, r"_\s*=\s*addCommandList")

    def test_main_and_module_resource_contract_is_explicit(self) -> None:
        self.assertIn('named: "commandDictionary"', self.source)
        self.assertIn('named: "extraCommandsDictionary"', self.source)
        self.assertIn("let mainBundle = Bundle.main", self.source)
        self.assertIn("let moduleBundle = Bundle.module", self.source)
        self.assertNotIn("sideLoading = true", self.source)
        self.assertIn("sideLoadingEnabled: false", self.source)

    def test_objective_c_command_values_are_bridged_individually(self) -> None:
        self.assertIn("let bridgedArray = rawCommands as NSArray", self.source)
        self.assertIn("value as? NSString", self.source)
        self.assertIn("commands_array_bridge_failure", self.source)


if __name__ == "__main__":
    unittest.main()
