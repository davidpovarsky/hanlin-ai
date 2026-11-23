#!/usr/bin/env python3
"""Portable diagnostic controls only; these do not run or simulate an Apple model."""
from contextlib import redirect_stdout
import hashlib
import importlib.util
import io
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location("fm_inspector", Path(__file__).with_name("inspect_foundation_models_interface.py"))
inspector = importlib.util.module_from_spec(spec)
spec.loader.exec_module(inspector)


class AvailabilityInspectorControls(unittest.TestCase):
    def test_default_does_not_query_availability(self):
        receipt = {"status": "DECLARATIONS_READ", "availability": "NOT_QUERIED", "modelExecution": "NOT_RUN"}
        with tempfile.TemporaryDirectory() as temporary:
            output = Path(temporary) / "inspection"
            with patch.object(inspector, "inspect", return_value=receipt), patch.object(inspector, "query_availability", side_effect=AssertionError("unexpected opt-in")) as query:
                with redirect_stdout(io.StringIO()) as captured:
                    inspector.main(["--output", str(output)])
            query.assert_not_called()
            self.assertEqual(json.loads(captured.getvalue()), receipt)
            self.assertFalse(output.exists())

    def test_actual_process_output_and_closed_pipe_timeout_are_bounded(self):
        cases = [("output", "print('x' * 1024)", "OUTPUT_LIMIT"),
                 ("closed", "import os,time;os.close(1);os.close(2);time.sleep(10)", "TIMEOUT")]
        with tempfile.TemporaryDirectory() as temporary:
            output = Path(temporary)
            for name, source, termination in cases:
                with self.subTest(name=name):
                    record = inspector.bounded_command([sys.executable, "-c", source], output, name, timeout=0.5, output_limit=64)
                    self.assertEqual(record["status"], "FAIL")
                    self.assertEqual(record["termination"], termination)
                    self.assertLess(record["elapsedSeconds"], 3)
                    for stream in ("stdout", "stderr"):
                        data = (output / record[stream]["path"]).read_bytes()
                        self.assertLessEqual(len(data), 64)
                        self.assertEqual(hashlib.sha256(data).hexdigest(), record[stream]["sha256"])

    def test_fixture_failure_and_unavailability_never_claim_model_execution(self):
        # Process fixtures exercise receipt admission, not FoundationModels semantics.
        observations = [
            ("model-not-ready", "modelNotReady", "NOT_RUN", False, "PASS"),
            ("invalid-model-claim", "available", "PASS", False, "FAIL"),
            ("invalid-enum-shape", [], "NOT_RUN", False, "FAIL"),
            ("compile-failure", "available", "NOT_RUN", True, "FAIL"),
        ]
        for label, availability, model_status, compile_fails, expected in observations:
            with self.subTest(name=label), tempfile.TemporaryDirectory() as temporary:
                output = Path(temporary)
                def fixture(args, destination, name, timeout, output_limit=65536):
                    command_output = {"xcode-version": "fixture Xcode", "sdk-path": "/fixture/AppleSDK",
                        "sdk-version": "fixture SDK", "compiler-version": "fixture Swift", "compile": ""}
                    if name == "compile" and not compile_fails:
                        Path(args[-1]).write_bytes(b"fixture executable; never executed")
                    if name == "query":
                        command_output[name] = json.dumps({"schemaVersion": 1,
                            "query": "SystemLanguageModel.default.availability", "platform": "macOS",
                            "osVersion": "fixture OS", "availability": availability,
                            "modelExecution": model_status, "toolExecution": "NOT_RUN"})
                    stdout = destination / (name + ".stdout.log")
                    stdout.write_text(command_output[name])
                    return {"command": list(args), "status": "FAIL" if compile_fails and name == "compile" else "PASS",
                        "returncode": 1 if compile_fails and name == "compile" else 0, "stdout": {"path": stdout.name}}
                with patch.object(inspector.platform, "system", return_value="Darwin"), patch.object(inspector, "bounded_command", side_effect=fixture):
                    receipt = inspector.query_availability(output)
                self.assertEqual(receipt["status"], expected)
                self.assertEqual(receipt["modelExecution"], "NOT_RUN")
                self.assertEqual(receipt["toolExecution"], "NOT_RUN")
                self.assertEqual(receipt["toolCapability"], "NOT_QUERIED")
                self.assertEqual(json.loads((output / "receipt.json").read_text()), receipt)
                self.assertEqual(receipt["availability"], "modelNotReady" if expected == "PASS" else "NOT_QUERIED")
                if compile_fails:
                    self.assertNotIn("observation", receipt)
                    self.assertEqual(len(receipt["commands"]), 5)


if __name__ == "__main__":
    unittest.main()
