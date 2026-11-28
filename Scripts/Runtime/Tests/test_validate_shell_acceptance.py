from __future__ import annotations

import copy
import unittest

from Scripts.Runtime.validate_ios_system_resources import EXPECTED_ENTRIES
from Scripts.Runtime.validate_shell_acceptance import (
    AcceptanceValidationError,
    validate_acceptance,
)


COMMANDS = sorted(EXPECTED_ENTRIES)
# Keep this native-producer fixture independent of the validator constant.
# A stale expected set must fail the positive fixture, rather than rewrite it.
CURRENT_PRODUCER_POLICIES = (
    "verified_command_catalog",
    "native_pipeline_and_redirection",
    "portable_command_chaining",
    "curl_http_native_dispatch",
    "curl_https_native_dispatch",
)


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
                for policy in CURRENT_PRODUCER_POLICIES
            ],
        },
    }


class ShellAcceptanceValidationTests(unittest.TestCase):
    def test_valid_result_passes(self) -> None:
        summary = validate_acceptance(valid_payload())
        self.assertEqual(summary["commandCount"], 23)
        self.assertEqual(summary["policyCount"], 5)

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

    def test_dynamic_catalog_superset_passes(self) -> None:
        payload = copy.deepcopy(valid_payload())
        for field in ("dictionaryCommands", "registeredCommands", "executableCommands", "rawCommandValues"):
            payload["registration"][field].append("extra_tool")
        payload["registration"]["rawCommandsCount"] = len(payload["registration"]["rawCommandValues"])
        payload["smoke"]["testedCommands"].append("extra_tool")
        payload["smoke"]["commandResults"].append(
            {
                "command": "extra_tool",
                "exitCode": 0,
                "representativeOutput": "ok",
                "passed": True,
                "failure": None,
            }
        )
        summary = validate_acceptance(payload)
        self.assertEqual(summary["commandCount"], 24)

    def test_missing_current_policy_fails(self) -> None:
        for policy in CURRENT_PRODUCER_POLICIES:
            with self.subTest(policy=policy):
                payload = valid_payload()
                payload["smoke"]["policyResults"] = [
                    row for row in payload["smoke"]["policyResults"] if row["policy"] != policy
                ]
                with self.assertRaisesRegex(AcceptanceValidationError, "policy coverage"):
                    validate_acceptance(payload)

    def test_legacy_policy_contract_fails(self) -> None:
        payload = valid_payload()
        payload["smoke"]["policyResults"] = [
            {"policy": policy, "passed": True, "detail": "legacy"}
            for policy in (
                "unknown_command", "pipeline", "redirection", "command_chaining",
                "curl_https_permission", "curl_http", "curl_offline_version",
            )
        ]
        with self.assertRaisesRegex(AcceptanceValidationError, "policy coverage"):
            validate_acceptance(payload)

    def test_unexpected_policy_fails(self) -> None:
        payload = valid_payload()
        payload["smoke"]["policyResults"].append(
            {"policy": "unapproved_policy", "passed": True, "detail": "unexpected"}
        )
        with self.assertRaisesRegex(AcceptanceValidationError, "policy coverage"):
            validate_acceptance(payload)

    def test_duplicate_current_policy_fails(self) -> None:
        for index, policy in enumerate(CURRENT_PRODUCER_POLICIES):
            with self.subTest(policy=policy):
                payload = valid_payload()
                payload["smoke"]["policyResults"].append(
                    copy.deepcopy(payload["smoke"]["policyResults"][index])
                )
                with self.assertRaisesRegex(AcceptanceValidationError, "duplicates"):
                    validate_acceptance(payload)

    def test_failed_current_policy_fails(self) -> None:
        for index, policy in enumerate(CURRENT_PRODUCER_POLICIES):
            with self.subTest(policy=policy):
                payload = valid_payload()
                payload["smoke"]["policyResults"][index]["passed"] = False
                with self.assertRaisesRegex(AcceptanceValidationError, "policy check failed"):
                    validate_acceptance(payload)

    def test_nonboolean_current_policy_success_fails(self) -> None:
        for index, policy in enumerate(CURRENT_PRODUCER_POLICIES):
            for value in (1, "true", None):
                with self.subTest(policy=policy, value=value):
                    payload = valid_payload()
                    payload["smoke"]["policyResults"][index]["passed"] = value
                    with self.assertRaisesRegex(AcceptanceValidationError, "policy check failed"):
                        validate_acceptance(payload)

    def test_offline_curl_output_must_identify_curl(self) -> None:
        payload = valid_payload()
        result = next(row for row in payload["smoke"]["commandResults"] if row["command"] == "curl")
        result["representativeOutput"] = "unrelated output"
        with self.assertRaisesRegex(AcceptanceValidationError, "does not identify curl"):
            validate_acceptance(payload)


if __name__ == "__main__":
    unittest.main()
