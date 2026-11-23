import unittest
from unittest.mock import Mock

from prepare_calendar_acceptance import METHOD, prepare


class CalendarAcceptanceAdmissionTests(unittest.TestCase):
    def test_unrelated_selection_cannot_touch_a_simulator_or_read_products(self):
        owner, runner = Mock(), Mock()
        self.assertIsNone(prepare("AI_HLYTests/CalendarToolTests", "/not-present",
                                  "/not-present", "/not-present", "1", "1",
                                  runner=runner, verify_owner=owner))
        owner.assert_not_called()
        runner.assert_not_called()

    def test_unowned_simulator_is_rejected_before_install_or_privacy_mutation(self):
        owner = Mock(side_effect=RuntimeError("not this run's owned simulator"))
        runner = Mock()
        with self.assertRaisesRegex(RuntimeError, "owned simulator"):
            prepare(METHOD + "()", "/not-present", "/not-present", "/not-present",
                    "1", "1", runner=runner, verify_owner=owner)
        runner.assert_not_called()


if __name__ == "__main__":
    unittest.main()
