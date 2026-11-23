#!/usr/bin/env python3
"""Require native Motion boot readiness, with at most one owned timeout recovery.

Only the current run's original freshly-created simulator may be shutdown and
booted once after an actual bootstatus timeout. An inventory state of Booted is
never readiness evidence. Existing ready-device consumers never receive recovery.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import time
import uuid

if __package__:
    from .owned_simulator_receipts import verify_owned_motion_creation
else:
    from owned_simulator_receipts import verify_owned_motion_creation

BOOT_SECONDS = 15.0
# Native cold-start admission only; Motion test/animation deadlines are separate.
BOOTSTATUS_SECONDS = 300.0
SHUTDOWN_SECONDS = 20.0


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def native_command(command, timeout, output):
    """Retain native output and distinguish an actual timeout from exit code124."""
    started = time.monotonic()
    timed_out = False
    with Path(output).open("wb") as stream:
        try:
            result = subprocess.run(command, stdout=stream, stderr=subprocess.STDOUT,
                                    timeout=timeout, check=False)
            code = result.returncode
        except subprocess.TimeoutExpired:
            timed_out, code = True, 124
    return {"command": command, "timeout_seconds": timeout, "return_code": code,
            "timed_out": timed_out, "elapsed_seconds": round(time.monotonic() - started, 3),
            "output_file": Path(output).name, "output_sha256": digest(output)}


def ensure_ready(device, selection, strategy, run_id, run_attempt, runner=native_command):
    selection = Path(selection)
    out = selection.parent
    receipt = {"schema_version": 1, "status": "NOT_READY", "device": device,
               "strategy": strategy, "run_id": run_id, "run_attempt": run_attempt,
               "attempts": [], "recovery_count": 0,
               "scope": "Simulator readiness only; Motion product tests NOT_RUN"}
    initial_hash = None
    owner = None

    def save():
        (out / "motion-boot-readiness.json").write_text(
            json.dumps(receipt, indent=2) + "\n", encoding="utf-8")

    def still_selected():
        if digest(selection) != initial_hash:
            raise RuntimeError("Motion simulator selection changed during readiness")
        if strategy == "fresh":
            current = verify_owned_motion_creation(selection, device, run_id, run_attempt)
            if current != owner:
                raise RuntimeError("Motion simulator ownership changed during readiness")

    def command(name, operation, timeout):
        still_selected()
        result = runner(["xcrun", "simctl", operation, device] +
                        (["-b"] if operation == "bootstatus" else []),
                        timeout, out / (name + ".log"))
        receipt["attempts"].append({"name": name, **result})
        save()
        return result

    def succeeded(result):
        return result["return_code"] == 0 and result["timed_out"] is False

    try:
        if strategy not in ("fresh", "ready"):
            raise RuntimeError("Unsupported Motion device strategy")
        device = str(uuid.UUID(device)).upper()
        receipt["device"] = device
        selected = json.loads(selection.read_bytes())
        if str(uuid.UUID(selected["device"]["udid"])).upper() != device:
            raise RuntimeError("Selected Motion UUID differs from requested device")
        initial_hash = digest(selection)
        if strategy == "fresh":
            owner = verify_owned_motion_creation(selection, device, run_id, run_attempt)
            receipt["ownership"] = owner
        elif selected["device"]["state"] != "Booted":
            raise RuntimeError("BLOCKED_ENVIRONMENT: ready strategy requires the existing booted selection")

        if selected["device"]["state"] != "Booted":
            if not succeeded(command("boot-initial", "boot", BOOT_SECONDS)):
                raise RuntimeError("Initial Motion boot command failed")
        first = command("bootstatus-attempt-1", "bootstatus", BOOTSTATUS_SECONDS)
        if not succeeded(first):
            if strategy != "fresh" or first["timed_out"] is not True:
                raise RuntimeError("Motion bootstatus failed; owned timeout recovery is not eligible")
            # Revalidate the immutable original creation receipt immediately before
            # the only shutdown/boot cycle. Never reset another device or service.
            still_selected()
            receipt["recovery_count"] = 1
            receipt["recovery_reason"] = "FIRST_NATIVE_BOOTSTATUS_TIMEOUT"
            save()
            if not succeeded(command("shutdown-recovery", "shutdown", SHUTDOWN_SECONDS)):
                raise RuntimeError("Owned Motion recovery shutdown failed")
            if not succeeded(command("boot-recovery", "boot", BOOT_SECONDS)):
                raise RuntimeError("Owned Motion recovery boot failed")
            second = command("bootstatus-attempt-2", "bootstatus", BOOTSTATUS_SECONDS)
            if not succeeded(second):
                raise RuntimeError("Owned Motion recovery did not establish boot readiness; no further retry")
        still_selected()
        receipt["status"] = "READY_FROM_NATIVE_BOOTSTATUS"
        save()
        return receipt
    except (OSError, ValueError, TypeError, AttributeError, KeyError, RuntimeError) as error:
        receipt["error"] = str(error)
        save()
        raise
    finally:
        # Preserve the old evidence name while retaining each attempt separately.
        logs = []
        for attempt in receipt["attempts"]:
            if attempt["name"].startswith("bootstatus-attempt"):
                path = out / attempt["output_file"]
                logs.append((json.dumps({k: v for k, v in attempt.items()
                                         if k != "output_sha256"}) + "\n").encode()
                            + (path.read_bytes() if path.is_file() else b""))
        (out / "bootstatus.log").write_bytes(b"\n".join(logs))


def retain_startup_context(out):
    # Record selected tooling without dumping unrelated environment variables.
    context = {"schema_version": 1, "developer_dir": os.environ.get("DEVELOPER_DIR"),
               "effective_uid": os.geteuid(), "python_executable": sys.executable,
               "scope": "Read-only startup diagnostics; not simulator readiness"}
    try:
        result = native_command(["xcrun", "--find", "simctl"], 5, out / "simctl-tool-path.log")
        context["simctl_lookup"] = result
        if result["return_code"] == 0 and not result["timed_out"]:
            context["simctl_path"] = (out / "simctl-tool-path.log").read_text(errors="replace").strip()
    except OSError as error:
        context["simctl_lookup_error"] = str(error)
    (out / "motion-startup-context.json").write_text(json.dumps(context, indent=2) + "\n")


def retain_failure_observations(out):
    # These were already collected by the original Motion wrapper on failure.
    # They diagnose readiness; their state never changes the failed verdict.
    for name, command in [
        ("devices-after", ["xcrun", "simctl", "list", "devices", "-j"]),
        ("core-simulator-log", ["log", "show", "--last", "3m", "--style", "compact",
                               "--predicate", 'process == "CoreSimulatorService"']),
    ]:
        try:
            result = subprocess.run(command, capture_output=True, timeout=15)
            (out / (name + ".stdout")).write_bytes(result.stdout)
            (out / (name + ".stderr")).write_bytes(result.stderr)
        except subprocess.TimeoutExpired as error:
            (out / (name + ".stdout")).write_bytes(error.stdout or b"")
            (out / (name + ".stderr")).write_bytes(error.stderr or b"")
            (out / (name + ".timeout")).write_text("15s observation deadline", encoding="utf-8")
        except OSError as error:
            (out / (name + ".error")).write_text(str(error), encoding="utf-8")

    # Only retain simulator-service names belonging to this runner user. This
    # never signals a service, reads process environments, or changes readiness.
    uid = os.geteuid()
    command = ["ps", "-u", str(uid), "-o", "pid=,ppid=,uid=,stat=,comm="]
    snapshot = {"schema_version": 1, "command": command, "timeout_seconds": 5,
                "effective_uid": uid, "processes": [], "timed_out": False}
    output = b""
    try:
        result = subprocess.run(command, capture_output=True, timeout=5)
        output = result.stdout
        snapshot.update(return_code=result.returncode, stderr=result.stderr.decode(errors="replace"))
    except subprocess.TimeoutExpired as error:
        output = error.stdout or b""
        snapshot.update(timed_out=True, return_code=124,
                        stderr=(error.stderr or b"").decode(errors="replace"))
    except OSError as error:
        snapshot["error"] = str(error)
    allowed = {"CoreSimulatorService", "com.apple.CoreSimulator.CoreSimulatorService",
               "simctl", "Simulator", "SimulatorTrampoline", "launchd_sim"}
    for line in output.decode(errors="replace").splitlines():
        fields = line.split(None, 4)
        if (len(fields) == 5 and all(value.isdigit() for value in fields[:3])
                and int(fields[2]) == uid and Path(fields[4]).name in allowed):
            snapshot["processes"].append({"pid": int(fields[0]), "ppid": int(fields[1]),
                "uid": int(fields[2]), "state": fields[3], "executable": fields[4]})
    (out / "simulator-process-observation.json").write_text(json.dumps(snapshot, indent=2) + "\n")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--device", required=True)
    parser.add_argument("--selection", type=Path, required=True)
    parser.add_argument("--strategy", choices=("fresh", "ready"), required=True)
    args = parser.parse_args()
    retain_startup_context(args.selection.parent)
    try:
        ensure_ready(args.device, args.selection, args.strategy,
                     os.environ.get("GITHUB_RUN_ID"), os.environ.get("GITHUB_RUN_ATTEMPT"))
    except (OSError, ValueError, TypeError, AttributeError, KeyError, RuntimeError) as error:
        retain_failure_observations(args.selection.parent)
        print("Motion preflight failed: " + str(error), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
