"""Bound recording to 120s, finalize with SIGINT; recording does not drive UI actions."""
import argparse
import json
import signal
import subprocess
import threading
import time
from pathlib import Path

MAX_RECORDING_SECONDS = 120
FINALIZE_TIMEOUT_SECONDS = 15
SCOPE_DESCRIPTION = 'first120s from an actual XCTest case event, not every preset or original app'


class _SignalTermination(BaseException):
    def __init__(self, sig: int):
        super().__init__(f'Terminated by signal {sig}')
        self.sig = sig


def _should_start_recording(line: str) -> bool:
    lower = line.lower()
    return ('test case' in lower and 'started' in lower) or 'start test at' in lower


def run_recording(
    device: str,
    evidence: Path,
    command: list[str],
    popen_fn=subprocess.Popen,
    timer_factory=threading.Timer,
    monotonic_fn=time.monotonic,
) -> int:
    log_path = evidence / 'video.log'
    mp4_path = evidence / 'motion-first120s.mp4'
    log = log_path.open('wb')
    video = None
    timer = None
    started_at = None
    stop_lock = threading.Lock()
    stop_reason = None
    elapsed_seconds = None
    sigint_sent = False
    timed_out_finalizing = False

    def stop(reason: str) -> None:
        nonlocal stop_reason, elapsed_seconds, sigint_sent
        with stop_lock:
            if video is None or stop_reason is not None:
                return
            stop_reason = reason
            if started_at is not None:
                elapsed_seconds = round(max(0.0, monotonic_fn() - started_at), 3)
            if video.poll() is None:
                try:
                    video.send_signal(signal.SIGINT)
                    sigint_sent = True
                except ProcessLookupError:
                    sigint_sent = False

    is_main_thread = threading.current_thread() is threading.main_thread()
    prev_sigterm = None
    if is_main_thread:
        def _handle_sigterm(signum, _frame):
            raise _SignalTermination(signum)

        prev_sigterm = signal.signal(signal.SIGTERM, _handle_sigterm)

    test = popen_fn(
        command,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        encoding='utf-8',
        errors='replace',
        bufsize=1,
    )
    finish_reason = 'test_finished'
    interrupted_exc: BaseException | None = None
    try:
        for line in test.stdout or ():
            print(line, end='', flush=True)
            # xcodebuild owns simulator startup. Capture starts only on an actual
            # XCTest case event, never on an assumed boot delay or private state.
            if video is None and _should_start_recording(line):
                started_at = monotonic_fn()
                video = popen_fn(
                    [
                        'xcrun',
                        'simctl',
                        'io',
                        device,
                        'recordVideo',
                        '--codec=h264',
                        str(mp4_path),
                    ],
                    stdout=log,
                    stderr=log,
                )
                timer = timer_factory(MAX_RECORDING_SECONDS, lambda: stop('timer_120s'))
                timer.start()
        result = test.wait()
    except KeyboardInterrupt as exc:
        finish_reason = 'interrupted'
        interrupted_exc = exc
    except _SignalTermination as exc:
        finish_reason = 'terminated'
        interrupted_exc = exc
    finally:
        prev_sigint = None
        if is_main_thread:
            prev_sigint = signal.signal(signal.SIGINT, signal.SIG_IGN)
            signal.signal(signal.SIGTERM, signal.SIG_IGN)
        try:
            if timer is not None:
                timer.cancel()
            stop(finish_reason)
            if video is not None:
                try:
                    video.wait(timeout=FINALIZE_TIMEOUT_SECONDS)
                except subprocess.TimeoutExpired:
                    timed_out_finalizing = True
                    video.kill()
                    video.wait()
                    mp4_path.unlink(missing_ok=True)
            output_bytes = mp4_path.stat().st_size if mp4_path.exists() else 0
            exit_code = video.returncode if video is not None else None
            status = 'CAPTURE_ATTEMPTED' if video is not None else 'NOT_STARTED_NO_XCTEST_CASE_EVENT'
            diagnostic_line = (
                f"[record_ui_run] status={status} exit_code={exit_code} "
                f"stop_reason={stop_reason} elapsed_seconds={elapsed_seconds} "
                f"sigint_sent={sigint_sent} timed_out_finalizing={timed_out_finalizing} "
                f"output_bytes={output_bytes}\n"
            )
            log.write(diagnostic_line.encode('utf-8'))
            log.close()
            (evidence / 'video-status.json').write_text(
                json.dumps(
                    {
                        'exit_code': exit_code,
                        'status': status,
                        'maximum_recording_seconds': MAX_RECORDING_SECONDS,
                        'scope': SCOPE_DESCRIPTION,
                        'stop_reason': stop_reason,
                        'elapsed_seconds': elapsed_seconds,
                        'sigint_sent': sigint_sent,
                        'timed_out_finalizing': timed_out_finalizing,
                        'output_bytes': output_bytes,
                    }
                )
            )
        finally:
            if is_main_thread:
                if prev_sigint is not None:
                    signal.signal(signal.SIGINT, prev_sigint)
                if prev_sigterm is not None:
                    signal.signal(signal.SIGTERM, prev_sigterm)
    if interrupted_exc is not None:
        if isinstance(interrupted_exc, _SignalTermination):
            return 128 + interrupted_exc.sig
        raise interrupted_exc
    return result


def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser()
    p.add_argument('--device', required=True)
    p.add_argument('--evidence', type=Path, required=True)
    p.add_argument('command', nargs=argparse.REMAINDER)
    a = p.parse_args(argv)
    command = a.command[1:] if a.command and a.command[0] == '--' else a.command
    try:
        return run_recording(device=a.device, evidence=a.evidence, command=command)
    except KeyboardInterrupt:
        return 128 + signal.SIGINT


if __name__ == '__main__':
    raise SystemExit(main())
