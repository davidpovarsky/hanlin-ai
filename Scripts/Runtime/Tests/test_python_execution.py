import hashlib
import json
import os
from pathlib import Path
import runpy
import sys
import tempfile
import threading
import time
import unittest


RUNNER = Path(__file__).resolve().parents[3] / "AI_HLY/Downstream/RuntimeCore/Python/Resources/HanlinPythonExecution.py"


class PythonExecutionTests(unittest.TestCase):
    def execute(self, source, *, timeout=None, preview=1024, cancelled=lambda: False, environment=None, cli=False, stdin=None, files=None):
        root = tempfile.TemporaryDirectory(prefix="hanlin-python-job-")
        self.addCleanup(root.cleanup)
        request = {"executionID": "fixture", "source": source, "workspace": root.name,
                   "outputDirectory": str(Path(root.name) / "output"), "packages": "",
                   "arguments": ["שלום", "second"], "environment": environment or {}, "maximumOutputBytes": preview}
        if cli:
            entry = Path(root.name) / "script directory" / "main.py"
            entry.parent.mkdir()
            entry.write_bytes(source if isinstance(source, bytes) else source.encode("utf-8"))
            for name, content in (files or {}).items():
                (entry.parent / name).write_text(content, encoding="utf-8")
            request["source"] = ""
            request["entryPoint"] = str(entry)
        if stdin is not None:
            stream = Path(root.name) / "stdin.bin"
            stream.write_bytes(stdin)
            request["standardInputPath"] = str(stream)
        if timeout is not None:
            request["timeoutSeconds"] = timeout
        namespace = runpy.run_path(str(RUNNER), init_globals={"__hanlin_request_json": json.dumps(request), "_hanlin_is_cancelled": cancelled})
        result = json.loads(namespace["_hanlin_response_json"])
        self.assertNotIn("error", result, result)
        return result

    def test_full_output_and_digest_exceed_preview_without_losing_unicode(self):
        text = "שלום 👨‍👩‍👧‍👦\n" * 400_000
        result = self.execute("import sys\nsys.stdout.write('שלום 👨‍👩‍👧‍👦\\n' * 400000)\nprint('stderr tail', file=sys.stderr)\n__hanlin_result__ = 42", preview=3)
        self.assertEqual(result["value"], 42)
        self.assertEqual(result["exitCode"], 0)
        self.assertTrue(result["outputWasTruncated"])
        self.assertNotIn("\ufffd", result["stdout"])
        artifact = result["outputFiles"]["stdout"]
        self.assertGreater(artifact["bytes"], 10 * 1024 * 1024)
        self.assertEqual(Path(artifact["path"]).read_text(encoding="utf-8"), text)
        self.assertEqual(artifact["sha256"], hashlib.sha256(text.encode()).hexdigest())
        self.assertEqual(Path(result["outputFiles"]["stderr"]["path"]).read_text().strip(), "stderr tail")

    def test_optional_deadline_and_restored_process_state(self):
        old_cwd, old_argv, old_path = os.getcwd(), list(sys.argv), list(sys.path)
        key = "HANLIN_TEST_JOB_ENV"
        old_value = os.environ.get(key)
        result = self.execute("import os, sys\nassert os.environ['HANLIN_TEST_JOB_ENV'] == 'yes'\n__hanlin_result__ = sys.argv[1:]", environment={key: "yes"})
        self.assertEqual(result["value"], ["שלום", "second"])
        self.assertEqual((os.getcwd(), sys.argv, sys.path), (old_cwd, old_argv, old_path))
        self.assertEqual(os.environ.get(key), old_value)
        self.assertFalse(result["didTimeOut"])

    def test_explicit_deadline_preserves_partial_output(self):
        result = self.execute("print('BEFORE_TIMEOUT')\nwhile True: pass", timeout=0.05)
        self.assertEqual(result["exitCode"], 1)
        self.assertTrue(result["didTimeOut"])
        self.assertFalse(result["wasCancelled"])
        self.assertIn("BEFORE_TIMEOUT", Path(result["outputFiles"]["stdout"]["path"]).read_text())

    def test_cancellation_is_distinct_and_keeps_partial_output(self):
        cancelled = threading.Event()
        timer = threading.Timer(0.05, cancelled.set)
        timer.start()
        self.addCleanup(timer.cancel)
        result = self.execute("print('BEFORE_CANCEL')\nwhile True: pass", cancelled=cancelled.is_set)
        self.assertTrue(result["wasCancelled"])
        self.assertFalse(result["didTimeOut"])
        self.assertIn("BEFORE_CANCEL", Path(result["outputFiles"]["stdout"]["path"]).read_text())

    def test_native_blocking_call_does_not_claim_instant_interruption(self):
        # Windows 3.12 monotonic() may use a ~15ms clock tick; perf_counter()
        # measures the actual native blocking call without rounding 80ms to 78ms.
        started = time.perf_counter()
        result = self.execute("import time\ntime.sleep(0.08)", timeout=0.01)
        self.assertGreaterEqual(time.perf_counter() - started, 0.08)
        self.assertTrue(result["didTimeOut"])

    def test_user_timeout_error_is_not_a_runtime_deadline(self):
        result = self.execute("raise TimeoutError('user exception')")
        self.assertEqual(result["exitCode"], 1)
        self.assertFalse(result["didTimeOut"])
        self.assertFalse(result["wasCancelled"])

    def test_actual_cli_file_argv_sibling_import_and_binary_stdin_preserve_state(self):
        old_stdin, old_main = sys.stdin, sys.modules["__main__"]
        payload = bytes(range(256)) * 45000
        source = """
import sys, pathlib, os
import cli_sibling_fixture
assert __name__ == '__main__'
assert pathlib.Path(__file__).name == 'main.py'
assert sys.modules['__main__'].__dict__ is globals()
assert sys.argv == [__file__, 'שלום', 'second']
assert os.environ['CLI_TEST'] == 'isolated'
assert cli_sibling_fixture.VALUE == 42
sys.stdout.buffer.write(sys.stdin.buffer.read())
print('CLI_STDERR', file=sys.stderr)
sys.exit(23)
"""
        try:
            result = self.execute(source, cli=True, stdin=payload, environment={"CLI_TEST": "isolated"},
                                  files={"cli_sibling_fixture.py": "VALUE = 42\n"}, preview=3)
            self.assertEqual(result['exitCode'], 23)
            self.assertFalse(result['didTimeOut'])
            self.assertFalse(result['wasCancelled'])
            self.assertEqual(Path(result['outputFiles']['stdout']['path']).read_bytes(), payload)
            self.assertEqual(result['outputFiles']['stdout']['sha256'], hashlib.sha256(payload).hexdigest())
            self.assertEqual(Path(result['outputFiles']['stderr']['path']).read_text().strip(), 'CLI_STDERR')
            self.assertIs(sys.stdin, old_stdin)
            self.assertIs(sys.modules['__main__'], old_main)
        finally:
            sys.modules.pop('cli_sibling_fixture', None)

    def test_python_cli_encoding_cookie_eof_and_standard_system_exit_outcomes(self):
        # run_path reads the real file using CPython's declared source encoding.
        source = b"# coding: latin-1\nimport sys\nassert sys.stdin.read() == ''\nprint('caf\xe9')\nsys.exit(0)\n"
        result = self.execute(source, cli=True)
        self.assertEqual(result['exitCode'], 0)
        self.assertEqual(result['stdout'].strip(), 'café')
        self.assertEqual(result['stderr'], '')
        for statement, code, diagnostic in [("sys.exit()", 0, ''), ("sys.exit(23)", 23, ''), ("sys.exit('actual diagnostic')", 1, 'actual diagnostic')]:
            with self.subTest(statement=statement):
                result = self.execute('import sys\n' + statement)
                self.assertEqual(result['exitCode'], code)
                self.assertEqual(result['stderr'].strip(), diagnostic)

    @unittest.skipUnless(os.environ.get("HANLIN_RUN_LONG_JOBS") == "1", "explicit >300s execution obligation")
    def test_actual_python_job_crosses_300_seconds(self):
        started = time.monotonic()
        result = self.execute("import time\nprint('LONG_JOB_STARTED')\ntime.sleep(305)\nprint('LONG_JOB_COMPLETED')\n__hanlin_result__ = 305")
        elapsed = time.monotonic() - started
        self.assertGreater(elapsed, 300)
        self.assertEqual(result["exitCode"], 0)
        self.assertEqual(result["value"], 305)
        self.assertIn("LONG_JOB_COMPLETED", result["stdout"])
        print(json.dumps({"proof": "portable-python-runner-over-300-seconds", "elapsedSeconds": elapsed, "pythonVersion": sys.version}))


if __name__ == "__main__":
    unittest.main()
