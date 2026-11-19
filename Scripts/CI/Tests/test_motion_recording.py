#!/usr/bin/env python3
"""Deterministic unit tests for docs/chat-motion/record_ui_run.py lifecycle and diagnostics."""

from __future__ import annotations

import contextlib
import importlib.util
import io
import json
from pathlib import Path
import signal
import subprocess
from tempfile import TemporaryDirectory
import unittest


_REPO_ROOT = Path(__file__).resolve().parents[3]
_MODULE_PATH = _REPO_ROOT / "docs" / "chat-motion" / "record_ui_run.py"
_SPEC = importlib.util.spec_from_file_location("record_ui_run", _MODULE_PATH)
assert _SPEC is not None and _SPEC.loader is not None
record_ui_run = importlib.util.module_from_spec(_SPEC)
_SPEC.loader.exec_module(record_ui_run)


class _FakeTestProcess:
    def __init__(self, lines: list[str], returncode: int = 0):
        self.stdout = iter(lines)
        self._returncode = returncode

    def wait(self) -> int:
        return self._returncode


class _FakeVideoProcess:
    def __init__(
        self,
        returncode: int = 0,
        mp4_path: Path | None = None,
        mp4_bytes: int = 0,
        raise_timeout_on_wait: bool = False,
    ):
        self._final_returncode = returncode
        self.returncode: int | None = None
        self._mp4_path = mp4_path
        self._mp4_bytes = mp4_bytes
        self._raise_timeout_on_wait = raise_timeout_on_wait
        self.signals: list[int] = []
        self.wait_timeouts: list[float | None] = []
        self.killed = False

    def poll(self) -> int | None:
        return self.returncode

    def send_signal(self, sig: int) -> None:
        self.signals.append(sig)

    def wait(self, timeout: float | None = None) -> int:
        self.wait_timeouts.append(timeout)
        if self._raise_timeout_on_wait and timeout is not None and not self.killed:
            raise subprocess.TimeoutExpired(cmd="xcrun", timeout=timeout)
        if self._mp4_path is not None and self._mp4_bytes > 0 and not self.killed:
            self._mp4_path.write_bytes(b"x" * self._mp4_bytes)
        self.returncode = -9 if self.killed else self._final_returncode
        return self.returncode

    def kill(self) -> None:
        self.killed = True


class _FakeTimer:
    def __init__(self, interval: float, callback, fire_on_start: bool = False):
        self.interval = interval
        self.callback = callback
        self.fire_on_start = fire_on_start
        self.started = False
        self.cancelled = False

    def start(self) -> None:
        self.started = True
        if self.fire_on_start:
            self.callback()

    def cancel(self) -> None:
        self.cancelled = True


class _FakeClock:
    def __init__(self, values: list[float]):
        self._values = iter(values)
        self._last = values[-1]

    def __call__(self) -> float:
        try:
            self._last = next(self._values)
        except StopIteration:
            pass
        return self._last


class MotionRecordingTests(unittest.TestCase):
    def test_capture_starts_only_on_xctest_case_event_and_records_not_started_when_absent(self):
        with TemporaryDirectory() as tmp:
            evidence = Path(tmp)
            spawned_cmds: list[list[str]] = []

            def fake_popen(cmd, **kwargs):
                spawned_cmds.append(list(cmd))
                return _FakeTestProcess(
                    ["Build Succeeded\n", "Testing started\n"],
                    returncode=0,
                )

            with contextlib.redirect_stdout(io.StringIO()):
                result = record_ui_run.run_recording(
                    device="SIM-UUID",
                    evidence=evidence,
                    command=["xcodebuild", "test"],
                    popen_fn=fake_popen,
                )

            self.assertEqual(result, 0)
            self.assertEqual(len(spawned_cmds), 1)
            status = json.loads((evidence / "video-status.json").read_text())
            self.assertEqual(status["status"], "NOT_STARTED_NO_XCTEST_CASE_EVENT")
            self.assertIsNone(status["exit_code"])
            self.assertEqual(status["maximum_recording_seconds"], 120)
            self.assertIsNone(status["stop_reason"])
            self.assertIsNone(status["elapsed_seconds"])
            self.assertFalse(status["sigint_sent"])
            self.assertFalse(status["timed_out_finalizing"])
            self.assertEqual(status["output_bytes"], 0)
            self.assertIn("[record_ui_run]", (evidence / "video.log").read_text())

    def test_test_finished_stops_once_with_monotonic_elapsed_and_output_bytes(self):
        with TemporaryDirectory() as tmp:
            evidence = Path(tmp)
            mp4_path = evidence / "motion-first120s.mp4"
            video_proc = _FakeVideoProcess(returncode=0, mp4_path=mp4_path, mp4_bytes=2048)
            timers: list[_FakeTimer] = []
            spawned_cmds: list[list[str]] = []

            def fake_popen(cmd, **kwargs):
                spawned_cmds.append(list(cmd))
                if cmd[0] == "xcodebuild":
                    return _FakeTestProcess(
                        [
                            "Prepare testing\n",
                            "Test Case '-[MotionUITests testA]' started.\n",
                            "Test Case '-[MotionUITests testA]' passed (4.250 seconds).\n",
                        ],
                        returncode=0,
                    )
                return video_proc

            def fake_timer(interval, callback):
                t = _FakeTimer(interval, callback, fire_on_start=False)
                timers.append(t)
                return t

            clock = _FakeClock([100.0, 104.25])

            with contextlib.redirect_stdout(io.StringIO()):
                result = record_ui_run.run_recording(
                    device="SIM-UUID",
                    evidence=evidence,
                    command=["xcodebuild", "test"],
                    popen_fn=fake_popen,
                    timer_factory=fake_timer,
                    monotonic_fn=clock,
                )

            self.assertEqual(result, 0)
            self.assertEqual(len(spawned_cmds), 2)
            self.assertEqual(
                spawned_cmds[1],
                [
                    "xcrun",
                    "simctl",
                    "io",
                    "SIM-UUID",
                    "recordVideo",
                    "--codec=h264",
                    str(mp4_path),
                ],
            )
            self.assertEqual(len(timers), 1)
            self.assertEqual(timers[0].interval, 120)
            self.assertTrue(timers[0].started)
            self.assertTrue(timers[0].cancelled)
            self.assertEqual(video_proc.signals, [signal.SIGINT])
            self.assertEqual(video_proc.wait_timeouts, [15])

            status = json.loads((evidence / "video-status.json").read_text())
            self.assertEqual(status["exit_code"], 0)
            self.assertEqual(status["status"], "CAPTURE_ATTEMPTED")
            self.assertEqual(status["maximum_recording_seconds"], 120)
            self.assertEqual(
                status["scope"],
                "first120s from an actual XCTest case event, not every preset or original app",
            )
            self.assertEqual(status["stop_reason"], "test_finished")
            self.assertEqual(status["elapsed_seconds"], 4.25)
            self.assertTrue(status["sigint_sent"])
            self.assertFalse(status["timed_out_finalizing"])
            self.assertEqual(status["output_bytes"], 2048)

            log_text = (evidence / "video.log").read_text()
            self.assertIn("stop_reason=test_finished", log_text)
            self.assertIn("elapsed_seconds=4.25", log_text)
            self.assertIn("output_bytes=2048", log_text)

    def test_timer_and_finally_overlap_sends_single_sigint_and_preserves_timer_reason(self):
        with TemporaryDirectory() as tmp:
            evidence = Path(tmp)
            mp4_path = evidence / "motion-first120s.mp4"
            video_proc = _FakeVideoProcess(returncode=0, mp4_path=mp4_path, mp4_bytes=4096)
            timers: list[_FakeTimer] = []

            def fake_popen(cmd, **kwargs):
                if cmd[0] == "xcodebuild":
                    return _FakeTestProcess(["Start test at 2026-11-19\n"], returncode=0)
                return video_proc

            def fake_timer(interval, callback):
                t = _FakeTimer(interval, callback, fire_on_start=True)
                timers.append(t)
                return t

            clock = _FakeClock([10.0, 130.0])

            with contextlib.redirect_stdout(io.StringIO()):
                result = record_ui_run.run_recording(
                    device="SIM-UUID",
                    evidence=evidence,
                    command=["xcodebuild", "test"],
                    popen_fn=fake_popen,
                    timer_factory=fake_timer,
                    monotonic_fn=clock,
                )

            self.assertEqual(result, 0)
            self.assertEqual(video_proc.signals, [signal.SIGINT])
            self.assertTrue(timers[0].cancelled)
            status = json.loads((evidence / "video-status.json").read_text())
            self.assertEqual(status["stop_reason"], "timer_120s")
            self.assertEqual(status["elapsed_seconds"], 120.0)
            self.assertTrue(status["sigint_sent"])
            self.assertEqual(status["output_bytes"], 4096)

    def test_finalization_timeout_kills_video_and_unlinks_mp4(self):
        with TemporaryDirectory() as tmp:
            evidence = Path(tmp)
            mp4_path = evidence / "motion-first120s.mp4"
            mp4_path.write_bytes(b"partial")
            video_proc = _FakeVideoProcess(
                returncode=0,
                mp4_path=mp4_path,
                mp4_bytes=0,
                raise_timeout_on_wait=True,
            )

            def fake_popen(cmd, **kwargs):
                if cmd[0] == "xcodebuild":
                    return _FakeTestProcess(
                        ["Test Case '-[MotionUITests testB]' started.\n"],
                        returncode=0,
                    )
                return video_proc

            with contextlib.redirect_stdout(io.StringIO()):
                record_ui_run.run_recording(
                    device="SIM-UUID",
                    evidence=evidence,
                    command=["xcodebuild", "test"],
                    popen_fn=fake_popen,
                    timer_factory=lambda interval, cb: _FakeTimer(interval, cb),
                    monotonic_fn=_FakeClock([50.0, 52.0]),
                )

            self.assertTrue(video_proc.killed)
            self.assertEqual(video_proc.wait_timeouts, [15, None])
            self.assertFalse(mp4_path.exists())
            status = json.loads((evidence / "video-status.json").read_text())
            self.assertTrue(status["timed_out_finalizing"])
            self.assertEqual(status["exit_code"], -9)
            self.assertEqual(status["output_bytes"], 0)
            self.assertEqual(status["status"], "CAPTURE_ATTEMPTED")

    def test_preserves_nonzero_video_exit_code_without_bypass(self):
        with TemporaryDirectory() as tmp:
            evidence = Path(tmp)
            video_proc = _FakeVideoProcess(returncode=-2, mp4_path=None, mp4_bytes=0)

            def fake_popen(cmd, **kwargs):
                if cmd[0] == "xcodebuild":
                    return _FakeTestProcess(
                        ["Test Case '-[MotionUITests testA]' started.\n"],
                        returncode=0,
                    )
                return video_proc

            with contextlib.redirect_stdout(io.StringIO()):
                result = record_ui_run.run_recording(
                    device="SIM-UUID",
                    evidence=evidence,
                    command=["xcodebuild", "test"],
                    popen_fn=fake_popen,
                    timer_factory=lambda interval, cb: _FakeTimer(interval, cb),
                    monotonic_fn=_FakeClock([1.0, 2.5]),
                )

            self.assertEqual(result, 0)
            status = json.loads((evidence / "video-status.json").read_text())
            self.assertEqual(status["exit_code"], -2)
            self.assertEqual(status["status"], "CAPTURE_ATTEMPTED")
            self.assertEqual(status["output_bytes"], 0)
            self.assertEqual(status["stop_reason"], "test_finished")
            self.assertEqual(status["elapsed_seconds"], 1.5)
            self.assertIn("exit_code=-2", (evidence / "video.log").read_text())


if __name__ == "__main__":
    unittest.main()
