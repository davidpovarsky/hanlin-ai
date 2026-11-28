"""Exercise the original workflow's pure UI budget selection, without Xcode."""
import os
from pathlib import Path
import subprocess
import unittest

import yaml


ROOT = Path(__file__).resolve().parents[3]
WORKFLOW = ROOT / ".github/workflows/build-ios26-unsigned-ipa.yml"
LEGACY = "AI_HLYUITests/HanlinExpoProductionE2ETests/testNativeLegacyWidgetWithHostTerminated"
LIVE = "AI_HLYUITests/AgentRuntimeConversationUITests/testLiveGeminiPythonConsentAndColdReopen"


def workflow_budget(selector, *, group="exact_test_selector", cohort=None, full=False):
    workflow = yaml.safe_load(WORKFLOW.read_text())
    steps = workflow["jobs"]["full-app-simulator-smoke"]["steps"]
    phase = next(step["run"] for step in steps if step["name"] == "Run simulator test suite")
    start = phase.index("ui_time_allowance=300")
    end = phase.index("xcodebuild test-without-building", start)
    block = phase[start:end]
    block = block.replace("${{ inputs.exact_test_selector }}", "$EXACT_TEST_SELECTOR")
    block = block.replace("${{ inputs.target_validation_group }}", "$TARGET_VALIDATION_GROUP")
    if "${{" in block:
        raise AssertionError("Unexpected unevaluated workflow expression in budget selection")
    env = os.environ.copy()
    env.update(EXACT_TEST_SELECTOR=selector, TARGET_VALIDATION_GROUP=group,
               cohort_selectors=selector if cohort is None else cohort,
               RUN_FULL_VALIDATION="true" if full else "false")
    result = subprocess.run(
        ["bash", "-c", "set -euo pipefail\nui_test_args=()\n" + block +
         '\nprintf "%s\\n" "$ui_time_allowance"\n'],
        env=env, capture_output=True, text=True, timeout=5, check=True,
    )
    return int(result.stdout.strip())


class LegacyWidgetCaseBudgetTests(unittest.TestCase):
    def test_original_legacy_allowance_is_confined_to_the_exact_request(self):
        self.assertEqual(workflow_budget(LEGACY), 600)
        for selector, group in [
            (LEGACY + "Extra", "exact_test_selector"),
            (LEGACY + ",AI_HLYUITests/Other/testExample", "exact_test_selector"),
            (LEGACY + " ", "exact_test_selector"),
            ("AI_HLYUITests/HanlinExpoProductionE2ETests/testNativeExpoWidgetSourceActionsWithHostTerminated", "exact_test_selector"),
            ("AI_HLYUITests/HanlinExpoProductionE2ETests", "exact_test_selector"),
            (LEGACY, "phase2_app_with_motion"),
            (LEGACY, ""),
        ]:
            with self.subTest(selector=selector, group=group):
                self.assertEqual(workflow_budget(selector, group=group), 300)

    def test_original_default_live_scriptui_and_full_budgets_are_preserved(self):
        for selector, cohort, full, expected in [
            ("AI_HLYUITests/HanlinContextualTextToolsUITests/testOriginalTextToolsReceiveTheMessageWithoutReplacingTheConversation", "", False, 300),
            (LIVE, LIVE, False, 420),
            ("", "AI_HLYUITests/HanlinScriptUIProductionE2ETests", False, 600),
            ("", "AI_HLYUITests", True, 600),
            (LIVE, LIVE, True, 600),
        ]:
            with self.subTest(selector=selector, cohort=cohort, full=full):
                self.assertEqual(workflow_budget(selector, cohort=cohort, full=full), expected)


if __name__ == "__main__":
    unittest.main()
