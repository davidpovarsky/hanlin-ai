from __future__ import annotations

import argparse
import importlib.util
import json
from pathlib import Path
import sys
import tempfile
import unittest

SCRIPT_PATH = Path(__file__).parents[1] / "run_runtime_tooling_acceptance.py"
SPEC = importlib.util.spec_from_file_location("run_runtime_tooling_acceptance", SCRIPT_PATH)
assert SPEC is not None and SPEC.loader is not None
acceptance_runner = importlib.util.module_from_spec(SPEC)
sys.modules["run_runtime_tooling_acceptance"] = acceptance_runner
SPEC.loader.exec_module(acceptance_runner)


class RuntimeToolingAcceptanceRunnerTests(unittest.TestCase):
    def test_partition_selectors_separates_unit_and_ui(self) -> None:
        unit_sel, ui_sel = acceptance_runner.partition_selectors(acceptance_runner.GROUPS)
        self.assertTrue(len(unit_sel) > 0)
        self.assertTrue(len(ui_sel) > 0)
        for s in unit_sel:
            self.assertTrue(s.startswith("AI_HLYTests/"), f"Expected unit selector: {s}")
        for s in ui_sel:
            self.assertTrue(s.startswith("AI_HLYUITests/"), f"Expected UI selector: {s}")
        self.assertEqual(len(unit_sel), len(set(unit_sel)))
        self.assertEqual(len(ui_sel), len(set(ui_sel)))

    def test_runner_executes_at_most_two_phases(self) -> None:
        invocations = []

        def mock_runner(args, phase_name, selectors, output):
            invocations.append((phase_name, list(selectors)))
            return acceptance_runner.PhaseExecutionResult(
                phase_name=phase_name,
                returncode=0,
                duration_seconds=1.5,
                log_path=output / "phases" / phase_name / "xcodebuild.log",
                result_bundle=output / "phases" / phase_name / "Result.xcresult",
                xcresult_json=output / "phases" / phase_name / "test-results.json",
                nodes=[],
                process_crashed=False,
            )

        with tempfile.TemporaryDirectory() as tmpdir:
            out_dir = Path(tmpdir)
            test_args = [
                "--project", "AI_HLY.xcodeproj",
                "--scheme", "AI_HLY",
                "--configuration", "Release",
                "--destination", "platform=iOS Simulator,id=12345",
                "--derived-data", str(out_dir / "DerivedData"),
                "--source-packages", str(out_dir / "SourcePackages"),
                "--output-dir", str(out_dir / "acceptance"),
                "--commit", "abc1234",
                "--branch", "main",
                "--xcode-version", "Xcode 16.0",
                "--simulator-device", "iPad Pro",
                "--simulator-os", "iOS 18.0",
            ]
            orig_argv = sys.argv
            sys.argv = ["run_runtime_tooling_acceptance.py"] + test_args
            try:
                exit_code = acceptance_runner.main(runner=mock_runner)
                self.assertEqual(exit_code, 1)
            finally:
                sys.argv = orig_argv

            self.assertEqual(len(invocations), 2)
            self.assertEqual(invocations[0][0], "unit")
            self.assertEqual(invocations[1][0], "ui")

            report_file = out_dir / "acceptance" / "runtime-tooling-acceptance.json"
            self.assertTrue(report_file.exists())
            report = json.loads(report_file.read_text(encoding="utf-8"))
            self.assertEqual(len(report["groupSummaries"]), 7)
            self.assertEqual(report["caseCount"], len(report["cases"]))

    def test_evaluate_acceptance_maps_nodes_to_cases(self) -> None:
        with tempfile.TemporaryDirectory() as tmpdir:
            out_dir = Path(tmpdir)
            unit_nodes = [
                {"name": "preparedSchemasHaveUniqueAliasesRoutesAndValidObjectContracts()", "result": "Passed", "duration": 0.12},
                {"name": "runtimeToolsRejectMalformedArgumentsSemantically()", "result": "Passed", "duration": 0.05},
                {"name": "agentToolExecutesPython()", "result": "Passed", "duration": 0.3},
            ]
            ui_nodes = [
                {"name": "testNodePackageManagerUIWorkflowAndSuccess()", "result": "Passed", "duration": 2.5},
            ]

            unit_phase = acceptance_runner.PhaseExecutionResult(
                phase_name="unit",
                returncode=0,
                duration_seconds=5.0,
                log_path=out_dir / "unit.log",
                result_bundle=out_dir / "unit.xcresult",
                xcresult_json=out_dir / "unit.json",
                nodes=unit_nodes,
                process_crashed=False,
            )
            ui_phase = acceptance_runner.PhaseExecutionResult(
                phase_name="ui",
                returncode=0,
                duration_seconds=10.0,
                log_path=out_dir / "ui.log",
                result_bundle=out_dir / "ui.xcresult",
                xcresult_json=out_dir / "ui.json",
                nodes=ui_nodes,
                process_crashed=False,
            )

            group_results, cases = acceptance_runner.evaluate_acceptance(
                out_dir, acceptance_runner.GROUPS, unit_phase, ui_phase
            )

            self.assertEqual(len(group_results), 7)
            cases_by_id = {c["caseID"]: c for c in cases}

            case_passed = cases_by_id["schema.all-tools.unique-routed-valid"]
            self.assertTrue(case_passed["passed"])
            self.assertEqual(case_passed["actualOutcome"], "passed")
            self.assertEqual(case_passed["durationSeconds"], 0.12)

            case_rejection = cases_by_id["schema.runtime.malformed-rejection"]
            self.assertTrue(case_rejection["passed"])
            self.assertEqual(case_rejection["actualOutcome"], "expected-rejection")

            case_missing = cases_by_id["schema.python.local-remote-unambiguous"]
            self.assertFalse(case_missing["passed"])
            self.assertEqual(case_missing["actualOutcome"], "missing")


if __name__ == "__main__":
    unittest.main()
