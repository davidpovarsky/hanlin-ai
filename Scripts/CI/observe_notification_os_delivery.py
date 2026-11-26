#!/usr/bin/env python3
"""Observe real simulator notification ingress while the separate XCTest owns UI.

The caller owns Xcode/simulator lifecycle, staging, source identity and budget.
This worker writes only its fresh evidence output and the UI runner's exchange
directory. Product registry, catalog, command queue and receipts are read-only.
A simctl submission is never sufficient for a successful result.
"""
from __future__ import annotations

import argparse
import datetime
import hashlib
import json
import math
import os
from pathlib import Path
import struct
import subprocess
import sys
import time
import traceback
import uuid


def check(condition, message):
    if not condition:
        raise RuntimeError(message)


def utc():
    return datetime.datetime.now(datetime.timezone.utc).isoformat()


def digest(data):
    return hashlib.sha256(data).hexdigest()


def write_json(path, value):
    temporary = path.with_name(path.name + "." + uuid.uuid4().hex + ".tmp")
    temporary.write_text(json.dumps(value, ensure_ascii=False, sort_keys=True, indent=2) + "\n")
    os.replace(temporary, path)


def read_json(path):
    return json.loads(path.read_bytes())


def wait_for(callback, deadline, description):
    while time.monotonic() < deadline:
        result = callback()
        if result is not None:
            return result
        time.sleep(0.2)
    raise TimeoutError(description)


def decode_value(value):
    """Read the existing tagged HanlinValue Codable representation."""
    kind = value["type"]
    payload = value.get("value")
    if kind == "null":
        check("value" not in value, "Unexpected null payload")
        return None
    if kind == "integer":
        check(isinstance(payload, str), "Integer payload is not canonical text")
        result = int(payload)
        check(str(result) == payload, "Integer payload is not canonical")
        return result
    if kind == "number":
        check(isinstance(payload, str) and len(payload) == 16, "Invalid binary64 bits")
        result = struct.unpack(">d", bytes.fromhex(payload))[0]
        check(math.isfinite(result), "Non-finite result")
        return result
    if kind in ("string", "bool"):
        check(isinstance(payload, str if kind == "string" else bool), "Invalid value type")
        return payload
    if kind == "array":
        return [decode_value(item) for item in payload]
    if kind == "object":
        check(isinstance(payload, list), "HanlinObject must encode unique key/value members")
        keys = [member["key"] for member in payload]
        check(len(set(keys)) == len(keys), "Duplicate result member")
        return {member["key"]: decode_value(member["value"]) for member in payload}
    raise RuntimeError("Unsupported result type in this fixture: " + str(kind))


class TargetNotPublished(Exception):
    pass


def installed_target(registry_path, extension_root, package_name, runtime, action, evidence):
    registry_bytes = registry_path.read_bytes()
    registry = json.loads(registry_bytes)
    candidates = [
        entry for entry in registry["packages"].values()
        if entry.get("enabled") is True and entry.get("manifest", {}).get("name") == package_name
    ]
    if not candidates:
        raise TargetNotPublished("The enabled fixture installation is not yet in the current registry")
    check(len(candidates) == 1, "Expected exactly one current enabled fixture installation")
    package = candidates[0]
    record = package["record"]
    check(record["activeGeneration"] > 0, "Missing installed generation")
    check(registry["packages"].get(record["installedPackageID"]) == package, "Installed registry identity mismatch")
    commit_path = extension_root / "commit.json"
    if not commit_path.is_file():
        raise TargetNotPublished("The original extension catalog has not committed its first revision")
    commit_bytes = commit_path.read_bytes()
    commit = json.loads(commit_bytes)
    snapshot_hash = commit["snapshotHash"]
    check(len(snapshot_hash) == 64 and all(c in "0123456789abcdef" for c in snapshot_hash), "Invalid snapshot digest")
    revision_bytes = (extension_root / "Revisions" / (snapshot_hash + ".json")).read_bytes()
    check(digest(revision_bytes) == snapshot_hash, "Committed snapshot bytes do not match their digest")
    envelope = json.loads(revision_bytes)
    snapshot = envelope["snapshot"]
    entities = [
        entity for entity in snapshot["intentEntities"]
        if entity["id"] == action
        and entity["identity"]["installedPackageID"] == record["installedPackageID"]
        and entity["identity"]["packageID"] == record["packageID"]
        and entity["identity"]["generation"] == record["activeGeneration"]
    ]
    if not entities:
        raise TargetNotPublished("The committed catalog does not yet publish the current installed generation/action")
    check(len(entities) == 1, "Expected one actual published action identity for the current installation")
    identity = entities[0]["identity"]
    entrypoints = [
        entry for entry in package["entrypoints"]
        if entry["id"] == identity["entrypointID"] and entry["kind"] == "appIntent"
        and entry["runtimeProfile"] == "hanlin-" + runtime
    ]
    check(len(entrypoints) == 1, "Published identity does not name the current original runtime entrypoint")
    app_id = package["manifest"].get("hanlinAppID") or record["packageID"]
    check(isinstance(app_id, str) and app_id, "No current canonical app identity")
    evidence.mkdir()
    (evidence / "registry.json").write_bytes(registry_bytes)
    (evidence / "commit.json").write_bytes(commit_bytes)
    (evidence / "revision.json").write_bytes(revision_bytes)
    write_json(evidence / "target.json", {
        "package": package, "entity": entities[0], "appID": app_id,
        "registrySHA256": digest(registry_bytes), "revisionSHA256": snapshot_hash
    })
    return app_id, identity


def ready_target(registry_path, extension_root, package_name, runtime, action, evidence, deadline):
    start = time.monotonic()
    attempts = 0
    last_pending = None
    limit = min(deadline, start + 15)
    while time.monotonic() < limit:
        attempts += 1
        try:
            target = installed_target(registry_path, extension_root, package_name, runtime, action, evidence)
        except TargetNotPublished as error:
            last_pending = str(error)
            time.sleep(0.2)
            continue
        write_json(evidence.with_name(evidence.name + "-readiness.json"), {
            "status": "READY", "attempts": attempts, "lastPendingReason": last_pending,
            "elapsedSeconds": time.monotonic() - start, "observedAt": utc(),
        })
        return target
    write_json(evidence.with_name(evidence.name + "-readiness.json"), {
        "status": "NOT_READY", "attempts": attempts, "lastPendingReason": last_pending,
        "elapsedSeconds": time.monotonic() - start, "observedAt": utc(),
    })
    raise TimeoutError("No coherent current installed action within the existing phase deadline: " + str(last_pending))


def terminal_record(extension_root, event_id):
    path = extension_root / "ResumeQueue" / "Receipts" / (str(uuid.UUID(event_id)) + ".json")
    if not path.is_file():
        return None
    data = path.read_bytes()
    record = json.loads(data)
    receipt = record.get("receipt", {})
    if receipt.get("status") in ("queued", "running", None):
        return None
    return path, data, record


def observe(args, request, run_directory, extension_root, registry_path, output, deadline):
    runtime = request["runtime"]
    phase = output / runtime
    phase.mkdir()
    observations = []
    expected_action = "hostServicesEcho" if runtime == "expo" else "parity.intent"
    app_id, identity = ready_target(
        registry_path, extension_root, request["packageName"], runtime, expected_action, phase / "target-success", deadline
    )
    parameters = {"ordinal": 41, "challenge": request["challenge"], "unicode": "שלום🙂"}
    created = int(time.time() * 1000)
    event = {
        "schemaVersion": 1, "id": str(uuid.uuid4()),
        "createdAtUnixMilliseconds": created, "expiresAtUnixMilliseconds": created + 180000,
        "appID": app_id, "identity": identity, "actionID": expected_action, "parameters": parameters,
    }
    first_bytes = None
    for kind in (["success", "duplicate", "failure"] if runtime == "expo" else ["success", "duplicate"]):
        if kind == "failure":
            failure_app_id, failure_identity = ready_target(
                registry_path, extension_root, request["packageName"], runtime,
                "hostServicesFail", phase / "target-failure", deadline
            )
            now = int(time.time() * 1000)
            event = {
                "schemaVersion": 1, "id": str(uuid.uuid4()),
                "createdAtUnixMilliseconds": now, "expiresAtUnixMilliseconds": now + 180000,
                "appID": failure_app_id, "identity": failure_identity,
                "actionID": "hostServicesFail", "parameters": None,
            }
        existing = terminal_record(extension_root, event["id"])
        check((kind == "duplicate") == (existing is not None), "Fresh event unexpectedly has a prior terminal record")
        payload = {"aps": {"alert": {"title": "Hanlin notification probe", "body": runtime}},
                   "hanlin-miniapp-event": event}
        payload_path = phase / (kind + ".apns")
        write_json(payload_path, payload)
        command = ["xcrun", "simctl", "push", args.device, "com.itorah.hanlinminiapps", str(payload_path)]
        started = utc()
        start = time.monotonic()
        completed = subprocess.run(command, capture_output=True, timeout=min(15, max(0.1, deadline - time.monotonic())))
        (phase / (kind + "-push.stdout")).write_bytes(completed.stdout)
        (phase / (kind + "-push.stderr")).write_bytes(completed.stderr)
        push = {
            "command": command, "startedAt": started, "finishedAt": utc(),
            "elapsedSeconds": time.monotonic() - start, "returncode": completed.returncode,
            "stdoutSHA256": digest(completed.stdout), "stderrSHA256": digest(completed.stderr),
        }
        write_json(phase / (kind + "-push.json"), push)
        check(completed.returncode == 0, "simctl rejected the notification submission")
        if kind == "duplicate":
            # A second successful simctl submission plus an unchanged durable
            # record is an observation, not proof of a second delegate callback.
            until = min(deadline, time.monotonic() + 3)
            while time.monotonic() < until:
                current = terminal_record(extension_root, event["id"])
                check(current is not None and current[1] == first_bytes, "Duplicate submission changed terminal evidence")
                time.sleep(0.2)
        path, raw, record = wait_for(
            lambda: terminal_record(extension_root, event["id"]),
            min(deadline, time.monotonic() + 70), "No actual terminal OS-ingress receipt"
        )
        receipt = record["receipt"]
        check(uuid.UUID(record["id"]) == uuid.UUID(event["id"]), "Command identity mismatch")
        check(uuid.UUID(receipt["invocationID"]) == uuid.UUID(event["id"]), "Receipt identity mismatch")
        check(receipt["attempt"] == 1 and receipt["cancellationRequested"] is False, "Unexpected attempt/cancellation")
        invocation = record["invocation"]
        check(invocation["identity"] == event["identity"], "Receipt bound to another installed entrypoint")
        check(invocation["entityID"] == event["actionID"], "Receipt action mismatch")
        delivery = invocation["delivery"]
        check(delivery["source"] == "notification" and delivery["appID"] == event["appID"]
              and delivery["expectedResult"] == "value" and delivery["userGesturePresent"] is False
              and delivery["canPresentUI"] is False and invocation["continueInForeground"] is True,
              "Receipt did not use the actual notification ingress contract")
        check(decode_value(invocation["parameters"]) == event["parameters"], "Receipt parameters differ from the real push")
        decoded = None
        if kind == "failure":
            check(receipt["status"] == "failed" and receipt.get("failure") == "actionFailed"
                  and "value" not in receipt, "Expected actual installed JS rejection")
        else:
            check(receipt["status"] == "succeeded" and "failure" not in receipt, "The original action did not succeed")
            decoded = decode_value(receipt["value"])
            if isinstance(decoded, str):
                decoded = json.loads(decoded)
            check(isinstance(decoded, dict), "Expected the real fixture's object reply")
            if runtime == "expo":
                check(uuid.UUID(decoded["id"]) == uuid.UUID(event["id"])
                      and decoded["caller"] == "hanlin.host" and decoded["action"] == "hostServicesEcho"
                      and decoded["parameters"] == parameters and decoded["computed"] == 42
                      and decoded["storageVerified"] is True, "Installed Hermes returned an incorrect result")
            else:
                check(decoded["source"] == "hanlin.demo.script-parity"
                      and decoded["caller"] == "hanlin.host" and decoded["action"] == "parity.intent"
                      and decoded["request"] == parameters
                      and isinstance(decoded["counter"], int) and not isinstance(decoded["counter"], bool)
                      and isinstance(decoded["name"], str), "Installed NativeScript returned an incorrect result")
        (phase / (kind + "-record.json")).write_bytes(raw)
        check(path.read_bytes() == raw, "Reopened terminal receipt changed")
        if kind == "success":
            first_bytes = raw
        if kind == "duplicate":
            check(raw == first_bytes, "Duplicate submission did not retain the identical receipt")
        observations.append({
            "kind": kind, "pushExitCode": completed.returncode, "push": push,
            "recordPath": str(path), "recordSHA256": digest(raw),
            "record": record, "decodedValue": decoded,
            "duplicateCallbackIndependentlyObserved": False if kind == "duplicate" else None,
        })
    return observations


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--device", required=True)
    parser.add_argument("--runner-data", type=Path, required=True)
    parser.add_argument("--app-data", type=Path, required=True)
    parser.add_argument("--app-group", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--started-after", type=float, required=True)
    parser.add_argument("--timeout", type=float, default=650)
    args = parser.parse_args()
    args.device = str(uuid.UUID(args.device)).upper()
    check(0 < args.timeout <= 650, "Worker deadline must fit the separate UI probe allowance")
    device_root = (Path.home() / "Library/Developer/CoreSimulator/Devices" / args.device / "data/Containers").resolve()
    for path in (args.runner_data, args.app_data, args.app_group):
        check(path.is_dir() and path.resolve().is_relative_to(device_root), "Container does not belong to the explicitly owned device")
    check(args.runner_data.resolve() != args.app_data.resolve(), "The UI exchange must be outside the product container")
    check(not args.output.exists(), "Use a fresh evidence output directory")
    args.output.mkdir(parents=True)
    exchange = args.runner_data / "Documents/HanlinNotificationOSProbe"
    registry_path = args.app_data / "Library/Application Support/Hanlin/ScriptingPlatform/Installed/registry/catalog.json"
    extension_root = args.app_group / "HanlinMiniApps/v1/ScriptingExtensions"
    deadline = time.monotonic() + args.timeout
    active_path = exchange / "active.json"
    active = wait_for(
        lambda: read_json(active_path) if active_path.is_file() and active_path.stat().st_mtime >= args.started_after else None,
        deadline, "The actual UI test did not publish a fresh exchange identity"
    )
    check(active["version"] == 1, "Unsupported exchange version")
    run_id = str(uuid.UUID(active["runID"]))
    check(run_id == active["runID"] and active["challenge"].startswith("notification-os-"), "Invalid UI identity")
    run_directory = exchange / run_id
    write_json(args.output / "active.json", active)
    for runtime, package_name in [("expo", "Expo SwiftUI Probe A"), ("nativescript", "HanlinScript Parity")]:
        request_path = run_directory / (runtime + ".request.json")
        request = wait_for(lambda: read_json(request_path) if request_path.is_file() else None,
                           deadline, "The UI did not reach " + runtime)
        check(request == {**active, "runtime": runtime, "packageName": package_name}, "UI request identity changed")
        write_json(args.output / (runtime + ".request.json"), request)
        completion = {**active, "runtime": runtime, "transport": "simctl_push", "status": "FAILED"}
        try:
            completion["observations"] = observe(
                args, request, run_directory, extension_root, registry_path,
                args.output, min(deadline, time.monotonic() + 110)
            )
            completion["status"] = "EXECUTED_PASS"
            completion["boundary"] = (
                "Foreground simulator OS ingress and actual installed action receipts. "
                "No real APNs provider, service-extension invocation, background or physical-device result is inferred."
            )
        except Exception as error:
            completion["reason"] = str(error)
            (args.output / (runtime + "-failure.txt")).write_text(traceback.format_exc())
        completion["finishedAt"] = utc()
        write_json(args.output / (runtime + ".complete.json"), completion)
        write_json(run_directory / (runtime + ".complete.json"), completion)
        check(completion["status"] == "EXECUTED_PASS", completion.get("reason", "OS observation failed"))
    ui_result = wait_for(
        lambda: read_json(run_directory / "ui-finished.json")
        if (run_directory / "ui-finished.json").is_file() else None,
        deadline, "The actual UI case did not complete"
    )
    check(ui_result == {**active, "status": "EXECUTED_PASS"}, "UI terminal identity mismatch")
    write_json(args.output / "ui-finished.json", ui_result)
    write_json(args.output / "observation-result.json", {
        **active, "status": "EXECUTED_PASS", "finishedAt": utc(),
        "requiresSeparateXCTestTerminalResult": True,
    })
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception:
        traceback.print_exc()
        sys.exit(1)
