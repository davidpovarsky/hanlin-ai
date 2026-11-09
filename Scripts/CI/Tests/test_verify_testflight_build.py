"""Exercise delivery polling without credentials or network access."""

import contextlib
import io
import json
from pathlib import Path
import runpy
import sys
import types
import unittest
from unittest.mock import patch


SCRIPT = Path(__file__).resolve().parents[1] / "verify_testflight_build.py"


class TestFlightReadinessTests(unittest.TestCase):
    def run_states(self, states, internal="IN_BETA_TESTING", expired=False):
        pending = iter(states)
        calls = []

        def urlopen(request, timeout):
            calls.append(request.full_url)
            if "/v1/apps?" in request.full_url:
                data = {"data": [{"id": "app"}]}
            elif request.full_url.endswith("/buildBetaDetail"):
                data = {"data": {"attributes": {"internalBuildState": internal}}}
            else:
                state = next(pending)
                data = {"data": [] if state is None else [{
                    "id": "build", "attributes": {"processingState": state, "expired": expired}
                }]}
            return io.BytesIO(json.dumps(data).encode())

        fake_jwt = types.SimpleNamespace(encode=lambda *args, **kwargs: "test-token")
        output = io.StringIO()
        with patch.dict(sys.modules, jwt=fake_jwt), \
             patch.dict("os.environ", {"ASC_ISSUER_ID": "test", "ASC_KEY_ID": "test",
                                       "ASC_KEY_PATH": "unused", "BUILD_DIR": ""}), \
             patch.object(sys, "argv", [str(SCRIPT), "91801"]), \
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


if __name__ == "__main__":
    unittest.main()
