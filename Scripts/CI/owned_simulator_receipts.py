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


def created_selection(selected, before, observed, requested_name, created_udid,
                      run_id, run_attempt):
    """Attach provenance only after native create returned a genuinely new UUID."""
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
                "run_id": run_id, "run_attempt": run_attempt,
                "simulator": simulator, "name": requested_name,
                "runtime": runtime, "device_type": source["deviceTypeIdentifier"],
                "source_device": _uuid(source["udid"]), "absent_before_create": True,
            }}


def _selection(log, simulator, run_id, run_attempt):
    expected_name = _job(run_id, run_attempt)
    raw = (Path(log) / SELECTION_FILE).read_bytes()
    selected = json.loads(raw)
    device, runtime, owner = selected["device"], selected["runtime"], selected["ownership"]
    if (owner.get("schema_version") != 1 or owner.get("operation") != "simctl_create"
            or owner.get("absent_before_create") is not True
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


def record_owned_boot(log, simulator, result, run_id=None, run_attempt=None):
    """Call only with the real completed targeted bootstatus command."""
    simulator = _uuid(simulator)
    run_id = run_id if run_id is not None else os.environ.get("GITHUB_RUN_ID")
    run_attempt = run_attempt if run_attempt is not None else os.environ.get("GITHUB_RUN_ATTEMPT")
    _, digest = _selection(log, simulator, run_id, run_attempt)
    expected_command = ["xcrun", "simctl", "bootstatus", simulator, "-b"]
    observed_command = [str(value) for value in result.args]
    if len(observed_command) == 5:
        observed_command[3] = _uuid(observed_command[3])
    if result.returncode != 0 or observed_command != expected_command:
        raise RuntimeError("Owned simulator has no successful targeted bootstatus result")
    receipt = {"schema_version": 1, "status": "BOOTED", "simulator": simulator,
               "run_id": run_id, "run_attempt": run_attempt,
               "selection_sha256": digest, "command": expected_command, "exit_code": 0,
               "output_sha256": hashlib.sha256((result.stdout + result.stderr).encode()).hexdigest()}
    path = Path(log) / BOOT_FILE
    temporary = path.with_suffix(".tmp")
    temporary.write_text(json.dumps(receipt, indent=2) + "\n", encoding="utf-8")
    temporary.replace(path)
    return receipt


def verify_owned_simulator(log, run_id, run_attempt):
    log = Path(log)
    simulator = _uuid((log / "simulator-udid.txt").read_text(encoding="utf-8").strip())
    _, digest = _selection(log, simulator, run_id, run_attempt)
    raw = (log / BOOT_FILE).read_bytes()
    boot = json.loads(raw)
    if (boot.get("schema_version") != 1 or boot.get("status") != "BOOTED"
            or boot.get("run_id") != run_id or boot.get("run_attempt") != run_attempt
            or _uuid(boot.get("simulator")) != simulator or boot.get("selection_sha256") != digest
            or boot.get("exit_code") != 0
            or boot.get("command") != ["xcrun", "simctl", "bootstatus", simulator, "-b"]):
        raise RuntimeError("Owned simulator lacks this creation's successful boot receipt")
    return {"simulator": simulator, "run_id": run_id, "run_attempt": run_attempt,
            "selection_sha256": digest, "boot_receipt_sha256": hashlib.sha256(raw).hexdigest()}


def verify_staged_owner(staged, observed):
    # A later legitimate boot may refresh its receipt. Creation and exact device
    # ownership remain immutable throughout stage, result inspection and cleanup.
    expected = staged.get("ownership", {})
    fields = ("simulator", "run_id", "run_attempt", "selection_sha256")
    if (staged.get("simulator") != observed["simulator"]
            or any(expected.get(field) != observed[field] for field in fields)):
        raise RuntimeError("Live credential ownership changed after staging")
