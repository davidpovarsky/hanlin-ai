"""New three-case report controls only; all current outcomes here are fixtures."""
import copy
import hashlib
import json
import re
from pathlib import Path
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "Scripts/CI/IntegrationValidation"))
import verify_stop_continuation_delta as report


def write(path, value):
    path.write_text(json.dumps(value, indent=2) + "\n")


class StopContinuationDeltaReportTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.evidence = Path(self.temp.name)
        for name in ("tested-source-commit.txt", "workflow-commit.txt"):
            (self.evidence / name).write_text("EXPLICIT_LOCAL_STOP_DELTA_REPORT_FIXTURE\n")
        (self.evidence / "producer-commit.txt").write_text(report.PRODUCER + "\n")
        write(self.evidence / "tested-source-sha256.json", report.COMPOSED_SOURCE)
        write(self.evidence / "selected-route.json",
              dict(exact_test_selector="HanlinStopContinuationDelta", target_validation_group="agent_sdk_exact_source_proof"))
        write(self.evidence / "process-status.json",
              dict(preparation_exit=0, delta_test_exit=0, ios_build_exit=0,
                   core_test_exit=None, sdk_test_exit=None, baseline_core_exit=None))
        write(self.evidence / "commands.json", [
            dict(name="StopContinuationTests", argv=["xcodebuild", "test", "-scheme", "HanlinPlatform-Package",
                 "-destination", "platform=macOS"] + ["-only-testing:" + s for s in report.SELECTORS], exit_code=0),
            dict(name="IOSBuild", argv=["xcodebuild", "build", "-scheme", "HanlinAgentCore",
                 "-destination", "generic/platform=iOS Simulator"], exit_code=0),
        ])
        nodes = []
        for method in report.METHODS:
            identity = report.SUITE + "/" + method + "()"
            nodes.append(dict(nodeType="Test Case", name=method, nodeIdentifier=identity, result="Passed",
                              nodeIdentifierURL="test://com.apple.xcode/HanlinPlatform/HanlinChatCoreTests/" + identity))
        write(self.evidence / "StopContinuationTests.json", dict(testNodes=nodes))
        (self.evidence / "raw-locks").mkdir()
        locks = []
        for index, package in enumerate(("HanlinAgentSDK", "HanlinPlatform")):
            relative = f"raw-locks/{index:02d}-Package.resolved"
            # Use the retained07431 fixture; the live product may deliberately advance.
            frozen = ROOT / "Scripts/CI/Tests/Fixtures/native-cancellation-07431/delta"
            lock_name = "sdk" if package == "HanlinAgentSDK" else "core"
            raw = (frozen / (lock_name + "-Package.resolved")).read_bytes()
            (self.evidence / relative).write_bytes(raw)
            locks.append(dict(source_path=f"/explicit-fixture/Packages/{package}/Package.resolved",
                              raw_file=relative, sha256=hashlib.sha256(raw).hexdigest()))
        write(self.evidence / "post-build-resolution.json", locks)

    def tearDown(self):
        self.temp.cleanup()

    def test_exact_three_fixture_cases_do_not_claim_any_prior_reuse_or_native_model(self):
        actual = report.summarize(self.evidence)
        self.assertEqual(actual["status"], "PASS", actual["errors"])
        self.assertEqual(len(actual["cases"]), 3)
        self.assertEqual(actual["reused_cases"], [])
        self.assertFalse(actual["shipping_native_tool_capability"])
        self.assertEqual(actual["system_model_generation"], "NOT_RUN")
        self.assertIsNone(actual["process_status"]["baseline_core_exit"])

    def test_raw_locks_keep_exactly_one_pinned_producer_after_digest_update(self):
        self.assertEqual(report.summarize(self.evidence)["status"], "PASS")
        posts = self.evidence / "post-build-resolution.json"
        original_posts = posts.read_bytes()
        for index, lock in enumerate(json.loads(original_posts)):
            path = self.evidence / lock["raw_file"]
            original = path.read_bytes()
            for mutation in ("revision", "missing", "duplicate"):
                with self.subTest(package=index, mutation=mutation):
                    value = json.loads(original)
                    producer = next(pin for pin in value["pins"] if pin["identity"] == "swift-ai-sdk")
                    if mutation == "revision":
                        producer["state"]["revision"] = "0" * 40
                    elif mutation == "missing":
                        value["pins"] = [pin for pin in value["pins"] if pin["identity"] != "swift-ai-sdk"]
                    else:
                        value["pins"].append(copy.deepcopy(producer))
                    try:
                        write(path, value)
                        changed_posts = json.loads(original_posts)
                        changed_posts[index]["sha256"] = hashlib.sha256(path.read_bytes()).hexdigest()
                        write(posts, changed_posts)
                        result = report.summarize(self.evidence)
                        self.assertEqual(result["status"], "BLOCKED")
                        self.assertIn("Raw lock is not pinned07431.", result["errors"])
                    finally:
                        path.write_bytes(original)
                        posts.write_bytes(original_posts)

    def test_case_process_pin_and_composed_source_adversaries_block(self):
        mutations = [
            ("missing-case", "StopContinuationTests.json", lambda d: d["testNodes"].pop()),
            ("duplicate-case", "StopContinuationTests.json", lambda d: d["testNodes"].append(copy.deepcopy(d["testNodes"][0]))),
            ("failed-case", "StopContinuationTests.json", lambda d: d["testNodes"][0].update(result="Failed")),
            ("skipped-case", "StopContinuationTests.json", lambda d: d["testNodes"][0].update(result="Skipped")),
            ("false-pass", "StopContinuationTests.json", lambda d: d["testNodes"][0].update(children=[dict(nodeType="Failure Message", name="failed")])),
            ("wrong-route", "selected-route.json", lambda d: d.update(exact_test_selector="HanlinNativeToolCandidate")),
            ("old-replay-exit", "process-status.json", lambda d: d.update(core_test_exit=0)),
            ("wrong-delta-exit", "process-status.json", lambda d: d.update(delta_test_exit=65)),
            ("wrong-build-exit", "process-status.json", lambda d: d.update(ios_build_exit=65)),
            ("wrong-selector", "commands.json", lambda d: d[0]["argv"].append("-only-testing:HanlinChatCoreTests")),
            ("extra-process", "commands.json", lambda d: d.append(copy.deepcopy(d[0]))),
            ("missing-build", "commands.json", lambda d: d.pop()),
            ("duplicate-lock", "post-build-resolution.json", lambda d: d.__setitem__(1, copy.deepcopy(d[0]))),
            ("wrong-composed-source", "tested-source-sha256.json", lambda d: d.update({next(iter(report.COMPOSED_SOURCE)): "changed"})),
        ]
        for label, name, mutate in mutations:
            with self.subTest(label=label):
                path = self.evidence / name
                original = path.read_bytes()
                data = json.loads(original)
                mutate(data); write(path, data)
                self.assertEqual(report.summarize(self.evidence)["status"], "BLOCKED")
                path.write_bytes(original)
        pin = self.evidence / "producer-commit.txt"
        pin.write_text("e7bf34111e603ca977becd007dd4e5bb109af857\n")
        self.assertEqual(report.summarize(self.evidence)["status"], "BLOCKED")

    def test_function_selectors_preserve_declared_singleton_identifiers(self):
        source = (ROOT / "Packages/HanlinPlatform/Tests/HanlinChatCoreTests/HanlinAppleToolInputBoundaryTests.swift").read_text()
        suite = source.split("struct HanlinProducerStopContinuationTests {", 1)[1]
        # These three cases have not run yet. Bind to their actual @Test
        # declarations, using the same complete singleton signature preserved
        # in authenticated Swift Testing result identifiers.
        signatures = re.findall(
            r"@Test\([^\n]*\)\s+@MainActor\s+func\s+([A-Za-z]\w*\(\))\s+async\s+throws",
            suite,
        )
        self.assertEqual(len(signatures), 3)
        self.assertEqual(len(set(signatures)), 3)
        expected = ["HanlinChatCoreTests/HanlinProducerStopContinuationTests/" + signature
                    for signature in signatures]
        self.assertCountEqual(report.SELECTORS, expected)
        commands = json.loads((self.evidence / "commands.json").read_text())
        selected = next(command for command in commands if command["name"] == "StopContinuationTests")
        selected["argv"] = [
            argument[:-2] if argument.startswith("-only-testing:") and argument.endswith("()")
            else argument for argument in selected["argv"]
        ]
        write(self.evidence / "commands.json", commands)
        self.assertEqual(report.summarize(self.evidence)["status"], "BLOCKED")

    def test_frozen_fixture_inventory_retains_exact_stop_labels_and_no_old_suite_selection(self):
        text = (ROOT / "Packages/HanlinPlatform/Tests/HanlinChatCoreTests/HanlinAppleToolInputBoundaryTests.swift").read_text()
        selected = text.split("struct HanlinProducerStopContinuationTests {", 1)[1]
        self.assertEqual(selected.count("@Test("), 3)
        self.assertEqual(selected.count("firstFinishReason: .stop"), 3)
        self.assertIn("kind: .openAI, input: input, requiresApproval: false", selected)
        self.assertIn("outcome.providerCalls == 1", selected)
        self.assertIn("outcome.providerFinishReasons == [.stop]", selected)
        self.assertIn("outcome.providerFinishReasons == [.stop, .stop]", selected)
        self.assertIn('outcome.stepFinishReasons.first == "stop"', selected)
        self.assertIn('outputs.first?.toolCallId == "native_call_1"', selected)
        self.assertIn("outputs.first?.output == expected", selected)
        runner = (ROOT / "Scripts/CI/IntegrationValidation/run_stop_continuation_delta.py").read_text()
        self.assertIn('selector not in {"HanlinStopContinuationDelta", "HanlinNativeToolCancellationRecheck"}', runner)
        self.assertIn('inputs.get("target_validation_group") != "agent_sdk_exact_source_proof"', runner)
        self.assertIn('test("StopContinuationTests", core, core_scheme, SELECTORS)', runner)
        self.assertNotIn('test("CoreTests"', runner)
        self.assertNotIn('test("SDKTests"', runner)
        self.assertNotIn('test("BaselineCoreTests"', runner)


if __name__ == "__main__":
    unittest.main()
