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


SCHEMA_VERSION = 3
SUPPORTED_SCHEMA_VERSIONS = {1, 2, SCHEMA_VERSION}
IGNORED_DIRECTORY_NAMES = {".build", ".git", ".swiftpm", "build", "xcuserdata"}


def digest(path: Path) -> str:
    hasher = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            hasher.update(chunk)
    return hasher.hexdigest()


def directory_digest(path: Path) -> str:
    entries = []
    with os.scandir(path) as children:
        for child in children:
            if child.is_symlink():
                kind = "symlink"
            elif child.is_dir(follow_symlinks=False):
                kind = "directory"
            elif child.is_file(follow_symlinks=False):
                kind = "file"
            else:
                kind = "other"
            entries.append((child.name, kind))
    encoded = json.dumps(sorted(entries), separators=(",", ":")).encode("utf-8")
    return hashlib.sha256(encoded).hexdigest()


def repository_path(repository: Path, raw_path: str) -> Path:
    repository = repository.resolve()
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
            for current, child_names, file_names in os.walk(path):
                child_names[:] = [
                    name for name in child_names if name not in IGNORED_DIRECTORY_NAMES
                ]
                files.update(
                    Path(current) / name
                    for name in file_names
                    if not suffixes or Path(name).suffix in suffixes
                )
    return sorted(files, key=lambda path: path.relative_to(repository).as_posix())


def input_directories(repository: Path, raw_paths: Iterable[str]) -> list[Path]:
    directories: set[Path] = set()
    for raw_path in raw_paths:
        path = repository_path(repository, raw_path)
        if not path.is_dir():
            continue
        for current, child_names, _ in os.walk(path):
            child_names[:] = [
                name for name in child_names if name not in IGNORED_DIRECTORY_NAMES
            ]
            directories.add(Path(current))
    return sorted(
        directories,
        key=lambda path: path.relative_to(repository).as_posix(),
    )


def capture(
    repository: Path,
    manifest: Path,
    raw_paths: list[str],
    suffixes: set[str],
    head: str,
    directory_roots: list[str] | None = None,
) -> int:
    repository = repository.resolve()
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

    directory_records = []
    all_directory_roots = raw_paths + (directory_roots or [])
    for path in input_directories(repository, all_directory_roots):
        stat = path.stat()
        directory_records.append(
            {
                "path": path.relative_to(repository).as_posix(),
                "entriesSha256": directory_digest(path),
                "mtimeNanoseconds": stat.st_mtime_ns,
            }
        )

    payload = {
        "schemaVersion": SCHEMA_VERSION,
        "repositoryHead": head,
        "files": records,
        "directories": directory_records,
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
    print(
        "XCODE_CACHE_INPUTS capture "
        f"files={len(records)} directories={len(directory_records)} "
        f"head={head or 'unknown'}"
    )
    return 0


def restore(repository: Path, manifest: Path) -> int:
    repository = repository.resolve()
    if not manifest.is_file():
        print("XCODE_CACHE_INPUTS restore status=no-manifest")
        return 0

    payload = json.loads(manifest.read_text(encoding="utf-8"))
    if payload.get("schemaVersion") not in SUPPORTED_SCHEMA_VERSIONS:
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

    restored_directories = 0
    changed_directories = 0
    missing_directories = 0
    invalid_directories = 0
    directory_records = payload.get("directories", [])
    if not isinstance(directory_records, list):
        directory_records = []
        invalid_directories += 1
    valid_directory_records = [
        record for record in directory_records if isinstance(record, dict)
    ]
    invalid_directories += len(directory_records) - len(valid_directory_records)
    ordered_directories = sorted(
        valid_directory_records,
        key=lambda record: str(record.get("path", "")).count("/"),
        reverse=True,
    )
    for record in ordered_directories:
        try:
            path = repository_path(repository, record["path"])
            expected_digest = record["entriesSha256"]
            mtime_nanoseconds = int(record["mtimeNanoseconds"])
        except (KeyError, TypeError, ValueError):
            invalid_directories += 1
            continue

        if not path.is_dir():
            missing_directories += 1
            continue
        if directory_digest(path) != expected_digest:
            changed_directories += 1
            continue
        stat = path.stat()
        os.utime(path, ns=(stat.st_atime_ns, mtime_nanoseconds))
        restored_directories += 1

    print(
        "XCODE_CACHE_INPUTS restore "
        f"status=complete restored={restored} changed={changed} "
        f"missing={missing} invalid={invalid} "
        f"directoriesRestored={restored_directories} "
        f"directoriesChanged={changed_directories} "
        f"directoriesMissing={missing_directories} "
        f"directoriesInvalid={invalid_directories} "
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
    capture_parser.add_argument("--directory-root", action="append", default=[])
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
                arguments.directory_root,
            )
        return restore(repository, manifest)
    except (OSError, ValueError, json.JSONDecodeError) as error:
        print(f"XCODE_CACHE_INPUTS error={error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
