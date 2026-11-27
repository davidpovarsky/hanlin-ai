"""Portable controls for the exact local MiniApps release family; no Apple calls."""
import base64
from datetime import datetime, timedelta, timezone
import hashlib
import json
import os
from pathlib import Path
import plistlib
import tempfile
import unittest
from unittest.mock import Mock, patch
import uuid

from audit_release_resources import ROOT, product_roles
from resolve_signing_profiles import resolve_local_miniapps_profiles
from test_local_distribution_profiles import CERTIFICATE, CERTIFICATE_SHA, SOURCE, BUILD, TEAM


class MiniAppsLocalProfilesTests(unittest.TestCase):
    def setUp(self):
        environment = patch.dict(os.environ, {"APPLE_TEAM_ID": TEAM, "GITHUB_RUN_ID": ""})
        environment.start()
        self.addCleanup(environment.stop)
        self.roles = product_roles("miniapps")
        self.by_role = {role: (bundle, source) for role, bundle, _, source in self.roles}
        self.required = {role: plistlib.loads((ROOT / source).read_bytes())
                         for role, (_, source) in self.by_role.items()}
        def expand(value):
            if isinstance(value, str):
                return (value.replace("$(APS_ENVIRONMENT)", "production")
                        .replace("$(AppIdentifierPrefix)", TEAM + ".")
                        .replace("$(TeamIdentifierPrefix)", TEAM + "."))
            if isinstance(value, list):
                return [expand(item) for item in value]
            return value
        self.profiles = {}
        for role, (bundle, _) in self.by_role.items():
            self.profiles[role] = {
                "UUID": str(uuid.uuid5(uuid.NAMESPACE_DNS, bundle)).upper(),
                "ApplicationIdentifierPrefix": [TEAM], "TeamIdentifier": [TEAM],
                "ExpirationDate": datetime.now(timezone.utc) + timedelta(days=30),
                "DeveloperCertificates": [CERTIFICATE],
                "Entitlements": {**{key: expand(value) for key, value in self.required[role].items()},
                                 "application-identifier": TEAM + "." + bundle,
                                 "get-task-allow": False},
            }
        self.missing = set()
        self.reads = []
        self.get = Mock(side_effect=self.read)
        self.create = Mock(side_effect=lambda bundle, cert, name: {
            "data": {"id": bundle.removesuffix("-bundle") + "-created"}})

    def read(self, path, parameters):
        self.reads.append((path, parameters))
        if path == "/v1/certificates":
            return {"data": [{"id": "original-certificate", "attributes": {
                "certificateType": "DISTRIBUTION",
                "certificateContent": base64.b64encode(CERTIFICATE).decode()}}]}
        if path == "/v1/bundleIds":
            requested = parameters["filter[identifier]"]
            # Apple actually returns prefix matches: the main lookup includes extensions.
            return {"data": [{"id": role + "-bundle", "attributes": {
                "identifier": bundle, "platform": "IOS"}}
                for role, (bundle, _) in self.by_role.items() if bundle.startswith(requested)]}
        if path.endswith("-bundle/profiles"):
            role = path.split("/")[-2].removesuffix("-bundle")
            return {"data": [] if role in self.missing else [{"id": role + "-existing",
                "attributes": {"profileType": "IOS_APP_STORE", "profileState": "ACTIVE"}}]}
        if path.startswith("/v1/profiles/"):
            identity = path.split("/")[-1]
            return {"data": {"attributes": {"profileType": "IOS_APP_STORE",
                    "profileState": "ACTIVE", "profileContent": identity}}}
        self.fail("Unexpected account request: " + path)

    def decode(self, value, directory):
        role = value.removesuffix("-existing").removesuffix("-created")
        return ("fixture-cms-" + value).encode(), self.profiles[role]

    def resolve(self, **kwargs):
        facts = []
        result = resolve_local_miniapps_profiles(
            CERTIFICATE_SHA, ".", facts, source_sha=kwargs.pop("source_sha", SOURCE),
            build_number=BUILD, get=self.get, create=self.create,
            decode_content=self.decode, **kwargs)
        return result, facts

    def test_all_eight_owned_roles_reuse_profiles_with_exact_prefix_matching(self):
        result, facts = self.resolve()
        self.assertEqual(len(result), 8)
        self.assertEqual({p["bundle"] for p in result}, {b for _, b, _, _ in self.roles})
        self.assertEqual(len({p["uuid"] for p in result}), 8)
        self.create.assert_not_called()
        for fact in facts:
            self.assertEqual(fact["status"], "READY_RESOURCE")
            self.assertEqual(fact["local_release_context"]["provider"], "local-mac")
            self.assertEqual(fact["entitlements_sha256"],
                hashlib.sha256((ROOT / fact["entitlements_path"]).read_bytes()).hexdigest())
        self.assertNotIn("fixture-cms-", json.dumps(facts))
        self.assertTrue(all(params["filter[identifier]"].startswith("com.itorah.hanlinminiapps")
                           for path, params in self.reads if path == "/v1/bundleIds"))

    def test_missing_extension_is_created_once_and_get_cms_is_authoritative(self):
        self.missing.add("miniapps_notification_service")
        _, facts = self.resolve()
        self.create.assert_called_once()
        self.assertEqual(self.create.call_args.args[0], "miniapps_notification_service-bundle")
        self.assertIn("/v1/profiles/miniapps_notification_service-created",
                      [path for path, _ in self.reads])
        created = next(fact for fact in facts if fact["role"] == "miniapps_notification_service")
        self.assertEqual(created["source"], "CREATED_AND_READ_BACK_APPLE_PROFILE")
        self.assertEqual(sum(fact["source"] == "CREATED_AND_READ_BACK_APPLE_PROFILE" for fact in facts), 1)

    def test_unassigned_extension_app_group_is_rejected_even_with_valid_main(self):
        role = "miniapps_share"
        self.profiles[role]["Entitlements"]["com.apple.security.application-groups"] = []
        with self.assertRaisesRegex(ValueError, "application-groups"):
            self.resolve()
        self.create.assert_called_once()
        self.assertEqual(self.create.call_args.args[0], role + "-bundle")

    def test_widget_icloud_container_stays_required(self):
        self.profiles["miniapps_widgets"]["Entitlements"]["com.apple.developer.icloud-container-identifiers"] = []
        with self.assertRaisesRegex(ValueError, "icloud-container-identifiers"):
            self.resolve()
        self.create.assert_called_once()

    def test_studio_document_container_remains_required_with_cloudkit_granted(self):
        key = "com.apple.developer.ubiquity-container-identifiers"
        self.assertEqual(self.required["miniapps"].get(key), ["iCloud.com.itorah.chavrusachat"])
        original = self.profiles["miniapps"]["Entitlements"].copy()
        for grant in (None, [], ["iCloud.com.itorah.other"]):
            with self.subTest(grant=grant):
                entitlements = original.copy()
                if grant is None:
                    entitlements.pop(key)
                else:
                    entitlements[key] = grant
                self.profiles["miniapps"]["Entitlements"] = entitlements
                self.create.reset_mock()
                with self.assertRaisesRegex(ValueError, "ubiquity-container-identifiers"):
                    self.resolve()
                self.create.assert_called_once()
                self.assertEqual(self.create.call_args.args[0], "miniapps-bundle")

    def test_all_source_plists_are_loaded_before_any_account_request(self):
        with tempfile.TemporaryDirectory() as folder:
            for _, _, _, source in self.roles[:-1]:
                path = Path(folder) / source
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_bytes((ROOT / source).read_bytes())
            with self.assertRaises(FileNotFoundError):
                self.resolve(source_root=folder)
        self.get.assert_not_called()
        self.create.assert_not_called()

    def test_invalid_release_identity_precedes_any_account_request(self):
        with self.assertRaisesRegex(ValueError, "Local Mac profile naming"):
            self.resolve(source_sha="not-a-source-sha")
        self.get.assert_not_called()
        self.create.assert_not_called()


if __name__ == "__main__":
    unittest.main()
