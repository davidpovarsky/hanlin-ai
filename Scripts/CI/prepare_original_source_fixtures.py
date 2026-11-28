#!/usr/bin/env python3
"""Deliver the current checkout's original source fixtures into the unit-test product."""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path, PurePosixPath
import shutil


BUNDLE_NAME = "OriginalSourceFixtures.bundle"
INPUT_LIST = Path(__file__).with_name("original-source-fixtures.xcfilelist")
PRODUCER_PATH = "Scripts/CI/prepare_original_source_fixtures.py"


def input_paths(input_list: Path = INPUT_LIST) -> tuple[str, ...]:
    paths = []
    for line in input_list.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        prefix = "$(SRCROOT)/"
        if not line.startswith(prefix):
            raise ValueError("Source fixture input must be relative to SRCROOT")
        relative = line[len(prefix):]
        path = PurePosixPath(relative)
        if (not relative or path.is_absolute() or ".." in path.parts
                or "\\" in relative or path.as_posix() != relative
                or relative in paths):
            raise ValueError("Invalid or duplicate source fixture input: " + relative)
        paths.append(relative)
    if not paths:
        raise ValueError("The declared source fixture input list is empty")
    return tuple(paths)


def prepare(source_root: Path, output: Path, input_list: Path = INPUT_LIST) -> dict:
    source_root = source_root.resolve(strict=True)
    if output.name != BUNDLE_NAME or output.is_symlink():
        raise ValueError("Output must be the owned, nonsymlink source fixture bundle")
    output = output.resolve()
    if source_root == output or source_root.is_relative_to(output):
        raise ValueError("Output cannot replace the checkout")
    if output.exists() and not output.is_dir():
        raise ValueError("Output bundle is not a directory")

    # Read every declared current source before changing an earlier build output.
    # The immutable expectation is copied verbatim, never regenerated from these bytes.
    contents = {}
    for relative in input_paths(input_list):
        source = source_root
        for part in PurePosixPath(relative).parts:
            source = source / part
            if source.is_symlink():
                raise ValueError("Source fixture symlink is not allowed: " + relative)
        if source.is_relative_to(output) or not source.is_file():
            raise ValueError("Missing or overlapping original source fixture: " + relative)
        contents[relative] = source.read_bytes()

    manifest = {
        "schemaVersion": 1,
        "producer": PRODUCER_PATH,
        "producerSHA256": hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
        "inputListSHA256": hashlib.sha256(input_list.read_bytes()).hexdigest(),
        "files": [
            {"path": path, "bytes": len(data), "sha256": hashlib.sha256(data).hexdigest()}
            for path, data in contents.items()
        ],
    }
    if output.exists():
        shutil.rmtree(output)
    output.mkdir(parents=True)
    for relative, data in contents.items():
        destination = output / relative
        destination.parent.mkdir(parents=True, exist_ok=True)
        destination.write_bytes(data)
    (output / "manifest.json").write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    return manifest


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-root", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    manifest = prepare(args.source_root, args.output)
    print(json.dumps({"status": "COPIED_CURRENT_SOURCE_BYTES", "files": len(manifest["files"])}))


if __name__ == "__main__":
    main()
