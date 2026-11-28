#!/usr/bin/env python3
"""Run a quiet child process while emitting bounded GitHub Actions heartbeats."""

from __future__ import annotations

import argparse
import os
from pathlib import Path
import signal
import subprocess
import sys
import time


def arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--log", required=True, type=Path)
    parser.add_argument("--summary", required=True, type=Path)
    parser.add_argument("--object-root", type=Path)
    parser.add_argument("--timeout", type=int, default=10_800)
    parser.add_argument("--interval", type=int, default=60)
    parser.add_argument("command", nargs=argparse.REMAINDER)
    result = parser.parse_args()
    if result.command and result.command[0] == "--":
        result.command = result.command[1:]
    if not result.command:
        parser.error("a command is required after --")
    return result


def tail_lines(path: Path, count: int = 5) -> list[str]:
    if not path.exists():
        return []
    with path.open("rb") as stream:
        stream.seek(0, os.SEEK_END)
        remaining = stream.tell()
        data = b""
        while remaining > 0 and data.count(b"\n") <= count:
            block = min(8192, remaining)
            remaining -= block
            stream.seek(remaining)
            data = stream.read(block) + data
    return [line[-500:] for line in data.decode("utf-8", errors="replace").splitlines()[-count:]]


def object_count(root: Path | None) -> int:
    if root is None or not root.exists():
        return 0
    return sum(filename.endswith(".o") for _, _, files in os.walk(root) for filename in files)


def emit(message: str, summary: Path) -> None:
    print(message, flush=True)
    with summary.open("a", encoding="utf-8") as stream:
        stream.write(f"{message}\n")


def stop_process_group(process: subprocess.Popen[bytes]) -> None:
    try:
        os.killpg(process.pid, signal.SIGTERM)
    except ProcessLookupError:
        return
    try:
        process.wait(timeout=15)
        return
    except subprocess.TimeoutExpired:
        pass
    try:
        os.killpg(process.pid, signal.SIGKILL)
    except ProcessLookupError:
        return
    process.wait(timeout=15)


def main() -> int:
    args = arguments()
    args.log.parent.mkdir(parents=True, exist_ok=True)
    args.summary.parent.mkdir(parents=True, exist_ok=True)
    args.summary.write_text("", encoding="utf-8")
    started = time.monotonic()
    last_size = -1
    unchanged_since = started
    warned = False

    with args.log.open("wb") as log_stream:
        process = subprocess.Popen(
            args.command,
            stdout=log_stream,
            stderr=subprocess.STDOUT,
            start_new_session=True,
        )

        while True:
            return_code = process.poll()
            elapsed = int(time.monotonic() - started)
            size = args.log.stat().st_size if args.log.exists() else 0
            if size != last_size:
                last_size = size
                unchanged_since = time.monotonic()
                warned = False

            lines = tail_lines(args.log)
            emit(
                f"[heartbeat] elapsed={elapsed}s log_bytes={size} objects={object_count(args.object_root)} "
                f"alive={return_code is None}",
                args.summary,
            )
            for line in lines:
                emit(f"[heartbeat:last] {line}", args.summary)

            if return_code is not None:
                emit(f"[heartbeat] child exited with status {return_code} after {elapsed}s", args.summary)
                return return_code

            if elapsed >= args.timeout:
                emit(f"[heartbeat] internal timeout reached after {elapsed}s; terminating process group", args.summary)
                stop_process_group(process)
                return 124

            if time.monotonic() - unchanged_since >= 600 and not warned:
                emit("[heartbeat] warning: build log has not changed for 10 minutes", args.summary)
                warned = True

            time.sleep(min(args.interval, max(1, args.timeout - elapsed)))


if __name__ == "__main__":
    sys.exit(main())
