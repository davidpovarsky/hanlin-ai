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

    def resolve(self, **kwargs):
        return resolve_profile("ai", BUNDLE, REQUIRED, CERTIFICATE_SHA, "existing-cert", TEAM, ".",
                               get=self.get, create=self.create, decode_content=self.decode, **kwargs)

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

    def test_explicit_local_release_context_creates_profile_without_fabricated_github_run(self):
        self.candidates["data"] = []
        source_sha = "a" * 40
        with patch.dict(os.environ, {"GITHUB_RUN_ID": ""}):
            _, facts = self.resolve(local_source_sha=source_sha, local_build_number="8302")
        self.create.assert_called_once_with("original-bundle", "existing-cert",
                                           "Hanlin ai App Store Mac 8302 " + source_sha[:12])
        self.assertEqual(facts["local_release_context"],
                         {"provider": "local-mac", "source_sha": source_sha, "build_number": "8302"})
        self.assertEqual(facts["status"], "READY_RESOURCE")
        self.assertIn("/v1/profiles/created", self.reads)

    def test_invalid_local_release_context_cannot_create_a_profile(self):
        self.candidates["data"] = []
        for source, build in (("../other", "8302"), ("two words", "8302"),
                              ("x" * 81, "8302"), ("a" * 40, "0"), ("a" * 40, None)):
            with self.subTest(source=source, build=build):
                with self.assertRaisesRegex(ValueError, "Local Mac profile naming"):
                    self.resolve(local_source_sha=source, local_build_number=build)
        self.create.assert_not_called()
        self.assertEqual(self.reads, [])

    def test_generic_operation_tag_cannot_replace_a_concrete_release_context(self):
        self.candidates["data"] = []
        # The incoming generic tag is not the root's source SHA/build contract.
        with patch.dict(os.environ, {"GITHUB_RUN_ID": "", "HANLIN_SIGNING_OPERATION_ID": "four-entrypoints-20261126"}):
            with self.assertRaisesRegex(ValueError, "concrete original GitHub run"):
                self.resolve()
        self.create.assert_not_called()

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




class SigningAdmissionDiagnosticTests(unittest.TestCase):
    def test_native_cms_integer_boolean_output_is_classified_without_claiming_xcode_admission(self):
        import json
        from signing_profile_preflight import _native_cms_signatures_valid
        # The actual Security.framework program emitted these numeric flags on
        # run44431826560. JSON booleans from explicit NSNumber BOOL are also valid.
        row = json.loads('{"read_ok":1,"decoder_status":0,"signer_count_status":0,'
                         '"signer_count":1,"signers":[{"api_status":0,"signer_status":1,'
                         '"certificate_status":0,"trust_result_status":0,"trust_result":4,'
                         '"signature_and_certificate_valid":1}]}')
        self.assertTrue(_native_cms_signatures_valid([row]))
        row["read_ok"] = True
        row["signers"][0]["signature_and_certificate_valid"] = True
        self.assertTrue(_native_cms_signatures_valid([row]))

    def test_cms_flags_reject_truthy_non_boolean_values_and_missing_signature(self):
        from signing_profile_preflight import _native_cms_signatures_valid
        for value in [False, 0, -1, 2, 1.0, "1", "true", None, [], {}]:
            with self.subTest(value=value):
                row = {"read_ok": True, "decoder_status": 0, "signer_count_status": 0,
                       "signer_count": 1, "signers": [{"signature_and_certificate_valid": value}]}
                self.assertFalse(_native_cms_signatures_valid([row]))
                row["read_ok"] = value
                row["signers"][0]["signature_and_certificate_valid"] = True
                self.assertFalse(_native_cms_signatures_valid([row]))

    def test_cms_signature_status_binds_exact_original_bytes_and_never_claims_xcode_acceptance(self):
        import json
        import time
        from signing_profile_preflight import profile_cms_diagnostics
        profile = {"uuid": valid_profile()["UUID"], "bundle": BUNDLE, "content": b"original-cms"}
        with tempfile.TemporaryDirectory() as directory:
            home = Path(directory)
            cache = home / "Library/Developer/Xcode/UserData/Provisioning Profiles"
            cache.mkdir(parents=True)
            (cache / (profile["uuid"] + ".mobileprovision")).write_bytes(profile["content"])
            report = {"format_version": 1, "profiles": [{
                "index": 0, "read_ok": True, "input_sha256": hashlib.sha256(profile["content"]).hexdigest(),
                "decoder_status": 0, "signer_count_status": 0, "signer_count": 1,
                "signers": [{"signature_and_certificate_valid": True}],
            }]}
            run = Mock(side_effect=[(0, ""), (0, json.dumps(report))])
            with patch.object(Path, "home", return_value=home):
                receipt = profile_cms_diagnostics(home, [profile], run, time.monotonic() + 60)
            self.assertEqual(receipt["status"], "CMS_SIGNATURES_VALID")
            self.assertIn("NOT_XCODE_ACCEPTANCE", receipt["scope"])
            self.assertEqual(receipt["profiles"][0]["bundle_id"], BUNDLE)

    def test_decodable_cms_without_valid_signature_or_signer_never_becomes_valid(self):
        import json
        import time
        from signing_profile_preflight import profile_cms_diagnostics
        profile = {"uuid": valid_profile()["UUID"], "bundle": BUNDLE, "content": b"original-cms"}
        for signature_valid, count in [(False, 1), (True, 0)]:
            with self.subTest(signature_valid=signature_valid, count=count), tempfile.TemporaryDirectory() as directory:
                home = Path(directory)
                cache = home / "Library/Developer/Xcode/UserData/Provisioning Profiles"
                cache.mkdir(parents=True)
                (cache / (profile["uuid"] + ".mobileprovision")).write_bytes(profile["content"])
                report = {"format_version": 1, "profiles": [{
                    "index": 0, "read_ok": True,
                    "input_sha256": hashlib.sha256(profile["content"]).hexdigest(),
                    "decoder_status": 0, "signer_count_status": 0, "signer_count": count,
                    "signers": [{"signature_and_certificate_valid": signature_valid}] if count else [],
                }]}
                run = Mock(side_effect=[(0, ""), (0, json.dumps(report))])
                with patch.object(Path, "home", return_value=home):
                    receipt = profile_cms_diagnostics(home, [profile], run, time.monotonic() + 60)
                self.assertEqual(receipt["status"], "CMS_SIGNATURE_OR_TRUST_REJECTED")

    def test_diagnostic_for_different_profile_cannot_prove_selected_profile(self):
        import json
        import time
        from signing_profile_preflight import profile_cms_diagnostics
        profile = {"uuid": valid_profile()["UUID"], "bundle": BUNDLE, "content": b"original-cms"}
        with tempfile.TemporaryDirectory() as directory:
            home = Path(directory)
            cache = home / "Library/Developer/Xcode/UserData/Provisioning Profiles"
            cache.mkdir(parents=True)
            (cache / (profile["uuid"] + ".mobileprovision")).write_bytes(profile["content"])
            run = Mock(side_effect=[(0, ""), (0, json.dumps({"format_version": 1, "profiles": [
                {"index": 0, "input_sha256": hashlib.sha256(b"other-cms").hexdigest()}
            ]}))])
            with patch.object(Path, "home", return_value=home):
                receipt = profile_cms_diagnostics(home, [profile], run, time.monotonic() + 60)
            self.assertEqual(receipt["status"], "DIAGNOSTIC_UNAVAILABLE")

    def test_changed_installed_bytes_stop_before_signature_inspection(self):
        import time
        from signing_profile_preflight import profile_cms_diagnostics
        profile = {"uuid": valid_profile()["UUID"], "bundle": BUNDLE, "content": b"original-cms"}
        with tempfile.TemporaryDirectory() as directory:
            home = Path(directory)
            cache = home / "Library/Developer/Xcode/UserData/Provisioning Profiles"
            cache.mkdir(parents=True)
            (cache / (profile["uuid"] + ".mobileprovision")).write_bytes(b"changed")
            run = Mock()
            with patch.object(Path, "home", return_value=home):
                with self.assertRaisesRegex(RuntimeError, "changed before"):
                    profile_cms_diagnostics(home, [profile], run, time.monotonic() + 60)
            run.assert_not_called()

    def test_owned_log_scope_rejects_other_process_and_retains_no_unowned_data(self):
        import json
        from signing_profile_preflight import retain_owned_xcode_signing_logs
        with tempfile.TemporaryDirectory() as directory:
            target = Path(directory) / "owned.json"
            process = Mock(returncode=0, stdout=json.dumps([
                {"processID": 999, "eventMessage": "profile from another job"}
            ]).encode())
            with patch("signing_profile_preflight.subprocess.run", return_value=process):
                with self.assertRaisesRegex(RuntimeError, "unowned"):
                    retain_owned_xcode_signing_logs(123, "2026-11-19 00:00:00", "2026-11-19 00:01:00",
                                                   target, lambda value: value)
            self.assertFalse(target.exists())

    def test_owned_log_scope_preserves_only_sanitized_signing_events(self):
        import json
        from signing_profile_preflight import retain_owned_xcode_signing_logs
        with tempfile.TemporaryDirectory() as directory:
            target = Path(directory) / "owned.json"
            process = Mock(returncode=0, stdout=json.dumps([
                {"processID": 123, "eventMessage": "profile lookup SECRET", "category": "profile"},
                {"processID": 123, "eventMessage": "unrelated work", "category": "other"},
            ]).encode())
            with patch("signing_profile_preflight.subprocess.run", return_value=process) as invoked:
                receipt = retain_owned_xcode_signing_logs(
                    123, "2026-11-19 00:00:00", "2026-11-19 00:01:00",
                    target, lambda value: value.replace("SECRET", "[REDACTED]"))
            self.assertEqual(receipt["events"], 1)
            self.assertNotIn("SECRET", target.read_text())
            self.assertNotIn("unrelated", target.read_text())
            argv = invoked.call_args.args[0]
            self.assertIn("processID == 123", argv[argv.index("--predicate") + 1])
            self.assertIn("--start", argv)
            self.assertIn("--end", argv)
            self.assertEqual(invoked.call_args.kwargs["timeout"], 15)

    def test_owned_process_records_actual_exit_and_pid(self):
        import sys
        from signing_profile_preflight import run_owned_process
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "child.log"
            with output.open("wb") as stream:
                code, pid = run_owned_process(
                    [sys.executable, "-c", "print('owned-child'); raise SystemExit(7)"],
                    directory, stream, 5)
            self.assertEqual(code, 7)
            self.assertGreater(pid, 1)
            self.assertIn("owned-child", output.read_text())

    def test_owned_process_timeout_finishes_its_child(self):
        import sys
        from signing_profile_preflight import run_owned_process
        with tempfile.TemporaryDirectory() as directory:
            with (Path(directory) / "child.log").open("wb") as stream:
                code, pid = run_owned_process(
                    [sys.executable, "-c", "import time; time.sleep(30)"],
                    directory, stream, 0.05)
            self.assertEqual(code, -1)
            self.assertGreater(pid, 1)

    def test_failed_native_archive_records_attempt_without_export_or_product_build(self):
        import plistlib
        import signing_profile_preflight as native
        profile = {"uuid": valid_profile()["UUID"], "bundle": "com.itorah.hanlinminiapps",
                   "content": b"original-cms"}
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = next(item[3] for item in native.ROLES if item[1] == profile["bundle"])
            entitlements = root / source
            entitlements.parent.mkdir(parents=True)
            entitlements.write_bytes(plistlib.dumps({}))
            receipt = {}
            run = Mock(return_value=(65, "No profile matching selected UUID found"))
            with patch.object(native, "ROOT", root), patch.object(
                    native, "profile_cms_diagnostics", return_value={"status": "CMS_SIGNATURES_VALID"}), patch.object(
                    native, "observe_owned_signing_build_settings", side_effect=ValueError("diagnostic failure")):
                with self.assertRaisesRegex(RuntimeError, "failed before original"):
                    native.run_profile_discovery_preflight(root, [profile], TEAM, "certificate-identity",
                                                           CERTIFICATE_SHA, run, receipt)
            self.assertEqual(receipt["status"], "EXECUTED_FAIL")
            self.assertEqual(receipt["native_products"][0]["archive"], "EXECUTED_FAIL")
            self.assertEqual(receipt["native_products"][0]["export"], "NOT_RUN")
            self.assertEqual(receipt["native_products"][0]["build_settings_diagnostic"]["status"],
                             "DIAGNOSTIC_UNAVAILABLE")
            self.assertEqual(run.call_count, 1)
            self.assertIn("PROVISIONING_PROFILE_SPECIFIER=" + profile["uuid"], run.call_args.args[0])


class OwnedSigningBuildSettingsTests(unittest.TestCase):
    def test_owned_target_projection_keeps_only_bound_signing_facts(self):
        import json
        import time
        import os
        import signing_profile_preflight as native
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            project = root / "ProfileDiscovery.xcodeproj"
            project.mkdir()
            nonce = "a" * 32
            argv = ["xcodebuild", "-project", project, "-scheme", "ProfileDiscovery", "archive",
                    "DEVELOPMENT_TEAM=" + TEAM, "PRODUCT_BUNDLE_IDENTIFIER=" + BUNDLE,
                    "HANLIN_PROFILE_DISCOVERY_NONCE=" + nonce]
            settings = {"PROJECT_FILE_PATH": str(project), "HANLIN_PROFILE_DISCOVERY_NONCE": nonce,
                        "CODE_SIGN_STYLE": "Manual", "DEVELOPMENT_TEAM": TEAM,
                        "PRODUCT_BUNDLE_IDENTIFIER": BUNDLE, "SDKROOT": "/Applications/Xcode.app/iPhoneOS27.2.sdk",
                        "PROVISIONING_PROFILE_SPECIFIER": "Private human profile name",
                        "UNRELATED_SECRET": "DO_NOT_RETAIN_THIS"}
            result = Mock(returncode=0, stdout=json.dumps([
                {"target": "ProfileDiscovery", "buildSettings": settings}]).encode(), stderr=b"")
            with patch.object(native.subprocess, "run", return_value=result) as invoked, patch.dict(
                    os.environ, {"XCODE_XCCONFIG_FILE": "/private/sensitive-key-name.p8",
                                 "UNRELATED_SECRET": "DO_NOT_RETAIN_THIS"}):
                receipt = native.observe_owned_signing_build_settings(argv, root, nonce, time.monotonic() + 30)
            self.assertEqual(receipt["status"], "OBSERVED_SETTINGS")
            self.assertTrue(receipt["project_and_nonce_match"])
            self.assertTrue(receipt["settings"]["DEVELOPMENT_TEAM"]["matches_selected_argument"])
            self.assertEqual(receipt["settings"]["SDKROOT"]["value"], "iPhoneOS27.2.sdk")
            encoded = json.dumps(receipt)
            for private in [TEAM, "DO_NOT_RETAIN_THIS", "sensitive-key-name.p8", "Private human profile name"]:
                self.assertNotIn(private, encoded)
            actual = invoked.call_args.args[0]
            self.assertEqual(actual, ["xcodebuild", "-showBuildSettings", "-json",
                                      *[str(value) for value in argv[1:]]])
            self.assertEqual(receipt["selected_scheme_action"], "archive")
            self.assertEqual(receipt["query_mode"], "showBuildSettings")
            self.assertEqual(invoked.call_count, 1)
            self.assertLessEqual(invoked.call_args.kwargs["timeout"], 15)
            self.assertEqual(set(receipt["inherited_environment"]),
                             {"HOME", "CFFIXED_USER_HOME", "DEVELOPER_DIR", "XCODE_XCCONFIG_FILE", "SDKROOT"})

    def test_command_failure_retains_redacted_error_category_and_original_status(self):
        import json
        import time
        import signing_profile_preflight as native
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            project = root / "ProfileDiscovery.xcodeproj"
            project.mkdir()
            nonce = "a" * 32
            profile = "0E5A9288-4FB6-4ADB-88E2-591A8D43F1B2"
            certificate = "B" * 40
            argv = ["xcodebuild", "-project", project, "-scheme", "ProfileDiscovery",
                    "-configuration", "Release", "-archivePath", root / "tiny.xcarchive", "archive",
                    "DEVELOPMENT_TEAM=" + TEAM, "PRODUCT_BUNDLE_IDENTIFIER=" + BUNDLE,
                    "CODE_SIGN_IDENTITY=" + certificate, "PROVISIONING_PROFILE_SPECIFIER=" + profile,
                    "HANLIN_PROFILE_DISCOVERY_NONCE=" + nonce]
            stderr = (
                "xcodebuild: error: Could not configure request to show build settings: "
                f"Scheme 'ProfileDiscovery' at '{project}' is not configured for archive; "
                f"team '{TEAM}', profile '{profile}', certificate '{certificate}', bundle '{BUNDLE}', "
                f"nonce '{nonce}', config '/private/sensitive-key-name.p8'.\n"
                "Usage: unrelated output is not retained.\n"
            ).encode()
            result = Mock(returncode=64, stdout=b"", stderr=stderr)
            with patch.object(native.subprocess, "run", return_value=result) as invoked, patch.dict(
                    os.environ, {"XCODE_XCCONFIG_FILE": "/private/sensitive-key-name.p8"}):
                receipt = native.observe_owned_signing_build_settings(argv, root, nonce, time.monotonic() + 30)
            self.assertEqual(receipt["status"], "SETTINGS_COMMAND_FAILED")
            self.assertEqual(receipt["exit"], 64)
            self.assertNotIn("settings", receipt)
            text = receipt["stderr_errors"]["text"]
            self.assertIn("Could not configure request to show build settings", text)
            self.assertIn("not configured for archive", text)
            self.assertIn("[OWNED_TARGET]", text)
            self.assertIn("[SELECTED_PROFILE]", text)
            self.assertNotIn("Usage:", text)
            for private in [str(project), TEAM, BUNDLE, profile, certificate, nonce, "sensitive-key-name.p8"]:
                self.assertNotIn(private, text)
            self.assertEqual(receipt["stderr_sha256"], hashlib.sha256(stderr).hexdigest())
            self.assertEqual(invoked.call_count, 1)

    def test_error_retention_is_bounded_and_timeout_preserves_its_category(self):
        import time
        import subprocess
        import signing_profile_preflight as native
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            project = root / "ProfileDiscovery.xcodeproj"
            project.mkdir()
            nonce = "a" * 32
            argv = ["xcodebuild", "-project", project, "-scheme", "ProfileDiscovery", "archive",
                    "HANLIN_PROFILE_DISCOVERY_NONCE=" + nonce]
            raw = ("xcodebuild: error: query " + "x" * 800 + "\n") * 20
            retained = native._redacted_settings_errors(raw.encode(), [str(x) for x in argv],
                                                       project, nonce, {})
            self.assertLessEqual(len(retained["text"].encode()), 4096)
            self.assertLessEqual(len(retained["text"].splitlines()), 8)
            self.assertTrue(retained["truncated"])
            timeout = subprocess.TimeoutExpired(argv, 15, stderr=b"xcodebuild: error: query timed out")
            with patch.object(native.subprocess, "run", side_effect=timeout) as invoked:
                receipt = native.observe_owned_signing_build_settings(argv, root, nonce, time.monotonic() + 30)
            self.assertEqual(receipt["status"], "SETTINGS_COMMAND_TIMED_OUT")
            self.assertIn("query timed out", receipt["stderr_errors"]["text"])
            self.assertNotIn("settings", receipt)
            self.assertEqual(invoked.call_count, 1)

    def test_other_project_or_nonce_cannot_supply_owned_target_settings(self):
        import json
        import time
        import signing_profile_preflight as native
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            project = root / "ProfileDiscovery.xcodeproj"
            project.mkdir()
            nonce = "a" * 32
            argv = ["xcodebuild", "-project", project, "-scheme", "ProfileDiscovery", "archive",
                    "HANLIN_PROFILE_DISCOVERY_NONCE=" + nonce]
            for path, actual_nonce in [(str(root / "Other.xcodeproj"), nonce), (str(project), "b" * 32)]:
                with self.subTest(path=path, nonce=actual_nonce):
                    result = Mock(returncode=0, stdout=json.dumps([{"target": "ProfileDiscovery",
                        "buildSettings": {"PROJECT_FILE_PATH": path,
                                          "HANLIN_PROFILE_DISCOVERY_NONCE": actual_nonce,
                                          "DEVELOPMENT_TEAM": TEAM}}]).encode(), stderr=b"")
                    with patch.object(native.subprocess, "run", return_value=result):
                        receipt = native.observe_owned_signing_build_settings(
                            argv, root, nonce, time.monotonic() + 30)
                    self.assertEqual(receipt["status"], "DIAGNOSTIC_UNAVAILABLE")
                    self.assertNotIn("settings", receipt)
                    self.assertNotIn(TEAM, json.dumps(receipt))

    def test_exhausted_deadline_starts_no_diagnostic_process(self):
        import time
        import signing_profile_preflight as native
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            project = root / "ProfileDiscovery.xcodeproj"
            project.mkdir()
            nonce = "a" * 32
            argv = ["xcodebuild", "-project", project, "-scheme", "ProfileDiscovery", "archive",
                    "HANLIN_PROFILE_DISCOVERY_NONCE=" + nonce]
            with patch.object(native.subprocess, "run") as invoked:
                receipt = native.observe_owned_signing_build_settings(
                    argv, root, nonce, time.monotonic() - 1)
            self.assertEqual(receipt["status"], "DEADLINE_EXHAUSTED")
            invoked.assert_not_called()


if __name__ == "__main__":
    unittest.main()
