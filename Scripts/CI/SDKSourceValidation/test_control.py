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

from continuation import validate_api, admit_archive, validate_source_continuity
from quota_continuation import parse_original_quota_failure, validate_unchanged_declarations, admit_quota_archive
from completed_quota import validate_recorded_scope, admit_completed_quota_archive


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

    def test_reviewed_test_only_successor_preserves_all_original_protected_guards(self):
        fixed = CONFIG["continuation"]
        source = "35d26911f70794a41361cee710b1fed24a35e269"
        inputs = {**admitted_inputs(), "exact_test_selector": fixed["selector"], CONFIG["sourceInput"]: source}
        environment = {"GITHUB_EVENT_NAME": "workflow_dispatch", "GITHUB_REPOSITORY": "davidpovarsky/hanlin-ai",
                       "HANLIN_SDK_SOURCE_SHA": source}
        self.assertEqual(control.validate_inputs(inputs, environment), source)
        original = control.protected_blobs(fixed["source"])
        successor = control.protected_blobs(source)
        self.assertEqual(original, CONFIG["protectedBlobs"])
        self.assertEqual(len(original), 19)
        self.assertEqual(set(successor), set(original))
        changed = [path for path in original if original[path] != successor[path]]
        change, = fixed["reviewedSourceSuccessors"][source]["inventoryChanges"]
        self.assertEqual(changed, [change["after"]["path"]])
        self.assertEqual(successor[changed[0]], change["after"]["blob"])
        for changes in ({"testflight_upload": "true"}, {"runtime_reuse_artifacts_run_id": "45958390748"},
                        {CONFIG["sourceInput"]: "f" * 40}):
            with self.subTest(changes=changes), self.assertRaises(RuntimeError):
                control.validate_inputs({**inputs, **changes}, environment)

    def test_complete_original_inventory_admits_only_the_reviewed_test_row(self):
        fixed = CONFIG["continuation"]
        source = "35d26911f70794a41361cee710b1fed24a35e269"
        fixture = (HERE / "Fixtures/original-45954793309-source-files.json").read_bytes()
        self.assertEqual(len(fixture), fixed["members"]["original-source-files.json"]["bytes"])
        self.assertEqual(hashlib.sha256(fixture).hexdigest(), fixed["members"]["original-source-files.json"]["sha256"])
        original = json.loads(fixture)
        change, = fixed["reviewedSourceSuccessors"][source]["inventoryChanges"]
        current = [change["after"] if row["path"] == change["before"]["path"] else row for row in original]
        baseline = validate_source_continuity(original, original, fixed["source"], fixed)
        self.assertEqual(baseline["unchangedSourceFiles"], 1005)
        admitted = validate_source_continuity(original, current, source, fixed)
        self.assertEqual(admitted["unchangedSourceFiles"], 1004)
        self.assertEqual(admitted["reviewedInventoryChanges"], [change])
        self.assertEqual(admitted["originalSource"], fixed["source"])
        self.assertEqual(admitted["currentSource"], source)
        variants = [("unchanged old test", original), ("missing file", current[:-1]),
                    ("duplicate file", current + [current[0]]),
                    ("foreign file", current + [{**current[0], "path": "Packages/Foreign.swift"}])]
        for prefix in ("Packages/HanlinAgentSDK/Sources/", "Packages/HanlinAgentSDK/Package.resolved",
                       "AI_HLY.xcodeproj/", "Fixtures/Widgets/", change["after"]["path"]):
            variant = copy.deepcopy(current)
            row = next(row for row in variant if row["path"].startswith(prefix))
            row["sha256"] = "0" * 64
            variants.append((prefix, variant))
        for name, rows in variants:
            with self.subTest(name=name), self.assertRaises(RuntimeError):
                validate_source_continuity(original, rows, source, fixed)
        with self.assertRaises(RuntimeError):
            validate_source_continuity(original, current, fixed["source"], fixed)
        with self.assertRaises(RuntimeError):
            validate_source_continuity(original, current, "f" * 40, fixed)
        self.assertEqual(json.loads(fixture), original)

    def test_actual_failed_quota_terminal_reuses_only_five_exact_passes(self):
        fixture = HERE / "Fixtures/original-45963272356-quota-terminal.log"
        provenance = json.loads((HERE / "Fixtures/original-45963272356-quota-terminal-provenance.json").read_text())
        self.assertEqual(len(fixture.read_bytes()), provenance["terminalBytes"])
        self.assertEqual(hashlib.sha256(fixture.read_bytes()).hexdigest(), provenance["terminalSHA256"])
        fixed = CONFIG["quotaContinuation"]
        result = parse_original_quota_failure(fixture.read_text(), fixed, CONFIG["suites"][1])
        self.assertEqual((result["methodCount"], result["caseCount"]), (5, 5))
        self.assertEqual(result["originalSuiteStatus"], "FAILED")
        self.assertEqual(result["originalFailedMethod"], fixed["failedMethod"])
        self.assertNotIn(fixed["failedMethod"], result["methods"])
        self.assertEqual(set(result["methods"]), {x["method"] for x in fixed["unchangedDeclarations"]})

    def test_quota_reuse_refuses_changed_failure_partial_foreign_duplicate_or_skipped_output(self):
        original = (HERE / "Fixtures/original-45963272356-quota-terminal.log").read_text()
        passed = next(x for x in original.splitlines(True) if x.startswith("✔ Test "))
        started = next(x for x in original.splitlines(True) if x.startswith("◇ Test simultaneous"))
        variants = [original.replace(passed, ""), original + passed, original.replace(started, ""),
            original + "◇ Test foreign() started.\n", original + "✔ Test foreign() passed after 0.1 seconds.\n",
            original + "◇ Test foreign(value:) started.\n", original + "◇ Test run started.\n",
            original + "◇ Test ignored() skipped.\n",
            original.replace("with 6 tests in 1 suite failed", "with 5 tests in 1 suite failed"),
            original.replace("ChatCodeFencePayloadRetentionTests.swift:44:9", "ChatCodeFencePayloadRetentionTests.swift:45:9"),
            original.replace("Snapshot(bytes: 13, payloads: 1)", "Snapshot(bytes: 0, payloads: 0)"),
            original.replace("with 1 issue.", "with 2 issues.", 1),
            original.replace("aka 'ChatCodeFencePayloadRetentionTests'", "aka 'ForeignSuite'")]
        for index, variant in enumerate(variants):
            with self.subTest(index=index), self.assertRaises(RuntimeError):
                parse_original_quota_failure(variant, CONFIG["quotaContinuation"], CONFIG["suites"][1])

    def test_lifetime_successor_requires_all_five_full_declarations_and_both_original_source_closures(self):
        fixed = CONFIG["quotaContinuation"]
        source, = fixed["reviewedSourceSuccessors"]
        old_test = (HERE / "Fixtures/original-35d-quota-test.swift").read_bytes()
        new_test = (HERE / "Fixtures/reviewed-0ae-quota-test.swift").read_bytes()
        names = validate_unchanged_declarations(old_test, new_test, fixed)
        self.assertEqual(set(names), set(CONFIG["suites"][1]["expectedMethods"]) - {fixed["failedMethod"]})
        for row in fixed["unchangedDeclarations"]:
            variant = new_test.replace(row["originalDeclaration"].encode(), row["originalDeclaration"].replace("#expect", "#require", 1).encode(), 1)
            with self.subTest(method=row["method"]), self.assertRaises(RuntimeError):
                validate_unchanged_declarations(old_test, variant, fixed)
        with self.assertRaises(RuntimeError):
            validate_unchanged_declarations(old_test, new_test + fixed["unchangedDeclarations"][0]["originalDeclaration"].encode(), fixed)
        for settings, fixture in ((CONFIG["continuation"], "original-45954793309-source-files.json"),
                                  (fixed, "original-45963272356-source-files.json")):
            raw = (HERE / "Fixtures" / fixture).read_bytes()
            self.assertEqual(hashlib.sha256(raw).hexdigest(), settings["members"]["original-source-files.json"]["sha256"])
            original = json.loads(raw)
            change, = settings["reviewedSourceSuccessors"][source]["inventoryChanges"]
            current = [change["after"] if x["path"] == change["before"]["path"] else x for x in original]
            self.assertEqual(control.blob_sha(new_test), change["after"]["blob"])
            self.assertEqual(hashlib.sha256(new_test).hexdigest(), change["after"]["sha256"])
            result = validate_source_continuity(original, current, source, settings)
            self.assertEqual((result["originalSourceFiles"], result["unchangedSourceFiles"]), (1005, 1004))
            self.assertEqual(result["reviewedInventoryChanges"], [change])
            for prefix in ("Packages/HanlinAgentSDK/Sources/", "Packages/HanlinPlatform/Sources/",
                           "Packages/HanlinPresentationSDK/Sources/", "AI_HLY.xcodeproj/", change["after"]["path"]):
                variant = copy.deepcopy(current)
                next(x for x in variant if x["path"].startswith(prefix))["sha256"] = "0" * 64
                with self.subTest(original=settings["source"], changed=prefix), self.assertRaises(RuntimeError):
                    validate_source_continuity(original, variant, source, settings)
            self.assertEqual(json.loads(raw), original)
        inputs = {**admitted_inputs(), "exact_test_selector": CONFIG["continuation"]["selector"], CONFIG["sourceInput"]: source}
        self.assertEqual(control.validate_inputs(inputs, {"GITHUB_EVENT_NAME": "workflow_dispatch",
            "GITHUB_REPOSITORY": "davidpovarsky/hanlin-ai", "HANLIN_SDK_SOURCE_SHA": source}), source)
        expected = control.protected_blobs(fixed["source"])
        observed = control.protected_blobs(source)
        self.assertEqual(len(observed), 19)
        self.assertEqual([x for x in expected if expected[x] != observed[x]], [fixed["testPath"]])

    def test_quota_continuation_selects_only_one_new_case_and_preserves_other_routes(self):
        fixed = CONFIG["quotaContinuation"]
        suite = CONFIG["suites"][1]
        original = copy.deepcopy(suite)
        selected = control.selected_quota_suite(suite, True)
        self.assertEqual(selected["filter"], suite["suite"] + "/" + fixed["failedMethod"].removesuffix("()"))
        self.assertEqual(selected["expectedMethods"], {fixed["failedMethod"]: 1})
        self.assertEqual(suite, original)
        for item in CONFIG["suites"]:
            self.assertIs(control.selected_quota_suite(item, False), item)
            if item["name"] != "payload-quota":
                self.assertIs(control.selected_quota_suite(item, True), item)
        prior = parse_original_quota_failure((HERE / "Fixtures/original-45963272356-quota-terminal.log").read_text(), fixed, suite)
        self.assertFalse(set(prior["methods"]) & set(selected["expectedMethods"]))
        self.assertEqual({**prior["methods"], **selected["expectedMethods"]}, suite["expectedMethods"])

    def test_original_quota_api_must_bind_failed_run_exact_artifact_and_all_skipped_siblings(self):
        fixture = json.loads((HERE / "Fixtures/original-45963272356-api-identities.json").read_text())
        fixed = CONFIG["quotaContinuation"]
        validate_api(fixture["run"], fixture["jobs"], fixture["artifact"], fixed)
        for kind, changes in (("run", {"run_attempt": 2}), ("run", {"conclusion": "success"}),
                              ("run", {"head_sha": CONFIG["continuation"]["controllerSHA"]}),
                              ("artifact", {"id": CONFIG["continuation"]["artifactID"]}),
                              ("artifact", {"digest": "sha256:" + "0" * 64}), ("artifact", {"expired": True})):
            variant = copy.deepcopy(fixture); variant[kind].update(changes)
            with self.subTest(kind=kind, changes=changes), self.assertRaises(RuntimeError):
                validate_api(variant["run"], variant["jobs"], variant["artifact"], fixed)
        variant = copy.deepcopy(fixture)
        next(x for x in variant["jobs"]["jobs"] if x["id"] != fixed["jobID"])["conclusion"] = "success"
        with self.assertRaises(RuntimeError):
            validate_api(variant["run"], variant["jobs"], variant["artifact"], fixed)

    def test_quota_continuation_rejects_wrong_archive_before_any_output(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary); archive = root / "wrong.zip"
            archive.write_bytes(b"CONTROL_ONLY_NOT_AN_ACTIONS_ARTIFACT")
            with self.assertRaisesRegex(RuntimeError, "ZIP bytes differ"):
                admit_quota_archive(archive, root, CONFIG["quotaContinuation"], [], {}, control,
                    "0ae1920d316b9592cbad0462bea96a07fd1ca351", b"")
            self.assertEqual(list(root.iterdir()), [archive])

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


class CompletedQuotaControls(unittest.TestCase):
    def test_actual_completed_quota_terminal_accepts_only_its_source_declared_alias(self):
        fixture = HERE / "Fixtures/original-45968129203-quota-terminal.log"
        provenance = json.loads((HERE / "Fixtures/original-45968129203-quota-terminal-provenance.json").read_text())
        self.assertEqual(hashlib.sha256(fixture.read_bytes()).hexdigest(), provenance["terminalSHA256"])
        self.assertEqual(len(fixture.read_bytes()), provenance["terminalBytes"])
        suite = control.selected_quota_suite(CONFIG["suites"][1], True)
        result = control.parse_swift_testing(fixture.read_text(), suite)
        self.assertEqual(result["methods"], {CONFIG["completedQuotaContinuation"]["method"]: 1})
        self.assertEqual(result["reportedSuite"], '"Original code-fence retained payload ownership" (aka \'ChatCodeFencePayloadRetentionTests\')')
        self.assertEqual((result["methodCount"], result["caseCount"]), (1, 1))

    def test_completed_alias_refuses_wrong_pair_duplicate_partial_skip_or_foreign_method(self):
        original = (HERE / "Fixtures/original-45968129203-quota-terminal.log").read_text()
        suite = control.selected_quota_suite(CONFIG["suites"][1], True)
        one = next(x for x in original.splitlines(True) if x.startswith("✔ Test cache"))
        variants = [original.replace("aka 'ChatCodeFencePayloadRetentionTests'", "aka 'ForeignSuite'"),
                    original.replace("Original code-fence retained payload ownership", "Foreign display"),
                    original.replace(" (aka 'ChatCodeFencePayloadRetentionTests')", " (aka 'ChatCodeFencePayloadRetentionTests.extra')"),
                    original + one, original.replace(one, ""),
                    original + "◇ Test foreign() started.\n",
                    original + "◇ Test foreign() skipped.\n",
                    original + "✔ Test foreign() passed after 0.1 seconds.\n",
                    original.replace("with 1 test in 1 suite", "with 0 tests in 1 suite")]
        for variant in variants:
            with self.subTest(length=len(variant)), self.assertRaises(RuntimeError):
                control.parse_swift_testing(variant, suite)

    def test_completed_original_api_and_recorded_scope_are_exact_but_not_archive_admission(self):
        fixed = CONFIG["completedQuotaContinuation"]
        fixture = json.loads((HERE / "Fixtures/original-45968129203-recorded-scope.json").read_text())
        raw = lambda name: fixture[name].encode()
        for name, text in fixture.items():
            self.assertEqual({"bytes": len(text.encode()), "sha256": hashlib.sha256(text.encode()).hexdigest()}, fixed["members"][name])
        run = json.loads((HERE / "Fixtures/original-45968129203-run.json").read_text())
        jobs = json.loads((HERE / "Fixtures/original-45968129203-jobs.json").read_text())
        artifact = json.loads((HERE / "Fixtures/original-45968129203-artifact.json").read_text())
        validate_api(run, jobs, artifact, fixed)
        result = validate_recorded_scope(raw, fixed, json.loads(raw("original-source-files.json")), control, fixed["source"])
        self.assertFalse(result["fullArchiveAdmission"])
        self.assertEqual((len(result["commands"]), len(result["checkouts"]), len(result["product"]["files"])), (90, 18, 267))
        self.assertEqual(result["continuity"]["reviewedInventoryChanges"], [])
        for changed in ({**artifact, "digest": "sha256:" + "0" * 64}, {**artifact, "expired": True}):
            with self.assertRaises(RuntimeError):
                validate_api(run, jobs, changed, fixed)
        with self.assertRaises(RuntimeError):
            validate_api(run, {**jobs, "jobs": jobs["jobs"][:-1]}, artifact, fixed)

    def test_completed_recorded_scope_rejects_late_lock_change_live_worker_and_changed_source(self):
        fixed = CONFIG["completedQuotaContinuation"]
        fixture = json.loads((HERE / "Fixtures/original-45968129203-recorded-scope.json").read_text())
        original = {name: json.loads(text) for name, text in fixture.items()}
        variants = []
        changed = copy.deepcopy(original)
        first = next(iter(changed["payload-quota-posttest-checkouts.json"]))
        changed["payload-quota-posttest-checkouts.json"][first]["head"] = "f" * 40
        variants.append(changed)
        changed = copy.deepcopy(original)
        row = next(x for x in changed["commands.json"] if x["label"] == "payload-quota-tests")
        row["groupCustody"]["groupAbsent"] = False
        changed["result.json"]["commands"] = changed["commands.json"]
        variants.append(changed)
        changed = copy.deepcopy(original)
        changed["result.json"]["error"] = "A different failure"
        variants.append(changed)
        for changed in variants:
            with self.assertRaises(RuntimeError):
                validate_recorded_scope(lambda name: json.dumps(changed[name]).encode(), fixed,
                    original["original-source-files.json"], control, fixed["source"])
        current = copy.deepcopy(original["original-source-files.json"])
        current[0]["sha256"] = "0" * 64
        with self.assertRaises(RuntimeError):
            validate_recorded_scope(lambda name: fixture[name].encode(), fixed, current, control, fixed["source"])
        with self.assertRaises(RuntimeError):
            validate_recorded_scope(lambda name: fixture[name].encode(), fixed,
                original["original-source-files.json"], control, CONFIG["quotaContinuation"]["source"])

    def test_completed_archive_requires_exact_original_zip_before_creating_any_reuse_output(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary); archive = root / "wrong.zip"
            archive.write_bytes(b"CONTROL_ONLY_NOT_AN_ACTIONS_ARTIFACT")
            with self.assertRaisesRegex(RuntimeError, "ZIP bytes differ"):
                admit_completed_quota_archive(archive, root, CONFIG["completedQuotaContinuation"], [], {}, control,
                    CONFIG["completedQuotaContinuation"]["source"])
            self.assertEqual(list(root.iterdir()), [archive])

    def test_console_first_cause_is_bounded_and_redacts_urls_authorization_and_environment_credentials(self):
        cause = "Original parser failed; https://example.invalid/artifact?sig=private-value Bearer abc.def GH-value token=inline-value"
        result = control.console_failure(cause, {"GH_TOKEN": "GH-value"})
        self.assertTrue(result.startswith("Original parser failed;"))
        for private in ("example.invalid", "private-value", "abc.def", "GH-value", "inline-value"):
            self.assertNotIn(private, result)
        self.assertEqual(control.console_failure(None, {}), None)
        self.assertEqual(len(control.console_failure("x" * 3000, {})), 2048)
        self.assertNotIn("\n", control.console_failure("first\nsecond", {}))


if __name__ == "__main__":
    unittest.main()
