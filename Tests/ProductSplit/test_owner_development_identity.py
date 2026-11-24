"""Proof that the explicit CSR path can act only on its newly generated key."""
import base64
from datetime import datetime, timedelta
import hashlib
from pathlib import Path
import sys
import unittest

from cryptography import x509
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import rsa
from cryptography.x509.oid import NameOID

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "Scripts/ProductSplit"))
from owner_development_identity import _owned_certificate_fact, _public_error_codes, _public_key_bytes


class OwnerDevelopmentIdentityTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
        cls.other_key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
        cls.key_sha = hashlib.sha256(_public_key_bytes(cls.key.public_key())).hexdigest()

    def record(self, team="OWNER", key=None, identifier="TASKNEW", kind="DEVELOPMENT"):
        key = key or self.key
        name = x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, "Synthetic ownership fixture"),
                          x509.NameAttribute(NameOID.ORGANIZATIONAL_UNIT_NAME, team)])
        now = datetime.utcnow()
        cert = (x509.CertificateBuilder().subject_name(name).issuer_name(name)
                .public_key(key.public_key()).serial_number(x509.random_serial_number())
                .not_valid_before(now - timedelta(minutes=1)).not_valid_after(now + timedelta(days=1))
                .sign(key, hashes.SHA256()))
        return {"id": identifier, "attributes": {"certificateType": kind,
                "certificateContent": base64.b64encode(cert.public_bytes(serialization.Encoding.DER)).decode()}}

    def check(self, record, before=()):
        return _owned_certificate_fact(record, self.key_sha, set(before), "OWNER")

    def test_new_current_development_resource_is_bound_to_the_generated_private_key(self):
        fact = self.check(self.record())
        self.assertEqual(fact["resource_id"], "TASKNEW")
        self.assertEqual(fact["public_key_sha256"], self.key_sha)
        self.assertTrue(fact["public_key_matches_task_owned_private_key"])

    def test_existing_identity_is_never_eligible_even_if_the_key_matches(self):
        with self.assertRaises(ValueError):
            self.check(self.record(identifier="EXISTING"), before=["EXISTING"])

    def test_another_jobs_new_certificate_is_rejected(self):
        with self.assertRaises(ValueError):
            self.check(self.record(key=self.other_key))

    def test_foreign_team_is_rejected(self):
        with self.assertRaises(ValueError):
            self.check(self.record(team="OTHER"))

    def test_distribution_or_legacy_types_are_not_created_or_selected(self):
        for kind in ["DISTRIBUTION", "IOS_DEVELOPMENT"]:
            with self.subTest(kind=kind), self.assertRaises(ValueError):
                self.check(self.record(kind=kind))

    def test_api_failure_keeps_only_public_error_codes(self):
        self.assertEqual(_public_error_codes(b'{"errors":[{"code":"ENTITY_ERROR.QUOTA","detail":"private response"}]}'),
                         ["ENTITY_ERROR.QUOTA"])
        self.assertEqual(_public_error_codes(b'{"errors":[{"code":"unsafe value with spaces"}]}'), [])


if __name__ == "__main__":
    unittest.main()
