#!/usr/bin/env python3
"""Run independent Runtime/Host Services/Agent acceptance groups and collect one report."""

from __future__ import annotations

import argparse
import datetime as dt
import json
import pathlib
import re
import shutil
import subprocess
import sys
import time
from dataclasses import dataclass
from typing import Any


@dataclass(frozen=True)
class AcceptanceCase:
    case_id: str
    selector_fragment: str
    expected_outcome: str = "pass"


@dataclass(frozen=True)
class AcceptanceGroup:
    name: str
    selectors: tuple[str, ...]
    cases: tuple[AcceptanceCase, ...]


GROUPS = (
    AcceptanceGroup(
        "tool-contracts",
        ("AI_HLYTests/RuntimeToolContractTests",),
        (
            AcceptanceCase("schema.all-tools.unique-routed-valid", "preparedSchemasHaveUniqueAliasesRoutesAndValidObjectContracts"),
            AcceptanceCase("schema.python.local-remote-unambiguous", "localAndRemotePythonAreUnambiguous"),
            AcceptanceCase("schema.shell.structured-enum", "shellSchemaIsStructurallyConstrained"),
            AcceptanceCase("schema.runtime.parameters-match", "runtimeSchemasAdvertiseOnlyHandledParameters"),
            AcceptanceCase("schema.runtime.malformed-rejection", "runtimeToolsRejectMalformedArgumentsSemantically", "rejection"),
            AcceptanceCase("runtime.jsc.value-preserved", "javaScriptCoreExpressionValueReachesModel"),
            AcceptanceCase("diagnostics.semantic-failure-count", "diagnosticsCountSemanticFailureInsideCompletedRun"),
        ),
    ),
    AcceptanceGroup(
        "runtime-host-services",
        ("AI_HLYTests/HanlinUnifiedHostServicesAgentAcceptanceTests",),
        (
            AcceptanceCase("host.agent.context", "agentContextCreation"),
            AcceptanceCase("host.agent.adapter-context", "agentAdapterMakesContextWithAllCapabilities"),
            AcceptanceCase("host.agent.session-isolation", "agentContextSessionIDsAreUnique"),
            AcceptanceCase("runtime.availability.disabled-rejection", "runtimeBrokerRejectsDisabledRuntime", "rejection"),
            AcceptanceCase("runtime.jsc.basic", "agentToolExecutesJavaScriptCore"),
            AcceptanceCase("runtime.node.basic", "agentToolExecutesNode"),
            AcceptanceCase("runtime.python.basic", "agentToolExecutesPython"),
            AcceptanceCase("runtime.typescript.execute", "agentToolExecutesTypeScript"),
            AcceptanceCase("runtime.shell.structured", "agentToolExecutesShell"),
            AcceptanceCase("runtime.shell.all-23-and-policy", "shellAllApprovedCommandsAndPolicies"),
            AcceptanceCase("runtime.availability.tool-outcome", "agentToolRespectsDisabledRuntimeToggle", "rejection"),
            AcceptanceCase("runtime.python.full-contract", "pythonFullContract"),
            AcceptanceCase("runtime.javascript.backends-full-contract", "javaScriptBackendsFullContract"),
            AcceptanceCase("runtime.typescript.full-contract", "typeScriptFullContract"),
            AcceptanceCase("runtime.shell.rejection-matrix", "shellRejectionMatrix", "rejection"),
            AcceptanceCase("capability.runtime-live-revoke-regrant", "runtimeCapabilityLiveRevokeAndRegrantUsesSameSession", "rejection"),
        ),
    ),
    AcceptanceGroup(
        "packages",
        (
            "AI_HLYTests/RuntimePackageAcceptanceTests",
            "AI_HLYUITests/HanlinRuntimeInstallationUITests/testNodePackageManagerUIWorkflowAndFailure",
            "AI_HLYUITests/HanlinRuntimeInstallationUITests/testNodePackageManagerUIWorkflowAndSuccess",
            "AI_HLYUITests/HanlinRuntimeInstallationUITests/testPythonPackageManagerUIWorkflowAndFailure",
            "AI_HLYUITests/HanlinRuntimeInstallationUITests/testPythonPackageManagerUIWorkflowAndSuccess",
        ),
        (
            AcceptanceCase("packages.npm.install-import-typescript-esm-uninstall", "npmInstallImportPersistenceAndUninstall"),
            AcceptanceCase("packages.npm.invalid-rollback", "npmInvalidInputsRollback", "rejection"),
            AcceptanceCase("packages.python.install-dependencies-import-uninstall", "pythonInstallDependencyImportPersistenceAndUninstall"),
            AcceptanceCase("packages.python.native-wheel-invalid-reject", "pythonUnsupportedAndInvalidInputs", "rejection"),
            AcceptanceCase("packages.npm.ui-invalid", "testNodePackageManagerUIWorkflowAndFailure", "rejection"),
            AcceptanceCase("packages.npm.ui-persistence", "testNodePackageManagerUIWorkflowAndSuccess"),
            AcceptanceCase("packages.python.ui-invalid", "testPythonPackageManagerUIWorkflowAndFailure", "rejection"),
            AcceptanceCase("packages.python.ui-persistence", "testPythonPackageManagerUIWorkflowAndSuccess"),
        ),
    ),
    AcceptanceGroup(
        "files-sqlite-capabilities",
        ("AI_HLYTests/HanlinUnifiedHostServicesE2ETests",),
        (
            AcceptanceCase("runtime.availability.broker-toggle", "runtimeBrokerRespectsAvailabilityToggle", "rejection"),
            AcceptanceCase("capability.grant-revoke", "capabilityAuthorityGrantRevokePersists"),
            AcceptanceCase("capability.package-precedence-live-revoke", "packageStoreGrantPrecedenceAndLiveRevocation"),
            AcceptanceCase("host.concurrent-callers", "crossCallerConcurrency"),
            AcceptanceCase("files.app-isolation", "storageIsolationBetweenApps"),
            AcceptanceCase("files.capability-denial", "fileCapabilityRequired", "rejection"),
            AcceptanceCase("files.scopes-delete-symlink-shared", "fileScopesOverwriteDeleteSharedGateAndSymlinkProtection"),
            AcceptanceCase("sqlite.path-bound-parameters", "sqliteScopeAndTraversalRejection"),
            AcceptanceCase("sqlite.crud-transaction-fk-types-concurrency-scopes", "sqliteTransactionsTypesConcurrencyAndScopeIsolation"),
            AcceptanceCase("engine.nativescript.session-binding", "nativeScriptSessionsResolveExactlyAndTeardownIndependently"),
            AcceptanceCase("engine.expo.app-context-binding", "expoAppContextsResolveExactlyAndTeardownIndependently"),
        ),
    ),
    AcceptanceGroup(
        "miniapp-engines",
        ("AI_HLYTests/CanonicalMiniAppIntegrationTests",),
        (
            AcceptanceCase("engine.swift.catalog", "CanonicalcatalogdiscoversSwiftbuiltinparityapp"),
            AcceptanceCase("engine.scriptui.runtime-bridge", "NativeservicesbridgeexposesPythonversion"),
            AcceptanceCase("engine.cross-engine.capability", "Inter-apprequestbrokerallowsauthorizedcross-engine"),
            AcceptanceCase("engine.storage.path-protection", "Privatestoragerejectspathtraversal"),
            AcceptanceCase("engine.entrypoint.isolation", "Per-entrypointisolationonhybridpackage"),
            AcceptanceCase("engine.four-providers.registered", "All4compiledminiappprovidersareregistered"),
            AcceptanceCase("engine.nativescript.active-container", "HanlinNativeServicesBridgeenforcesactivecontainerisolation"),
        ),
    ),
    AcceptanceGroup(
        "agent-e2e",
        ("AI_HLYTests/AgentRuntimeConversationAcceptanceTests",),
        (
            AcceptanceCase("agent.conversation.runtime-sequence", "successfulRuntimeChain"),
            AcceptanceCase("agent.conversation.failure-recovery", "recoversAfterRejectedShellCall", "rejection"),
            AcceptanceCase("agent.conversation.parameters", "runtimeParameters"),
            AcceptanceCase("agent.conversation.malformed-recovery", "malformedCallsRecover", "rejection"),
        ),
    ),
    AcceptanceGroup(
        "runtime-ui",
        (
            "AI_HLYUITests/HanlinRuntimeInstallationUITests/testRuntimeCenterEmbeddedRuntimesSmokeAndReadiness",
            "AI_HLYUITests/HanlinRuntimeCommandAcceptanceUITests",
            "AI_HLYUITests/AgentRuntimeConversationUITests",
        ),
        (
            AcceptanceCase("ui.runtime-center.smoke-relaunch", "testRuntimeCenterEmbeddedRuntimesSmokeAndReadiness"),
            AcceptanceCase("ui.runtime.commands-coherence", "testRuntimeCenterCommandSmokeAndCoherence"),
            AcceptanceCase("ui.runtime.session-restart-persistence", "testRuntimeSessionStateAndRestartPersistence"),
            AcceptanceCase("ui.chat.real-agent-tool-loop", "testRealChatUISendsPromptShowsToolActivityAndFinalAnswer"),
        ),
    ),
)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--project", required=True)
    parser.add_argument("--scheme", required=True)
    parser.add_argument("--configuration", required=True)
    parser.add_argument("--destination", required=True)
    parser.add_argument("--derived-data", required=True)
    parser.add_argument("--source-packages", required=True)
    parser.add_argument("--output-dir", required=True)
    parser.add_argument("--commit", required=True)
    parser.add_argument("--branch", required=True)
    parser.add_argument("--xcode-version", required=True)
    parser.add_argument("--simulator-device", required=True)
    parser.add_argument("--simulator-os", required=True)
    return parser.parse_args()


def iso_now() -> str:
    return dt.datetime.now(dt.timezone.utc).isoformat().replace("+00:00", "Z")


def normalized(value: str) -> str:
    return re.sub(r"[^a-z0-9]", "", value.lower())


def test_nodes(payload: Any) -> list[dict[str, Any]]:
    found: list[dict[str, Any]] = []
    if isinstance(payload, dict):
        name = payload.get("name") or payload.get("testIdentifier") or payload.get("nodeIdentifier")
        status = payload.get("result") or payload.get("testStatus") or payload.get("status")
        if isinstance(name, str) and status is not None:
            found.append(payload)
        for value in payload.values():
            found.extend(test_nodes(value))
    elif isinstance(payload, list):
        for value in payload:
            found.extend(test_nodes(value))
    return found


def node_status(node: dict[str, Any]) -> str:
    raw = node.get("result") or node.get("testStatus") or node.get("status") or "unknown"
    if isinstance(raw, dict):
        raw = raw.get("value") or raw.get("name") or "unknown"
    return str(raw).lower()


def node_name(node: dict[str, Any]) -> str:
    return " ".join(
        str(node.get(key) or "")
        for key in ("name", "testIdentifier", "nodeIdentifier", "nodeIdentifierURL")
    )


def node_duration(node: dict[str, Any]) -> float | None:
    raw = node.get("duration")
    if isinstance(raw, dict):
        raw = raw.get("value")
    try:
        return float(raw)
    except (TypeError, ValueError):
        return None


def run_group(args: argparse.Namespace, output: pathlib.Path, group: AcceptanceGroup) -> tuple[dict[str, Any], list[dict[str, Any]]]:
    group_dir = output / "groups" / group.name
    group_dir.mkdir(parents=True, exist_ok=True)
    result_bundle = group_dir / "Result.xcresult"
    log_path = group_dir / "xcodebuild.log"
    if result_bundle.exists():
        shutil.rmtree(result_bundle)

    command = [
        "xcodebuild", "test-without-building",
        "-project", args.project,
        "-scheme", args.scheme,
        "-configuration", args.configuration,
        "-destination", args.destination,
        "-derivedDataPath", args.derived_data,
        "-clonedSourcePackagesDirPath", args.source_packages,
        "-resultBundlePath", str(result_bundle),
        "-skipPackagePluginValidation",
        "-skipMacroValidation",
        "-parallel-testing-enabled", "NO",
    ]
    command.extend(f"-only-testing:{selector}" for selector in group.selectors)
    started = time.monotonic()
    with log_path.open("w", encoding="utf-8", errors="replace") as log:
        process = subprocess.run(command, stdout=log, stderr=subprocess.STDOUT, check=False, text=True)
    duration = time.monotonic() - started
    log_text = log_path.read_text(encoding="utf-8", errors="replace")
    process_crashed = process.returncode != 0 and any(
        marker in log_text.lower()
        for marker in (
            "test runner exited before completing",
            "lost connection to the test process",
            "terminated due to signal",
            "test process crashed",
            "unexpectedly quit",
        )
    )

    nodes: list[dict[str, Any]] = []
    xcresult_json = group_dir / "test-results.json"
    if result_bundle.exists():
        result = subprocess.run(
            ["xcrun", "xcresulttool", "get", "test-results", "tests", "--path", str(result_bundle), "--format", "json"],
            capture_output=True,
            text=True,
            check=False,
        )
        xcresult_json.write_text(result.stdout or result.stderr, encoding="utf-8")
        if result.returncode == 0:
            try:
                nodes = test_nodes(json.loads(result.stdout))
            except json.JSONDecodeError:
                nodes = []

    case_results: list[dict[str, Any]] = []
    for expected in group.cases:
        needle = normalized(expected.selector_fragment)
        matches = [node for node in nodes if needle in normalized(node_name(node))]
        selected = min(matches, key=lambda item: len(node_name(item)), default=None)
        status = node_status(selected) if selected else "missing"
        passed = status in {"passed", "success", "succeeded"}
        crashed = selected is None and process_crashed
        if passed and expected.expected_outcome == "rejection":
            actual_outcome = "expected-rejection"
        elif passed:
            actual_outcome = "passed"
        elif crashed:
            actual_outcome = "crashed"
        else:
            actual_outcome = status
        case_results.append({
            "caseID": expected.case_id,
            "group": group.name,
            "expectedOutcome": expected.expected_outcome,
            "actualOutcome": actual_outcome,
            "passed": passed,
            "durationSeconds": node_duration(selected) if selected else None,
            "errorCategory": None if passed else ("process_crash" if crashed else "test_failure"),
            "diagnosticReferences": [str(log_path), str(result_bundle), str(xcresult_json)],
        })

    group_result = {
        "name": group.name,
        "status": "passed" if process.returncode == 0 and all(case["passed"] for case in case_results) else "failed",
        "exitCode": process.returncode,
        "durationSeconds": round(duration, 3),
        "caseCount": len(case_results),
        "passedCount": sum(1 for case in case_results if case["passed"]),
        "failedCount": sum(1 for case in case_results if not case["passed"] and case["actualOutcome"] != "crashed"),
        "crashedCount": sum(1 for case in case_results if case["actualOutcome"] == "crashed"),
        "log": str(log_path),
        "resultBundle": str(result_bundle),
    }
    return group_result, case_results


def markdown(report: dict[str, Any]) -> str:
    lines = [
        "# Runtime / Tooling Acceptance",
        "",
        f"- Commit: `{report['commitSHA']}`",
        f"- Branch: `{report['branch']}`",
        f"- Xcode: `{report['xcodeVersion']}`",
        f"- Simulator: `{report['simulator']['device']}` / `{report['simulator']['os']}`",
        f"- Result: **{'PASS' if report['failedCount'] == 0 and report['crashedCount'] == 0 else 'FAIL'}**",
        f"- Cases: {report['caseCount']} total, {report['passedCount']} passed, {report['failedCount']} failed, {report['crashedCount']} crashed",
        "",
        "## Groups",
        "",
        "| Group | Status | Passed | Failed | Crashed | Duration |",
        "|---|---:|---:|---:|---:|---:|",
    ]
    for group in report["groupSummaries"]:
        lines.append(
            f"| {group['name']} | {group['status'].upper()} | {group['passedCount']} | "
            f"{group['failedCount']} | {group['crashedCount']} | {group['durationSeconds']:.1f}s |"
        )
    lines.extend(["", "## Cases", "", "| Case ID | Group | Expected | Actual |", "|---|---|---|---|"])
    for case in report["cases"]:
        lines.append(f"| `{case['caseID']}` | {case['group']} | {case['expectedOutcome']} | {case['actualOutcome']} |")
    lines.append("")
    return "\n".join(lines)


def main() -> int:
    args = parse_args()
    output = pathlib.Path(args.output_dir)
    output.mkdir(parents=True, exist_ok=True)
    started_at = iso_now()
    group_results: list[dict[str, Any]] = []
    cases: list[dict[str, Any]] = []

    for group in GROUPS:
        group_result, case_results = run_group(args, output, group)
        group_results.append(group_result)
        cases.extend(case_results)
        print(f"[{group_result['status'].upper()}] {group.name}: {group_result['passedCount']}/{group_result['caseCount']}", flush=True)

    report = {
        "schemaVersion": 1,
        "commitSHA": args.commit,
        "branch": args.branch,
        "xcodeVersion": args.xcode_version,
        "simulator": {"device": args.simulator_device, "os": args.simulator_os},
        "startedAt": started_at,
        "endedAt": iso_now(),
        "caseCount": len(cases),
        "passedCount": sum(1 for case in cases if case["passed"]),
        "failedCount": sum(1 for case in cases if not case["passed"] and case["actualOutcome"] != "crashed"),
        "crashedCount": sum(1 for case in cases if case["actualOutcome"] == "crashed"),
        "expectedRejectionCount": sum(1 for case in cases if case["expectedOutcome"] == "rejection" and case["passed"]),
        "unexpectedSuccessCount": 0,
        "groupSummaries": group_results,
        "cases": cases,
        "diagnosticArtifactPaths": [str(output / "groups")],
    }
    (output / "runtime-tooling-acceptance.json").write_text(
        json.dumps(report, indent=2, ensure_ascii=False) + "\n", encoding="utf-8"
    )
    (output / "runtime-tooling-acceptance.md").write_text(markdown(report), encoding="utf-8")
    print(markdown(report))
    return 0 if report["failedCount"] == 0 and report["crashedCount"] == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
