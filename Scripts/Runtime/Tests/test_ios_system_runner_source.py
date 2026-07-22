from __future__ import annotations

import re
import unittest
from pathlib import Path


REPOSITORY_ROOT = Path(__file__).resolve().parents[3]
RUNNER = REPOSITORY_ROOT / "Packages/IOSSystemLite/Sources/IOSSystemLite/IOSSystemRunner.swift"
STREAM_BRIDGE = REPOSITORY_ROOT / "Packages/IOSSystemLite/Sources/IOSSystemStreamBridge/IOSSystemStreamBridge.m"


class IOSSystemRunnerSourceTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.source = RUNNER.read_text(encoding="utf-8")
        cls.stream_bridge = STREAM_BRIDGE.read_text(encoding="utf-8")

    def test_initialize_environment_has_one_production_call_site(self) -> None:
        self.assertEqual(len(re.findall(r"\binitializeEnvironment\(\)", self.source)), 1)
        self.assertIn("Mutex<RegistrationState>", self.source)
        self.assertIn("case uninitialized", self.source)
        self.assertIn("case initialized(IOSSystemRegistrationReport)", self.source)
        self.assertIn("case failed(IOSSystemRegistrationError)", self.source)

    def test_legacy_add_command_list_fallback_is_removed(self) -> None:
        self.assertNotIn("addCommandList(", self.source)
        self.assertNotRegex(self.source, r"_\s*=\s*addCommandList")

    def test_structured_registration_error_is_publicly_constructible(self) -> None:
        self.assertRegex(
            self.source,
            r"public struct IOSSystemRegistrationError[\s\S]*?public init\(\s*category:",
        )

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

    def test_each_execution_refreshes_session_and_thread_local_streams(self) -> None:
        self.assertIn("import IOSSystemStreamBridge", self.source)
        self.assertIn("hanlin_ios_system_set_streams(input, output, error)", self.source)
        self.assertIn("ios_setStreams(standard_input, standard_output, standard_error)", self.stream_bridge)
        self.assertIn("thread_stdin = standard_input", self.stream_bridge)
        self.assertIn("thread_stdout = standard_output", self.stream_bridge)
        self.assertIn("thread_stderr = standard_error", self.stream_bridge)


if __name__ == "__main__":
    unittest.main()
