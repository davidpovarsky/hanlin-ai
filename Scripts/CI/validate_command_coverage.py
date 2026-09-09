#!/usr/bin/env python3
"""Deterministic completeness check for Hanlin runtime commands and operations.

Validates that every public/app-exposed canonical command, operation, primitive,
and capability in the authoritative source code has a registered entry in the
versioned coverage manifest (runtime-command-coverage-manifest.json).

Fails with a nonzero exit code if any canonical command is unmapped.
"""

from __future__ import annotations

import json
from pathlib import Path
import re
import sys
from typing import Any

ROOT = Path(__file__).resolve().parents[2]
MANIFEST_PATH = Path(__file__).parent / "runtime-command-coverage-manifest.json"
REPORT_PATH = ROOT / "docs" / "runtime-command-coverage-map.md"

IOS_SYSTEM_RUNNER_PATH = ROOT / "Packages" / "IOSSystemLite" / "Sources" / "IOSSystemLite" / "IOSSystemRunner.swift"
SCRIPT_UI_CONTRACTS_PATH = ROOT / "Packages" / "HanlinPlatform" / "Sources" / "HanlinScriptUI" / "HanlinScriptUIContracts.swift"
SCRIPT_ANALYZER_PATH = ROOT / "Packages" / "HanlinPlatform" / "Sources" / "HanlinScriptCompiler" / "HanlinScriptAnalyzer.swift"


def extract_shell_commands() -> set[str]:
    content = IOS_SYSTEM_RUNNER_PATH.read_text(encoding="utf-8")
    match = re.search(r"public static let linkedCommands: Set<String> = \[\s*([\s\S]*?)\s*\]", content)
    if not match:
        raise ValueError(f"Could not find linkedCommands in {IOS_SYSTEM_RUNNER_PATH}")
    commands = re.findall(r'"([a-z0-9_]+)"', match.group(1))
    return set(commands)


def extract_script_ui_commands() -> set[str]:
    content = SCRIPT_UI_CONTRACTS_PATH.read_text(encoding="utf-8")
    match = re.search(r"public enum HanlinScriptUICommand:[\s\S]*?\{([\s\S]*?)\n\}", content)
    if not match:
        raise ValueError(f"Could not find HanlinScriptUICommand in {SCRIPT_UI_CONTRACTS_PATH}")
    cases = re.findall(r"case\s+([a-zA-Z0-9_]+)", match.group(1))
    return set(cases)


def extract_capabilities() -> set[str]:
    content = SCRIPT_ANALYZER_PATH.read_text(encoding="utf-8")
    match = re.search(r"private static func inferredCapability\(for symbol: String\) -> HanlinCapabilityID\? \{([\s\S]*?)\n\s*\}", content)
    if not match:
        raise ValueError(f"Could not find inferredCapability in {SCRIPT_ANALYZER_PATH}")
    caps = re.findall(r',\s*"([a-z0-9_-]+)"\)', match.group(1))
    return set(caps)


def load_manifest() -> dict[str, Any]:
    if not MANIFEST_PATH.exists():
        raise FileNotFoundError(f"Manifest missing at {MANIFEST_PATH}")
    with open(MANIFEST_PATH, "r", encoding="utf-8") as f:
        return json.load(f)


def validate_coverage(manifest: dict[str, Any] | None = None) -> list[str]:
    if manifest is None:
        manifest = load_manifest()

    errors: list[str] = []
    operations = manifest.get("operations", [])
    ops_by_id = {op["canonical_id"]: op for op in operations}

    required_fields = [
        "canonical_id", "public_name", "authoritative_source", "runtime_bridge_owner",
        "app_exposed", "inputs", "outputs", "state_mutation", "capability_requirement",
        "async_behavior", "cancellation_support"
    ]

    # Validate each operation entry
    for op in operations:
        cid = op.get("canonical_id", "UNKNOWN")
        for f in required_fields:
            if f not in op:
                errors.append(f"Operation {cid} missing required field '{f}'")
        has_test = bool(op.get("existing_acceptance_test") or op.get("new_acceptance_test"))
        has_justification = bool(op.get("justified_exclusion"))
        if not has_test and not has_justification:
            errors.append(f"Operation {cid} has neither test coverage nor justified exclusion")

    # 1. Check all shell commands
    shell_cmds = extract_shell_commands()
    for cmd in sorted(shell_cmds):
        expected_id = f"shell.{cmd}"
        if expected_id not in ops_by_id:
            errors.append(f"Missing shell command coverage entry: {expected_id}")

    # 2. Check all ScriptUI commands
    ui_cmds = extract_script_ui_commands()
    for cmd in sorted(ui_cmds):
        expected_id = f"script_ui.command.{cmd}"
        if expected_id not in ops_by_id:
            errors.append(f"Missing ScriptUI command coverage entry: {expected_id}")

    # 3. Check all capabilities
    capabilities = extract_capabilities()
    for cap in sorted(capabilities):
        expected_id = f"capability.{cap}"
        if expected_id not in ops_by_id:
            errors.append(f"Missing capability coverage entry: {expected_id}")

    return errors


def generate_markdown_report(manifest: dict[str, Any]) -> str:
    lines = [
        "# Hanlin AI — Runtime Commands & Operations Coverage Map",
        "",
        f"**Schema Version:** {manifest.get('schema_version', 1)}  ",
        f"**Last Audited:** {manifest.get('last_audited', '2026-09-09')}  ",
        f"**Total Registered Operations:** {len(manifest.get('operations', []))}  ",
        "",
        "| Canonical ID | Public Name | Owner / Runtime | Capability | State Mutation | Existing Acceptance | New Acceptance |",
        "|---|---|---|---|---|---|---|"
    ]

    for op in sorted(manifest.get("operations", []), key=lambda x: x["canonical_id"]):
        cid = op["canonical_id"]
        name = op["public_name"]
        owner = op["runtime_bridge_owner"]
        cap = op["capability_requirement"] or "None"
        mut = "Yes" if op["state_mutation"] else "No"
        exist = op.get("existing_acceptance_test") or "-"
        new = op.get("new_acceptance_test") or "-"
        lines.append(f"| `{cid}` | {name} | {owner} | {cap} | {mut} | {exist} | {new} |")

    lines.append("")
    return "\n".join(lines)


def main() -> int:
    try:
        manifest = load_manifest()
        errors = validate_coverage(manifest)
        if errors:
            print("ERROR: Runtime command coverage completeness check FAILED:", file=sys.stderr)
            for err in errors:
                print(f"  - {err}", file=sys.stderr)
            return 1

        REPORT_PATH.parent.mkdir(parents=True, exist_ok=True)
        report_content = generate_markdown_report(manifest)
        REPORT_PATH.write_text(report_content, encoding="utf-8")
        print(f"Coverage check passed successfully! Audited {len(manifest['operations'])} operations.")
        print(f"Generated report at {REPORT_PATH}")
        return 0
    except Exception as e:
        print(f"FATAL: {e}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
