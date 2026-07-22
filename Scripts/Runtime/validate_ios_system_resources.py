#!/usr/bin/env python3
"""Validate Hanlin's restricted ios_system command resources."""

from __future__ import annotations

import argparse
import hashlib
import json
import plistlib
from pathlib import Path
from typing import Any


EXPECTED_ENTRIES: dict[str, list[str]] = {
    "awk": ["awk.framework/awk", "awk_main", "dhiflM:N:nsuw", "file"],
    "cat": ["text.framework/text", "cat_main", "benstuv", "file"],
    "cp": ["files.framework/files", "cp_main", "cHLPRXafinprv", "file"],
    "curl": ["curl_ios.framework/curl_ios", "curl_main", "2346aAbBcCdDeEfgGhHiIjJkKlLmMnNoOpPqQrRsStTuUvVwxXYyz#", "file"],
    "grep": ["text.framework/text", "grep_main", "0123456789A:B:C:D:EFGHIJMLOPSRUVZabcd:e:f:hilm:nopqrsuvwxXy", "file"],
    "head": ["text.framework/text", "head_main", "n:c:", "file"],
    "ln": ["files.framework/files", "ln_main", "Ffhinsv", "file"],
    "ls": ["files.framework/files", "ls_main", "1@ABCFGHLOPRSTUWabcdefghiklmnopqrstuvwx", "file"],
    "mkdir": ["files.framework/files", "mkdir_main", "m:pv", "directory"],
    "mv": ["files.framework/files", "mv_main", "finv", "file"],
    "readlink": ["files.framework/files", "stat_main", "n", "file"],
    "rm": ["files.framework/files", "rm_main", "dfiPRrvW", "file"],
    "rmdir": ["files.framework/files", "rmdir_main", "p", "directory"],
    "sed": ["text.framework/text", "sed_main", "Eae:f:i:ln", "file"],
    "sort": ["text.framework/text", "sort_main", "bcCdfghik:Mmno:RrsS:t:T:uVz", "file"],
    "stat": ["files.framework/files", "stat_main", "f:FlLnqrst:x", "file"],
    "tail": ["text.framework/text", "tail_main", "Fb:c:fn:qr", "file"],
    "tar": ["tar.framework/tar", "tar_main", "Bb:C:cf:HhI:JjkLlmnOoPpqrSs:T:tUuvW:wX:xyZz", "file"],
    "touch": ["files.framework/files", "touch_main", "A:acfhmr:t:", "file"],
    "tr": ["text.framework/text", "tr_main", "Ccdsu", "no"],
    "uniq": ["text.framework/text", "uniq_main", "cdif:s:u", "file"],
    "unlink": ["files.framework/files", "rm_main", "", "file"],
    "wc": ["text.framework/text", "wc_main", "dhiflM:N:nsuw", "file"],
}

RESOURCE_DIRECTORY = Path("Packages/IOSSystemLite/Sources/IOSSystemLite/Resources")
COMMAND_DICTIONARY = RESOURCE_DIRECTORY / "commandDictionary.plist"
EXTRA_DICTIONARY = RESOURCE_DIRECTORY / "extraCommandsDictionary.plist"


class ResourceValidationError(RuntimeError):
    pass


def read_dictionary(path: Path) -> tuple[dict[str, Any], bytes]:
    if not path.is_file():
        raise ResourceValidationError(f"Required plist is missing: {path}")
    raw = path.read_bytes()
    try:
        value = plistlib.loads(raw)
    except Exception as error:  # plistlib exposes several parse error types.
        raise ResourceValidationError(f"Malformed plist {path}: {error}") from error
    if not isinstance(value, dict):
        raise ResourceValidationError(f"Plist root must be a dictionary: {path}")
    return value, raw


def validate_command_dictionary(path: Path) -> tuple[bytes, dict[str, Any]]:
    value, raw = read_dictionary(path)
    actual_keys = set(value)
    expected_keys = set(EXPECTED_ENTRIES)
    missing = sorted(expected_keys - actual_keys)
    unexpected = sorted(actual_keys - expected_keys)
    if missing or unexpected:
        raise ResourceValidationError(
            f"Command catalog mismatch for {path}: missing={missing}, unexpected={unexpected}"
        )
    for command, expected in EXPECTED_ENTRIES.items():
        entry = value[command]
        if not isinstance(entry, list) or len(entry) != 4 or not all(isinstance(item, str) for item in entry):
            raise ResourceValidationError(f"Command {command} must contain exactly four strings")
        if entry != expected:
            raise ResourceValidationError(
                f"Command metadata mismatch for {command}: expected={expected!r}, actual={entry!r}"
            )
    return raw, value


def validate_empty_extra_dictionary(path: Path) -> bytes:
    value, raw = read_dictionary(path)
    if value:
        raise ResourceValidationError(f"Extra command dictionary must be empty: {path}")
    return raw


def validate_source_resources(repository_root: Path) -> dict[str, Any]:
    command_path = repository_root / COMMAND_DICTIONARY
    extra_path = repository_root / EXTRA_DICTIONARY
    command_raw, _ = validate_command_dictionary(command_path)
    extra_raw = validate_empty_extra_dictionary(extra_path)

    package_text = (repository_root / "Packages/IOSSystemLite/Package.swift").read_text(encoding="utf-8")
    if 'resources: [.process("Resources")]' not in package_text:
        raise ResourceValidationError("IOSSystemLite must process its canonical Resources directory")

    project_text = (repository_root / "AI_HLY.xcodeproj/project.pbxproj").read_text(encoding="utf-8")
    for relative_path in (COMMAND_DICTIONARY, EXTRA_DICTIONARY):
        normalized = relative_path.as_posix()
        if normalized not in project_text:
            raise ResourceValidationError(f"Xcode project does not reference canonical resource: {normalized}")
    for resource_name in ("commandDictionary.plist in Resources", "extraCommandsDictionary.plist in Resources"):
        if project_text.count(resource_name) < 2:
            raise ResourceValidationError(f"Xcode Copy Bundle Resources entry is missing: {resource_name}")

    if (repository_root / RESOURCE_DIRECTORY / "RuntimeCommands.plist").exists():
        raise ResourceValidationError("Legacy RuntimeCommands.plist must not coexist with the canonical dictionary")

    return make_result(command_raw, extra_raw)


def validate_app_resources(app_path: Path, canonical_command: Path, canonical_extra: Path) -> dict[str, Any]:
    canonical_command_raw, _ = validate_command_dictionary(canonical_command)
    canonical_extra_raw = validate_empty_extra_dictionary(canonical_extra)
    app_command = app_path / "commandDictionary.plist"
    app_extra = app_path / "extraCommandsDictionary.plist"
    app_command_raw, _ = validate_command_dictionary(app_command)
    app_extra_raw = validate_empty_extra_dictionary(app_extra)
    if app_command_raw != canonical_command_raw:
        raise ResourceValidationError("Built app commandDictionary.plist differs from the canonical source bytes")
    if app_extra_raw != canonical_extra_raw:
        raise ResourceValidationError("Built app extraCommandsDictionary.plist differs from the canonical source bytes")
    return make_result(app_command_raw, app_extra_raw)


def make_result(command_raw: bytes, extra_raw: bytes) -> dict[str, Any]:
    return {
        "approvedCommandCount": len(EXPECTED_ENTRIES),
        "approvedCommands": sorted(EXPECTED_ENTRIES),
        "commandDictionarySHA256": hashlib.sha256(command_raw).hexdigest(),
        "extraDictionarySHA256": hashlib.sha256(extra_raw).hexdigest(),
        "unexpectedCommands": [],
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repository-root", type=Path, default=Path.cwd())
    parser.add_argument("--app", type=Path)
    parser.add_argument("--json-output", type=Path)
    arguments = parser.parse_args()

    root = arguments.repository_root.resolve()
    result = validate_source_resources(root)
    if arguments.app:
        result = validate_app_resources(
            arguments.app.resolve(),
            root / COMMAND_DICTIONARY,
            root / EXTRA_DICTIONARY,
        )
        result["appPath"] = str(arguments.app.resolve())
    rendered = json.dumps(result, indent=2, sort_keys=True) + "\n"
    if arguments.json_output:
        arguments.json_output.write_text(rendered, encoding="utf-8")
    print(rendered, end="")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
