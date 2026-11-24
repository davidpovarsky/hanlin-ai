"""Portable CMS verification and explicit absence of fabricated Keychain facts."""
import base64
from datetime import datetime, timedelta, timezone
from pathlib import Path
import plistlib
import sys
import tempfile
import unittest
from unittest.mock import patch

from cryptography import x509
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import rsa
from cryptography.hazmat.primitives.serialization import pkcs7
from cryptography.x509.oid import NameOID

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "Scripts/ProductSplit"))
from owner_profile_readback_entry import portable_profile_cms
from owner_profile_readback import _existing_development_identity_availability


class PortableOwnerProfileReadbackTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
        name = x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, "CMS signature fixture"),
                          x509.NameAttribute(NameOID.ORGANIZATIONAL_UNIT_NAME, "OWNER")])
        now = datetime.now(timezone.utc)
        cls.cert = (x509.CertificateBuilder().subject_name(name).issuer_name(name)
            .public_key(cls.key.public_key()).serial_number(x509.random_serial_number())
            .not_valid_before(now - timedelta(minutes=1)).not_valid_after(now + timedelta(days=1))
            .sign(cls.key, hashes.SHA256()))
        cls.payload = {"Name": "Synthetic CMS fixture", "Entitlements": {"application-identifier": "OWNER.fixture"}}
        cls.cms = (pkcs7.PKCS7SignatureBuilder().set_data(plistlib.dumps(cls.payload))
            .add_signer(cls.cert, cls.key, hashes.SHA256())
            .sign(serialization.Encoding.DER, [pkcs7.PKCS7Options.Binary]))

    def test_real_openssl_verifies_and_decodes_cms_content(self):
        with tempfile.TemporaryDirectory() as folder:
            raw, profile = portable_profile_cms(base64.b64encode(self.cms).decode(), folder)
            self.assertEqual(raw, self.cms)
            self.assertEqual(profile, self.payload)
            self.assertEqual(list(Path(folder).iterdir()), [])

    def test_modified_cms_signature_is_rejected(self):
        damaged = self.cms[:-1] + bytes([self.cms[-1] ^ 1])
        with tempfile.TemporaryDirectory() as folder, self.assertRaises(ValueError):
            portable_profile_cms(base64.b64encode(damaged).decode(), folder)

    def test_linux_inventory_does_not_invent_keychain_availability(self):
        record = {"id": "PUBLICCERT", "attributes": {"certificateType": "DEVELOPMENT",
            "certificateContent": base64.b64encode(self.cert.public_bytes(serialization.Encoding.DER)).decode()}}
        with patch("owner_profile_readback._development_certificates", return_value=[record]), \
             patch("owner_profile_readback._private_output", side_effect=AssertionError("No native keychain command is allowed")):
            result = _existing_development_identity_availability("OWNER", inspect_local_keychain=False)
        self.assertEqual(result["local_keychain_inspection"], "NOT_INSPECTED_ON_LINUX")
        self.assertIsNone(result["reusable_valid_owner_development_identity_count"])
        self.assertIsNone(result["certificates"][0]["private_identity_available_in_existing_search_list"])
        self.assertTrue(result["certificates"][0]["valid_dates"])


if __name__ == "__main__":
    unittest.main()
