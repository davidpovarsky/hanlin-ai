"""Automatic selection is reconciled to the actual archive certificate and grants."""
from datetime import datetime, timedelta, timezone
import copy
import hashlib
from pathlib import Path
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "Scripts/ProductSplit"))
from cross_app_owner_provisioning import _automatic_archive_signing_settings, _development_archive_fact


class AutomaticOwnerArchiveTests(unittest.TestCase):
    def setUp(self):
        self.team = "OWNERTEAM1"
        self.bundle = "example.owner.consumer"
        self.leaf = b"synthetic task certificate DER"
        self.sha = hashlib.sha256(self.leaf).hexdigest()
        self.required = {"aps-environment": "development",
                         "com.apple.security.application-groups": ["group.example.owner.shared"]}
        self.expected = {"bundle_id": self.bundle, "entitlements": self.required}
        self.signed = dict(self.required, **{"application-identifier": self.team + "." + self.bundle})
        self.profile = {"UUID": "synthetic-profile", "TeamIdentifier": [self.team],
                        "ExpirationDate": datetime.now(timezone.utc) + timedelta(days=1),
                        "DeveloperCertificates": [self.leaf], "ProvisionedDevices": ["synthetic-test-device"],
                        "Entitlements": dict(self.signed, **{"get-task-allow": True})}

    def fact(self, *, leaf=None, profile=None, signed=None):
        return _development_archive_fact(
            {"CFBundleIdentifier": self.bundle}, profile or self.profile,
            signed or self.signed, leaf or self.leaf, self.expected, self.team, self.sha)

    def test_automatic_selection_uses_development_class_then_verifies_exact_leaf(self):
        settings = _automatic_archive_signing_settings(self.team)
        self.assertIn("CODE_SIGN_STYLE=Automatic", settings)
        self.assertEqual([value for value in settings if value.startswith("CODE_SIGN_IDENTITY=")],
                         ["CODE_SIGN_IDENTITY=Apple Development"])
        self.assertEqual(self.fact()["status"], "DEVELOPMENT_ARCHIVE_READBACK_PASS")
        self.assertEqual(self.fact(leaf=b"other certificate")["status"],
                         "DEVELOPMENT_ARCHIVE_READBACK_FAILED")

    def test_valid_profile_does_not_mask_missing_signed_source_group(self):
        signed = dict(self.signed, **{"com.apple.security.application-groups": []})
        fact = self.fact(signed=signed)
        self.assertEqual(fact["status"], "DEVELOPMENT_ARCHIVE_READBACK_FAILED")
        self.assertEqual(fact["missing_signed_entitlement_keys"], ["com.apple.security.application-groups"])
        self.assertEqual(fact["missing_profile_entitlement_keys"], [])

    def test_distribution_profile_cannot_impersonate_development_archive(self):
        profile = copy.deepcopy(self.profile)
        profile.pop("ProvisionedDevices")
        profile["Entitlements"]["get-task-allow"] = False
        profile["Entitlements"]["aps-environment"] = "production"
        fact = self.fact(profile=profile)
        self.assertEqual(fact["status"], "DEVELOPMENT_ARCHIVE_READBACK_FAILED")
        self.assertFalse(fact["checks"]["development_profile_has_registered_devices"])
        self.assertIn("aps-environment", fact["missing_profile_entitlement_keys"])


if __name__ == "__main__":
    unittest.main()
