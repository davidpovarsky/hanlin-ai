#!/usr/bin/env python3
"""Preserve build-input mtimes across ephemeral CI checkouts.

Xcode's build database records input metadata. A fresh checkout gives unchanged
repository files new mtimes, which can invalidate otherwise reusable DerivedData.
This helper restores a prior mtime only after verifying the file's SHA-256 digest.
Changed or missing files are never normalized.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import sys
import tempfile
from typing import Iterable


SCHEMA_VERSION = 1


def digest(path: Path) -> str:
    hasher = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            hasher.update(chunk)
    return hasher.hexdigest()


def repository_path(repository: Path, raw_path: str) -> Path:
    candidate = (repository / raw_path).resolve()
    try:
        candidate.relative_to(repository)
    except ValueError as error:
        raise ValueError(f"build input escapes repository: {raw_path}") from error
    return candidate


def input_files(
    repository: Path,
    raw_paths: Iterable[str],
    suffixes: set[str],
) -> list[Path]:
    files: set[Path] = set()
    for raw_path in raw_paths:
        path = repository_path(repository, raw_path)
        if path.is_file():
            files.add(path)
        elif path.is_dir():
            files.update(
                child
                for child in path.rglob("*")
                if child.is_file() and (not suffixes or child.suffix in suffixes)
            )
    return sorted(files, key=lambda path: path.relative_to(repository).as_posix())


def capture(
    repository: Path,
    manifest: Path,
    raw_paths: list[str],
    suffixes: set[str],
    head: str,
) -> int:
    records = []
    for path in input_files(repository, raw_paths, suffixes):
        stat = path.stat()
        records.append(
            {
                "path": path.relative_to(repository).as_posix(),
                "sha256": digest(path),
                "size": stat.st_size,
                "mtimeNanoseconds": stat.st_mtime_ns,
            }
        )

    payload = {
        "schemaVersion": SCHEMA_VERSION,
        "repositoryHead": head,
        "files": records,
    }
    manifest.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(
        mode="w",
        encoding="utf-8",
        dir=manifest.parent,
        prefix=f".{manifest.name}.",
        suffix=".tmp",
        delete=False,
    ) as stream:
        json.dump(payload, stream, indent=2, sort_keys=True)
        stream.write("\n")
        temporary = Path(stream.name)
    temporary.replace(manifest)
    print(f"XCODE_CACHE_INPUTS capture files={len(records)} head={head or 'unknown'}")
    return 0


def restore(repository: Path, manifest: Path) -> int:
    if not manifest.is_file():
        print("XCODE_CACHE_INPUTS restore status=no-manifest")
        return 0

    payload = json.loads(manifest.read_text(encoding="utf-8"))
    if payload.get("schemaVersion") != SCHEMA_VERSION:
        print("XCODE_CACHE_INPUTS restore status=unsupported-schema")
        return 0

    restored = 0
    changed = 0
    missing = 0
    invalid = 0
    for record in payload.get("files", []):
        try:
            path = repository_path(repository, record["path"])
            expected_digest = record["sha256"]
            expected_size = int(record["size"])
            mtime_nanoseconds = int(record["mtimeNanoseconds"])
        except (KeyError, TypeError, ValueError):
            invalid += 1
            continue

        if not path.is_file():
            missing += 1
            continue
        stat = path.stat()
        if stat.st_size != expected_size or digest(path) != expected_digest:
            changed += 1
            continue
        os.utime(path, ns=(stat.st_atime_ns, mtime_nanoseconds))
        restored += 1

    print(
        "XCODE_CACHE_INPUTS restore "
        f"status=complete restored={restored} changed={changed} "
        f"missing={missing} invalid={invalid} "
        f"head={payload.get('repositoryHead') or 'unknown'}"
    )
    return 0


def parser() -> argparse.ArgumentParser:
    result = argparse.ArgumentParser()
    result.add_argument("--repository", type=Path, default=Path.cwd())
    subparsers = result.add_subparsers(dest="command", required=True)

    capture_parser = subparsers.add_parser("capture")
    capture_parser.add_argument("--manifest", type=Path, required=True)
    capture_parser.add_argument("--head", default="")
    capture_parser.add_argument("--suffix", action="append", default=[])
    capture_parser.add_argument("paths", nargs="+")

    restore_parser = subparsers.add_parser("restore")
    restore_parser.add_argument("--manifest", type=Path, required=True)
    return result


def main() -> int:
    arguments = parser().parse_args()
    repository = arguments.repository.resolve()
    manifest = arguments.manifest.resolve()
    try:
        if arguments.command == "capture":
            return capture(
                repository,
                manifest,
                arguments.paths,
                set(arguments.suffix),
                arguments.head,
            )
        return restore(repository, manifest)
    except (OSError, ValueError, json.JSONDecodeError) as error:
        print(f"XCODE_CACHE_INPUTS error={error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
