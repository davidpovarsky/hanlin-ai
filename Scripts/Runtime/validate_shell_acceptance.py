#!/usr/bin/env python3
"""Validate the full-app simulator shell acceptance result."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any

try:
    from .validate_ios_system_resources import EXPECTED_ENTRIES
except ImportError:
    from validate_ios_system_resources import EXPECTED_ENTRIES


EXPECTED_COMMANDS = set(EXPECTED_ENTRIES)
EXPECTED_POLICIES = {
    "unknown_command",
    "pipeline",
    "redirection",
    "command_chaining",
    "parent_traversal",
    "absolute_path",
    "curl_https_permission",
    "curl_http",
    "curl_offline_version",
}


class AcceptanceValidationError(RuntimeError):
    pass


def require(condition: bool, message: str) -> None:
    if not condition:
        raise AcceptanceValidationError(message)


def validate_acceptance(payload: dict[str, Any]) -> dict[str, Any]:
    require(payload.get("schemaVersion") == 1, "Unsupported shell acceptance schema")
    require(payload.get("passed") is True, f"Shell acceptance failed: {payload.get('failureMessage')}")

    snapshot = payload.get("snapshot") or {}
    require(snapshot.get("state") == "ready", "Shell runtime snapshot is not ready")
    require(snapshot.get("healthCategory") == "ready", "Shell health category is not ready")
    require(snapshot.get("lastErrorCode") is None, "Shell snapshot contains an error code")
    require(snapshot.get("missingCommands") in (None, []), "Shell snapshot contains missing commands")

    registration = payload.get("registration") or {}
    for field in ("dictionaryCommands", "registeredCommands", "executableCommands", "rawCommandValues"):
        values = registration.get(field)
        require(isinstance(values, list), f"Registration field {field} is missing")
        require(set(values) == EXPECTED_COMMANDS, f"Registration field {field} is not the exact approved catalog")
        require(len(values) == len(EXPECTED_COMMANDS), f"Registration field {field} contains duplicates")
    require(registration.get("rawCommandsCount") == 23, "Raw Objective-C command count is not 23")
    require(registration.get("missingRegisteredCommands") == [], "Registered commands are missing")
    require(registration.get("missingExecutableCommands") == [], "Executable commands are missing")
    require(registration.get("sideLoadingEnabled") is False, "ios_system sideLoading is enabled")
    require(registration.get("initializeEnvironmentCallCount") == 1, "initializeEnvironment did not run exactly once")

    smoke = payload.get("smoke") or {}
    require(smoke.get("passed") is True, "Shell smoke suite did not pass")
    require(smoke.get("workspaceContained") is True, "Shell smoke writes escaped the workspace")
    require(smoke.get("workspaceEscapeCount") == 0, "Shell smoke reported a workspace escape")
    require(set(smoke.get("testedCommands") or []) == EXPECTED_COMMANDS, "Not all approved commands were tested")

    command_results = smoke.get("commandResults") or []
    require(len(command_results) == 23, "Shell smoke result count is not 23")
    results_by_name = {result.get("command"): result for result in command_results}
    require(set(results_by_name) == EXPECTED_COMMANDS, "Shell smoke commands are missing or unexpected")
    for command, result in results_by_name.items():
        require(result.get("passed") is True, f"Shell command failed: {command}: {result.get('failure')}")
        require(result.get("exitCode") == 0, f"Shell command returned nonzero: {command}")
    curl_output = results_by_name["curl"].get("representativeOutput", "")
    require("curl" in curl_output.lower(), "curl --version output does not identify curl")

    policy_results = smoke.get("policyResults") or []
    policies_by_name = {result.get("policy"): result for result in policy_results}
    require(set(policies_by_name) == EXPECTED_POLICIES, "Shell policy coverage is incomplete or unexpected")
    for policy, result in policies_by_name.items():
        require(result.get("passed") is True, f"Shell policy check failed: {policy}")

    return {
        "passed": True,
        "commandCount": len(command_results),
        "commands": [
            {
                "command": command,
                "exitCode": results_by_name[command]["exitCode"],
                "representativeOutput": results_by_name[command]["representativeOutput"],
            }
            for command in sorted(results_by_name)
        ],
        "policyCount": len(policy_results),
        "workspaceEscapeCount": smoke["workspaceEscapeCount"],
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("result", type=Path)
    parser.add_argument("--summary-output", type=Path)
    arguments = parser.parse_args()
    payload = json.loads(arguments.result.read_text(encoding="utf-8"))
    summary = validate_acceptance(payload)
    rendered = json.dumps(summary, indent=2, sort_keys=True) + "\n"
    if arguments.summary_output:
        arguments.summary_output.write_text(rendered, encoding="utf-8")
    print(rendered, end="")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
