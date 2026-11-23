"""Fresh profile readback must not present pre-mutation grants as current."""
from datetime import datetime, timedelta, timezone
import hashlib
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import Mock

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "Scripts/ProductSplit"))
from owner_profile_readback import _fresh_profile, _identity_fingerprints


class OwnerProfileReadbackTests(unittest.TestCase):
    def setUp(self):
        self.product = {"role": "test_owner", "bundle_id": "example.owner", "apple_bundle_resource_id": "BUNDLE"}
        self.public_certificate = b"existing-test-distribution-certificate"
        now = datetime.now(timezone.utc)
        self.profile = {
            "Name": "Fresh", "UUID": "profile-uuid", "TeamIdentifier": ["OWNER"],
            "ApplicationIdentifierPrefix": ["OWNER"], "CreationDate": now,
            "ExpirationDate": now + timedelta(days=30),
            "DeveloperCertificates": [self.public_certificate],
            "Entitlements": {"application-identifier": "OWNER.example.owner", "get-task-allow": False}}
        self.create = Mock(return_value={"data": {"id": "NEW"}})
        self.decode = Mock(return_value=(b"current-profile-cms", self.profile))

    def read(self, records):
        def get(path, parameters):
            if path.endswith("/profiles"):
                return {"data": records}
            return {"data": {"attributes": {"profileType": "IOS_APP_STORE", "profileState": "ACTIVE",
                                            "profileContent": "opaque-in-memory"}}}
        with tempfile.TemporaryDirectory() as folder:
            return _fresh_profile(self.product, Path(folder), "OWNER",
                                  hashlib.sha256(self.public_certificate).hexdigest(), "CERT", "RUN",
                                  get=get, create=self.create, decode_profile=self.decode)

    def test_profile_issued_before_probe_is_not_reused_as_current_assignment(self):
        profile, fact = self.read([{"id": "OLD", "attributes": {
            "name": "Old owner profile", "profileType": "IOS_APP_STORE", "profileState": "ACTIVE"}}])
        self.create.assert_called_once_with("BUNDLE", "CERT", "MiniApps owner readback test_owner RUN")
        self.assertEqual(fact["resource_id"], "NEW")
        self.assertEqual(fact["source"], "CREATED_FRESH_PROFILE_WITHOUT_APP_ID_OR_GROUP_MUTATION")
        self.assertEqual(fact["app_groups"], [])
        self.assertFalse(fact["signed_profile_supports_shared_group"])

    def test_same_run_profile_is_reconciled_without_duplicate_creation(self):
        _, fact = self.read([{"id": "SAME_RUN", "attributes": {
            "name": "MiniApps owner readback test_owner RUN"}}])
        self.create.assert_not_called()
        self.assertEqual(fact["resource_id"], "SAME_RUN")
        self.assertEqual(fact["source"], "RECONCILED_THIS_READBACK_RUN_PROFILE")

    def test_uncertain_create_is_never_retried(self):
        self.create.side_effect = TimeoutError("uncertain response")
        with self.assertRaises(TimeoutError):
            self.read([])
        self.create.assert_called_once()
        self.decode.assert_not_called()

    def test_wrong_owner_certificate_readback_is_rejected(self):
        self.profile["DeveloperCertificates"] = [b"another-existing-certificate"]
        with self.assertRaisesRegex(ValueError, "existing owner identity"):
            self.read([])

    def test_native_security_output_matches_exact_valid_identity_fingerprint(self):
        fingerprint = "0123456789ABCDEF0123456789ABCDEF01234567"
        listing = '  1) ' + fingerprint.lower() + ' "Apple Development: metadata"' + chr(10) + '     1 valid identities found' + chr(10)
        self.assertEqual(_identity_fingerprints(listing), {fingerprint})
        self.assertEqual(_identity_fingerprints("unrelated " + fingerprint), set())


if __name__ == "__main__":
    unittest.main()
