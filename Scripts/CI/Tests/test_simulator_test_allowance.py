import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location("simulator_test_allowance", Path(__file__).parents[1] / "simulator_test_allowance.py")
assert spec and spec.loader
allowance = importlib.util.module_from_spec(spec)
spec.loader.exec_module(allowance)


class SimulatorTestAllowanceTests(unittest.TestCase):
    def test_exact_long_method_retains_its_required_allowance(self):
        self.assertEqual(allowance.unit_allowance(allowance.LONG_METHOD + "()"), 660)
        self.assertEqual(allowance.unit_allowance(allowance.LONG_METHOD), 660)

    def test_whole_suite_and_full_bundle_still_include_the_long_obligation(self):
        self.assertEqual(allowance.unit_allowance(allowance.LONG_SUITE), 660)
        self.assertEqual(allowance.unit_allowance("AI_HLYTests"), 660)
        self.assertEqual(allowance.unit_allowance("AI_HLYTests/Other," + allowance.LONG_SUITE), 660)

    def test_ordinary_registry_method_does_not_extend_unrelated_native_cases(self):
        selected = allowance.LONG_SUITE + "/actualGlobalNpmInstallUpdateImportAndRemovalUsePreservedGenerations(),AI_HLYTests/HanlinUnifiedHostServicesE2ETests"
        self.assertEqual(allowance.unit_allowance(selected), 300)

    def test_similar_names_and_suffixes_do_not_match_an_unselected_long_test(self):
        for name in [allowance.LONG_SUITE + "Extra", allowance.LONG_METHOD + "Extra()", "Other/" + allowance.LONG_METHOD, ""]:
            with self.subTest(selector=name):
                self.assertEqual(allowance.unit_allowance(name), 300)
