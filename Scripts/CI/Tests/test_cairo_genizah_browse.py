"""Offline regression for the actual maintained Cairo Genizah browse script.

These tests exercise its production main function and transport boundary. They
do not query a service or treat fixture responses as externally verified facts.
"""
import contextlib
import importlib.util
import io
import json
from pathlib import Path
import sys
import unittest
from unittest import mock
from urllib.error import HTTPError, URLError

SCRIPT = Path(__file__).resolve().parents[3] / "Skills/cairo-genizah-research/scripts/browse.py"


class CairoGenizahBrowseTests(unittest.TestCase):
    def run_main(self, *, response=None, error=None, arguments=("T-S 12.345",)):
        spec = importlib.util.spec_from_file_location("cairo_genizah_browse", SCRIPT)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        stdout, stderr = io.StringIO(), io.StringIO()
        transport = mock.MagicMock()
        transport.return_value.__enter__.return_value.read.return_value = response
        if error is not None:
            transport.side_effect = error
        status = 0
        with mock.patch.object(module.urllib.request, "urlopen", transport), \
             mock.patch.object(sys, "argv", [str(SCRIPT), *arguments]), \
             contextlib.redirect_stdout(stdout), contextlib.redirect_stderr(stderr):
            try:
                module.main()
            except SystemExit as exit:
                status = exit.code
        return status, stdout.getvalue(), stderr.getvalue(), transport

    def test_transport_failures_are_nonzero_without_invented_records_or_retry(self):
        errors = [
            URLError("offline regression"),
            HTTPError("https://api.genizah.org/v1/browse", 503, "Unavailable", {}, None),
            TimeoutError("offline regression timeout"),
        ]
        for error in errors:
            with self.subTest(error=type(error).__name__):
                status, stdout, stderr, transport = self.run_main(error=error)
                self.assertEqual(status, 1)
                self.assertEqual(stdout, "")
                self.assertIn("Error querying Cairo Genizah API:", stderr)
                self.assertIn(str(error), stderr)
                self.assertEqual(transport.call_count, 1)

    def test_invalid_json_does_not_become_a_successful_cambridge_record(self):
        status, stdout, stderr, transport = self.run_main(response=b"<html>unavailable</html>")
        self.assertEqual(status, 1)
        self.assertEqual(stdout, "")
        self.assertIn("Error querying Cairo Genizah API:", stderr)
        self.assertEqual(transport.call_count, 1)

    def test_success_preserves_service_response_and_empty_results(self):
        for payload in [{"sys_id": "T-S 12.345", "transcription": "מקור"}, {"results": []}]:
            with self.subTest(payload=payload):
                status, stdout, stderr, transport = self.run_main(
                    response=json.dumps(payload, ensure_ascii=False).encode("utf-8"))
                self.assertEqual(status, 0)
                self.assertEqual(json.loads(stdout), payload)
                self.assertEqual(stderr, "")
                self.assertEqual(transport.call_count, 1)
                request = transport.call_args.args[0]
                self.assertTrue(request.full_url.startswith("https://api.genizah.org/v1/browse?sys_id="))
                self.assertEqual(transport.call_args.kwargs["timeout"], 15)

    def test_missing_identifier_fails_before_any_transport(self):
        status, stdout, stderr, transport = self.run_main(arguments=())
        self.assertEqual(status, 1)
        self.assertEqual(stdout, "")
        self.assertEqual(stderr, "Usage: browse.py <sys_id>\n")
        transport.assert_not_called()


if __name__ == "__main__":
    unittest.main()
