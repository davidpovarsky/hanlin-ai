"""Exercise delivery polling without credentials or network access."""

import contextlib
import io
import json
from pathlib import Path
import runpy
import sys
import types
import unittest
import urllib.parse
from unittest.mock import patch


SCRIPT = Path(__file__).resolve().parents[1] / "verify_testflight_build.py"


class TestFlightReadinessTests(unittest.TestCase):
    def run_states(self, states, internal="IN_BETA_TESTING", expired=False,
                   audience=None, previous_groups=None, current_groups=None,
                   expected_build_id=None, build_count=1, group_states=None,
                   internal_states=None):
        pending = iter(states)
        calls = []
        assigned = set(current_groups or [])
        groups_pending = iter(group_states) if group_states is not None else None
        internal_pending = iter(internal_states) if internal_states is not None else None
        self.last_methods = []

        def urlopen(request, timeout):
            calls.append(request.full_url)
            self.last_methods.append(request.get_method())
            self.assertEqual(request.get_method(), "GET", "Readiness must never mutate the tester audience")
            self.assertIsNone(request.data)
            if "/v1/apps?" in request.full_url:
                data = {"data": [{"id": "app"}]}
            elif "/previous?include=betaGroups" in request.full_url:
                data = {"included": [{"type": "betaGroups", **group} for group in (previous_groups or [])]}
            elif "/build?include=betaGroups" in request.full_url:
                current = next(groups_pending) if groups_pending is not None else assigned
                data = {"included": [{"id": group, "type": "betaGroups"} for group in current]}
            elif request.full_url.endswith("/buildBetaDetail"):
                current_internal = next(internal_pending) if internal_pending is not None else internal
                data = {"data": {"attributes": {"internalBuildState": current_internal}}}
            elif urllib.parse.parse_qs(urllib.parse.urlsplit(request.full_url).query).get("filter[version]") == ["89401"]:
                data = {"data": [{"id": "previous"}]}
            else:
                state = next(pending)
                data = {"data": [] if state is None else [{
                    "id": "build", "attributes": {"processingState": state, "expired": expired}
                }] * build_count}
            return io.BytesIO(json.dumps(data).encode())

        fake_jwt = types.SimpleNamespace(encode=lambda *args, **kwargs: "test-token")
        output = io.StringIO()
        arguments = [str(SCRIPT), "91801"]
        if audience:
            arguments += ["--reuse-internal-audience-from", audience]
        with patch.dict(sys.modules, jwt=fake_jwt), \
             patch.dict("os.environ", {"ASC_ISSUER_ID": "test", "ASC_KEY_ID": "test",
                                       "ASC_KEY_PATH": "unused", "BUILD_DIR": "",
                                       "HANLIN_EXPECTED_ASC_BUILD_ID": expected_build_id or "",
                                       "HANLIN_EXPECTED_ASC_APP_ID": ""}), \
             patch.object(sys, "argv", arguments), \
             patch("pathlib.Path.read_bytes", return_value=b"test-only"), \
             patch("urllib.request.urlopen", side_effect=urlopen), \
             patch("time.sleep") as sleep, contextlib.redirect_stdout(output):
            with self.assertRaises(SystemExit) as result:
                runpy.run_path(str(SCRIPT), run_name="__main__")
        return result.exception.code, calls, sleep.call_count, output.getvalue()

    def test_processing_is_not_success(self):
        result, calls, sleeps, output = self.run_states([None, "PROCESSING", "VALID"])
        self.assertEqual(result, 0)
        self.assertEqual(sleeps, 2)
        self.assertIn('"processingState": "VALID"', output)
        self.assertTrue(calls[-1].endswith("/buildBetaDetail"))

    def test_authenticated_build_id_mismatch_blocks_before_distribution(self):
        result, _, sleeps, _ = self.run_states(["VALID"], audience="89401", expected_build_id="other-build")
        self.assertIn("authenticated UI release proof", result)
        self.assertEqual(sleeps, 0)
        self.assertEqual(set(self.last_methods), {"GET"})

    def test_ambiguous_build_number_blocks_before_distribution(self):
        result, _, _, _ = self.run_states(["VALID"], audience="89401", build_count=2)
        self.assertIn("Ambiguous", result)
        self.assertEqual(set(self.last_methods), {"GET"})

    def test_rejected_build_fails_without_waiting(self):
        for state in ("FAILED", "INVALID"):
            with self.subTest(state=state):
                result, _, sleeps, _ = self.run_states([state])
                self.assertIn("rejected", result)
                self.assertEqual(sleeps, 0)

    def test_expired_build_fails(self):
        result, _, sleeps, _ = self.run_states(["VALID"], expired=True)
        self.assertIn("expired", result)
        self.assertEqual(sleeps, 0)

    def test_ready_build_is_accepted(self):
        result, _, _, _ = self.run_states(["VALID"], internal="READY_FOR_BETA_TESTING")
        self.assertEqual(result, 0)

    def test_blocked_testing_is_not_success(self):
        for internal in ("PROCESSING_EXCEPTION", "EXPIRED", "MISSING_EXPORT_COMPLIANCE"):
            with self.subTest(internal=internal):
                result, _, sleeps, _ = self.run_states(["VALID"], internal=internal)
                self.assertIn(internal, result)
                self.assertEqual(sleeps, 0)

    def test_unfinished_processing_times_out(self):
        result, _, sleeps, _ = self.run_states(["PROCESSING"] * 40)
        self.assertIn("not ready", result)
        self.assertEqual(sleeps, 40)

    def test_valid_binary_without_testing_readiness_times_out(self):
        result, _, sleeps, _ = self.run_states(["VALID"] * 40, internal="PROCESSING")
        self.assertIn("not ready", result)
        self.assertEqual(sleeps, 40)

    def test_confirms_only_previously_assigned_internal_groups(self):
        groups = [{"id": "owner", "attributes": {"isInternalGroup": True}},
                  {"id": "external", "attributes": {"isInternalGroup": False}}]
        result, calls, _, output = self.run_states(["VALID"], audience="89401",
                                                   previous_groups=groups, current_groups=["owner"])
        self.assertEqual(result, 0)
        self.assertEqual(set(self.last_methods), {"GET"})
        self.assertIn('"internalBetaGroupIDs": ["owner"]', output)
        self.assertTrue(any("/previous?include=betaGroups" in url for url in calls))
        self.assertFalse(any("/betaGroups?" in url for url in calls))

    def test_automatic_internal_membership_can_appear_after_valid(self):
        groups = [{"id": "owner", "attributes": {
            "isInternalGroup": True, "hasAccessToAllBuilds": True}}]
        result, calls, sleeps, output = self.run_states(
            ["VALID", "VALID"], audience="89401", previous_groups=groups,
            group_states=[[], ["owner"]])
        self.assertEqual(result, 0)
        self.assertEqual(sleeps, 1)
        self.assertEqual(sum("/build?include=betaGroups" in url for url in calls), 2)
        self.assertIn('"internalBuildState": "IN_BETA_TESTING"', output)
        self.assertEqual(set(self.last_methods), {"GET"})

    def test_in_beta_testing_and_all_builds_access_without_membership_time_out(self):
        groups = [{"id": "owner", "attributes": {
            "isInternalGroup": True, "hasAccessToAllBuilds": True}}]
        result, calls, sleeps, output = self.run_states(
            ["VALID"] * 40, audience="89401", previous_groups=groups)
        self.assertIn("not ready", result)
        self.assertEqual(sleeps, 40)
        self.assertEqual(sum("/build?include=betaGroups" in url for url in calls), 40)
        self.assertNotIn('"internalBetaGroupIDs"', output)
        self.assertEqual(set(self.last_methods), {"GET"})

    def test_membership_is_read_again_when_testing_becomes_ready(self):
        groups = [{"id": "owner", "attributes": {"isInternalGroup": True}}]
        result, calls, sleeps, _ = self.run_states(
            ["VALID"] * 3, audience="89401", previous_groups=groups,
            group_states=[["owner"], [], ["owner"]],
            internal_states=["PROCESSING", "IN_BETA_TESTING", "IN_BETA_TESTING"])
        self.assertEqual(result, 0)
        self.assertEqual(sleeps, 2)
        self.assertEqual(sum("/build?include=betaGroups" in url for url in calls), 3)
        self.assertEqual(sum("/previous?include=betaGroups" in url for url in calls), 1)

    def test_confirmed_audience_still_requires_in_beta_testing(self):
        groups = [{"id": "owner", "attributes": {"isInternalGroup": True}}]
        result, _, sleeps, output = self.run_states(
            ["VALID"] * 40, internal="READY_FOR_BETA_TESTING", audience="89401",
            previous_groups=groups, current_groups=["owner"])
        self.assertIn("not ready", result)
        self.assertEqual(sleeps, 40)
        self.assertNotIn('"internalBetaGroupIDs"', output)

    def test_missing_prior_internal_audience_changes_nothing(self):
        result, _, _, _ = self.run_states(["VALID"], audience="89401")
        self.assertIn("no assigned internal group", result)
        self.assertEqual(set(self.last_methods), {"GET"})

    def test_already_assigned_audience_is_idempotent(self):
        groups = [{"id": "owner", "attributes": {"isInternalGroup": True}}]
        result, _, _, _ = self.run_states(["VALID"], audience="89401",
                                          previous_groups=groups, current_groups=["owner"])
        self.assertEqual(result, 0)
        self.assertEqual(set(self.last_methods), {"GET"})

    def test_ordinary_verification_does_not_assign_testers(self):
        result, _, _, _ = self.run_states(["VALID"])
        self.assertEqual(result, 0)
        self.assertEqual(set(self.last_methods), {"GET"})


if __name__ == "__main__":
    unittest.main()
