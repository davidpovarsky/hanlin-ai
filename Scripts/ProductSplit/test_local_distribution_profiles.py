"""Portable contract checks for local main/Widgets profile reconciliation."""
from copy import deepcopy
from datetime import datetime, timedelta, timezone
import base64
import hashlib
import json
import os
from pathlib import Path
import plistlib
import tempfile
import unittest
from unittest.mock import Mock, patch

from audit_release_resources import AppleReadFailure, ROOT, ROLES, evaluate_profile
from resolve_signing_profiles import resolve_local_distribution_profiles, resolve_profile

TEAM = "FIXTURETEAM"
CERTIFICATE = b"fixture-public-certificate"
CERTIFICATE_SHA = hashlib.sha256(CERTIFICATE).hexdigest()
SOURCE = "85e374570dba0ca464f9b64c9085b8e9f8d445d4"
BUILD = "148901"
TARGETS = {role: (bundle, source) for role, bundle, _, source in ROLES if role in {"ai", "widgets"}}


def required_for(role):
    return plistlib.loads((ROOT / TARGETS[role][1]).read_bytes())


def valid_profile(role):
    def expanded(value):
        if isinstance(value, str):
            return (value.replace("$(APS_ENVIRONMENT)", "production")
                    .replace("$(TeamIdentifierPrefix)", TEAM + ".")
                    .replace("$(AppIdentifierPrefix)", TEAM + "."))
        if isinstance(value, list):
            return [expanded(item) for item in value]
        return value
    return {
        "Name": "Fixture " + role,
        "UUID": "0E5A9288-4FB6-4ADB-88E2-591A8D43F1B2" if role == "ai" else "FE74FFAB-4BD0-4EE0-B9B6-075465A1457A",
        "ApplicationIdentifierPrefix": [TEAM],
        "TeamIdentifier": [TEAM],
        "ExpirationDate": datetime.now(timezone.utc) + timedelta(days=30),
        "DeveloperCertificates": [CERTIFICATE],
        "Entitlements": {
            **{key: expanded(value) for key, value in required_for(role).items()},
            "application-identifier": TEAM + "." + TARGETS[role][0],
            "get-task-allow": False,
        },
    }


def assess(profile, role="ai"):
    return evaluate_profile(profile, required_for(role), TARGETS[role][0],
                            TEAM, CERTIFICATE_SHA, datetime.now(timezone.utc))


class ApplicationPrefixTests(unittest.TestCase):
    def test_actual_main_and_widgets_source_entitlements_are_covered(self):
        for role in TARGETS:
            with self.subTest(role=role):
                self.assertIn("$(AppIdentifierPrefix)", required_for(role)["keychain-access-groups"][0])
                result = assess(valid_profile(role), role)
                self.assertEqual(result["status"], "READY_RESOURCE")
                self.assertEqual(result["missing_or_mismatched_entitlement_keys"], [])

    def test_invalid_or_ambiguous_prefix_cannot_be_hidden_by_wildcard_grants(self):
        for prefix in [None, [], TEAM, [TEAM, "OTHER"], ["OTHER"], [None], [42],
                       [""], [TEAM + "."], [" " + TEAM]]:
            with self.subTest(prefix=prefix):
                profile = valid_profile("ai")
                if prefix is None:
                    profile.pop("ApplicationIdentifierPrefix")
                else:
                    profile["ApplicationIdentifierPrefix"] = prefix
                profile["Entitlements"]["keychain-access-groups"] = ["*"]
                result = assess(profile)
                self.assertEqual(result["status"], "BLOCKED")
                self.assertIn("keychain-access-groups", result["missing_or_mismatched_entitlement_keys"])

    def test_prefix_must_match_actual_application_identifier(self):
        profile = valid_profile("ai")
        profile["Entitlements"]["application-identifier"] = "OTHER." + TARGETS["ai"][0]
        profile["Entitlements"]["keychain-access-groups"] = ["*"]
        result = assess(profile)
        self.assertFalse(result["checks"]["bundle_matches"])
        self.assertIn("keychain-access-groups", result["missing_or_mismatched_entitlement_keys"])

    def test_granted_keychain_group_must_cover_exact_prefix_and_service(self):
        for granted in [["OTHER.com.itorah.chavrusachat.scriptwidget.services"],
                        [TEAM + ".another-service"], []]:
            with self.subTest(granted=granted):
                profile = valid_profile("ai")
                profile["Entitlements"]["keychain-access-groups"] = granted
                self.assertEqual(assess(profile)["missing_or_mismatched_entitlement_keys"],
                                 ["keychain-access-groups"])

    def test_icloud_capability_without_the_source_container_is_rejected(self):
        profile = valid_profile("widgets")
        profile["Entitlements"]["com.apple.developer.icloud-container-identifiers"] = []
        result = assess(profile, "widgets")
        self.assertEqual(result["status"], "BLOCKED")
        self.assertEqual(result["missing_or_mismatched_entitlement_keys"],
                         ["com.apple.developer.icloud-container-identifiers"])


class LocalResolutionTests(unittest.TestCase):
    def setUp(self):
        self.environment = patch.dict(os.environ, {"APPLE_TEAM_ID": TEAM, "GITHUB_RUN_ID": "12345"})
        self.environment.start()
        self.addCleanup(self.environment.stop)
        self.candidates = {role: [role + "-existing"] for role in TARGETS}
        self.profiles = {role + "-" + state: valid_profile(role)
                         for role in TARGETS for state in ["existing", "created"]}
        self.reads = []
        self.create = Mock(side_effect=self.create_response)
        self.get = Mock(side_effect=self.read_response)

    def create_response(self, bundle_id, certificate_id, name):
        self.assertEqual(certificate_id, "existing-cert")
        role = bundle_id.removesuffix("-bundle")
        self.assertIn(role, TARGETS)
        # Creation content is not authoritative: the resolver must GET this ID.
        return {"data": {"id": role + "-created",
                         "attributes": {"profileContent": "UNTRUSTED_POST_CONTENT"}}}

    def read_response(self, path, parameters):
        self.reads.append((path, parameters))
        if path == "/v1/certificates":
            return {"data": [{"id": "existing-cert", "attributes": {
                "certificateType": "DISTRIBUTION",
                "certificateContent": base64.b64encode(CERTIFICATE).decode()}}]}
        if path == "/v1/bundleIds":
            bundle = parameters["filter[identifier]"]
            role = next(role for role, (identifier, _) in TARGETS.items() if identifier == bundle)
            return {"data": [{"id": role + "-bundle",
                              "attributes": {"identifier": bundle, "platform": "IOS"}}]}
        for role in TARGETS:
            if path == "/v1/bundleIds/" + role + "-bundle/profiles":
                return {"data": [{"id": identity, "attributes": {
                    "profileType": "IOS_APP_STORE", "profileState": "ACTIVE"}}
                    for identity in self.candidates[role]]}
        if path.startswith("/v1/profiles/"):
            identity = path.removeprefix("/v1/profiles/")
            self.assertIn(identity, self.profiles)
            return {"data": {"attributes": {"profileType": "IOS_APP_STORE",
                    "profileState": "ACTIVE", "profileContent": identity}}}
        self.fail("Unexpected Apple operation: " + path)

    def decode(self, encoded, directory):
        return ("fixture-cms-" + encoded).encode(), self.profiles[encoded]

    def resolve_pair(self, **kwargs):
        facts = []
        result = resolve_local_distribution_profiles(
            CERTIFICATE_SHA, ".", facts, source_sha=kwargs.get("source_sha", SOURCE),
            build_number=kwargs.get("build_number", BUILD),
            get=self.get, create=self.create, decode_content=self.decode)
        return result, facts

    def resolve_main(self, **kwargs):
        return resolve_profile("ai", TARGETS["ai"][0], required_for("ai"), CERTIFICATE_SHA,
                               "existing-cert", TEAM, ".", get=self.get, create=self.create,
                               decode_content=self.decode, **kwargs)

    def test_pair_reuses_existing_profiles_and_returns_private_metadata_separately(self):
        profiles, facts = self.resolve_pair()
        self.create.assert_not_called()
        self.assertEqual({p["bundle"] for p in profiles}, {value[0] for value in TARGETS.values()})
        self.assertEqual({p["profile_id"] for p in profiles}, {"ai-existing", "widgets-existing"})
        for profile, fact in zip(profiles, facts):
            self.assertEqual(fact["source"], "REUSED_COMPATIBLE_APPLE_PROFILE")
            self.assertEqual(fact["local_release_context"]["source_sha"], SOURCE)
            self.assertEqual(fact["entitlements_sha256"],
                             hashlib.sha256((ROOT / fact["entitlements_path"]).read_bytes()).hexdigest())
            self.assertIn("Name", profile["decoded"])
            self.assertIsInstance(profile["content"], bytes)
        receipt = json.dumps(facts)
        self.assertNotIn("fixture-cms-", receipt)
        self.assertNotIn("DeveloperCertificates", receipt)
        bundles = {parameters["filter[identifier]"] for path, parameters in self.reads if path == "/v1/bundleIds"}
        self.assertEqual(bundles, {value[0] for value in TARGETS.values()})

    def test_later_compatible_candidate_is_reused_before_any_creation(self):
        self.profiles["ai-incompatible"] = valid_profile("ai")
        self.profiles["ai-incompatible"]["Entitlements"]["com.apple.developer.homekit"] = False
        self.candidates["ai"].insert(0, "ai-incompatible")
        profiles, facts = self.resolve_pair()
        self.create.assert_not_called()
        self.assertEqual(profiles[0]["profile_id"], "ai-existing")
        self.assertEqual(len(facts[0]["examined_existing_profiles"]), 2)

    def test_missing_pair_has_one_creation_each_and_full_get_readback(self):
        self.candidates = {role: [] for role in TARGETS}
        profiles, facts = self.resolve_pair()
        self.assertEqual(self.create.call_count, 2)
        self.assertEqual([call.args for call in self.create.call_args_list], [
            ("ai-bundle", "existing-cert", "Hanlin ai App Store Mac " + BUILD + " " + SOURCE[:12]),
            ("widgets-bundle", "existing-cert", "Hanlin widgets App Store Mac " + BUILD + " " + SOURCE[:12]),
        ])
        self.assertEqual({p["content"] for p in profiles},
                         {b"fixture-cms-ai-created", b"fixture-cms-widgets-created"})
        for role in TARGETS:
            self.assertIn("/v1/profiles/" + role + "-created", [path for path, _ in self.reads])
        self.assertTrue(all(fact["status"] == "READY_RESOURCE" for fact in facts))

    def test_created_widget_with_empty_container_is_rejected_without_retry(self):
        self.candidates["widgets"] = []
        self.profiles["widgets-created"]["Entitlements"]["com.apple.developer.icloud-container-identifiers"] = []
        with self.assertRaisesRegex(ValueError, "icloud-container-identifiers"):
            self.resolve_pair()
        self.assertEqual(self.create.call_count, 1)
        self.assertEqual(self.create.call_args.args[0], "widgets-bundle")

    def test_invalid_local_naming_fails_before_any_account_read_or_write(self):
        cases = [(None, BUILD), ("bad", BUILD), (SOURCE.upper(), BUILD), (SOURCE + "0", BUILD),
                 (SOURCE, None), (SOURCE, 148901), (SOURCE, True), (SOURCE, "0"),
                 (SOURCE, "0148901"), (SOURCE, "148901\n"), (SOURCE, "1" * 19)]
        for source_sha, build in cases:
            with self.subTest(source_sha=source_sha, build=build):
                self.get.reset_mock()
                self.create.reset_mock()
                with self.assertRaisesRegex(ValueError, "Local Mac profile naming"):
                    self.resolve_pair(source_sha=source_sha, build_number=build)
                self.get.assert_not_called()
                self.create.assert_not_called()

    def test_partial_local_context_cannot_fall_back_to_gha(self):
        for arguments in [{"local_source_sha": SOURCE}, {"local_build_number": BUILD}]:
            with self.subTest(arguments=arguments):
                self.get.reset_mock()
                with self.assertRaisesRegex(ValueError, "Local Mac profile naming"):
                    self.resolve_main(**arguments)
                self.get.assert_not_called()
                self.create.assert_not_called()

    def test_explicit_local_naming_does_not_require_or_change_github_environment(self):
        self.candidates["ai"] = []
        with patch.dict(os.environ, {"GITHUB_RUN_ID": ""}):
            _, facts = self.resolve_main(local_source_sha=SOURCE, local_build_number=BUILD)
            self.assertEqual(os.environ["GITHUB_RUN_ID"], "")
        self.assertEqual(facts["local_release_context"]["provider"], "local-mac")
        self.assertEqual(self.create.call_args.args[2], "Hanlin ai App Store Mac " + BUILD + " " + SOURCE[:12])

    def test_original_numeric_github_creation_default_is_unchanged(self):
        self.candidates["ai"] = []
        _, facts = self.resolve_main()
        self.create.assert_called_once_with("ai-bundle", "existing-cert", "Hanlin ai App Store 12345")
        self.assertNotIn("local_release_context", facts)

    def test_default_still_rejects_missing_or_nonnumeric_github_run(self):
        self.candidates["ai"] = []
        for value in ["", "local-mac", "0", "12345\n"]:
            with self.subTest(value=value), patch.dict(os.environ, {"GITHUB_RUN_ID": value}):
                self.create.reset_mock()
                with self.assertRaisesRegex(ValueError, "concrete original GitHub run"):
                    self.resolve_main()
                self.create.assert_not_called()

    def test_uncertain_creation_is_not_retried(self):
        self.candidates["ai"] = []
        self.create.side_effect = AppleReadFailure("PROFILE_CREATE_OUTCOME_UNKNOWN_RECONCILE_BEFORE_RETRY")
        with self.assertRaisesRegex(AppleReadFailure, "OUTCOME_UNKNOWN"):
            self.resolve_pair()
        self.assertEqual(self.create.call_count, 1)
        self.assertNotIn("/v1/profiles/ai-created", [path for path, _ in self.reads])

    def test_wrong_certificate_prevents_all_profile_resolution(self):
        with self.assertRaisesRegex(ValueError, "exactly one Apple record"):
            resolve_local_distribution_profiles(
                hashlib.sha256(b"another-certificate").hexdigest(), ".", [],
                source_sha=SOURCE, build_number=BUILD,
                get=self.get, create=self.create, decode_content=self.decode)
        self.create.assert_not_called()
        self.assertEqual([path for path, _ in self.reads], ["/v1/certificates"])


if __name__ == "__main__":
    unittest.main()
