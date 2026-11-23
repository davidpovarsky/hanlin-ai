"""Only probe-created development identities may be cleaned up."""
import base64
import hashlib
from pathlib import Path
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "Scripts/ProductSplit"))
from cross_app_owner_provisioning import _owned_temporary_development_certificates


class TemporaryDevelopmentIdentityTests(unittest.TestCase):
    def record(self, identifier, certificate=b"owned-public-certificate", kind="DEVELOPMENT"):
        return {"id": identifier, "attributes": {
            "certificateType": kind,
            "certificateContent": base64.b64encode(certificate).decode()}}

    def select(self, before, records):
        owned = hashlib.sha1(b"owned-public-certificate").hexdigest().upper()
        return _owned_temporary_development_certificates(before, records, {owned})

    def test_existing_identity_is_preserved_even_when_private_key_is_available(self):
        self.assertEqual(self.select({"PREEXISTING"}, [self.record("PREEXISTING")]), [])

    def test_another_jobs_new_identity_is_preserved_without_our_private_key(self):
        self.assertEqual(self.select(set(), [self.record("OTHERJOB", b"other-public-certificate")]), [])

    def test_distribution_identity_is_never_selected_for_cleanup(self):
        self.assertEqual(self.select(set(), [self.record("DISTRIBUTION", kind="DISTRIBUTION")]), [])

    def test_exact_probe_owned_new_development_identity_has_recheck_proof(self):
        value = self.select(set(), [self.record("OWNEDNEW")])
        self.assertEqual(len(value), 1)
        self.assertEqual(value[0]["resource_id"], "OWNEDNEW")
        self.assertEqual(value[0]["public_certificate_sha256"],
                         hashlib.sha256(b"owned-public-certificate").hexdigest())
        self.assertTrue(value[0]["created_after_probe_started"])
        self.assertTrue(value[0]["private_key_in_owned_temporary_keychain"])


if __name__ == "__main__":
    unittest.main()
