#!/usr/bin/env python3
"""Embed actual source/pin identity, without credentials or machine paths."""
import hashlib
import json
import pathlib
import subprocess


def write_provenance(root: pathlib.Path) -> pathlib.Path:
    lock = root / "AI_HLY.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"
    output = root / "AI_HLY/Downstream/AgentDiagnostics/HanlinDiagnosticsBuildProvenance.json"
    raw = lock.read_bytes()
    pins = json.loads(raw)["pins"]
    # Locations may be authenticated remote URLs. Only identities and exact
    # resolved states belong in the distributable provenance resource.
    commit = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=root, text=True).strip()
    modified = subprocess.check_output(["git", "diff", "--name-only", "HEAD", "--", ".", ":(exclude)" + str(output.relative_to(root)).replace("\\", "/")], cwd=root, text=True).splitlines()
    value = {"schemaVersion": 1, "sourceCommit": commit, "trackedWorkspaceModified": bool(modified),
             "packageResolvedSHA256": hashlib.sha256(raw).hexdigest(),
             "dependencyPins": [{"identity": p["identity"], "state": p["state"]} for p in pins]}
    data = (json.dumps(value, indent=2, sort_keys=True) + "\n").encode("utf8")
    if not output.exists() or output.read_bytes() != data:
        output.write_bytes(data)
    return output


if __name__ == "__main__":
    write_provenance(pathlib.Path(__file__).resolve().parents[2])
