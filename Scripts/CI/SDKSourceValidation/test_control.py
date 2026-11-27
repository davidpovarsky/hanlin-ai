"""Control-only tests. These do not compile or execute a Swift/native product."""
import ast
import copy
import hashlib
import importlib.util
import json
from pathlib import Path
import re
import tempfile
import unittest
from unittest.mock import patch


HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("original_sdk_control", HERE / "run.py")
control = importlib.util.module_from_spec(spec)
spec.loader.exec_module(control)
CONFIG = control.CONFIG

from continuation import validate_api, admit_archive


def admitted_inputs():
    return {**{name: "false" for name in control.FALSE_INPUTS},
            **{name: "" for name in control.EMPTY_INPUTS},
            "target_validation_group": CONFIG["group"], "exact_test_selector": CONFIG["selector"],
            CONFIG["sourceInput"]: CONFIG["referenceSource"]}


def job_value(expression, inputs, event="workflow_dispatch"):
    # Closed source-review evaluator, not a replacement for GitHub execution.
    expression = expression.removeprefix("${{").removesuffix("}}").strip()
    def value(match):
        path = match[0]
        if path.startswith("inputs."):
            return repr(inputs.get(path.removeprefix("inputs."), ""))
        if path == "github.event_name":
            return repr(event)
        if path.startswith("needs."):
            return repr("")  # Planner is not admitted in this closed SDK route.
        raise AssertionError("Unexpected workflow variable: " + path)
    expression = re.sub(r"(?:inputs|github|needs)\.[A-Za-z0-9_.-]+", value, expression)
    expression = expression.replace("&&", " and ").replace("||", " or ")
    expression = re.sub(r"!(?!=)", " not ", expression).strip()
    tree = ast.parse(expression, mode="eval")
    permitted = (ast.Expression, ast.BoolOp, ast.And, ast.Or, ast.UnaryOp, ast.Not,
                 ast.Compare, ast.Eq, ast.NotEq, ast.Constant, ast.Call, ast.Name, ast.Load)
    for node in ast.walk(tree):
        if not isinstance(node, permitted):
            raise AssertionError("Unexpected workflow expression")
        if isinstance(node, ast.Call):
            if not isinstance(node.func, ast.Name) or node.func.id not in ("always", "cancelled") or node.args:
                raise AssertionError("Unexpected workflow call")
    return bool(eval(compile(tree, "<closed workflow predicate>", "eval"),
                     {"__builtins__": {}, "always": lambda: True, "cancelled": lambda: False}))


class ControlTests(unittest.TestCase):
    def test_explicit_source_and_side_effect_inputs_fail_closed(self):
        inputs = admitted_inputs()
        environment = {"GITHUB_EVENT_NAME": "workflow_dispatch", "GITHUB_REPOSITORY": "davidpovarsky/hanlin-ai",
                       "HANLIN_SDK_SOURCE_SHA": CONFIG["referenceSource"]}
        self.assertEqual(control.validate_inputs(inputs, environment), CONFIG["referenceSource"])
        for changes in ({CONFIG["sourceInput"]: "main"}, {CONFIG["sourceInput"]: ""},
                        {"runtime_publish_release": "true"}, {"testflight_upload": "true"},
                        {"exact_test_selector": "HanlinNativeToolCancellationRecheck"},
                        {"scripting_package_test_filter": "AllTests"}):
            with self.subTest(changes=changes), self.assertRaises(RuntimeError):
                control.validate_inputs({**inputs, **changes}, environment)
        with self.assertRaises(RuntimeError):
            control.validate_inputs(inputs, {**environment, "HANLIN_SDK_SOURCE_SHA": "f" * 40})
        with self.assertRaises(RuntimeError):
            control.validate_inputs(inputs, {**environment, "GITHUB_EVENT_NAME": "push"})
        with self.assertRaises(RuntimeError):
            control.validate_inputs({**inputs, CONFIG["sourceInput"]: "f" * 40},
                                    {**environment, "HANLIN_SDK_SOURCE_SHA": "f" * 40})

    def test_actual_original_terminal_has_five_methods_and_seven_cases(self):
        fixture = HERE / "Fixtures/original-385-stop-terminal.log"
        provenance = json.loads((HERE / "Fixtures/original-385-stop-terminal-provenance.json").read_text())
        self.assertEqual(hashlib.sha256(fixture.read_bytes()).hexdigest(), provenance["terminalSHA256"])
        result = control.parse_swift_testing(fixture.read_text(), CONFIG["suites"][0])
        self.assertEqual(result["methodCount"], 5)
        self.assertEqual(result["caseCount"], 7)

    def test_actual_2403_terminal_distinguishes_method_and_individual_case_success(self):
        fixture = HERE / "Fixtures/original-45954793309-stop-terminal.log"
        provenance = json.loads((HERE / "Fixtures/original-45954793309-stop-terminal-provenance.json").read_text())
        self.assertEqual(hashlib.sha256(fixture.read_bytes()).hexdigest(), provenance["terminalSHA256"])
        result = control.parse_swift_testing(fixture.read_text(), CONFIG["suites"][0])
        self.assertEqual(result["methodCount"], 5)
        self.assertEqual(result["caseCount"], 7)
        self.assertEqual(result["arguments"]["stopAtEOFJoinsConfirmedReceiptWorkerBeforeReleasingRun(stopAtEOF:)"], ["false", "true"])

    def test_2403_refuses_partial_duplicate_foreign_or_wrong_typed_cases(self):
        original = (HERE / "Fixtures/original-45954793309-stop-terminal.log").read_text()
        one = next(x for x in original.splitlines(True) if x.startswith("✔ Test case passing"))
        variants = [original.replace(one, ""), original + one,
            "".join(x for x in original.splitlines(True) if not x.startswith("✔ Test case passing")),
            original.replace("false (Swift.Bool)", "false (Other.Bool)", 1),
            original.replace("false (Swift.Bool)", "0 (Swift.Int)", 1),
            original + "✔ Test case passing 1 argument other → true (Swift.Bool) to foreign(value:) passed after 0.1 seconds.\n",
            original + "◇ Test foreign() started.\n",
            original + "✔ Test foreign() passed after 0.1 seconds.\n",
            original + "✔ Test run with 5 tests in 1 suite passed after 0.204 seconds.\n"]
        for variant in variants:
            with self.subTest(length=len(variant)), self.assertRaises(RuntimeError):
                control.parse_swift_testing(variant, CONFIG["suites"][0])

    def test_continuation_only_admits_the_fixed_run_source_and_unchanged_side_effect_inputs(self):
        fixed = CONFIG["continuation"]
        inputs = {**admitted_inputs(), "exact_test_selector": fixed["selector"], CONFIG["sourceInput"]: fixed["source"]}
        environment = {"GITHUB_EVENT_NAME": "workflow_dispatch", "GITHUB_REPOSITORY": "davidpovarsky/hanlin-ai",
                       "HANLIN_SDK_SOURCE_SHA": fixed["source"]}
        self.assertEqual(control.validate_inputs(inputs, environment), fixed["source"])
        for changes in ({CONFIG["sourceInput"]: CONFIG["referenceSource"]}, {"runtime_bundle_artifact_run_id": "45954793309"},
                        {"testflight_upload": "true"}, {"exact_test_selector": fixed["selector"] + "-other"}):
            with self.subTest(changes=changes), self.assertRaises(RuntimeError):
                control.validate_inputs({**inputs, **changes}, environment)

    def test_continuation_api_refuses_foreign_attempt_artifact_or_executed_sibling_job(self):
        fixture = json.loads((HERE / "Fixtures/original-45954793309-api-identities.json").read_text())
        fixed = CONFIG["continuation"]
        validate_api(fixture["run"], fixture["jobs"], fixture["artifact"], fixed)
        for kind, changes in (("run", {"run_attempt": 2}), ("run", {"conclusion": "success"}),
                              ("run", {"head_sha": "f" * 40}), ("artifact", {"expired": True}),
                              ("artifact", {"digest": "sha256:" + "0" * 64}), ("artifact", {"size_in_bytes": 1})):
            variant = copy.deepcopy(fixture); variant[kind].update(changes)
            with self.subTest(kind=kind, changes=changes), self.assertRaises(RuntimeError):
                validate_api(variant["run"], variant["jobs"], variant["artifact"], fixed)
        variant = copy.deepcopy(fixture)
        next(x for x in variant["jobs"]["jobs"] if x["id"] != fixed["jobID"])["conclusion"] = "success"
        with self.assertRaises(RuntimeError):
            validate_api(variant["run"], variant["jobs"], variant["artifact"], fixed)

    def test_continuation_refuses_wrong_archive_before_any_source_or_product_admission(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary); archive = root / "wrong.zip"
            archive.write_bytes(b"CONTROL_ONLY_NOT_AN_ACTIONS_ARTIFACT")
            with self.assertRaisesRegex(RuntimeError, "ZIP bytes differ"):
                admit_archive(archive, root, CONFIG["continuation"], [], {}, control)
            self.assertEqual(list(root.iterdir()), [archive])

    def test_partial_duplicate_skipped_or_zero_test_output_is_never_acceptance(self):
        original = (HERE / "Fixtures/original-385-stop-terminal.log").read_text()
        case = next(line for line in original.splitlines(True) if "changeAccount → false" in line)
        passed = next(line for line in original.splitlines(True) if line.startswith("✔ Test stopPreserves"))
        variants = [original.replace(case, ""), original + passed,
                    original.replace("with 2 test cases passed", "with 1 test cases passed", 1),
                    original.replace("Test run with 5 tests", "Test run with 0 tests"),
                    original + "◇ Test missing() skipped.\n", original + "✘ Test failure() failed.\n",
                    original.replace("Suite AgentSessionTests", "Suite ForeignSuite"),
                    original + "✔ Suite AgentSessionTests passed after 0.1 seconds.\n"]
        for variant in variants:
            with self.subTest(length=len(variant)), self.assertRaises(RuntimeError):
                control.parse_swift_testing(variant, CONFIG["suites"][0])

    def test_actual_dependency_revision_and_repository_must_match_published_lock(self):
        original = {"package": {"revision": "a" * 40, "location": "https://github.com/owner/package"}}
        control.validate_lock(original, original, {"package"})
        for actual in ({}, {"package": {"revision": "b" * 40, "location": original["package"]["location"]}},
                       {"package": {"revision": "a" * 40, "location": "https://github.com/other/package"}},
                       {**original, "unknown": original["package"]}):
            with self.subTest(actual=actual), self.assertRaises(RuntimeError):
                control.validate_lock(actual, original, {"package"})

    def test_original_apple_swift_build_products_are_retained(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            output = root / "evidence"
            output.mkdir()
            build = root / "original-build"
            binary = build / "apple/Products/Debug/Fixture.xctest/Contents/MacOS/Fixture"
            binary.parent.mkdir(parents=True)
            binary.write_bytes(b"CONTROL_FIXTURE_ONLY_NOT_A_NATIVE_BINARY")
            run = control.Run(root, output)
            run.build_roots.append(("control-fixture", build))
            run.preserve_products()
            self.assertEqual(len(run.products), 1)
            self.assertEqual(run.products[0]["files"][0]["sha256"], hashlib.sha256(binary.read_bytes()).hexdigest())
            self.assertTrue((output / "control-fixture-original-products.tar").is_file())

    def test_exited_leader_does_not_hide_its_remaining_original_group(self):
        class OriginalLeader:
            pid = 123456
            def poll(self):
                return 0
        calls = []
        observations = iter([True, False])
        def group_signal(pgid, signum):
            self.assertEqual(pgid, OriginalLeader.pid)
            calls.append(signum)
            if signum == 0 and not next(observations):
                raise ProcessLookupError()
        with patch.object(control.os, "killpg", group_signal):
            result = control.finish_original_process_group(OriginalLeader(), OriginalLeader.pid)
        self.assertTrue(result["groupAbsent"])
        self.assertTrue(result["abnormalCleanup"])
        self.assertEqual(result["signals"], [int(control.signal.SIGTERM)])
        self.assertEqual(calls, [0, control.signal.SIGTERM, 0])

        with patch.object(control.os, "killpg") as kill, patch.object(control.time, "monotonic", side_effect=[0, 4, 5, 11]):
            result = control.finish_original_process_group(OriginalLeader(), OriginalLeader.pid)
        self.assertFalse(result["groupAbsent"])
        self.assertEqual(result["signals"], [int(control.signal.SIGTERM), int(control.signal.SIGKILL)])
        self.assertTrue(all(call.args[0] == OriginalLeader.pid for call in kill.call_args_list))

    def test_new_selector_preserves_every_legacy_job_and_only_selects_one_new_job(self):
        workflow = HERE.parents[2] / ".github/workflows/build-ios26-unsigned-ipa.yml"
        actual = {}
        jobs = workflow.read_text().split("\njobs:\n", 1)[1]
        for match in re.finditer(r"^  (?P<name>[a-z0-9-]+):\n(?P<body>.*?)(?=^  [a-z0-9-]+:|\Z)", jobs, re.M | re.S):
            condition = re.search(r"^    if: (.+)$", match["body"], re.M)
            self.assertIsNotNone(condition)
            actual[match["name"]] = condition[1]
        prior = json.loads((HERE / "Fixtures/original-workflow-conditions.json").read_text())["conditions"]
        self.assertEqual(set(actual), set(prior) | {"sdk-original-obligations"})
        for name, condition in prior.items():
            expected = condition
            if name in ("agent-sdk-proof", "presentation-sdk-proof"):
                guards = ("${{ inputs.exact_test_selector != '" + CONFIG["selector"] + "' && " +
                          "inputs.exact_test_selector != '" + CONFIG["continuation"]["selector"] + "' && ")
                expected = condition.replace("${{ ", guards, 1)
            self.assertEqual(actual[name], expected)
        inputs = {key: (False if value == "false" else value) for key, value in admitted_inputs().items()}
        self.assertEqual([name for name, condition in actual.items() if job_value(condition, inputs)],
                         ["sdk-original-obligations"])
        continued = {**inputs, "exact_test_selector": CONFIG["continuation"]["selector"],
                     CONFIG["sourceInput"]: CONFIG["continuation"]["source"]}
        self.assertEqual([name for name, condition in actual.items() if job_value(condition, continued)],
                         ["sdk-original-obligations"])
        for selector in ("", "HanlinPresentationSDK", "HanlinAgentCoreTests,HanlinChatCoreTests",
                         "HanlinNativeToolCancellationRecheck"):
            variant = {**inputs, "exact_test_selector": selector}
            self.assertEqual({name: job_value(condition, variant) for name, condition in prior.items()},
                             {name: job_value(actual[name], variant) for name in prior})
        self.assertFalse(job_value(actual["sdk-original-obligations"], inputs, event="push"))


if __name__ == "__main__":
    unittest.main()
