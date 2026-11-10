import importlib.util
from pathlib import Path
import unittest

SPEC = importlib.util.spec_from_file_location("selected", Path(__file__).parents[1] / "verify_selected_tests.py")
module = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(module)

class SelectedTestsExecutionGateTests(unittest.TestCase):
    def fixture(self, method="realTest()", result="Passed", suite="RuntimeAutonomyV3Tests"):
        return {"testNodes": [{"nodeType": "Test Suite", "result": "Passed", "children": [{
            "nodeType": "Test Case", "nodeIdentifierURL": f"test://com.apple.xcode/AI_HLY/AI_HLYTests/{suite}/{method}", "result": result
        }]}]}

    def test_green_empty_suite_never_proves_requested_tests(self):
        data = {"testNodes": [{"nodeType": "Test Suite", "result": "Passed", "name": "RuntimeAutonomyV3Tests"}]}
        self.assertEqual(module.missing_selectors(data, ["AI_HLYTests/RuntimeAutonomyV3Tests"]), ["AI_HLYTests/RuntimeAutonomyV3Tests"])

    def test_actual_swift_testing_case_matches_its_suite_and_parentheses_signature(self):
        for selector in ["AI_HLYTests/RuntimeAutonomyV3Tests", "AI_HLYTests/RuntimeAutonomyV3Tests/realTest()"]:
            self.assertEqual(module.missing_selectors(self.fixture(), [selector]), [])

    def test_one_executed_case_does_not_hide_an_omitted_method(self):
        missing = "AI_HLYTests/RuntimeAutonomyV3Tests/omitted()"
        self.assertEqual(module.missing_selectors(self.fixture(), ["AI_HLYTests/RuntimeAutonomyV3Tests/realTest()", missing]), [missing])

    def test_skipped_case_does_not_count_as_execution(self):
        selector = "AI_HLYTests/RuntimeAutonomyV3Tests/realTest()"
        self.assertEqual(module.missing_selectors(self.fixture(result="Skipped"), [selector]), [selector])

    def test_failed_case_executed_but_remains_owned_by_xcode_failure_status(self):
        self.assertEqual(module.missing_selectors(self.fixture(result="Failed"), ["AI_HLYTests/RuntimeAutonomyV3Tests"]), [])

    def test_xctest_method_uses_actual_case_identity_and_supports_older_bundleless_results(self):
        data = {"testNodes": [{"nodeType": "Test Case", "nodeIdentifier": "UITests/testActualTap()", "result": "Passed"}]}
        self.assertEqual(module.missing_selectors(data, ["AI_HLYUITests/UITests/testActualTap"]), [])
        self.assertEqual(module.missing_selectors(data, ["AI_HLYTests/WrongSuite"]), ["AI_HLYTests/WrongSuite"])

if __name__ == "__main__": unittest.main()
