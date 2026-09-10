from __future__ import annotations

import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

SCRIPT_PATH = Path(__file__).parents[1] / "analyze_performance_results.py"

SPEC = importlib.util.spec_from_file_location("analyze_performance_results", SCRIPT_PATH)
assert SPEC is not None and SPEC.loader is not None
analyzer = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(analyzer)


class AnalyzePerformanceResultsTests(unittest.TestCase):
    def test_compute_statistics_empty(self) -> None:
        stats = analyzer.compute_statistics([])
        self.assertEqual(stats["count"], 0)
        self.assertEqual(stats["mean"], 0.0)

    def test_compute_statistics_values(self) -> None:
        samples = [0.10, 0.20, 0.30, 0.40, 0.50]
        stats = analyzer.compute_statistics(samples)
        self.assertEqual(stats["count"], 5)
        self.assertAlmostEqual(stats["mean"], 0.30)
        self.assertAlmostEqual(stats["median"], 0.30)
        self.assertAlmostEqual(stats["min"], 0.10)
        self.assertAlmostEqual(stats["max"], 0.50)
        self.assertGreater(stats["std_dev"], 0.0)
        self.assertGreater(stats["cv_percent"], 0.0)

    def test_analyze_records_informational_pass(self) -> None:
        records = [
            {
                "flow_number": 1,
                "flow_name": "Application Cold Launch",
                "category": "App Launch",
                "metric": "launch_duration",
                "unit": "s",
                "samples": [0.42, 0.44, 0.43, 0.45, 0.41],
                "classification": "informational",
            }
        ]
        summary = analyzer.analyze_records(records)
        self.assertTrue(summary["hard_gate_passed"])
        self.assertEqual(len(summary["metrics"]), 1)
        metric = summary["metrics"][0]
        self.assertEqual(metric["flow_number"], 1)
        self.assertEqual(metric["status"], "PASS")
        self.assertAlmostEqual(metric["statistics"]["median"], 0.43)

    def test_analyze_records_hard_gate_failure(self) -> None:
        records = [
            {
                "flow_number": 0,
                "flow_name": "Memory Stability",
                "category": "Memory",
                "metric": "memory_growth_delta",
                "unit": "MB",
                "samples": [75.0],
                "classification": "hard_gate",
            }
        ]
        summary = analyzer.analyze_records(records)
        self.assertFalse(summary["hard_gate_passed"])
        self.assertEqual(len(summary["hard_gate_failures"]), 1)
        self.assertIn("75.00 MB", summary["hard_gate_failures"][0])

    def test_parse_log_files(self) -> None:
        with tempfile.TemporaryDirectory() as tmpdir:
            log_file = Path(tmpdir) / "test.log"
            sample_payload = {
                "flow_number": 4,
                "flow_name": "JSC Init",
                "category": "Runtime",
                "metric": "init_latency",
                "unit": "s",
                "samples": [0.01, 0.012],
                "classification": "informational",
            }
            log_file.write_text(
                f"Some prefix log\nHANLIN_PERF_SAMPLE: {json.dumps(sample_payload)}\nSome suffix",
                encoding="utf-8",
            )

            samples = analyzer.parse_log_files(Path(tmpdir))
            self.assertEqual(len(samples), 1)
            self.assertEqual(samples[0]["flow_number"], 4)
            self.assertEqual(samples[0]["metric"], "init_latency")

    def test_render_markdown_report(self) -> None:
        records = [
            {
                "flow_number": 1,
                "flow_name": "Application Cold Launch",
                "category": "App Launch",
                "metric": "launch_duration",
                "unit": "s",
                "samples": [0.42, 0.44],
                "classification": "informational",
            }
        ]
        summary = analyzer.analyze_records(records)
        md = analyzer.render_markdown_report(summary)
        self.assertIn("iPad Performance & Regression Baseline Report", md)
        self.assertIn("Application Cold Launch", md)
        self.assertIn("Simulator vs. Physical iPad Limitation Notice", md)


if __name__ == "__main__":
    unittest.main()
