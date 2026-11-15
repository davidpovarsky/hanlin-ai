import hashlib
import json
import os
import importlib
from pathlib import Path
import runpy
import sys
import subprocess
import tempfile
import threading
import time
import unittest


RUNNER = Path(__file__).resolve().parents[3] / "AI_HLY/Downstream/RuntimeCore/Python/Resources/HanlinPythonExecution.py"


class PythonExecutionTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        # Compile the actual production thread-state owner, not a mocked list of
        # Thread objects. Raw _thread aliases are an explicit regression case.
        # Windows keeps a loaded extension DLL mapped until process exit.
        cls.native_root = tempfile.TemporaryDirectory(prefix="hanlin-thread-capi-", ignore_cleanup_errors=os.name == 'nt')
        cls.addClassCleanup(cls.native_root.cleanup)
        root = Path(cls.native_root.name)
        repository = RUNNER.parents[5]
        fixture = repository / "Scripts/Runtime/Tests/python_thread_probe.cpp"
        (root / "probe.cpp").write_bytes(fixture.read_bytes())
        include = str(RUNNER.parents[1] / "Native")
        flags = ["/std:c++17"] if os.name == "nt" else ["-std=c++17"]
        (root / "setup.py").write_text(
            "from setuptools import setup, Extension\n" +
            f"setup(name='thread-owner-probe', ext_modules=[Extension('_thread_owner_probe', ['probe.cpp'], include_dirs=[{include!r}], extra_compile_args={flags!r}, language='c++')])\n", encoding="utf-8")
        result = subprocess.run([sys.executable, "setup.py", "build_ext", "--inplace"], cwd=root,
                                stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=120)
        if result.returncode:
            raise RuntimeError(result.stdout.decode("utf-8", errors="replace"))
        sys.path.insert(0, str(root))
        cls.addClassCleanup(lambda: sys.path.remove(str(root)))
        cls.native = importlib.import_module("_thread_owner_probe")

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
        counter, close = self.native.make()
        try:
            namespace = runpy.run_path(str(RUNNER), init_globals={"__hanlin_request_json": json.dumps(request),
                "_hanlin_is_cancelled": cancelled, "_hanlin_owned_thread_count": counter})
        finally:
            close()
        result = json.loads(namespace["_hanlin_response_json"])
        self.assertNotIn("error", result, result)
        return result

    def test_daemon_and_raw_threads_drain_before_output_and_process_state_close(self):
        # The raw start alias is captured before the runner imports/thread hooks.
        import _thread
        import builtins
        builtins._hanlin_test_raw_start = _thread.start_new_thread
        self.addCleanup(lambda: delattr(builtins, "_hanlin_test_raw_start"))
        old_cwd, old_trace = os.getcwd(), threading.gettrace()
        source = """
import threading, time, os, pathlib, builtins
workspace = os.getcwd()
def child(label, remaining):
    time.sleep(0.04)
    assert os.getcwd() == workspace
    assert os.environ['THREAD_JOB_TEST'] == 'owned'
    assert not __import__('sys').stdout.closed
    print(label, flush=True)
    pathlib.Path(label).write_text('completed', encoding='utf-8')
    if remaining:
        builtins._hanlin_test_raw_start(child, ('raw-descendant', False))
threading.Thread(target=child, args=('daemon-child', False), daemon=True).start()
builtins._hanlin_test_raw_start(child, ('raw-child', True))
print('main-finished')
"""
        result = self.execute(source, environment={'THREAD_JOB_TEST': 'owned'})
        self.assertEqual(result['exitCode'], 0, result)
        text = Path(result['outputFiles']['stdout']['path']).read_text(encoding='utf-8')
        self.assertEqual(set(text.splitlines()), {'main-finished','daemon-child','raw-child','raw-descendant'})
        workspace = Path(result['outputFiles']['stdout']['path']).parent.parent
        for name in ('daemon-child','raw-child','raw-descendant'):
            self.assertEqual((workspace / name).read_text(), 'completed')
        self.assertEqual(os.getcwd(), old_cwd)
        self.assertIs(threading.gettrace(), old_trace)
        self.assertNotIn('THREAD_JOB_TEST', os.environ)

    def test_worker_cancellation_keeps_scope_until_cooperative_thread_cleanup(self):
        cancel = threading.Event()
        timer = threading.Timer(0.08, cancel.set)
        timer.start()
        self.addCleanup(timer.cancel)
        result = self.execute("""
import threading, sys
def child():
    try:
        print('thread-started', flush=True)
        while True:
            pass
    finally:
        print('thread-cleaned', flush=True)
threading.Thread(target=child, daemon=True).start()
""", cancelled=cancel.is_set)
        self.assertTrue(result['wasCancelled'], result)
        self.assertIn('thread-cleaned', Path(result['outputFiles']['stdout']['path']).read_text(), result)

    def test_thread_owner_excludes_prior_threads_and_rejects_retained_or_foreign_calls(self):
        existing = threading.Event()
        before = threading.Thread(target=existing.wait)
        before.start()
        try:
            counter, close = self.native.make()
            self.assertEqual(counter(), 0)
            failures = []
            def foreign():
                try: counter()
                except RuntimeError as error: failures.append(str(error))
            child = threading.Thread(target=foreign)
            child.start(); child.join()
            self.assertEqual(len(failures), 1)
            close()
            with self.assertRaisesRegex(RuntimeError, 'active job executor'):
                counter()
        finally:
            existing.set(); before.join()

    def test_raw_untraced_thread_finishes_before_cancellation_settles(self):
        cancel = threading.Event()
        timer = threading.Timer(0.03, cancel.set)
        timer.start()
        self.addCleanup(timer.cancel)
        started = time.perf_counter()
        result = self.execute("""
import _thread, time
def child():
    time.sleep(0.12)
    print('actual-raw-thread-late-output', flush=True)
_thread.start_new_thread(child, ())
""", cancelled=cancel.is_set)
        self.assertGreaterEqual(time.perf_counter() - started, 0.12)
        self.assertTrue(result['wasCancelled'], result)
        self.assertIn('actual-raw-thread-late-output', Path(result['outputFiles']['stdout']['path']).read_text())

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
