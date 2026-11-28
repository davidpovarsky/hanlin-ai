"""Actual Swift Testing transcript controls; no compiler, process query or native rerun."""
import ast
import collections
import hashlib
import pathlib
import re
import unittest

SOURCE = pathlib.Path(__file__).resolve().parents[1] / "IntegrationValidation/run_host_mcp_wire_comparison.py"
TRANSCRIPT = pathlib.Path(__file__).parent / "fixtures/mcp-wire-swift-testing-6.4.2.txt"
# Exact terminal bytes from native run 46042428539, full log SHA256 b96460920bd1acc4cc8c0d6572af89a7f382ce091e7163c73660905599ec09df.
TRANSCRIPT_SHA256 = "90d8588a16606e1f5af988edad6154c90f4b0410706d5d51dcc93c47bef5b3fd"


class MCPWireReconciliationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        tree = ast.parse(SOURCE.read_text())
        cls.expected = ast.literal_eval(next(
            n.value for n in tree.body if isinstance(n, ast.Assign)
            and any(isinstance(t, ast.Name) and t.id == "EXPECTED_METHODS" for t in n.targets)))
        gate = next(n for n in tree.body if isinstance(n, ast.FunctionDef)
                    and n.name == "run_prepared_original_gate")
        body = next(n.body for n in gate.body if isinstance(n, ast.Try))
        begin = next(i for i, n in enumerate(body) if isinstance(n, ast.Assign)
                     and any(isinstance(t, ast.Name) and t.id == "starts" for t in n.targets))
        # Execute the actual existing reconciliation and source/exit/stop guards only.
        # No native launch, process observation, lock, cleanup or receipt write is selected.
        block = body[begin:]
        assert isinstance(block[-1], ast.Assign)
        assert ast.unparse(block[-1].targets[0]) == "data['status']"
        cls.block = compile(ast.Module(body=block, type_ignores=[]), str(SOURCE), "exec")
        cls.transcript = TRANSCRIPT.read_text()

    def reconcile(self, transcript=None, *, exit_code=0, stop_reason=None, source_change=None):
        record = {"exitCode": exit_code}
        if stop_reason is not None:
            record["stopReason"] = stop_reason

        def git(*args):
            if args == ("rev-parse", "HEAD"):
                return "changed" if source_change == "head" else "admitted-source"
            if args == ("status", "--porcelain=v1"):
                return " M owned-input" if source_change == "dirty" else ""
            if args == ("rev-parse", "HEAD:owned-package"):
                return "changed" if source_change == "tree" else "admitted-tree"
            raise AssertionError("Unexpected Git operation in pure reconciliation")

        ns = {"re": re, "collections": collections,
              "final_text": self.transcript if transcript is None else transcript,
              "EXPECTED_METHODS": self.expected, "data": record,
              "SOURCE": "admitted-source", "ROOT": pathlib.Path("/admitted-checkout"),
              "BINDING": {"packageTrees": {"owned-package": "admitted-tree"},
                          "sourceAndPinHashes": {"owned-input": "admitted-hash"}},
              "git": git, "digest": lambda _: "changed" if source_change == "hash" else "admitted-hash"}
        exec(self.block, ns)
        return record

    def test_actual_native_transcript_counts_eleven_methods_and_separate_run_metadata(self):
        self.assertEqual(hashlib.sha256(TRANSCRIPT.read_bytes()).hexdigest(), TRANSCRIPT_SHA256)
        result = self.reconcile()
        self.assertTrue(result["focused11Passed"])
        self.assertEqual(result["status"], "FOCUSED_ORIGINAL_MCP_WIRE_11_PASSED")
        observed = result["reconciliation"]
        expected = {name + "()": 1 for name in self.expected}
        self.assertEqual(observed["starts"], expected)
        self.assertEqual(observed["terminals"], expected)
        self.assertEqual(observed["states"], {"passed": 11})
        self.assertEqual(observed["methodStarts"], 11)
        self.assertEqual(observed["methodTerminals"], 11)
        self.assertEqual(observed["summaryRows"], [("11", "passed")])
        self.assertEqual(observed["reportedPassedCount"], 11)
        self.assertTrue(result["sourceUnchanged"])

    def test_missing_or_duplicate_real_method_rows_fail_closed(self):
        first = self.expected[0] + "()"
        start = next(line for line in self.transcript.splitlines(True)
                     if "Test " + first + " started." in line)
        terminal = next(line for line in self.transcript.splitlines(True)
                        if "Test " + first + " passed after " in line)
        for name, raw in [("missing-start", self.transcript.replace(start, "", 1)),
                          ("missing-terminal", self.transcript.replace(terminal, "", 1)),
                          ("duplicate-start", self.transcript + start),
                          ("duplicate-terminal", self.transcript + terminal)]:
            with self.subTest(name=name):
                self.assertFalse(self.reconcile(raw)["focused11Passed"])

    def test_unexpected_method_names_are_not_filtered_as_run_metadata(self):
        for name in ["unexpected()", "run()", "run with unexpected label"]:
            raw = self.transcript + f"◇ Test {name} started.\n✔ Test {name} passed after 0.001 seconds.\n"
            with self.subTest(name=name):
                result = self.reconcile(raw)
                self.assertFalse(result["focused11Passed"])
                self.assertIn(name, result["reconciliation"]["starts"])
                self.assertIn(name, result["reconciliation"]["terminals"])

    def test_failed_skipped_or_suite_skip_rows_never_become_pass(self):
        original = "Test " + self.expected[0] + "() passed after "
        for status in ["failed", "skipped"]:
            with self.subTest(status=status):
                raw = self.transcript.replace(original, original.replace("passed", status), 1)
                self.assertFalse(self.reconcile(raw)["focused11Passed"])
        raw = self.transcript + "↷ Suite unrelated skipped after 0.001 seconds.\n"
        self.assertFalse(self.reconcile(raw)["focused11Passed"])

    def test_summary_is_still_required_exact_and_nonfailed(self):
        summary = next(line for line in self.transcript.splitlines(True) if "Test run with 11 tests " in line)
        for name, raw in [("missing", self.transcript.replace(summary, "", 1)),
                          ("wrong-count", self.transcript.replace(summary, summary.replace("11 tests", "10 tests"), 1)),
                          ("duplicate", self.transcript + summary),
                          ("failed", self.transcript.replace(summary, summary.replace("passed", "failed"), 1)),
                          ("malformed", self.transcript.replace(summary, summary.replace("11 tests", "eleven tests"), 1))]:
            with self.subTest(name=name):
                self.assertFalse(self.reconcile(raw)["focused11Passed"])

    def test_exit_stop_and_each_original_source_guard_remain_required(self):
        self.assertFalse(self.reconcile(exit_code=1)["focused11Passed"])
        stopped = self.reconcile(stop_reason="ORIGINAL_3600_SECOND_SWIFT_PHASE_DEADLINE")
        self.assertFalse(stopped["focused11Passed"])
        self.assertEqual(stopped["status"], "FOCUSED_ORIGINAL_MCP_WIRE_STOPPED")
        for changed in ["head", "dirty", "tree", "hash"]:
            with self.subTest(changed=changed):
                with self.assertRaisesRegex(AssertionError, "Source or pinned package inputs changed"):
                    self.reconcile(source_change=changed)


if __name__ == "__main__":
    unittest.main(verbosity=2)
