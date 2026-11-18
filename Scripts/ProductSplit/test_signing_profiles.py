"""Behavior checks for exact original identity/profile selection and cache ownership."""
from copy import deepcopy
from datetime import datetime, timedelta, timezone
import base64
import hashlib
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import Mock, patch

from resolve_signing_profiles import (
    install_profile, original_certificate_id, remove_installed_profiles, resolve_profile,
)

CERTIFICATE = b"fixture-public-certificate-only"
CERTIFICATE_SHA = hashlib.sha256(CERTIFICATE).hexdigest()
BUNDLE = "com.itorah.chavrusachat"
TEAM = "FIXTURETEAM"
REQUIRED = {"com.apple.security.application-groups": ["group.fixture"],
            "com.apple.developer.kernel.extended-virtual-addressing": True}


def valid_profile():
    return {
        "UUID": "0E5A9288-4FB6-4ADB-88E2-591A8D43F1B2",
        "TeamIdentifier": [TEAM],
        "ExpirationDate": datetime.now(timezone.utc) + timedelta(days=30),
        "DeveloperCertificates": [CERTIFICATE],
        "Entitlements": {
            "application-identifier": TEAM + "." + BUNDLE,
            "get-task-allow": False,
            **deepcopy(REQUIRED),
        },
    }


class ProfileResolutionTests(unittest.TestCase):
    def setUp(self):
        self.bundle_response = {"data": [
            {"id": "original-bundle", "attributes": {"identifier": BUNDLE, "platform": "IOS"}},
            {"id": "other-extension", "attributes": {"identifier": BUNDLE + ".share", "platform": "IOS"}},
        ]}
        self.candidates = {"data": [
            {"id": "existing", "attributes": {"profileType": "IOS_APP_STORE", "profileState": "ACTIVE"}},
        ]}
        self.profiles = {"existing": valid_profile(), "created": valid_profile()}
        self.create = Mock(return_value={"data": {"id": "created"}})
        self.reads = []
        self.run_environment = patch.dict(os.environ, {"GITHUB_RUN_ID": "12345"})
        self.run_environment.start()
        self.addCleanup(self.run_environment.stop)

    def get(self, path, parameters):
        self.reads.append(path)
        if path == "/v1/bundleIds":
            return self.bundle_response
        if path == "/v1/bundleIds/original-bundle/profiles":
            return self.candidates
        identity = path.removeprefix("/v1/profiles/")
        if identity not in self.profiles:
            raise AssertionError("Unexpected resource path")
        return {"data": {"attributes": {
            "profileType": "IOS_APP_STORE", "profileState": "ACTIVE", "profileContent": identity,
        }}}

    def decode(self, encoded, directory):
        return ("fixture-cms-" + encoded).encode(), self.profiles[encoded]

    def resolve(self):
        return resolve_profile("ai", BUNDLE, REQUIRED, CERTIFICATE_SHA, "existing-cert", TEAM, ".",
                               get=self.get, create=self.create, decode_content=self.decode)

    def test_reuses_exact_compatible_profile_without_mutation(self):
        profile, facts = self.resolve()
        self.assertEqual(profile["bundle"], BUNDLE)
        self.assertEqual(facts["source"], "REUSED_COMPATIBLE_APPLE_PROFILE")
        self.assertEqual(facts["status"], "READY_RESOURCE")
        self.create.assert_not_called()

    def test_mismatched_or_expired_profiles_never_become_export_inputs(self):
        changes = [
            lambda p: p.update(DeveloperCertificates=[b"different-public-certificate"]),
            lambda p: p.update(TeamIdentifier=["WRONGTEAM"]),
            lambda p: p.update(ExpirationDate=datetime.now(timezone.utc) - timedelta(days=1)),
            lambda p: p["Entitlements"].update({"application-identifier": TEAM + ".other-app"}),
            lambda p: p["Entitlements"].update({"com.apple.security.application-groups": ["group.other"]}),
            lambda p: p["Entitlements"].update({"com.apple.developer.kernel.extended-virtual-addressing": False}),
            lambda p: p.update(ProvisionedDevices=["fixture-device"]),
        ]
        for change in changes:
            with self.subTest(change=changes.index(change)):
                self.profiles["existing"] = valid_profile()
                change(self.profiles["existing"])
                self.create.reset_mock()
                profile, facts = self.resolve()
                self.assertEqual(profile["content"], b"fixture-cms-created")
                self.assertEqual(facts["source"], "CREATED_AND_READ_BACK_APPLE_PROFILE")
                self.create.assert_called_once_with("original-bundle", "existing-cert", "Hanlin ai App Store 12345")

    def test_missing_profile_is_created_with_original_bundle_and_certificate(self):
        self.candidates["data"] = []
        _, facts = self.resolve()
        self.assertEqual(facts["status"], "READY_RESOURCE")
        self.create.assert_called_once_with("original-bundle", "existing-cert", "Hanlin ai App Store 12345")
        self.assertIn("/v1/profiles/created", self.reads)

    def test_created_profile_must_pass_the_same_entitlement_checks(self):
        self.candidates["data"] = []
        self.profiles["created"]["Entitlements"]["com.apple.security.application-groups"] = []
        with self.assertRaisesRegex(ValueError, "does not cover"):
            self.resolve()

    def test_partial_listing_cannot_authorize_creation(self):
        self.candidates["links"] = {"next": "https://api.appstoreconnect.apple.com/next"}
        with self.assertRaisesRegex(ValueError, "incomplete"):
            self.resolve()
        self.create.assert_not_called()

    def test_prefix_only_bundle_match_is_rejected(self):
        self.bundle_response["data"] = self.bundle_response["data"][1:]
        with self.assertRaisesRegex(ValueError, "missing or ambiguous"):
            self.resolve()
        self.create.assert_not_called()

    def test_unreadable_existing_profile_stops_without_creating_a_replacement(self):
        self.profiles["existing"].pop("ExpirationDate")
        with self.assertRaises(ValueError):
            self.resolve()
        self.create.assert_not_called()

    def test_uuid_cannot_escape_the_profile_cache(self):
        self.profiles["existing"]["UUID"] = "../../another-file"
        with self.assertRaises(ValueError):
            self.resolve()
        self.create.assert_not_called()

    def test_certificate_selection_requires_the_existing_public_certificate(self):
        response = {"data": [
            {"id": "wrong", "attributes": {"certificateType": "DISTRIBUTION",
                                           "certificateContent": base64.b64encode(b"other").decode()}},
            {"id": "original", "attributes": {"certificateType": "DISTRIBUTION",
                                              "certificateContent": base64.b64encode(CERTIFICATE).decode()}},
        ]}
        self.assertEqual(original_certificate_id(response, CERTIFICATE_SHA), "original")
        with self.assertRaisesRegex(ValueError, "exactly one"):
            original_certificate_id(response, hashlib.sha256(b"unavailable").hexdigest())
        response["data"].append(deepcopy(response["data"][1]))
        with self.assertRaisesRegex(ValueError, "exactly one"):
            original_certificate_id(response, CERTIFICATE_SHA)


class ProfileCacheTests(unittest.TestCase):
    def test_failed_private_write_leaves_no_profile_cache_entry(self):
        with tempfile.TemporaryDirectory() as directory:
            created = []
            with patch.object(Path, "chmod", side_effect=OSError("fixture permission failure")):
                with self.assertRaisesRegex(OSError, "fixture permission"):
                    install_profile({"uuid": valid_profile()["UUID"], "content": b"complete"},
                                    [directory], created)
            self.assertEqual(created, [])
            self.assertEqual(list(Path(directory).iterdir()), [])

    def test_cleanup_preserves_preexisting_identical_profiles(self):
        with tempfile.TemporaryDirectory() as directory:
            profile = {"uuid": valid_profile()["UUID"], "content": b"same"}
            created = []
            install_profile(profile, [directory], created)
            preexisting = list(Path(directory).glob("*"))
            second_job = []
            install_profile(profile, [directory], second_job)
            self.assertEqual(second_job, [])
            remove_installed_profiles(second_job)
            self.assertTrue(preexisting[0].exists())
            remove_installed_profiles(created)
            self.assertFalse(preexisting[0].exists())

    def test_different_uuid_collision_is_preserved(self):
        with tempfile.TemporaryDirectory() as directory:
            profile = {"uuid": valid_profile()["UUID"], "content": b"original"}
            created = []
            install_profile(profile, [directory], created)
            with self.assertRaisesRegex(ValueError, "different provisioning"):
                install_profile({**profile, "content": b"replacement"}, [directory], [])
            self.assertEqual(created[0][0].read_bytes(), b"original")
            remove_installed_profiles(created)

    def test_cleanup_continues_after_preserving_a_changed_profile(self):
        with tempfile.TemporaryDirectory() as directory:
            created = []
            install_profile({"uuid": valid_profile()["UUID"], "content": b"first"}, [directory], created)
            install_profile({"uuid": "FE74FFAB-4BD0-4EE0-B9B6-075465A1457A", "content": b"second"},
                            [directory], created)
            created[-1][0].write_bytes(b"changed-by-another-job")
            with self.assertRaisesRegex(ValueError, "changed during signing"):
                remove_installed_profiles(created)
            self.assertFalse(created[0][0].exists())
            self.assertEqual(created[-1][0].read_bytes(), b"changed-by-another-job")

    def test_cleanup_does_not_delete_a_profile_changed_by_another_job(self):
        with tempfile.TemporaryDirectory() as directory:
            created = []
            install_profile({"uuid": valid_profile()["UUID"], "content": b"original"}, [directory], created)
            created[0][0].write_bytes(b"changed-by-another-job")
            with self.assertRaisesRegex(ValueError, "changed during signing"):
                remove_installed_profiles(created)
            self.assertEqual(created[0][0].read_bytes(), b"changed-by-another-job")


if __name__ == "__main__":
    unittest.main()
