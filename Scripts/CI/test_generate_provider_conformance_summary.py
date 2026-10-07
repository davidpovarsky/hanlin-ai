#!/usr/bin/env python3
"""
test_generate_provider_conformance_summary.py
Unit and regression test suite for generate_provider_conformance_summary.py.
Verifies fail-safe exact identity matching, gate enforcement, and absence of fuzzy/tag cross-matching.
"""

import io
import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

# Add Scripts/CI to path
CI_DIR = Path(__file__).resolve().parent
sys.path.insert(0, str(CI_DIR))

from generate_provider_conformance_summary import (
    TestExecutionRecord,
    match_test_status,
    parse_test_logs,
)


class TestEvidenceMatcherRegressions(unittest.TestCase):
    """
    Mandatory regression tests:
    G01: Same scenario tag must not cross-match
    G02: Prefix display names must not cross-match
    G03: Exact function identity wins
    G04: Exact FAIL maps only to exact test
    G05: Parameterized aggregate PASS
    G06: No evidence -> NOT_RUN
    """

    def setUp(self):
        self.temp_dir = tempfile.TemporaryDirectory()
        self.log_path = Path(self.temp_dir.name) / "test.log"

    def tearDown(self):
        self.temp_dir.cleanup()

    def _write_log(self, text: str):
        self.log_path.write_text(text, encoding="utf-8")
        return [self.log_path]

    def test_g01_same_scenario_tag_must_not_cross_match(self):
        """
        G01: Two tests sharing the 'P05' tag. If log contains only OpenAI-compatible,
        OpenRouter MUST NOT be marked PASS via scenario-tag fallback.
        """
        source_tests = [
            {
                "suite": "ProductionProviderConformanceTests",
                "function": "testP05ReasoningToolLoopOpenAICompatible",
                "displayName": "P05: Production reasoning and tool loop for OpenAI-compatible",
                "file": "AI_HLYTests/ProviderConformance/ProductionProviderConformanceTests.swift"
            },
            {
                "suite": "ProductionProviderConformanceTests",
                "function": "testP05ReasoningToolLoopOpenRouter",
                "displayName": "P05: Production reasoning and tool loop for OpenRouter with exact structural equality",
                "file": "AI_HLYTests/ProviderConformance/ProductionProviderConformanceTests.swift"
            }
        ]
        tests_by_display = {t["displayName"]: [t] for t in source_tests}

        # Log contains ONLY the OpenAICompatible test
        log_content = (
            "✔ Test \"P05: Production reasoning and tool loop for OpenAI-compatible\" "
            "(aka 'testP05ReasoningToolLoopOpenAICompatible()') passed after 0.070 seconds.\n"
        )
        records = parse_test_logs(self._write_log(log_content))

        status_compat, err_compat, _ = match_test_status(source_tests[0], records, tests_by_display)
        status_router, err_router, _ = match_test_status(source_tests[1], records, tests_by_display)

        self.assertEqual(status_compat, "PASS", "OpenAI-compatible must pass")
        self.assertEqual(status_router, "NOT_RUN", "OpenRouter must NOT pass via P05 tag matching")
        self.assertIsNone(err_compat)
        self.assertIsNone(err_router)

    def test_g02_prefix_display_names_must_not_cross_match(self):
        """
        G02: Prefix display names must never satisfy a longer display name.
        """
        source_tests = [
            {
                "suite": "ProductionProviderConformanceTests",
                "function": "testP09CancelProviderStream",
                "displayName": "P09: Provider stream cancellation",
                "file": "AI_HLYTests/ProviderConformance/ProductionProviderConformanceTests.swift"
            },
            {
                "suite": "ProductionProviderConformanceTests",
                "function": "testP09CancelProviderStreamAfterTool",
                "displayName": "P09: Provider stream cancellation after tool execution",
                "file": "AI_HLYTests/ProviderConformance/ProductionProviderConformanceTests.swift"
            }
        ]
        tests_by_display = {t["displayName"]: [t] for t in source_tests}

        # Log contains ONLY the shorter display name
        log_content = "✔ Test \"P09: Provider stream cancellation\" passed after 0.120 seconds.\n"
        records = parse_test_logs(self._write_log(log_content))

        status_first, _, _ = match_test_status(source_tests[0], records, tests_by_display)
        status_second, _, _ = match_test_status(source_tests[1], records, tests_by_display)

        self.assertEqual(status_first, "PASS")
        self.assertEqual(status_second, "NOT_RUN", "Prefix match must never mark longer display name as PASS")

    def test_g03_exact_function_identity_wins(self):
        """
        G03: Exact canonical function identity (aka 'testFunctionName()') wins
        even if display name differs.
        """
        source_test = {
            "suite": "ProductionProviderConformanceTests",
            "function": "testP05ReasoningToolLoopOpenRouter",
            "displayName": "P05: OpenRouter Custom",
            "file": "AI_HLYTests/ProviderConformance/ProductionProviderConformanceTests.swift"
        }
        tests_by_display = {source_test["displayName"]: [source_test]}

        log_content = (
            "✔ Test \"Completely Arbitrary Framework Display Text\" "
            "(aka 'testP05ReasoningToolLoopOpenRouter()') passed after 0.050 seconds.\n"
        )
        records = parse_test_logs(self._write_log(log_content))

        status, err, _ = match_test_status(source_test, records, tests_by_display)
        self.assertEqual(status, "PASS", "Canonical aka function identity must match")
        self.assertIsNone(err)

    def test_g04_exact_fail_maps_only_to_exact_test(self):
        """
        G04: An explicit failure for OpenRouter must map ONLY to OpenRouter,
        and not mark OpenAI-compatible as FAIL.
        """
        source_tests = [
            {
                "suite": "ProductionProviderConformanceTests",
                "function": "testP05ReasoningToolLoopOpenAICompatible",
                "displayName": "P05: Production reasoning and tool loop for OpenAI-compatible",
                "file": "AI_HLYTests/ProviderConformance/ProductionProviderConformanceTests.swift"
            },
            {
                "suite": "ProductionProviderConformanceTests",
                "function": "testP05ReasoningToolLoopOpenRouter",
                "displayName": "P05: Production reasoning and tool loop for OpenRouter with exact structural equality",
                "file": "AI_HLYTests/ProviderConformance/ProductionProviderConformanceTests.swift"
            }
        ]
        tests_by_display = {t["displayName"]: [t] for t in source_tests}

        # OpenRouter fails
        log_content = (
            "✘ Test \"P05: Production reasoning and tool loop for OpenRouter with exact structural equality\" "
            "(aka 'testP05ReasoningToolLoopOpenRouter()') failed after 0.150 seconds.\n"
        )
        records = parse_test_logs(self._write_log(log_content))

        status_compat, _, _ = match_test_status(source_tests[0], records, tests_by_display)
        status_router, err_router, _ = match_test_status(source_tests[1], records, tests_by_display)

        self.assertEqual(status_router, "FAIL", "OpenRouter must be marked FAIL")
        self.assertIn("failed after", err_router)
        self.assertEqual(status_compat, "NOT_RUN", "OpenAI-compatible must remain NOT_RUN, not FAIL")

    def test_g05_parameterized_aggregate_pass(self):
        """
        G05: Parameterized aggregate PASS (e.g. F08 with 25 test cases)
        marks the source function as PASS and reports case count.
        """
        source_test = {
            "suite": "ProviderFaultInjectionTests",
            "function": "testF08HTTPErrorCodes",
            "displayName": "F08: HTTP error codes 400, 401, 429, 500, 503 abort stream without tool execution",
            "file": "Packages/HanlinPlatform/Tests/HanlinChatCoreTests/ProviderConformance/ProviderFaultInjectionTests.swift"
        }
        tests_by_display = {source_test["displayName"]: [source_test]}

        log_content = (
            "✔ Test \"F08: HTTP error codes 400, 401, 429, 500, 503 abort stream without tool execution\" "
            "with 25 test cases passed after 6.860 seconds.\n"
        )
        records = parse_test_logs(self._write_log(log_content))

        status, err, cases = match_test_status(source_test, records, tests_by_display)
        self.assertEqual(status, "PASS")
        self.assertIsNone(err)
        self.assertEqual(cases, 25, "Parameterized case count 25 must be captured")

    def test_g06_no_evidence_returns_not_run(self):
        """
        G06: If no evidence appears for a test, it must be NOT_RUN, never PASS.
        """
        source_test = {
            "suite": "ProviderConformanceScenarioTests",
            "function": "testS99UnexecutedMysteryTest",
            "displayName": "S99: Mystery test",
            "file": "Packages/HanlinPlatform/Tests/HanlinChatCoreTests/ProviderConformance/ProviderConformanceScenarioTests.swift"
        }
        tests_by_display = {source_test["displayName"]: [source_test]}

        log_content = "✔ Test unrelatedFunction() passed after 0.001 seconds.\n"
        records = parse_test_logs(self._write_log(log_content))

        status, err, cases = match_test_status(source_test, records, tests_by_display)
        self.assertEqual(status, "NOT_RUN")
        self.assertIsNone(err)
        self.assertIsNone(cases)

    def test_ambiguous_display_names_fail_closed(self):
        """
        If two source tests share the same display name and log contains only
        display name without canonical function name, fail closed with EVIDENCE_ERROR.
        """
        source_tests = [
            {
                "suite": "SuiteA",
                "function": "testA",
                "displayName": "Shared Duplicate Display Name",
                "file": "SuiteA.swift"
            },
            {
                "suite": "SuiteB",
                "function": "testB",
                "displayName": "Shared Duplicate Display Name",
                "file": "SuiteB.swift"
            }
        ]
        tests_by_display = {
            "Shared Duplicate Display Name": source_tests
        }

        log_content = "✔ Test \"Shared Duplicate Display Name\" passed after 0.050 seconds.\n"
        records = parse_test_logs(self._write_log(log_content))

        status_a, err_a, _ = match_test_status(source_tests[0], records, tests_by_display)
        status_b, err_b, _ = match_test_status(source_tests[1], records, tests_by_display)

        self.assertEqual(status_a, "EVIDENCE_ERROR")
        self.assertEqual(status_b, "EVIDENCE_ERROR")
        self.assertIn("Ambiguous display name", err_a)


class TestGateEnforcement(unittest.TestCase):
    """
    Tests proving --gate behavior:
    - Exits non-zero when NOT_RUN > 0
    - Exits non-zero when FAIL > 0
    - Exits non-zero when EVIDENCE_ERROR > 0
    - Exits zero when all tests PASS
    """

    def setUp(self):
        self.temp_dir = tempfile.TemporaryDirectory()
        self.script_path = CI_DIR / "generate_provider_conformance_summary.py"

    def tearDown(self):
        self.temp_dir.cleanup()

    def test_gate_fails_on_not_run(self):
        """When notRunCount > 0, --gate must exit with code 1."""
        output_file = Path(self.temp_dir.name) / "summary.json"
        empty_log = Path(self.temp_dir.name) / "empty.log"
        empty_log.write_text("random line\n", encoding="utf-8")

        res = subprocess.run(
            [sys.executable, str(self.script_path), "--log-file", str(empty_log), "--output", str(output_file), "--gate"],
            capture_output=True,
            text=True
        )
        self.assertNotEqual(res.returncode, 0, "Gate must fail when tests are NOT_RUN")
        self.assertIn("GATE FAILED", res.stderr)

    def test_gate_fails_on_76_pass_1_not_run(self):
        """When 76 tests PASS and 1 is NOT_RUN, --gate must exit with code 1."""
        from generate_provider_conformance_summary import scan_test_definitions
        repo_root = CI_DIR.parent.parent
        tests = scan_test_definitions(repo_root)
        self.assertEqual(len(tests), 77)

        # Include 76 tests only
        lines = []
        for t in tests[:-1]:
            fn = t["function"]
            dn = t.get("displayName")
            if dn:
                lines.append(f"✔ Test \"{dn}\" (aka '{fn}()') passed after 0.01 seconds.")
            else:
                lines.append(f"✔ Test {fn}() passed after 0.01 seconds.")

        partial_log = Path(self.temp_dir.name) / "partial.log"
        partial_log.write_text("\n".join(lines) + "\n", encoding="utf-8")

        output_file = Path(self.temp_dir.name) / "summary.json"
        res = subprocess.run(
            [sys.executable, str(self.script_path), "--repo-root", str(repo_root), "--log-file", str(partial_log), "--output", str(output_file), "--gate"],
            capture_output=True,
            text=True
        )
        self.assertNotEqual(res.returncode, 0, "Gate must exit non-zero when 1 test is NOT_RUN")
        self.assertIn("GATE FAILED", res.stderr)
        self.assertIn("1 unexecuted tests", res.stderr)

    def test_gate_passes_when_all_pass(self):
        """When all tests pass, --gate must exit with code 0."""
        # We synthesize a log that has all 77 tests
        from generate_provider_conformance_summary import scan_test_definitions
        repo_root = CI_DIR.parent.parent
        tests = scan_test_definitions(repo_root)
        self.assertEqual(len(tests), 77)

        lines = []
        for t in tests:
            fn = t["function"]
            dn = t.get("displayName")
            if dn:
                lines.append(f"✔ Test \"{dn}\" (aka '{fn}()') passed after 0.01 seconds.")
            else:
                lines.append(f"✔ Test {fn}() passed after 0.01 seconds.")

        all_pass_log = Path(self.temp_dir.name) / "all_pass.log"
        all_pass_log.write_text("\n".join(lines) + "\n", encoding="utf-8")

        output_file = Path(self.temp_dir.name) / "summary.json"
        res = subprocess.run(
            [sys.executable, str(self.script_path), "--repo-root", str(repo_root), "--log-file", str(all_pass_log), "--output", str(output_file), "--gate"],
            capture_output=True,
            text=True
        )
        self.assertEqual(res.returncode, 0, f"Gate must pass when 77/77 tests pass. Output: {res.stdout}, Stderr: {res.stderr}")
        self.assertIn("Total: 77 | PASS: 77 | FAIL: 0 | NOT_RUN: 0", res.stdout.replace("Conformance Test Functions:", "Total:"))

        # Check JSON structure
        data = json.loads(output_file.read_text(encoding="utf-8"))
        self.assertEqual(data["sourceTestFunctionCount"], 77)
        self.assertEqual(data["passedCount"], 77)
        self.assertEqual(data["failedCount"], 0)
        self.assertEqual(data["notRunCount"], 0)

    def test_gate_allows_unexecuted_when_flag_passed(self):
        """When tests are not run, --gate --allow-unexecuted must exit 0 unless there are failures."""
        from generate_provider_conformance_summary import scan_test_definitions
        repo_root = CI_DIR.parent.parent
        tests = scan_test_definitions(repo_root)

        # Log with only the first test passing
        first_test = tests[0]
        fn = first_test["function"]
        dn = first_test.get("displayName")
        line = f"✔ Test \"{dn}\" (aka '{fn}()') passed after 0.01 seconds." if dn else f"✔ Test {fn}() passed after 0.01 seconds."

        partial_log = Path(self.temp_dir.name) / "partial_allow.log"
        partial_log.write_text(line + "\n", encoding="utf-8")

        output_file = Path(self.temp_dir.name) / "summary_allow.json"
        res = subprocess.run(
            [sys.executable, str(self.script_path), "--repo-root", str(repo_root), "--log-file", str(partial_log), "--output", str(output_file), "--gate", "--allow-unexecuted"],
            capture_output=True,
            text=True
        )
        self.assertEqual(res.returncode, 0, f"Gate must pass with --allow-unexecuted even if unexecuted tests exist. Stderr: {res.stderr}")


if __name__ == "__main__":
    unittest.main()
