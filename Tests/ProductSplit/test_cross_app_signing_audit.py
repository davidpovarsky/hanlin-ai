"""Focused new audit checks; synthetic metadata is not Apple signing evidence."""
from datetime import datetime, timedelta, timezone
import hashlib
import importlib.util
import json
from pathlib import Path
import unittest

path = Path(__file__).resolve().parents[2] / "Scripts/ProductSplit/audit_cross_app_signing.py"
spec = importlib.util.spec_from_file_location("cross_app_signing", path)
audit = importlib.util.module_from_spec(spec)
spec.loader.exec_module(audit)


class CrossAppSigningAuditTests(unittest.TestCase):
    def setUp(self):
        self.now = datetime(2026, 11, 23, tzinfo=timezone.utc)
        self.certificate = b"synthetic-public-certificate"
        self.certificate_sha = hashlib.sha256(self.certificate).hexdigest()
        self.profile = {
            "Name": "Owner MiniApps", "UUID": "public-profile-uuid", "TeamIdentifier": ["NA6HPWARQ2"],
            "ExpirationDate": self.now + timedelta(days=10), "DeveloperCertificates": [self.certificate],
            "ProvisionedDevices": ["must-not-leave-memory-device-id"],
            "Entitlements": {
                "application-identifier": "NA6HPWARQ2.com.itorah.hanlinminiapps", "get-task-allow": False,
                "com.apple.security.application-groups": [audit.SHARED_GROUP],
            },
        }

    def fact(self):
        return audit.profile_fact(self.profile, bundle="com.itorah.hanlinminiapps",
            team="NA6HPWARQ2", certificate_sha=self.certificate_sha, now=self.now)

    def test_exact_profile_group_not_capability_establishes_assignment(self):
        self.assertTrue(self.fact()["compatible_with_existing_certificate"])
        self.profile["Entitlements"]["com.apple.security.application-groups"] = ["group.other"]
        self.assertFalse(self.fact()["checks"]["shared_group_granted"])
        self.assertFalse(self.fact()["compatible_with_existing_certificate"])

    def test_profile_wrong_owner_and_bundle_cannot_be_selected(self):
        self.profile["TeamIdentifier"] = ["J3NXTX3T5S"]
        self.profile["Entitlements"]["application-identifier"] = "J3NXTX3T5S.io.anytype.app"
        fact = self.fact()
        self.assertFalse(fact["checks"]["owner_team_matches"])
        self.assertFalse(fact["checks"]["bundle_matches"])
        self.assertFalse(fact["signed_profile_supports_shared_group"])

    def test_same_owner_legacy_app_identifier_prefix_is_valid(self):
        self.profile["ApplicationIdentifierPrefix"] = ["LEGACYSEED"]
        self.profile["Entitlements"]["application-identifier"] = "LEGACYSEED.com.itorah.hanlinminiapps"
        self.assertTrue(self.fact()["compatible_with_existing_certificate"])

    def test_profile_report_excludes_device_and_certificate_payloads(self):
        output = json.dumps(self.fact())
        self.assertNotIn("must-not-leave-memory-device-id", output)
        self.assertNotIn("synthetic-public-certificate", output)
        self.assertNotIn("DeveloperCertificates", output)
        self.assertNotIn("ProvisionedDevices", output)

    def test_full_pagination_and_origin_validation(self):
        calls = []
        def get(path, parameters):
            calls.append((path, parameters))
            if "cursor" not in parameters:
                return {"data": [{"id": "one"}], "links": {"next":
                    "https://api.appstoreconnect.apple.com/v1/bundleIds?cursor=two&limit=200"}}
            return {"data": [{"id": "two"}]}
        self.assertEqual(audit.all_records(get, "/v1/bundleIds"), [{"id": "one"}, {"id": "two"}])
        self.assertEqual(len(calls), 2)
        for next_url in ["https://other.example/v1/bundleIds?cursor=two",
                         "https://api.appstoreconnect.apple.com/v1/profiles?cursor=two"]:
            with self.subTest(next_url=next_url), self.assertRaises(ValueError):
                audit.all_records(lambda *_: {"data": [], "links": {"next": next_url}}, "/v1/bundleIds")

    def test_complete_audit_retains_identity_without_raw_profile_content(self):
        calls = []
        def get(path, parameters):
            calls.append(path)
            if path == "/v1/bundleIds":
                return {"data": [{"id": "bundle", "attributes": {"identifier": "com.itorah.hanlinminiapps",
                    "name": "Hanlin MiniApps", "platform": "IOS"}}]}
            if path.endswith("/bundleIdCapabilities"):
                self.assertEqual(parameters, {})
                return {"data": [{"attributes": {"capabilityType": "APP_GROUPS"}}]}
            if path.endswith("/profiles"):
                return {"data": [{"id": "profile", "attributes": {"name": "Owner MiniApps",
                    "profileState": "ACTIVE", "profileType": "IOS_APP_STORE"}}]}
            return {"data": {"attributes": {"profileContent": "private-cms-never-report"}}}
        report = audit.audit_cross_app_resources(get, lambda _: self.profile,
            certificate_sha=self.certificate_sha, team="NA6HPWARQ2", now=self.now)
        self.assertEqual(report["status"], "OWNER_RESOURCES_READ_BACK")
        self.assertTrue(report["bundle_inventory_complete"])
        self.assertEqual(report["candidate_products"][0]["usable_shared_group_profile_count"], 1)
        self.assertNotIn("private-cms-never-report", json.dumps(report))
        self.assertEqual(len(calls), 4)

    def test_capability_failure_still_reads_profile_grants(self):
        def get(path, parameters):
            if path == "/v1/bundleIds":
                return {"data": [{"id": "bundle", "attributes": {"identifier": "com.itorah.hanlinminiapps", "name": "Hanlin MiniApps", "platform": "IOS"}}]}
            if path.endswith("/bundleIdCapabilities"):
                raise RuntimeError("HTTP_403")
            if path.endswith("/profiles"):
                return {"data": [{"id": "profile", "attributes": {"profileState": "ACTIVE", "profileType": "IOS_APP_STORE"}}]}
            return {"data": {"attributes": {"profileContent": "private-cms-never-report"}}}
        report = audit.audit_cross_app_resources(get, lambda _: self.profile,
            certificate_sha=self.certificate_sha, team="NA6HPWARQ2", now=self.now)
        self.assertEqual(report["status"], "PARTIAL_READBACK")
        product = report["candidate_products"][0]
        self.assertEqual(product["capability_read_error"]["code"], "HTTP_403")
        self.assertEqual(product["usable_shared_group_profile_count"], 1)
        self.assertEqual(audit.error_fact(RuntimeError("do-not-retain-secret")), {"kind": "RuntimeError"})

    def test_missing_credentials_performs_no_network_read(self):
        def unexpected(*_):
            self.fail("No account call is permitted without credentials")
        report = audit.audit_cross_app_resources(unexpected, unexpected, certificate_sha=None,
            team="", now=self.now, missing_credentials=["ASC_KEY_ID"])
        self.assertEqual(report["status"], "MISSING_CREDENTIALS")

    def test_repeated_cursor_is_reported_instead_of_hanging(self):
        page = {"data": [], "links": {"next":
            "https://api.appstoreconnect.apple.com/v1/bundleIds?cursor=same"}}
        with self.assertRaises(ValueError):
            audit.all_records(lambda *_: page, "/v1/bundleIds")

if __name__ == "__main__":
    unittest.main()
