"""Bind live-provider access to the simulator this job created and booted.

Ownership is established by the successful create command and its native
readback. Boot readiness is established by the actual targeted bootstatus result.
Consumers validate those receipts without repeating a global simulator inventory.
"""
from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path
import re
import uuid


SELECTION_FILE = "verified-simulator-environment.json"
BOOT_FILE = "08-owned-simulator-boot.json"


def _uuid(value):
    try:
        return str(uuid.UUID(value)).upper()
    except (ValueError, TypeError, AttributeError):
        raise RuntimeError("Owned simulator requires a valid UUID") from None


def _job(run_id, run_attempt):
    if not all(isinstance(value, str) and re.fullmatch(r"[1-9][0-9]*", value)
               for value in (run_id, run_attempt)):
        raise RuntimeError("Owned simulator requires the current GitHub run and attempt")
    return "Hanlin-Phase2-" + run_id + "-" + run_attempt


def motion_run_identity(run_id, run_attempt, run_provider="github"):
    """Keep local Mac labels distinct from the original numeric GitHub identity."""
    if run_provider == "github":
        _job(run_id, run_attempt)
        name = "Hanlin-Phase2-Motion-" + run_id
    elif run_provider == "local-mac":
        if (not isinstance(run_id, str)
                or not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._-]{0,63}", run_id)
                or not isinstance(run_attempt, str)
                or not re.fullmatch(r"[1-9][0-9]*", run_attempt)):
            raise RuntimeError("Local Mac Motion requires an explicit bounded run label and positive attempt")
        name = "Hanlin-Phase2-Motion-local-" + run_id + "-" + run_attempt
    else:
        raise RuntimeError("Unsupported Motion run provider")
    if len(name) > 120:
        raise RuntimeError("A bounded Phase2-owned simulator name is required")
    return {"run_provider": run_provider, "run_id": run_id,
            "run_attempt": run_attempt, "name": name}


def motion_run_from_environment(environment=None):
    environment = os.environ if environment is None else environment
    local_keys = ("HANLIN_LOCAL_RUN_ID", "HANLIN_LOCAL_RUN_ATTEMPT")
    if any(key in environment for key in local_keys):
        if (environment.get("GITHUB_ACTIONS", "").lower() == "true"
                or any(key in environment for key in ("GITHUB_RUN_ID", "GITHUB_RUN_ATTEMPT"))):
            raise RuntimeError("Motion must not mix GitHub and local Mac ownership")
        return motion_run_identity(environment.get(local_keys[0]),
                                   environment.get(local_keys[1]), "local-mac")
    return motion_run_identity(environment.get("GITHUB_RUN_ID"),
                               environment.get("GITHUB_RUN_ATTEMPT"))


def simulator_run_identity(run_id, run_attempt, run_provider="github"):
    """Use Motion's validated providers while keeping ordinary app runs distinct."""
    identity = motion_run_identity(run_id, run_attempt, run_provider)
    name = (_job(run_id, run_attempt) if run_provider == "github"
            else "Hanlin-Phase2-local-" + run_id + "-" + run_attempt)
    return {**identity, "name": name}


def simulator_run_from_environment(environment=None):
    identity = motion_run_from_environment(environment)
    return simulator_run_identity(identity["run_id"], identity["run_attempt"],
                                  identity["run_provider"])


def created_selection(selected, before, observed, requested_name, created_udid,
                      run_id, run_attempt, *, run_provider="github"):
    """Attach provenance only after native create returned a genuinely new UUID."""
    if run_provider == "local-mac":
        allowed_names = {
            motion_run_identity(run_id, run_attempt, run_provider)["name"],
            simulator_run_identity(run_id, run_attempt, run_provider)["name"],
        }
        if requested_name not in allowed_names:
            raise RuntimeError("Local Mac simulator name must match the current run provenance")
    elif run_provider != "github":
        raise RuntimeError("Unsupported simulator run provider")
    simulator = _uuid(created_udid)
    previous = {_uuid(device["udid"]) for devices in before["devices"].values()
                for device in devices}
    if simulator in previous:
        raise RuntimeError("Simulator create returned a device that already existed")
    runtime = selected["runtime"]["identifier"]
    source = selected["device"]
    matches = [device for device in observed["devices"].get(runtime, [])
               if _uuid(device["udid"]) == simulator]
    if (len(matches) != 1 or matches[0]["name"] != requested_name
            or matches[0].get("deviceTypeIdentifier") != source["deviceTypeIdentifier"]
            or matches[0].get("isAvailable") is not True):
        raise RuntimeError("New owned simulator identity, hardware or runtime was not observed")
    return {**selected, "source_device": source, "model": source["name"], "device": matches[0],
            "ownership": {
                "schema_version": 1, "operation": "simctl_create",
                "run_provider": run_provider, "run_id": run_id, "run_attempt": run_attempt,
                "simulator": simulator, "name": requested_name,
                "runtime": runtime, "device_type": source["deviceTypeIdentifier"],
                "source_device": _uuid(source["udid"]), "absent_before_create": True,
            }}


def _created_selection(path, simulator, run_id, run_attempt, expected_name, *, run_provider="github"):
    raw = Path(path).read_bytes()
    selected = json.loads(raw)
    device, runtime, owner = selected["device"], selected["runtime"], selected["ownership"]
    if (owner.get("schema_version") != 1 or owner.get("operation") != "simctl_create"
            or owner.get("absent_before_create") is not True
            or owner.get("run_provider", "github") != run_provider
            or owner.get("run_id") != run_id or owner.get("run_attempt") != run_attempt
            or owner.get("name") != expected_name or device.get("name") != expected_name
            or _uuid(owner.get("simulator")) != simulator or _uuid(device.get("udid")) != simulator
            or _uuid(owner.get("source_device")) == simulator
            or _uuid(selected["source_device"].get("udid")) != _uuid(owner.get("source_device"))
            or owner.get("runtime") != runtime.get("identifier")
            or not owner.get("device_type")
            or owner["device_type"] != device.get("deviceTypeIdentifier")
            or owner["device_type"] != selected["source_device"].get("deviceTypeIdentifier")
            or device.get("isAvailable") is not True):
        raise RuntimeError("Live credentials require this run's freshly created simulator")
    return selected, hashlib.sha256(raw).hexdigest()


def _selection(log, simulator, run_id, run_attempt, *, run_provider="github"):
    identity = simulator_run_identity(run_id, run_attempt, run_provider)
    return _created_selection(Path(log) / SELECTION_FILE, simulator, run_id, run_attempt,
                              identity["name"], run_provider=run_provider)


def verify_owned_motion_creation(path, simulator, run_id, run_attempt, *, run_provider="github"):
    """Validate the original Motion create receipt before touching its UUID."""
    identity = motion_run_identity(run_id, run_attempt, run_provider)
    simulator = _uuid(simulator)
    _, digest = _created_selection(path, simulator, run_id, run_attempt, identity["name"],
                                   run_provider=run_provider)
    return {**identity, "simulator": simulator, "selection_sha256": digest}


def record_owned_boot(log, simulator, result, run_id=None, run_attempt=None, *, run_provider="github"):
    """Call only with the real completed targeted bootstatus command."""
    simulator = _uuid(simulator)
    if run_id is None and run_attempt is None:
        identity = simulator_run_from_environment()
        run_id, run_attempt = identity["run_id"], identity["run_attempt"]
        run_provider = identity["run_provider"]
    else:
        run_id = run_id if run_id is not None else os.environ.get("GITHUB_RUN_ID")
        run_attempt = run_attempt if run_attempt is not None else os.environ.get("GITHUB_RUN_ATTEMPT")
    _, digest = _selection(log, simulator, run_id, run_attempt, run_provider=run_provider)
    expected_command = ["xcrun", "simctl", "bootstatus", simulator, "-b"]
    observed_command = [str(value) for value in result.args]
    if len(observed_command) == 5:
        observed_command[3] = _uuid(observed_command[3])
    if result.returncode != 0 or observed_command != expected_command:
        raise RuntimeError("Owned simulator has no successful targeted bootstatus result")
    receipt = {"schema_version": 1, "status": "BOOTED", "simulator": simulator,
               "run_provider": run_provider, "run_id": run_id, "run_attempt": run_attempt,
               "selection_sha256": digest, "command": expected_command, "exit_code": 0,
               "output_sha256": hashlib.sha256((result.stdout + result.stderr).encode()).hexdigest()}
    path = Path(log) / BOOT_FILE
    temporary = path.with_suffix(".tmp")
    temporary.write_text(json.dumps(receipt, indent=2) + "\n", encoding="utf-8")
    temporary.replace(path)
    return receipt


def verify_owned_simulator(log, run_id, run_attempt, *, run_provider="github"):
    log = Path(log)
    simulator = _uuid((log / "simulator-udid.txt").read_text(encoding="utf-8").strip())
    _, digest = _selection(log, simulator, run_id, run_attempt, run_provider=run_provider)
    raw = (log / BOOT_FILE).read_bytes()
    boot = json.loads(raw)
    if (boot.get("schema_version") != 1 or boot.get("status") != "BOOTED"
            or boot.get("run_provider", "github") != run_provider
            or boot.get("run_id") != run_id or boot.get("run_attempt") != run_attempt
            or _uuid(boot.get("simulator")) != simulator or boot.get("selection_sha256") != digest
            or boot.get("exit_code") != 0
            or boot.get("command") != ["xcrun", "simctl", "bootstatus", simulator, "-b"]):
        raise RuntimeError("Owned simulator lacks this creation's successful boot receipt")
    return {"simulator": simulator, "run_provider": run_provider,
            "run_id": run_id, "run_attempt": run_attempt,
            "selection_sha256": digest, "boot_receipt_sha256": hashlib.sha256(raw).hexdigest()}


def verify_staged_owner(staged, observed):
    # A later legitimate boot may refresh its receipt. Creation and exact device
    # ownership remain immutable throughout stage, result inspection and cleanup.
    expected = staged.get("ownership", {})
    fields = ("simulator", "run_id", "run_attempt", "selection_sha256")
    if (staged.get("simulator") != observed["simulator"]
            or expected.get("run_provider", "github") != observed.get("run_provider", "github")
            or any(expected.get(field) != observed[field] for field in fields)):
        raise RuntimeError("Live credential ownership changed after staging")


if __name__ == "__main__":
    import argparse
    parser = argparse.ArgumentParser(description="Resolve explicit simulator run provenance without native commands")
    names = parser.add_mutually_exclusive_group(required=True)
    names.add_argument("--motion-name", action="store_true")
    names.add_argument("--name", action="store_true")
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    identity = (motion_run_from_environment() if args.motion_name
                else simulator_run_from_environment())
    if args.output:
        args.output.write_text(json.dumps(identity, indent=2) + "\n", encoding="utf-8")
    print(identity["name"])
