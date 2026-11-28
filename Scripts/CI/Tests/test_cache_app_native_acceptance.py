"""Source inventory and real xcresult-shape fixtures; these are not native runs."""
import copy
import hashlib
import json
from pathlib import Path
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "Scripts/CI/IntegrationValidation"))
sys.path.insert(0, str(ROOT / "Scripts/CI"))
from verify_cache_app_tests import SUITES, parse_suite, source_inventory, verify_results
from verify_selected_tests import missing_selectors


def result_fixture(inventory):
    """Observed Xcode27 Test Case/Arguments shape with explicit fixture identities."""
    suites = []
    for suite, methods in inventory["suites"].items():
        children = []
        for name, arguments in methods.items():
            identity = suite + "/" + name + ("()" if arguments is None else "(_:)")
            url = "test://com.apple.xcode/AI_HLY/AI_HLYTests/" + identity
            case = {"nodeType": "Test Case", "nodeIdentifier": identity,
                    "nodeIdentifierURL": url, "name": "fixture " + name, "result": "Passed"}
            if arguments is not None:
                case["children"] = [
                    {"nodeType": "Arguments", "name": '"' + values[0] + '"', "result": "Passed",
                     "nodeIdentifierURL": url + "?args=" + hashlib.sha256(
                         values[0].encode()).hexdigest()}
                    for values in arguments]
            children.append(case)
        suites.append({"nodeType": "Test Suite", "name": suite, "children": children})
    return {"testNodes": [{"nodeType": "Test Plan", "children": suites}]}


def cases(data):
    return [case for suite in data["testNodes"][0]["children"] for case in suite["children"]]


class CacheAppAcceptanceTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.inventory = source_inventory(ROOT)
        cls.complete = result_fixture(cls.inventory)

    def inspect(self, data):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "actual-shape-fixture.json"
            path.write_text(json.dumps(data))
            return verify_results(path, self.inventory)

    def test_current_exact_source_inventory_and_complete_invocations(self):
        expected_counts = dict(zip(SUITES, (4, 32, 7, 3)))
        self.assertEqual({suite: len(methods) for suite, methods in self.inventory["suites"].items()},
                         expected_counts)
        self.assertEqual(self.inventory["suites"]["HanlinMiniAppAssistantIntegrationTests"][
            "invalidStructuredOutput"], [
                ('{"count":"seven"}',), ('{"count":9007199254740993}',),
                ('{"count":7,"extra":true}',)])
        report = self.inspect(self.complete)
        self.assertEqual(report["status"], "PASS", report["errors"])
        self.assertEqual(report["expectedMethodCount"], 46)
        self.assertEqual(report["expectedInvocationCount"], 48)
        self.assertEqual(report["observedInvocationCount"], 48)
        self.assertEqual(report["passedInvocationCount"], 48)

    def test_one_pass_per_suite_cannot_satisfy_the_exact_gate(self):
        partial = copy.deepcopy(self.complete)
        for suite in partial["testNodes"][0]["children"]:
            suite["children"] = suite["children"][:1]
        # This fixture reproduces the actual old acceptance gap.
        self.assertEqual(missing_selectors(partial, ["AI_HLYTests/" + suite for suite in SUITES]), [])
        report = self.inspect(partial)
        self.assertEqual(report["status"], "BLOCKED")
        self.assertTrue(any("missing method" in error for error in report["errors"]))

    def test_missing_single_method_and_zero_cases_are_rejected(self):
        partial = copy.deepcopy(self.complete)
        partial["testNodes"][0]["children"][0]["children"].pop()
        for data in (partial, {"testNodes": []}):
            with self.subTest(nodes=bool(data["testNodes"])):
                self.assertEqual(self.inspect(data)["status"], "BLOCKED")

    def test_skipped_unrun_failed_and_expected_failure_methods_are_rejected(self):
        for status in ("Skipped", "Not Run", "Failed", "Expected Failure", None):
            with self.subTest(status=status):
                data = copy.deepcopy(self.complete)
                cases(data)[0]["result"] = status
                report = self.inspect(data)
                self.assertEqual(report["status"], "BLOCKED")
                self.assertEqual(report["nonPassingResultNodes"][0]["result"], status)

    def test_parameterized_aggregate_pass_cannot_replace_any_invocation(self):
        for count in (0, 1, 2):
            with self.subTest(actual_arguments=count):
                data = copy.deepcopy(self.complete)
                parameterized = next(case for case in cases(data) if "children" in case)
                parameterized["children"] = parameterized["children"][:count]
                report = self.inspect(data)
                self.assertEqual(report["status"], "BLOCKED")
                self.assertTrue(any("missing arguments" in error for error in report["errors"]))

    def test_skipped_argument_is_rejected_even_when_method_reports_pass(self):
        data = copy.deepcopy(self.complete)
        parameterized = next(case for case in cases(data) if "children" in case)
        parameterized["children"][1]["result"] = "Skipped"
        report = self.inspect(data)
        self.assertEqual(report["status"], "BLOCKED")
        self.assertEqual(report["observedInvocationCount"], 48)
        self.assertEqual(report["passedInvocationCount"], 47)

    def test_duplicate_method_argument_and_argument_url_are_rejected(self):
        for mutation in ("method", "argument", "url"):
            with self.subTest(mutation=mutation):
                data = copy.deepcopy(self.complete)
                parameterized = next(case for case in cases(data) if "children" in case)
                if mutation == "method":
                    data["testNodes"][0]["children"][0]["children"].append(copy.deepcopy(cases(data)[0]))
                elif mutation == "argument":
                    duplicate = copy.deepcopy(parameterized["children"][0])
                    duplicate["nodeIdentifierURL"] = duplicate["nodeIdentifierURL"].split("?")[0] + "?args=" + "a" * 64
                    parameterized["children"].append(duplicate)
                else:
                    parameterized["children"][1]["nodeIdentifierURL"] = parameterized["children"][0]["nodeIdentifierURL"]
                self.assertEqual(self.inspect(data)["status"], "BLOCKED")

    def test_changed_argument_bytes_wrong_target_and_failure_diagnostics_are_rejected(self):
        for mutation in ("argument", "target", "diagnostic", "unknown-method"):
            with self.subTest(mutation=mutation):
                data = copy.deepcopy(self.complete)
                if mutation == "argument":
                    parameterized = next(case for case in cases(data) if "children" in case)
                    parameterized["children"][0]["name"] = '"{ "count": "seven" }"'
                elif mutation == "target":
                    case = cases(data)[0]
                    case["nodeIdentifierURL"] = case["nodeIdentifierURL"].replace("/AI_HLYTests/", "/OtherTests/")
                elif mutation == "diagnostic":
                    cases(data)[0]["children"] = [{"nodeType": "Test Failure", "name": "retained failure"}]
                else:
                    case = cases(data)[0]
                    case["nodeIdentifier"] = "HanlinPromptCachingIntegrationTests/undeclaredMethod()"
                self.assertEqual(self.inspect(data)["status"], "BLOCKED")


class SwiftDeclarationInventoryTests(unittest.TestCase):
    def test_comments_strings_helpers_and_interpolation_cannot_add_test_identities(self):
        source = r'''
        // @Test func commentGhost() {}
        /* nested /* @Test func ghost() {} */ block */
        @Suite("Fixture") struct Fixture {
            let string = #"@Test func rawGhost() {}"#
            let multiline = """
                @Test func multilineGhost() {}
                """
            let interpolation = "value \(String("@Test func innerGhost() {}"))"
            private func helper() {}
            @Test("description mentions @Test and }")
            func first() {}
            @Test func second() async throws {}
        }
        '''
        methods, records = parse_suite(source, "Fixture")
        self.assertEqual(methods, {"first": None, "second": None})
        self.assertEqual([row["id"] for row in records], ["Fixture/first()", "Fixture/second()"])
        changed = source.replace("private func helper() {}", "@Test func addedLater() {}")
        self.assertIn("addedLater", parse_suite(changed, "Fixture")[0])

    def test_finite_inline_arguments_preserve_exact_string_values(self):
        source = r'''
        struct Fixture {
            @Test("inputs", arguments: [#"{"count":"seven"}"#, "ordinary\nstring",])
            func parameterized(_ text: String) async throws {}
        }
        '''
        methods, _ = parse_suite(source, "Fixture")
        self.assertEqual(methods, {"parameterized": [('{"count":"seven"}',), ("ordinary\nstring",)]})

    def test_unsupported_dynamic_nested_or_duplicate_declarations_fail_closed(self):
        for body in (
            '@Test(arguments: inputs) func bad(_ text: String) {}',
            '@Test(arguments: ["x", "x"]) func bad(_ text: String) {}',
            '@Test(arguments: [1, 2]) func bad(_ number: Int) {}',
            '@Test func bad(_ text: String) {}',
            '@Test func duplicate() {} @Test func duplicate() {}',
            'struct Nested { @Test func hidden() {} }',
        ):
            with self.subTest(body=body):
                with self.assertRaises(ValueError):
                    parse_suite("struct Fixture { " + body + " }", "Fixture")


if __name__ == "__main__":
    unittest.main()
