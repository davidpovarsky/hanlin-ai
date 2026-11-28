"""Acceptance-resource checks: synthetic profile metadata, never signing proof."""
import copy
from datetime import datetime, timedelta, timezone
import hashlib
import importlib.util
from pathlib import Path
import unittest

path = Path(__file__).resolve().parents[2] / "Scripts/ProductSplit/audit_release_resources.py"
spec = importlib.util.spec_from_file_location("release_audit", path)
audit = importlib.util.module_from_spec(spec)
spec.loader.exec_module(audit)

class ProfileChecks(unittest.TestCase):
    def setUp(self):
        self.now = datetime(2026, 11, 18, tzinfo=timezone.utc)
        self.cert = b"synthetic public certificate"
        self.digest = hashlib.sha256(self.cert).hexdigest()
        self.required = {"com.apple.security.application-groups": ["group.com.itorah.chavrusachat", "group.com.itorah.shared"],
                         "com.apple.developer.healthkit": True, "aps-environment": "$(APS_ENVIRONMENT)"}
        self.profile = {"TeamIdentifier": ["TEAM"], "ExpirationDate": self.now + timedelta(days=1),
                        "DeveloperCertificates": [self.cert], "Entitlements": {
                            "application-identifier": "TEAM.com.itorah.hanlinminiapps", "get-task-allow": False,
                            "com.apple.security.application-groups": list(self.required["com.apple.security.application-groups"]),
                            "com.apple.developer.healthkit": True, "aps-environment": "production"}}
    def evaluate(self):
        return audit.evaluate_profile(self.profile, self.required, "com.itorah.hanlinminiapps", "TEAM", self.digest, self.now)
    def test_matching_distribution_metadata_is_ready_resource_only(self):
        self.assertEqual(self.evaluate()["status"], "READY_RESOURCE")
    def test_expired_profile_is_blocked(self):
        self.profile["ExpirationDate"] = self.now
        self.assertFalse(self.evaluate()["checks"]["not_expired"])
        self.assertEqual(self.evaluate()["status"], "BLOCKED")
    def test_missing_shared_group_and_capability_are_reported(self):
        self.profile["Entitlements"]["com.apple.security.application-groups"].pop()
        self.profile["Entitlements"]["com.apple.developer.healthkit"] = False
        self.assertEqual(self.evaluate()["missing_or_mismatched_entitlement_keys"],
                         ["com.apple.developer.healthkit", "com.apple.security.application-groups"])
    def test_development_adhoc_and_enterprise_profiles_are_not_store_profiles(self):
        for key, value in [("get-task-allow", True), ("ProvisionedDevices", []), ("ProvisionsAllDevices", True)]:
            with self.subTest(key=key):
                original = copy.deepcopy(self.profile)
                if key == "get-task-allow":
                    self.profile["Entitlements"][key] = value
                else:
                    self.profile[key] = value
                self.assertFalse(self.evaluate()["checks"]["distribution_profile"])
                self.profile = original
    def test_other_team_bundle_and_signer_cannot_pass(self):
        self.profile["TeamIdentifier"] = ["OTHER"]
        self.profile["Entitlements"]["application-identifier"] = "OTHER.com.example.wrong"
        self.profile["DeveloperCertificates"] = [b"another certificate"]
        result = self.evaluate()
        self.assertEqual(result["status"], "BLOCKED")
        for key in ["team_matches", "bundle_matches", "certificate_matches"]:
            self.assertFalse(result["checks"][key])
    def test_cloud_service_wildcard_does_not_grant_boolean_capability(self):
        self.assertTrue(audit.entitlement_allows(["*"], ["CloudKit", "CloudDocuments"]))
        self.assertFalse(audit.entitlement_allows("*", True))
        self.assertFalse(audit.entitlement_allows(1, True))
        self.assertFalse(audit.entitlement_allows(["group.other"], ["group.required"]))

class BundleIdentityChecks(unittest.TestCase):
    def test_exact_product_excludes_prefix_extensions_and_other_platform(self):
        def row(identifier, platform, identity):
            return {"id": identity, "attributes": {"identifier": identifier, "platform": platform}}
        bundle = "com.itorah.chavrusachat"
        exact = row(bundle, "IOS", "actual")
        response = {"data": [row(bundle + ".share", "IOS", "extension"),
                             row(bundle, "MAC_OS", "mac"), exact]}
        self.assertEqual(audit.exact_bundles(response, bundle), [exact])

    def test_missing_or_unknown_platform_cannot_establish_a_product(self):
        response = {"data": [{"id": "unknown", "attributes": {"identifier": "com.itorah.hanlinminiapps"}}]}
        self.assertEqual(audit.exact_bundles(response, "com.itorah.hanlinminiapps"), [])

if __name__ == "__main__":
    unittest.main()
