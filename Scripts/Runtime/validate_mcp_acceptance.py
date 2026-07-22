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
    }
    failures = [f"{key}: expected {value!r}, received {payload.get(key)!r}" for key, value in expected.items() if payload.get(key) != value]
    if not isinstance(payload.get("toolCount"), int) or payload["toolCount"] < 1:
        failures.append("toolCount must be at least one")
    if not isinstance(payload.get("reachableModuleCount"), int) or payload["reachableModuleCount"] < 1:
        failures.append("reachableModuleCount must be at least one")
    if payload.get("failureMessage") is not None:
        failures.append(f"failureMessage: {payload['failureMessage']}")
    if failures:
        raise SystemExit("MCP acceptance failed:\n" + "\n".join(failures))

    summary = {
        key: payload.get(key)
        for key in [
            "nodeVersion", "modulePolicyHooksAvailable", "packageName", "resolvedVersion",
            "resolvedEntryPoint", "reachableModuleCount", "resolvedModuleCount", "toolCount",
            "harmlessToolSucceeded", "workerStopped",
        ]
    }
    if args.summary_output:
        args.summary_output.write_text(json.dumps(summary, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(json.dumps(summary, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
