"""Read-only CI evidence for the known widget fixtures in a simulator App Group."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import time


def identity_key(record):
    return json.dumps(record.get("identity", {}).get("installedPackageID"), sort_keys=True)


def capture(arguments):
    lookup = subprocess.run(
        ["xcrun", "simctl", "get_app_container", arguments.device, arguments.bundle_id, arguments.group],
        text=True, capture_output=True, timeout=20, check=True,
    )
    root = (Path(lookup.stdout.strip()) / "ScriptingExtensions").resolve()
    commit = json.loads((root / "commit.json").read_bytes())
    snapshot_hash = commit["snapshotHash"]
    if len(snapshot_hash) != 64 or any(c not in "0123456789abcdef" for c in snapshot_hash):
        raise ValueError("Invalid committed snapshot hash")
    data = (root / "Revisions" / f"{snapshot_hash}.json").read_bytes()
    if hashlib.sha256(data).hexdigest() != snapshot_hash:
        raise ValueError("Committed revision integrity mismatch")
    snapshot = json.loads(data)["snapshot"]
    prefixes = ("Expo Counter Widget", "Expo Visuals Widget", "ScriptWidget Dashboard", "ScriptWidget Actions", "Widget Legacy Regression")
    widgets = [item for item in snapshot.get("widgets", []) if item.get("displayName", "").startswith(prefixes)]
    installed = {identity_key(item) for item in widgets}
    programs = {}
    for widget in widgets:
        payload = widget.get("payload", {})
        descriptor = payload.get("expoDescriptor") or payload.get("scriptDescriptor") or {}
        reference = descriptor.get("layoutRef") or descriptor.get("scriptRef")
        digest = descriptor.get("layoutSHA256") or descriptor.get("scriptSHA256")
        if not reference:
            continue
        file = (root / reference).resolve()
        if not file.is_relative_to(root):
            raise ValueError("Program reference escaped the App Group")
        program_bytes = file.read_bytes()
        if hashlib.sha256(program_bytes).hexdigest() != digest:
            raise ValueError("Widget program integrity mismatch")
        program = json.loads(program_bytes)
        programs[digest] = {key: program.get(key) for key in ("abiVersion", "engine", "upstreamCommit", "sourceSHA256", "compilerSHA256", "families", "actions")}
    return {
        "status": "CAPTURED", "capturedAtUTC": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "snapshotSHA256": snapshot_hash, "widgets": widgets, "programs": programs,
        "instances": [item for item in snapshot.get("widgetInstances", []) if identity_key(item) in installed],
        "states": [item for item in snapshot.get("widgetStates", []) if identity_key(item) in installed],
        "scope": "Known CI fixtures only. Capture is not an interaction PASS assertion.",
    }


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--device", required=True)
    parser.add_argument("--bundle-id", required=True)
    parser.add_argument("--group", required=True)
    parser.add_argument("--output", type=Path, required=True)
    arguments = parser.parse_args()
    try:
        result = capture(arguments)
    except (OSError, ValueError, KeyError, subprocess.SubprocessError) as error:
        result = {"status": "NOT_CAPTURED", "reason": str(error)}
    arguments.output.parent.mkdir(parents=True, exist_ok=True)
    arguments.output.write_text(json.dumps(result, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print(result["status"])
