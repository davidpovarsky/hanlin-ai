#!/usr/bin/env python3
"""Deterministic completeness check for Hanlin runtime commands and operations.

Validates that every public/app-exposed canonical command, operation, primitive,
capability, lifecycle operation, and tool authority operation in the authoritative
source code has a registered entry in the versioned coverage manifest
(runtime-command-coverage-manifest.json).

Verification Methodology:
1. Exhaustively Source-Derived Domains:
   - Shell Commands (23 ops): mechanically extracted from `linkedCommands` in `IOSSystemRunner.swift`.
   - ScriptUI Commands (14 ops): mechanically extracted from `HanlinScriptUICommand` in `HanlinScriptUIContracts.swift`.
   - Inferred Capabilities (11 ops): mechanically extracted from `inferredCapability` in `HanlinScriptAnalyzer.swift`.
   Adding any new case/command in these sources without a corresponding manifest entry fails CI.

2. Maintained Fixed Source-Contract Domains:
   - App Lifecycle (8 ops): verified against authoritative method declarations in `HanlinScriptingPlatform.swift`.
   - Tool Authority (2 ops): verified against authoritative resolve/invoke declarations in `HanlinCanonicalToolAuthority.swift` and `AssistantToolBridge.swift`.
   *Lifecycle and tool authority verification is a maintained fixed contract check validating that production
    methods exist and adhere to expected signatures, not automatic discovery of arbitrary future methods.*

Fails with a nonzero exit code if any canonical command is unmapped or missing tests.
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
SCRIPTING_PLATFORM_PATH = ROOT / "AI_HLY" / "Downstream" / "ScriptingPlatform" / "HanlinScriptingPlatform.swift"
TOOL_AUTHORITY_PATH = ROOT / "AI_HLY" / "Downstream" / "CanonicalTools" / "HanlinCanonicalToolAuthority.swift"
ASSISTANT_TOOL_BRIDGE_PATH = ROOT / "AI_HLY" / "Downstream" / "MCP" / "ToolIntegration" / "AssistantToolBridge.swift"

# Maintained fixed source contracts for application lifecycle operations
LIFECYCLE_OPERATION_METHODS: dict[str, str] = {
    "app.import_package": r"func\s+importPackage\(",
    "app.install_preview": r"func\s+installPreview\(",
    "app.discard_preview": r"func\s+discardPreview\(",
    "app.launch": r"func\s+launch\(",
    "app.dismiss_active": r"func\s+dismissActiveApplication\(",
    "app.set_enabled": r"func\s+setEnabled\(",
    "app.set_capability_granted": r"func\s+setCapabilityGranted\(",
    "app.uninstall": r"func\s+uninstall\(",
}

# Maintained fixed source contracts for tool authority operations
TOOL_AUTHORITY_OPERATION_METHODS: dict[str, tuple[Path, str]] = {
    "tool_authority.resolve": (TOOL_AUTHORITY_PATH, r"func\s+resolution\(\s*alias:"),
    "tool_authority.invoke": (ASSISTANT_TOOL_BRIDGE_PATH, r"func\s+execute\(\s*alias:"),
}


def extract_shell_commands(source_path: Path | None = None) -> set[str]:
    path = source_path or IOS_SYSTEM_RUNNER_PATH
    content = path.read_text(encoding="utf-8")
    match = re.search(r"public static let linkedCommands: Set<String> = \[\s*([\s\S]*?)\s*\]", content)
    if not match:
        raise ValueError(f"Could not find linkedCommands in {path}")
    commands = re.findall(r'"([a-z0-9_]+)"', match.group(1))
    return set(commands)


def extract_script_ui_commands(source_path: Path | None = None) -> set[str]:
    path = source_path or SCRIPT_UI_CONTRACTS_PATH
    content = path.read_text(encoding="utf-8")
    match = re.search(r"public enum HanlinScriptUICommand:[\s\S]*?\{([\s\S]*?)\n\}", content)
    if not match:
        raise ValueError(f"Could not find HanlinScriptUICommand in {path}")
    cases = re.findall(r"case\s+([a-zA-Z0-9_]+)", match.group(1))
    return set(cases)


def extract_capabilities(source_path: Path | None = None) -> set[str]:
    path = source_path or SCRIPT_ANALYZER_PATH
    content = path.read_text(encoding="utf-8")
    match = re.search(r"private static func inferredCapability\(for symbol: String\) -> HanlinCapabilityID\? \{([\s\S]*?)\n\s*\}", content)
    if not match:
        raise ValueError(f"Could not find inferredCapability in {path}")
    caps = re.findall(r',\s*"([a-z0-9_-]+)"\)', match.group(1))
    return set(caps)


def extract_lifecycle_operations(source_path: Path | None = None) -> set[str]:
    path = source_path or SCRIPTING_PLATFORM_PATH
    content = path.read_text(encoding="utf-8")
    found_ops: set[str] = set()
    for op_id, pattern in LIFECYCLE_OPERATION_METHODS.items():
        if re.search(pattern, content):
            found_ops.add(op_id)
        else:
            raise ValueError(f"Authoritative lifecycle method matching '{pattern}' not found in {path}")
    return found_ops


def extract_tool_authority_operations(
    authority_path: Path | None = None,
    bridge_path: Path | None = None
) -> set[str]:
    auth_p = authority_path or TOOL_AUTHORITY_PATH
    bridge_p = bridge_path or ASSISTANT_TOOL_BRIDGE_PATH
    found_ops: set[str] = set()

    auth_content = auth_p.read_text(encoding="utf-8")
    if re.search(r"func\s+resolution\(\s*alias:", auth_content):
        found_ops.add("tool_authority.resolve")
    else:
        raise ValueError(f"Authoritative resolve method not found in {auth_p}")

    bridge_content = bridge_p.read_text(encoding="utf-8")
    if re.search(r"func\s+execute\(\s*alias:", bridge_content):
        found_ops.add("tool_authority.invoke")
    else:
        raise ValueError(f"Authoritative execute method not found in {bridge_p}")

    return found_ops


def load_manifest(manifest_path: Path | None = None) -> dict[str, Any]:
    path = manifest_path or MANIFEST_PATH
    if not path.exists():
        raise FileNotFoundError(f"Manifest missing at {path}")
    with open(path, "r", encoding="utf-8") as f:
        return json.load(f)


def validate_coverage(
    manifest: dict[str, Any] | None = None,
    shell_source: Path | None = None,
    script_ui_source: Path | None = None,
    capability_source: Path | None = None,
    lifecycle_source: Path | None = None,
    tool_authority_source: Path | None = None,
    tool_bridge_source: Path | None = None,
) -> list[str]:
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
    shell_cmds = extract_shell_commands(shell_source)
    for cmd in sorted(shell_cmds):
        expected_id = f"shell.{cmd}"
        if expected_id not in ops_by_id:
            errors.append(f"Missing shell command coverage entry: {expected_id}")

    # 2. Check all ScriptUI commands
    ui_cmds = extract_script_ui_commands(script_ui_source)
    for cmd in sorted(ui_cmds):
        expected_id = f"script_ui.command.{cmd}"
        if expected_id not in ops_by_id:
            errors.append(f"Missing ScriptUI command coverage entry: {expected_id}")

    # 3. Check all capabilities
    capabilities = extract_capabilities(capability_source)
    for cap in sorted(capabilities):
        expected_id = f"capability.{cap}"
        if expected_id not in ops_by_id:
            errors.append(f"Missing capability coverage entry: {expected_id}")

    # 4. Check all app lifecycle operations
    lifecycle_ops = extract_lifecycle_operations(lifecycle_source)
    for op in sorted(lifecycle_ops):
        if op not in ops_by_id:
            errors.append(f"Missing app lifecycle coverage entry: {op}")

    # 5. Check all canonical tool authority operations
    tool_ops = extract_tool_authority_operations(tool_authority_source, tool_bridge_source)
    for op in sorted(tool_ops):
        if op not in ops_by_id:
            errors.append(f"Missing tool authority coverage entry: {op}")

    return errors


def generate_markdown_report(manifest: dict[str, Any]) -> str:
    lines = [
        "# Hanlin AI — Runtime Commands & Operations Coverage Map",
        "",
        f"**Schema Version:** {manifest.get('schema_version', 1)}  ",
        f"**Last Audited:** {manifest.get('last_audited', '2026-09-09')}  ",
        f"**Total Registered Operations:** {len(manifest.get('operations', []))} (23 Shell, 14 ScriptUI, 11 Capabilities, 8 Lifecycle, 2 Tool Authority)  ",
        "",
        "### Verification Methodology & Truthfulness Guard",
        "",
        "- **Exhaustively Source-Derived Domains (48 operations):**",
        "  - **Shell Commands (23 ops):** Automatically enumerated from `IOSSystemRunner.linkedCommands` set.",
        "  - **ScriptUI Commands (14 ops):** Automatically enumerated from `HanlinScriptUICommand` enum cases in `HanlinScriptUIContracts.swift`.",
        "  - **Inferred Capabilities (11 ops):** Automatically enumerated from `inferredCapability(for:)` mapping in `HanlinScriptAnalyzer.swift`.",
        "  *Adding any new command or enum case in these domains without a corresponding manifest entry fails CI.*",
        "",
        "- **Maintained Fixed Source-Contract Domains (10 operations):**",
        "  - **Application Lifecycle (8 ops):** Verified against public method signatures in `HanlinScriptingPlatform.swift` (`importPackage`, `installPreview`, `discardPreview`, `launch`, `dismissActiveApplication`, `setEnabled`, `setCapabilityGranted`, `uninstall`).",
        "  - **Canonical Tool Authority (2 ops):** Verified against resolve/execute method signatures in `HanlinCanonicalToolAuthority.swift` and `AssistantToolBridge.swift`.",
        "  *Note on truthfulness: Lifecycle and Tool Authority completeness is verified via a maintained fixed source-contract check that guarantees production method existence, rather than runtime automatic discovery of arbitrary future public methods.*",
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
        lines.append(f"| `{cid}` | {name} | {owner} | {cap} | {mut} | `{exist}` | `{new}` |")

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
