"""Only missing source-required public capabilities are requested once."""
from pathlib import Path
import subprocess
import sys
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "Scripts/ProductSplit"))
from cross_app_owner_provisioning import _prepare_required_public_capabilities, _private_output


class OwnerCapabilityPreparationTests(unittest.TestCase):
    def setUp(self):
        self.product = {"apple_bundle_resource_id": "OWNERFIXTURE"}
        self.required = {"aps-environment": "production",
                         "com.apple.developer.associated-domains": ["applinks:example.invalid"],
                         "com.apple.developer.networking.multicast": True,
                         "com.apple.developer.usernotifications.communication": True}
        self.before = ["APP_GROUPS", "IN_APP_PURCHASE"]
        self.after = self.before + ["ASSOCIATED_DOMAINS", "PUSH_NOTIFICATIONS"]

    def test_only_supported_missing_public_capabilities_are_enabled(self):
        with patch("cross_app_owner_provisioning._capabilities", side_effect=[self.before, self.after]), \
             patch("register_miniapps_bundle.request", return_value={"data": {}}) as request:
            fact = _prepare_required_public_capabilities(self.product, self.required)
        self.assertEqual(request.call_count, 2)
        self.assertEqual({call.kwargs["body"]["data"]["attributes"]["capabilityType"] for call in request.call_args_list},
                         {"ASSOCIATED_DOMAINS", "PUSH_NOTIFICATIONS"})
        self.assertTrue(fact["existing_capabilities_preserved"])
        self.assertEqual(fact["missing_public_capabilities"], [])
        self.assertEqual(len(fact["managed_entitlements"]), 2)

    def test_uncertain_write_is_reconciled_without_a_duplicate_mutation(self):
        with patch("cross_app_owner_provisioning._capabilities", side_effect=[self.before, self.after]), \
             patch("register_miniapps_bundle.request", side_effect=[TimeoutError(), {"data": {}}]) as request:
            fact = _prepare_required_public_capabilities(self.product, self.required)
        self.assertEqual(request.call_count, 2)
        self.assertEqual(fact["operations"][0]["status"], "OUTCOME_UNKNOWN")
        self.assertEqual(fact["missing_public_capabilities"], [])

    def test_private_signing_timeout_does_not_render_command_arguments(self):
        command = ["security", "import", "owned.p12", "-P", "synthetic-one-time-password"]
        with patch("cross_app_owner_provisioning.subprocess.run",
                   side_effect=subprocess.TimeoutExpired(command, 45)):
            with self.assertRaises(RuntimeError) as raised:
                _private_output(command)
        self.assertNotIn("synthetic-one-time-password", str(raised.exception))
        self.assertEqual(str(raised.exception), "Native signing operation failed: security")


if __name__ == "__main__":
    unittest.main()
