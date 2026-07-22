from __future__ import annotations

import copy
import unittest

from Scripts.Runtime.validate_ios_system_resources import EXPECTED_ENTRIES
from Scripts.Runtime.validate_shell_acceptance import (
    EXPECTED_POLICIES,
    AcceptanceValidationError,
    validate_acceptance,
)


COMMANDS = sorted(EXPECTED_ENTRIES)


def valid_payload() -> dict[str, object]:
    return {
        "schemaVersion": 1,
        "passed": True,
        "snapshot": {
            "state": "ready",
            "healthCategory": "ready",
            "lastErrorCode": None,
            "missingCommands": None,
        },
        "registration": {
            "dictionaryCommands": COMMANDS.copy(),
            "registeredCommands": COMMANDS.copy(),
            "executableCommands": COMMANDS.copy(),
            "rawCommandValues": COMMANDS.copy(),
            "rawCommandsCount": 23,
            "missingRegisteredCommands": [],
            "missingExecutableCommands": [],
            "sideLoadingEnabled": False,
            "initializeEnvironmentCallCount": 1,
        },
        "smoke": {
            "passed": True,
            "workspaceContained": True,
            "workspaceEscapeCount": 0,
            "testedCommands": COMMANDS.copy(),
            "commandResults": [
                {
                    "command": command,
                    "exitCode": 0,
                    "representativeOutput": "curl 8" if command == "curl" else "ok",
                    "passed": True,
                    "failure": None,
                }
                for command in COMMANDS
            ],
            "policyResults": [
                {"policy": policy, "passed": True, "detail": "ok"}
                for policy in sorted(EXPECTED_POLICIES)
            ],
        },
    }


class ShellAcceptanceValidationTests(unittest.TestCase):
    def test_valid_result_passes(self) -> None:
        self.assertEqual(validate_acceptance(valid_payload())["commandCount"], 23)

    def test_missing_command_fails(self) -> None:
        payload = valid_payload()
        payload["registration"]["registeredCommands"].pop()
        with self.assertRaisesRegex(AcceptanceValidationError, "exact approved catalog"):
            validate_acceptance(payload)

    def test_nonzero_command_fails(self) -> None:
        payload = valid_payload()
        payload["smoke"]["commandResults"][0]["exitCode"] = 1
        with self.assertRaisesRegex(AcceptanceValidationError, "nonzero"):
            validate_acceptance(payload)

    def test_workspace_escape_fails(self) -> None:
        payload = copy.deepcopy(valid_payload())
        payload["smoke"]["workspaceEscapeCount"] = 1
        with self.assertRaisesRegex(AcceptanceValidationError, "workspace escape"):
            validate_acceptance(payload)


if __name__ == "__main__":
    unittest.main()
