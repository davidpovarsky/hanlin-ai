#!/usr/bin/env python3
"""Embed actual source/pin identity, without credentials or machine paths."""
import hashlib
import json
import pathlib
import re
import subprocess
from urllib.parse import urlsplit


def retain_safe_lock(lock: pathlib.Path, destination: pathlib.Path) -> None:
    """Retain exact resolver bytes only when they contain public, credential-free URLs."""
    raw = lock.read_bytes()
    for pin in json.loads(raw)["pins"]:
        url = urlsplit(pin["location"])
        if (url.scheme != "https" or url.hostname != "github.com" or url.username is not None
                or url.password is not None or url.query or url.fragment):
            raise ValueError("Raw package resolution contains a non-public location; retain redacted provenance only")
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_bytes(raw)


def canonical_repository(value: str) -> str:
    url = urlsplit(value)
    return (str(url.hostname) + url.path.removesuffix(".git").rstrip("/")).lower()


def requested_revision_pins(root: pathlib.Path) -> dict[str, str]:
    project = root / "AI_HLY.xcodeproj/project.pbxproj"
    if not project.exists():
        return {}
    text = project.read_text(encoding="utf8")
    requested = {}
    for url, body in re.findall(r'repositoryURL\s*=\s*"([^"]+)";\s*requirement\s*=\s*\{([^}]+)\}', text):
        if not re.search(r'kind\s*=\s*revision\s*;', body):
            continue
        match = re.search(r'revision\s*=\s*"?([a-fA-F0-9]{40})"?\s*;', body)
        if not match:
            raise ValueError("Invalid requested package revision")
        requested[canonical_repository(url)] = match.group(1).lower()
    return requested


def write_provenance(root: pathlib.Path) -> pathlib.Path:
    lock = root / "AI_HLY.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"
    output = root / "AI_HLY/Downstream/AgentDiagnostics/HanlinDiagnosticsBuildProvenance.json"
    raw = lock.read_bytes()
    pins = json.loads(raw)["pins"]
    requested = requested_revision_pins(root)
    resolved = {canonical_repository(p["location"]): p["state"].get("revision", "").lower() for p in pins}
    if any(resolved.get(repository) != revision for repository, revision in requested.items()):
        raise ValueError("Package.resolved does not match requested revisions; resolve Xcode packages before generating provenance")
    # Locations may be authenticated remote URLs. Only identities and exact
    # resolved states belong in the distributable provenance resource.
    commit = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=root, text=True).strip()
    modified = subprocess.check_output(["git", "diff", "--name-only", "HEAD", "--", ".", ":(exclude)" + str(output.relative_to(root)).replace("\\", "/")], cwd=root, text=True).splitlines()
    value = {"schemaVersion": 1, "sourceCommit": commit, "trackedWorkspaceModified": bool(modified),
             "packageResolvedSHA256": hashlib.sha256(raw).hexdigest(),
             "requestedRevisionPins": [{"identity": repository.rsplit("/", 1)[-1], "revision": revision} for repository, revision in sorted(requested.items())],
             "dependencyPins": [{"identity": p["identity"], "state": p["state"]} for p in pins]}
    data = (json.dumps(value, indent=2, sort_keys=True) + "\n").encode("utf8")
    if not output.exists() or output.read_bytes() != data:
        output.write_bytes(data)
    return output


if __name__ == "__main__":
    import argparse
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--retain-safe-lock", type=pathlib.Path)
    args = parser.parse_args()
    root = pathlib.Path(__file__).resolve().parents[2]
    write_provenance(root)
    if args.retain_safe_lock:
        retain_safe_lock(root / "AI_HLY.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved", args.retain_safe_lock)
