#!/usr/bin/env python3
"""Verify original copied SDK resources in the actual built SwiftPM resource bundle."""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import sys


def digest(path: Path) -> str:
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def bundle_inventory(bundle: Path) -> dict:
    """Bind the complete packaged layout, including processed resources and safe links."""
    base = bundle.resolve()
    result = {}
    for path in sorted(bundle.rglob("*")):
        relative = str(path.relative_to(bundle))
        try:
            resolved = path.resolve(strict=True)
        except (OSError, RuntimeError) as error:
            raise ValueError(f"Invalid SDK resource entry {relative}: {error}") from error
        if not resolved.is_relative_to(base):
            raise ValueError(f"SDK resource escapes its bundle: {relative}")
        if path.is_symlink():
            result[relative] = {"kind": "symlink", "target": str(resolved.relative_to(base))}
        elif path.is_dir():
            result[relative] = {"kind": "directory"}
        elif path.is_file():
            result[relative] = {"kind": "file", "bytes": path.stat().st_size, "sha256": digest(path)}
        else:
            raise ValueError(f"Unsupported SDK resource entry: {relative}")
    return result


def module_bundle(app: Path, module: str, *, copies: list | None = None) -> Path:
    matches = sorted(
        (path for path in app.rglob("*.bundle")
         if path.is_dir() and (path.name == module + ".bundle"
                              or path.name.endswith("_" + module + ".bundle"))),
        key=lambda path: (path.parent != app, str(path.relative_to(app))),
    )
    if not matches or len({path.name for path in matches}) != 1:
        raise ValueError(f"Expected one {module} SDK resource bundle identity, found {len(matches)}: "
                         + ", ".join(str(path.relative_to(app)) for path in matches))
    inventories = []
    for bundle in matches:
        if not bundle.resolve().is_relative_to(app.resolve()):
            raise ValueError("SDK resource bundle escapes the built application")
        inventory = bundle_inventory(bundle)
        inventories.append(inventory)
        if copies is not None:
            encoded = json.dumps(inventory, sort_keys=True, separators=(",", ":")).encode()
            copies.append({"path": str(bundle.relative_to(app)),
                           "inventorySHA256": hashlib.sha256(encoded).hexdigest(),
                           "entries": len(inventory),
                           "files": sum(row["kind"] == "file" for row in inventory.values())})
    primary = inventories[0]
    for bundle, inventory in zip(matches[1:], inventories[1:]):
        if inventory != primary:
            difference = next(name for name in sorted(primary.keys() | inventory.keys())
                              if primary.get(name) != inventory.get(name))
            raise ValueError(
                f"Conflicting {module} SDK resource bundle copies: "
                f"{matches[0].relative_to(app)} and {bundle.relative_to(app)} differ at {difference}: "
                f"{json.dumps(primary.get(difference), sort_keys=True)} != "
                f"{json.dumps(inventory.get(difference), sort_keys=True)}")
    # SwiftPM can copy one resource product into both the app and its product
    # framework. Accept only identical complete copies; original source checks
    # below still run against the selected bundle and cannot use loose app files.
    return matches[0]


def validate(root: Path, app: Path, module: str, manifest: dict) -> dict:
    if not app.is_dir():
        raise ValueError(f"Built application does not exist: {app}")
    targets = [target for target in manifest["targets"] if target["name"] == module]
    if len(targets) != 1:
        raise ValueError(f"Expected one canonical target for {module}")
    target = targets[0]
    source_root = root / target["path"]
    bundle_copies = []
    bundle = module_bundle(app, module, copies=bundle_copies)
    copied = [item for item in target.get("resources", []) if "copy" in item["rule"]]
    if not copied:
        raise ValueError(f"{module} has no original copied resources to validate")
    checked = []
    errors = []
    seen = set()
    for item in copied:
        source = source_root / item["path"]
        if not source.resolve().is_relative_to(root.resolve()) or not source.exists():
            raise ValueError(f"Missing or external canonical resource: {source}")
        sources = sorted(path for path in source.rglob("*") if path.is_file()) if source.is_dir() else [source]
        if not sources:
            raise ValueError(f"Empty canonical resource directory: {source}")
        for path in sources:
            relative = Path(source.name) / path.relative_to(source) if source.is_dir() else Path(source.name)
            if str(relative) in seen:
                raise ValueError(f"Ambiguous copied resource destination: {relative}")
            seen.add(str(relative))
            packaged = bundle / relative
            if not packaged.resolve().is_relative_to(bundle.resolve()) or not packaged.is_file():
                errors.append({"resource": str(relative), "reason": "missing from original SDK bundle"})
                continue
            source_hash, packaged_hash = digest(path), digest(packaged)
            checked.append({"resource": str(relative), "source": str(path.relative_to(root)),
                            "sha256": packaged_hash, "bytes": packaged.stat().st_size})
            if source_hash != packaged_hash:
                errors.append({"resource": str(relative), "reason": "packaged bytes differ from canonical source",
                               "sourceSHA256": source_hash, "packagedSHA256": packaged_hash})
    return {"status": "FAIL" if errors else "PASS", "module": module,
            "bundle": str(bundle.relative_to(app)), "bundleCopies": bundle_copies,
            "copiedResourceFiles": len(seen),
            "checked": checked, "errors": errors,
            "processedResources": [item["path"] for item in target.get("resources", []) if "process" in item["rule"]]}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repository-root", type=Path, default=Path(__file__).resolve().parents[2])
    parser.add_argument("--app", type=Path, required=True)
    parser.add_argument("--module", default="AI_Hanlin")
    parser.add_argument("--json-output", type=Path)
    args = parser.parse_args()
    try:
        root, app = args.repository_root.resolve(), args.app.resolve()
        raw = subprocess.check_output(["swift", "package", "--package-path", str(root), "dump-package"], text=True)
        result = validate(root, app, args.module, json.loads(raw))
    except (OSError, ValueError, KeyError, subprocess.SubprocessError) as error:
        result = {"status": "FAIL", "module": args.module, "errors": [{"reason": str(error)}]}
    encoded = json.dumps(result, indent=2, sort_keys=True) + "\n"
    if args.json_output:
        args.json_output.parent.mkdir(parents=True, exist_ok=True)
        args.json_output.write_text(encoded)
    print(encoded, end="")
    return 0 if result["status"] == "PASS" else 1


if __name__ == "__main__":
    sys.exit(main())
