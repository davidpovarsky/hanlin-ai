"""New localization-only proof admission; no native tests are executed here."""
from pathlib import Path
import json
import os
import subprocess
import unittest

import reuse_cross_app_native_proof as proof

ROOT = Path(__file__).resolve().parents[2]
DIRECT = {
    "testCompletionIsSavedBeforeSourceOpensAndSurvivesColdRestore",
    "testTwoWindowsKeepTheirOwnInputOutputAndCallbacks",
    "testCancelAndDisplayDoneReturnNoDocumentMutation",
    "testActualProducerAttachmentOperationsPreserveBytes",
    "testUnavailableCallbackRetainsResultForSourceRecovery",
    "testTextStudioWindowsRestoreTheirOwnDrafts",
    "testReusingValueWindowKeepsItsInvocationBindingCurrent",
    "testRemovingInvocationOwnerCancelsWhileSessionIsStillRetained",
}
SCENE = "testActualIncomingRequestsCreateDistinctIPadScenes"


class LocalizationDeltaAdmissionTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.spec = proof.description(ROOT)
        cls.original = subprocess.check_output(
            ["git", "show", cls.spec["origin"]["source_sha"] + ":" + proof.INFO_PLIST], cwd=ROOT)
        cls.current = (ROOT / proof.INFO_PLIST).read_bytes()

    def testAuthenticatedOriginalRetainsExactlyEightDirectCases(self):
        archive = os.environ.get("HANLIN_LOCALIZATION_ORIGIN_ZIP")
        previous = os.environ.get("HANLIN_LOCALIZATION_NATIVE_PROOF")
        if not archive or not previous:
            self.skipTest("Provide the retained authenticated ZIP and actual Mac preboot proof")
        observed = json.loads(Path(previous).read_text())
        self.assertEqual(observed["target_sha"], "df3cb6d5ac27fdef24e3a45c6b3b2558f4563274")
        self.assertEqual(observed["origin"]["source_sha"], self.spec["origin"]["source_sha"])
        expected = {proof.PREFIX + method for method in DIRECT}
        self.assertEqual(set(observed["reusable_selectors"]), expected)
        # Replay only admission with the retained real Mac environment. This is
        # neither a current Linux platform claim nor fresh native execution.
        plan = proof.plan_reuse(ROOT, archive, observed["current_environment"])
        self.assertEqual(set(plan["reusable_selectors"]), expected)
        self.assertEqual(plan["rerun_selectors"], [proof.PREFIX + SCENE])
        self.assertEqual(plan["fresh_tests_executed_by_verifier"], 0)
        self.assertEqual(plan["origin_failed_test_count"], 4)
        for case in plan["cases"]:
            with self.subTest(selector=case["selector"]):
                if case["selector"] not in expected:
                    self.assertEqual(case["qualified_input_deltas"], [])
                    self.assertIn("source:" + proof.INFO_PLIST, case["invalidation_reasons"])
                    continue
                self.assertEqual(case["status"], "REUSED_VERIFIED_PASS")
                self.assertEqual(len(case["qualified_input_deltas"]), 1)
                delta = case["qualified_input_deltas"][0]
                self.assertEqual(delta["original_sha256"], proof.digest(self.original))
                self.assertEqual(delta["current_sha256"], proof.digest(self.current))
                self.assertEqual(delta["added_localizations"], ["en", "he", "zh-Hans"])
                self.assertEqual(delta["all_other_bytes_and_values"], "UNCHANGED")
        self.assertIsNone(proof.qualify_localization_delta(self.original, self.current, SCENE))
        self.assertIsNone(proof.qualify_localization_delta(
            self.original, self.current, "testAppleStyleEditorAddsFavoriteWithNativeEditControls"))

    def testRejectsOtherPlistMutations(self):
        mutations = [
            (b"<string>hanlinminiapps</string>", b"<string>anotherminiapps</string>"),
            (b"<key>UIApplicationSupportsMultipleScenes</key>\n\t\t<true/>",
             b"<key>UIApplicationSupportsMultipleScenes</key>\n\t\t<false/>"),
            (b"<string>group.com.itorah.chavrusachat</string>",
             b"<string>group.com.itorah.other</string>"),
        ]
        for old, new in mutations:
            with self.subTest(changed_value=old.decode()):
                self.assertIn(old, self.current)
                changed = self.current.replace(old, new, 1)
                for method in DIRECT:
                    self.assertIsNone(proof.qualify_localization_delta(self.original, changed, method))

    def testRejectsAlteredLanguageDeclarations(self):
        mutations = [
            (b"<string>he</string>", b"<string>fr</string>"),
            (b"\t\t<string>he</string>\n", b""),
            (b"<string>en</string>\n\t\t<string>he</string>",
             b"<string>he</string>\n\t\t<string>en</string>"),
            (b"<string>zh-Hans</string>", b"<string>zh-Hans</string>\n\t\t<string>fr</string>"),
        ]
        for old, new in mutations:
            with self.subTest(changed_language=old.decode()):
                self.assertIn(old, self.current)
                changed = self.current.replace(old, new, 1)
                for method in DIRECT:
                    self.assertIsNone(proof.qualify_localization_delta(self.original, changed, method))


if __name__ == "__main__":
    unittest.main()
