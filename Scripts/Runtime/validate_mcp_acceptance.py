#!/usr/bin/env python3
import argparse
import json
from pathlib import Path


def main() -> None:
    parser = argparse.ArgumentParser(description="Validate embedded MCP simulator acceptance evidence.")
    parser.add_argument("report", type=Path)
    parser.add_argument("--summary-output", type=Path)
    args = parser.parse_args()

    payload = json.loads(args.report.read_text(encoding="utf-8"))
    expected = {
        "schemaVersion": 3,
        "passed": True,
        "nodeVersion": "24.5.0",
        "modulePolicyHooksAvailable": True,
        "packageName": "@modelcontextprotocol/server-everything",
        "resolvedVersion": "2026.7.4",
        "resolvedEntryPoint": "dist/index.js",
        "clientStdioLoaded": False,
        "crossSpawnLoaded": False,
        "childProcessResolved": False,
        "initializeSucceeded": True,
        "toolsListSucceeded": True,
        "harmlessToolSucceeded": True,
        "workerStopped": True,
        "terminalInstallErrorCount": 0,
        "lazyStartSucceeded": True,
        "duplicateStartWasIdempotent": True,
        "duplicateStopWasIdempotent": True,
        "restartStressPassed": True,
        "backgroundStopPassed": True,
        "foregroundLazyRestartPassed": True,
        "registryPreserved": True,
        "forcedTerminationCount": 0,
        "childProcessImportOnlyPassed": True,
        "subprocessExecutionBlocked": True,
        "healthCancellationPreserved": True,
        "oldRegistryDecoded": True,
        "backupRecoveryPassed": True,
        "pathMigrationPassed": True,
        "partialFailureIsolationPassed": True,
        "toolCallLazyRecoveryPassed": True,
        "multiServerCollectionPassed": True,
    }
    failures = [f"{key}: expected {value!r}, received {payload.get(key)!r}" for key, value in expected.items() if payload.get(key) != value]
    if not isinstance(payload.get("toolCount"), int) or payload["toolCount"] < 1:
        failures.append("toolCount must be at least one")
    if not isinstance(payload.get("reachableModuleCount"), int) or payload["reachableModuleCount"] < 1:
        failures.append("reachableModuleCount must be at least one")
    if not isinstance(payload.get("maximumConcurrentWorkers"), int) or payload["maximumConcurrentWorkers"] > 1:
        failures.append("maximumConcurrentWorkers must be at most one")
    if payload.get("failureMessage") is not None:
        failures.append(f"failureMessage: {payload['failureMessage']}")
    server_tool_counts = payload.get("serverToolCounts")
    expected_servers = {
        "@modelcontextprotocol/server-everything",
        "@modelcontextprotocol/server-memory",
        "@modelcontextprotocol/server-sequential-thinking",
    }
    if not isinstance(server_tool_counts, dict) or set(server_tool_counts) != expected_servers:
        failures.append("serverToolCounts must contain exactly the three pinned MCP servers")
    elif any(not isinstance(value, int) or value < 1 for value in server_tool_counts.values()):
        failures.append("every pinned MCP server must expose at least one tool")
    canonical_shadow = payload.get("canonicalShadow")
    required_shadow_domains = {
        "native.tools",
        "mcp",
        "runtime.core",
        "cross-domain.tools",
    }
    if not isinstance(canonical_shadow, dict):
        failures.append("canonicalShadow must be present")
    else:
        canonical_summary = canonical_shadow.get("summary")
        if not isinstance(canonical_summary, dict) or canonical_summary.get("mismatchCount") != 0:
            failures.append("canonicalShadow must contain zero mismatches")
        domains = {
            item.get("domain"): item
            for item in canonical_shadow.get("domains", [])
            if isinstance(item, dict)
        }
        for domain in required_shadow_domains:
            if domains.get(domain, {}).get("status") != "passed":
                failures.append(f"canonicalShadow domain {domain} must pass")
    if failures:
        raise SystemExit("MCP acceptance failed:\n" + "\n".join(failures))

    summary = {
        key: payload.get(key)
        for key in [
            "nodeVersion", "modulePolicyHooksAvailable", "packageName", "resolvedVersion",
            "resolvedEntryPoint", "reachableModuleCount", "resolvedModuleCount", "toolCount",
            "harmlessToolSucceeded", "workerStopped", "lazyStartSucceeded",
            "restartStressPassed", "registryPreserved", "maximumConcurrentWorkers",
            "childProcessImportOnlyPassed", "subprocessExecutionBlocked",
            "pathMigrationPassed", "partialFailureIsolationPassed",
            "toolCallLazyRecoveryPassed", "multiServerCollectionPassed",
            "serverToolCounts",
            "canonicalShadow",
        ]
    }
    if args.summary_output:
        args.summary_output.write_text(json.dumps(summary, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(json.dumps(summary, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
