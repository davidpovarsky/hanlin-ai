"""Portable checks of real command evidence; no native build or simulator is run."""
from pathlib import Path
import hashlib
import importlib.util
import json
import os
import signal
import subprocess
import sys
import tempfile
import time
import unittest
from unittest.mock import patch

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
with patch.dict(os.environ, {"SPLIT_EVIDENCE": tempfile.gettempdir()}):
    spec = importlib.util.spec_from_file_location("paired_command_runner", HERE / "run_paired_acceptance.py")
    runner = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(runner)


class PairedCommandEvidenceTests(unittest.TestCase):
    def setUp(self):
        retained = os.environ.get("PAIRED_COMMAND_TEST_EVIDENCE")
        if retained:
            self.evidence = Path(retained).resolve() / self._testMethodName
            self.evidence.mkdir(parents=True, exist_ok=False)
        else:
            temporary = tempfile.TemporaryDirectory()
            self.addCleanup(temporary.cleanup)
            self.evidence = Path(temporary.name)
        self.patch = patch.multiple(runner, EVIDENCE=self.evidence, COMMAND_HEARTBEAT_SECONDS=0.05)
        self.patch.start()
        self.addCleanup(self.patch.stop)

    def records(self, name):
        path = self.evidence / name
        return [json.loads(line) for line in path.read_text().splitlines()] if path.exists() else []

    def assert_completed_contract(self, expected):
        records = self.records("commands.jsonl")
        self.assertEqual(len(records), expected)
        for record in records:
            self.assertEqual(set(record), {"argv", "exit", "seconds", "log", "sha256"})
            self.assertEqual(record["sha256"], hashlib.sha256((self.evidence / record["log"]).read_bytes()).hexdigest())
        return records

    def test_failed_minibuild_records_execution_without_starting_ai_or_ui(self):
        # Stub only simulator discovery/cleanup. The failed build command and
        # the production main/finally receipt path execute for real on Linux.
        evidence = self.evidence / "acceptance"
        real_command = runner.command
        observed = []
        discovery = {
            "source-sha.txt": "portable-reporting-harness\n",
            "sdk.txt": "27.2\n",
            "runtimes.json": json.dumps({"runtimes": [{"isAvailable": True,
                "identifier": "iOS-27-2", "supportedDeviceTypes": [{"identifier": "test-iPad"}]}]}),
            "device-types.json": json.dumps({"devicetypes": [{"productFamily": "iPad",
                "identifier": "test-iPad", "name": "Portable receipt harness"}]}),
            "created-simulator.txt": "portable-receipt-harness\n",
        }

        def isolated_command(argv, name, **options):
            observed.append(name)
            if name == "mini-build.log":
                self.assertEqual(options, {"timeout": 3600})
                return real_command([sys.executable, "-c", "import sys; print('build failed',flush=True); sys.exit(65)"],
                    name, **options)
            return 0, discovery.get(name, "")

        with patch.multiple(runner, EVIDENCE=evidence, TEST_SCOPE="miniapp_authoring"), \
                patch.object(runner, "command", isolated_command), \
                patch.object(runner.subprocess, "run"), \
                patch.dict(os.environ, {"SPLIT_DERIVED_DATA": str(self.evidence / "derived")}):
            self.assertEqual(runner.main(), 1)
        receipt = json.loads((evidence / "acceptance.json").read_text())
        self.assertEqual(receipt["build"], "EXECUTED_FAIL")
        self.assertEqual(receipt["mini_build"], "EXECUTED_FAIL")
        self.assertEqual(receipt["ai_build"], "NOT_RUN")
        self.assertEqual(receipt["ui"], "NOT_RUN")
        self.assertEqual(receipt["status"], "BUILD_FAILED")
        self.assertNotIn("ai-build.log", observed)
        self.assertNotIn("original-runtimes.log", observed)
        self.assertNotIn("paired-tests.log", observed)
        completed = [json.loads(line) for line in (evidence / "commands.jsonl").read_text().splitlines()]
        self.assertEqual([(record["log"], record["exit"]) for record in completed], [("mini-build.log", 65)])

    def test_success_keeps_streamed_output_environment_and_completed_contract(self):
        source = ("import os,sys; "
                  "print('out:'+os.environ['PAIRED_COMMAND_PROBE'], flush=True); "
                  "print('err', file=sys.stderr, flush=True); "
                  "print('cwd:'+os.getcwd(), flush=True)")
        argv = [sys.executable, "-c", source]
        with patch.dict(os.environ, {"PAIRED_COMMAND_PROBE": "inherited"}):
            code, output = runner.command(argv, "success.log")
        self.assertEqual(code, 0)
        self.assertEqual(output, f"out:inherited\nerr\ncwd:{runner.ROOT}\n")
        events = self.records("command-events.jsonl")
        self.assertEqual(events[0]["status"], "starting")
        self.assertIsNone(events[0]["pid"])
        self.assertFalse(events[0]["completion_recorded"])
        self.assertEqual(events[0]["timeout"], 60)
        self.assertEqual(events[-1]["status"], "completed")
        self.assertEqual(events[-1]["exit"], 0)
        self.assertTrue(events[-1]["completion_recorded"])
        self.assertGreater(events[-1]["pid"], 0)
        self.assertEqual(events[-1]["observed_returncode"], 0)
        self.assertEqual(events[-1]["log_bytes"], len(output.encode()))
        self.assertEqual(json.loads((self.evidence / "active-command.json").read_text()), events[-1])
        record = self.assert_completed_contract(1)[0]
        self.assertEqual(record["argv"], argv)
        self.assertEqual(record["exit"], 0)
        self.assertEqual(runner.command_phase_status(events[-1]), "EXECUTED_PASS")

    def test_build_phase_aggregation_requires_both_builds_and_ignores_cleanup(self):
        state = {"ui": "NOT_RUN"}
        runner.record_build_phases(state)
        self.assertEqual((state["build"], state["mini_build"], state["ai_build"]), ("NOT_RUN",) * 3)
        runner.command([sys.executable, "-c", "print('mini build')"], "mini-build.log")
        runner.record_build_phases(state)
        self.assertEqual((state["build"], state["mini_build"], state["ai_build"]),
            ("INCOMPLETE", "EXECUTED_PASS", "NOT_RUN"))
        runner.command([sys.executable, "-c", "print('ai build')"], "ai-build.log")
        runner.command([sys.executable, "-c", "import sys; sys.exit(9)"], "cleanup.log", allow_failure=True)
        runner.record_build_phases(state)
        self.assertEqual((state["build"], state["mini_build"], state["ai_build"]), ("EXECUTED_PASS",) * 3)
        self.assertEqual(state["ui"], "NOT_RUN")
        self.assertEqual(set(state["build_commands"]), {"mini_build", "ai_build"})

    def test_launch_failure_is_not_reported_as_an_executed_build(self):
        with self.assertRaises(FileNotFoundError):
            runner.command([str(self.evidence / "missing-executable")], "mini-build.log")
        state = {"ui": "NOT_RUN"}
        runner.record_build_phases(state)
        self.assertEqual(state["build"], "LAUNCH_FAILED")
        self.assertEqual(state["mini_build"], "LAUNCH_FAILED")
        self.assertEqual(state["ai_build"], "NOT_RUN")
        self.assertEqual(state["ui"], "NOT_RUN")
        self.assertFalse((self.evidence / "commands.jsonl").exists())

    def test_nonzero_and_signal_exit_keep_failure_policy_without_inventing_timeout(self):
        argv = [sys.executable, "-c", "import sys; print('failed', flush=True); sys.exit(7)"]
        with self.assertRaisesRegex(RuntimeError, "exit 7; inspect failed.log"):
            runner.command(argv, "failed.log")
        self.assertEqual(runner.command(argv, "allowed.log", allow_failure=True), (7, "failed\n"))
        code, _ = runner.command([sys.executable, "-c",
            "import os,signal; os.kill(os.getpid(),signal.SIGHUP)"], "signal.log", allow_failure=True)
        self.assertEqual(code, -signal.SIGHUP)
        completed = self.assert_completed_contract(3)
        self.assertEqual([r["exit"] for r in completed], [7, 7, -signal.SIGHUP])
        final = self.records("command-events.jsonl")[-1]
        self.assertEqual(final["status"], "completed")
        self.assertTrue(final["completion_recorded"])
        self.assertEqual(final["exit"], -signal.SIGHUP)
        self.assertEqual(runner.command_phase_status(final), "EXECUTED_FAIL")

    def test_timeout_retains_partial_output_kills_child_and_preserves_minus_one(self):
        argv = [sys.executable, "-c", "import time; print('before-timeout', flush=True); time.sleep(30)"]
        code, output = runner.command(argv, "timeout.log", timeout=0.2, allow_failure=True)
        self.assertEqual((code, output), (-1, "before-timeout\n"))
        final = self.records("command-events.jsonl")[-1]
        self.assertEqual(final["status"], "timed_out")
        self.assertEqual(final["timeout"], 0.2)
        self.assertEqual(final["observed_returncode"], -signal.SIGKILL)
        self.assertEqual(runner.command_phase_status(final), "TIMED_OUT")
        self.assertTrue(final["completion_recorded"])
        with self.assertRaises(ProcessLookupError):
            os.kill(final["pid"], 0)
        self.assertEqual(self.assert_completed_contract(1)[0]["exit"], -1)
        with self.assertRaisesRegex(RuntimeError, "exit -1; inspect timeout-error.log"):
            runner.command(argv, "timeout-error.log", timeout=0.2)
        self.assertEqual(self.assert_completed_contract(2)[1]["exit"], -1)

    def test_keyboard_interrupt_keeps_child_cleanup_and_unfinished_receipt(self):
        driver = """
import json, os, pathlib, sys
sys.path.insert(0, sys.argv[1])
import run_paired_acceptance as runner
runner.EVIDENCE = pathlib.Path(sys.argv[2])
runner.COMMAND_HEARTBEAT_SECONDS = 0.05
try:
    runner.command([sys.executable, '-c', "import time; print('before-interrupt',flush=True); time.sleep(30)"],
                   'interrupted.log', timeout=20)
except KeyboardInterrupt:
    # Test-only observer: production preserves subprocess.run's brief SIGINT
    # wait, so a final poll can be unknown. Reap our own child here to verify
    # that the existing kill occurred without changing production cancellation.
    observed = json.loads((runner.EVIDENCE/'active-command.json').read_text())
    code = observed['observed_returncode']
    if code is None:
        _, status = os.waitpid(observed['pid'], 0)
        code = os.waitstatus_to_exitcode(status)
    (runner.EVIDENCE/'child-cleanup.json').write_text(json.dumps({'observed_exit': code}))
    raise
"""
        with (self.evidence / "driver.log").open("wb") as log:
            process = subprocess.Popen([sys.executable, "-c", driver, str(HERE), str(self.evidence)],
                stdout=log, stderr=subprocess.STDOUT,
                env={**os.environ, "SPLIT_EVIDENCE": str(self.evidence)})
            try:
                deadline = time.monotonic() + 5
                active = None
                while time.monotonic() < deadline:
                    current = self.evidence / "active-command.json"
                    if current.exists():
                        observed = json.loads(current.read_text())
                        if observed["pid"] is not None and observed["log_bytes"] > 0:
                            active = observed
                            break
                    if process.poll() is not None:
                        self.fail("driver exited before SIGINT observation")
                    time.sleep(0.01)
                self.assertIsNotNone(active)
                process.send_signal(signal.SIGINT)
                self.assertNotEqual(process.wait(timeout=5), 0)
                final = self.records("command-events.jsonl")[-1]
                self.assertEqual(final["status"], "interrupted")
                self.assertEqual(final["exception_type"], "KeyboardInterrupt")
                self.assertEqual(runner.command_phase_status(final), "INTERRUPTED")
                self.assertFalse(final["completion_recorded"])
                self.assertIn(final["observed_returncode"], (None, -signal.SIGKILL))
                cleanup = json.loads((self.evidence / "child-cleanup.json").read_text())
                self.assertEqual(cleanup["observed_exit"], -signal.SIGKILL)
                self.assertFalse((self.evidence / "commands.jsonl").exists())
                self.assertEqual((self.evidence / "interrupted.log").read_text(), "before-interrupt\n")
                with self.assertRaises(ProcessLookupError):
                    os.kill(final["pid"], 0)
            finally:
                if process.poll() is None:
                    process.kill()
                    process.wait()

    def test_external_termination_preserves_precompletion_checkpoint_and_partial_output_through_cleanup(self):
        # The child observes the real durable start journal before it emits any
        # output. Then the test terminates the runner, as an external cancellation
        # would; production signal handling is not replaced or installed.
        child = ("import json,os,pathlib,sys,time; "
                 "events=[json.loads(x) for x in pathlib.Path(sys.argv[1]).read_text().splitlines()]; "
                 "start=events[0]; assert start['status']=='starting' and start['pid'] is None; "
                 "os.write(1, ('partial-pid='+str(os.getpid())+'\\n').encode()); time.sleep(30)")
        driver = """
import os, pathlib, sys
sys.path.insert(0, sys.argv[1])
import run_paired_acceptance as runner
runner.EVIDENCE = pathlib.Path(sys.argv[2])
runner.COMMAND_HEARTBEAT_SECONDS = 0.05
runner.command([sys.executable, '-c', sys.argv[3], str(runner.EVIDENCE/'command-events.jsonl')],
               'unfinished.log', timeout=20)
"""
        env = {**os.environ, "SPLIT_EVIDENCE": str(self.evidence)}
        child_pid = None
        with (self.evidence / "driver.log").open("wb") as log:
            process = subprocess.Popen([sys.executable, "-c", driver, str(HERE), str(self.evidence), child],
                stdout=log, stderr=subprocess.STDOUT, env=env)
            try:
                deadline = time.monotonic() + 5
                active = None
                while time.monotonic() < deadline:
                    current = self.evidence / "active-command.json"
                    if current.exists():
                        observed = json.loads(current.read_text())
                        if observed["pid"] is not None:
                            child_pid = observed["pid"]
                        if observed["status"] == "running" and observed["log_bytes"] > 0:
                            active = observed
                            break
                    if process.poll() is not None:
                        self.fail("driver exited before precompletion observation: " + (self.evidence / "driver.log").read_text())
                    time.sleep(0.01)
                self.assertIsNotNone(active, "no durable running heartbeat with streamed output")
                self.assertEqual(active["runner_pid"], process.pid)
                self.assertFalse(active["completion_recorded"])
                self.assertIsNone(active["observed_returncode"])
                self.assertIsNone(process.poll())
                self.assertIn(f"partial-pid={child_pid}", (self.evidence / "unfinished.log").read_text())
                self.assertFalse((self.evidence / "commands.jsonl").exists())
                self.assertIn("Paired command running: unfinished.log", (self.evidence / "driver.log").read_text())
                process.terminate()
                self.assertEqual(process.wait(timeout=5), -signal.SIGTERM)
                retained_events = self.records("command-events.jsonl")
                unfinished_id = active["command_id"]
                self.assertTrue(all(not e["completion_recorded"] for e in retained_events))
                self.assertEqual(runner.command_phase_status(retained_events[-1]), "INCOMPLETE")
                self.assertFalse((self.evidence / "commands.jsonl").exists())
                # A successful cleanup command may overwrite only the latest
                # observation; it must not erase the unfinished command journal.
                runner.command([sys.executable, "-c", "print('cleanup', flush=True)"], "cleanup.log")
                events = self.records("command-events.jsonl")
                self.assertEqual(events[:len(retained_events)], retained_events)
                unfinished = [e for e in events if e["command_id"] == unfinished_id]
                self.assertTrue(unfinished)
                self.assertTrue(all(not e["completion_recorded"] for e in unfinished))
                self.assertEqual(self.assert_completed_contract(1)[0]["log"], "cleanup.log")
                self.assertIn(f"partial-pid={child_pid}", (self.evidence / "unfinished.log").read_text())
                (self.evidence / "interruption-observation.json").write_text(json.dumps({
                    "driver_returncode": process.returncode, "unfinished_command_id": unfinished_id,
                    "child_pid": child_pid, "partial_output_survived": True,
                    "unfinished_command_retained_after_cleanup": True,
                    "completion_recorded_for_unfinished_command": False}, indent=2) + "\n")
            finally:
                if process.poll() is None:
                    process.kill()
                    process.wait()
                if child_pid is not None:
                    try:
                        os.kill(child_pid, signal.SIGKILL)
                    except ProcessLookupError:
                        pass


if __name__ == "__main__":
    unittest.main()
