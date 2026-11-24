#!/usr/bin/env python3
"""Retain the original AppIntents compiler inputs without changing build products."""
import argparse
import hashlib
import json
from pathlib import Path

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--derived-data", type=Path, required=True)
parser.add_argument("--output", type=Path, required=True)
args = parser.parse_args()
root = args.derived_data.resolve() / "Build" / "Intermediates.noindex"
args.output.mkdir(parents=True, exist_ok=True)
names = {"HanlinScriptingAppIntents.swiftconstvalues", "HanlinScriptingWidgets.swiftconstvalues",
         "VisionIntent.swiftconstvalues", "ChavrusaSystemIntegrations.swiftconstvalues",
         "HanlinScriptingWidgets.SwiftConstValuesFileList", "HanlinScriptingWidgets.SwiftFileList"}
records = []
total = 0
if root.is_dir():
    for source in sorted(root.rglob("*")):
        if source.name not in names or not source.is_file() or source.is_symlink():
            continue
        relative = source.relative_to(root)
        data = source.read_bytes()
        total += len(data)
        if len(records) >= 32 or total > 4 * 1024 * 1024:
            raise SystemExit("AppIntents metadata retention exceeded its bounded evidence budget")
        destination = args.output / relative
        destination.parent.mkdir(parents=True, exist_ok=True)
        destination.write_bytes(data)
        records.append({"path": relative.as_posix(), "bytes": len(data),
                        "sha256": hashlib.sha256(data).hexdigest()})
receipt = {"schemaVersion": 1, "status": "RETAINED" if records else "NOT_FOUND",
           "scope": "Original compiler metadata only; no extraction or build pass inferred",
           "derivedData": str(args.derived_data.resolve()), "files": records}
(args.output / "receipt.json").write_text(json.dumps(receipt, indent=2) + "\n")
print(json.dumps(receipt))
