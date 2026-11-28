#!/usr/bin/env python3
"""Apply hash-pinned upstream backports to an already verified Node archive."""
import hashlib
import json
from pathlib import Path
import sys


def digest(data):
    return hashlib.sha256(data).hexdigest()


def apply_patches(source_root, lock_path, repository_root=None):
    repository = Path(repository_root or Path(__file__).resolve().parents[2]).resolve()
    source = Path(source_root).resolve(strict=True)
    lock = json.loads(Path(lock_path).read_text(encoding="utf-8"))
    plans = {}
    evidence = []
    for patch in lock["node"].get("sourcePatches", []):
        manifest_path = (repository / patch["path"]).resolve(strict=True)
        if not manifest_path.is_relative_to(repository / "Scripts/Runtime/Patches"):
            raise ValueError("Patch manifest must remain within Scripts/Runtime/Patches")
        data = manifest_path.read_bytes()
        if digest(data) != patch["sha256"]:
            raise ValueError("Node source patch manifest checksum mismatch")
        manifest = json.loads(data)
        if manifest["schemaVersion"] != 1 or manifest["sourceCommit"] != lock["node"]["commit"]:
            raise ValueError("Node source patch does not match the pinned source commit")
        if manifest["upstreamCommit"] != patch["upstreamCommit"]:
            raise ValueError("Node source patch upstream provenance mismatch")
        originals = ([manifest["upstreamPatch"]] if manifest.get("upstreamPatch") else []) + manifest.get("upstreamPatches", [])
        for upstream in originals:
            original = (repository / upstream["path"]).resolve(strict=True)
            if not original.is_relative_to(repository / "Scripts/Runtime/Patches"):
                raise ValueError("Upstream patch evidence escapes the patch directory")
            if digest(original.read_bytes()) != upstream["sha256"]:
                raise ValueError("Upstream patch evidence checksum mismatch")
        for change in manifest["files"]:
            target = (source / change["path"]).resolve(strict=True)
            if not target.is_relative_to(source / "deps/v8"):
                raise ValueError("V8 source patch target escapes its source directory")
            stages = plans.setdefault(target, [])
            if stages and stages[-1]["afterSHA256"] != change["beforeSHA256"]:
                raise ValueError(f"Discontinuous Node source patch chain: {change['path']}")
            stages.append(change)
        evidence.append(patch)
    updates = []
    for target, stages in plans.items():
        before = target.read_bytes()
        checkpoints = [stages[0]["beforeSHA256"]] + [stage["afterSHA256"] for stage in stages]
        matches = [index for index, checkpoint in enumerate(checkpoints) if digest(before) == checkpoint]
        if len(matches) != 1:
            raise ValueError(f"Unexpected Node source preimage or ambiguous patch checkpoint: {target.relative_to(source)}")
        text = before.decode("utf-8")
        for change in stages[matches[0]:]:
            for replacement in change["replacements"]:
                if text.count(replacement["before"]) != 1:
                    raise ValueError(f"Ambiguous Node source patch: {change['path']}")
                text = text.replace(replacement["before"], replacement["after"], 1)
            after = text.encode("utf-8")
            if digest(after) != change["afterSHA256"]:
                raise ValueError(f"Unexpected Node source postimage: {change['path']}")
        if (after := text.encode("utf-8")) != before:
            updates.append((target, after))
    # Validate every preimage and patch hash before modifying the disposable tree.
    for target, data in updates:
        target.write_bytes(data)
    return evidence


if __name__ == "__main__":
    if len(sys.argv) != 3:
        raise SystemExit("Usage: apply-node-source-patches.py SOURCE_ROOT LOCK_FILE")
    result = apply_patches(sys.argv[1], sys.argv[2])
    print(json.dumps({"appliedSourcePatches": result}, sort_keys=True))
