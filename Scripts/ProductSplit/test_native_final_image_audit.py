import json
from pathlib import Path
import subprocess
import tempfile
import threading
import unittest
from unittest.mock import patch

from native_final_image_audit import ImageAudit


class ImageOriginTransportTests(unittest.TestCase):
    def setUp(self):
        evidence = tempfile.TemporaryDirectory()
        self.addCleanup(evidence.cleanup)
        self.audit = ImageAudit.__new__(ImageAudit)
        self.audit.out = Path(evidence.name)
        self.audit.sim = "OWNED-SIMULATOR"
        self.audit.stop = threading.Event()
        self.argv = ["/usr/bin/xcrun", "simctl", "spawn", self.audit.sim, "launchctl", "list"]

    def test_timeout_requires_a_successful_second_snapshot(self):
        timeout = subprocess.TimeoutExpired(self.argv, 5, output=b"partial original output")
        success = subprocess.CompletedProcess(self.argv, 0, "PID Status Label\n", "")
        with patch("native_final_image_audit.subprocess.run", side_effect=[timeout, success]) as run:
            roles, pids = self.audit.scoped_processes("native-ui")
        self.assertEqual(pids, set())
        self.assertEqual(roles, {"app": [], "ui_runner": []})
        self.assertEqual(run.call_count, 2)
        records = [json.loads(line) for line in
                   (self.audit.out / "owned-launchctl-attempts.jsonl").read_text().splitlines()]
        self.assertTrue(records[0]["timed_out"])
        self.assertEqual(records[1]["returncode"], 0)
        self.assertEqual((self.audit.out / records[0]["raw_file"]).read_bytes(), b"partial original output")
        self.assertTrue(all(call.args[0] == self.argv for call in run.call_args_list))

    def test_unrecovered_transport_error_remains_fatal(self):
        interrupted = subprocess.CompletedProcess(self.argv, 143, "", "interrupted")
        with patch("native_final_image_audit.subprocess.run", return_value=interrupted) as run:
            with self.assertRaisesRegex(RuntimeError, "Owned simulator process observation failed"):
                self.audit.scoped_processes("native-ui")
        self.assertEqual(run.call_count, 2)

    def test_invalid_output_is_not_retried(self):
        malformed = subprocess.CompletedProcess(self.argv, 0, "incorrect header\n", "")
        with patch("native_final_image_audit.subprocess.run", return_value=malformed) as run:
            with self.assertRaisesRegex(AssertionError, "Unexpected launchctl format"):
                self.audit.scoped_processes("native-ui")
        run.assert_called_once()


if __name__ == "__main__":
    unittest.main()
