#!/usr/bin/env python3
"""
generate_provider_conformance_summary.py
Generates machine-checkable provider conformance summary artifact conforming to Section 24.
Parses actual executed test logs to determine PASS / FAIL / NOT_RUN status with full provenance.
"""

import argparse
import datetime
import json
import os
import re
import subprocess
import sys
from pathlib import Path

CONFORMANCE_TEST_DIRS = [
    "Packages/HanlinPlatform/Tests/HanlinChatCoreTests/ProviderConformance",
    "AI_HLYTests/ProviderConformance"
]

DEFAULT_SEARCH_LOG_DIRS = [
    "build-logs",
    "simulator-logs",
    "build/ci-artifacts/build/acceptance/phases/unit",
    "build/ci-artifacts/simulator-logs",
    "."
]

DEFAULT_LOG_PATTERNS = [
    "05-swift-test.log",
    "08-downstream-unit-tests.log",
    "xcodebuild.log"
]


def get_git_commit_sha(repo_root: Path) -> str:
    env_sha = os.environ.get("GITHUB_SHA")
    if env_sha:
        return env_sha.strip()
    try:
        res = subprocess.run(
            ["git", "rev-parse", "HEAD"],
            cwd=str(repo_root),
            capture_output=True,
            text=True,
            check=True
        )
        return res.stdout.strip()
    except Exception:
        return "UNKNOWN"


def scan_test_definitions(repo_root: Path):
    tests = []
    suite_pattern = re.compile(r'@Suite(?:\([^)]*\))?\s*struct\s+(\w+)')
    test_decl_pattern = re.compile(
        r'(@Test(?:\(\s*(?:"([^"]+)")?[^)]*\))?\s*)?'
        r'func\s+(test\w+)\s*\('
    )

    for rel_dir in CONFORMANCE_TEST_DIRS:
        abs_dir = repo_root / rel_dir
        if not abs_dir.exists():
            continue
        for root, _, files in os.walk(abs_dir):
            for file in sorted(files):
                if file.endswith(".swift"):
                    file_path = Path(root) / file
                    content = file_path.read_text(encoding="utf-8")
                    current_suite = file_path.stem
                    sm = suite_pattern.search(content)
                    if sm:
                        current_suite = sm.group(1)

                    for tm in test_decl_pattern.finditer(content):
                        display_name = tm.group(2)
                        func_name = tm.group(3)
                        tests.append({
                            "suite": current_suite,
                            "function": func_name,
                            "displayName": display_name,
                            "file": str(file_path.relative_to(repo_root)).replace("\\", "/")
                        })
    return tests


def parse_test_logs(log_paths):
    passed_tests = set()
    failed_tests = set()
    failure_messages = {}

    swift_test_pass_pattern = re.compile(
        r'✔\s+Test\s+(?:"([^"]+)"|(\w+)(?:\(\))?)(?:\s+with\s+\d+\s+test\s+cases)?\s+passed\s+after'
    )
    swift_test_fail_pattern = re.compile(
        r'✘\s+Test\s+(?:"([^"]+)"|(\w+)(?:\(\))?)\s+failed\s+after'
    )
    xctest_pass_pattern = re.compile(
        r"Test\s+[Cc]ase\s+'(?:-\[(\w+)\s+(\w+)\]|([^']+))'\s+passed"
    )
    xctest_fail_pattern = re.compile(
        r"Test\s+[Cc]ase\s+'(?:-\[(\w+)\s+(\w+)\]|([^']+))'\s+failed"
    )

    for log_path in log_paths:
        if not log_path.exists():
            continue
        try:
            with open(log_path, "r", encoding="utf-8", errors="replace") as f:
                for line in f:
                    # Swift Testing pass
                    m = swift_test_pass_pattern.search(line)
                    if m:
                        name = m.group(1) or m.group(2)
                        passed_tests.add(name.strip())
                        continue

                    # Swift Testing fail
                    m = swift_test_fail_pattern.search(line)
                    if m:
                        name = m.group(1) or m.group(2)
                        failed_tests.add(name.strip())
                        failure_messages[name.strip()] = line.strip()
                        continue

                    # XCTest pass
                    m = xctest_pass_pattern.search(line)
                    if m:
                        if m.group(2):
                            passed_tests.add(m.group(2).strip())
                            passed_tests.add(f"{m.group(1)}.{m.group(2)}".strip())
                        elif m.group(3):
                            passed_tests.add(m.group(3).strip())
                        continue

                    # XCTest fail
                    m = xctest_fail_pattern.search(line)
                    if m:
                        if m.group(2):
                            fn = m.group(2).strip()
                            failed_tests.add(fn)
                            failure_messages[fn] = line.strip()
                        elif m.group(3):
                            fn = m.group(3).strip()
                            failed_tests.add(fn)
                            failure_messages[fn] = line.strip()
                        continue
        except Exception as e:
            print(f"Warning: Failed to parse log {log_path}: {e}", file=sys.stderr)

    return passed_tests, failed_tests, failure_messages


def match_test_status(test, passed_set, failed_set, failure_messages):
    func = test["function"]
    display = test.get("displayName")
    suite = test["suite"]
    full_ident = f"{suite}.{func}"

    # Check for failures first
    for candidate in [func, display, full_ident]:
        if candidate and candidate in failed_set:
            return "FAIL", failure_messages.get(candidate, "Test failed during execution")

    # Check for passes
    for candidate in [func, display, full_ident]:
        if candidate and candidate in passed_set:
            return "PASS", None

    # Substring / fuzzy match on display name if present
    if display:
        for p in passed_set:
            if display == p or display.startswith(p) or p.startswith(display):
                return "PASS", None
        for f in failed_set:
            if display == f or display.startswith(f) or f.startswith(display):
                return "FAIL", failure_messages.get(f, "Test failed")

    return "NOT_RUN", None


def classify_scenario_and_profile(test):
    func = test["function"]
    display = test.get("displayName") or ""
    scenario = "Unknown"
    profile = "allApplicable"

    # Scenario matching
    for tag in ["S01", "S02", "S03", "S04", "S05", "S06", "S07", "S08", "S09", "S10",
                "F01", "F02", "F03", "F04", "F05", "F06", "F07", "F08", "F09",
                "P01", "P02", "P03", "P04", "P05", "P06", "P07", "P08", "P09", "P10"]:
        if tag in func or tag in display:
            scenario = tag
            break
    if scenario == "Unknown":
        if "FinishReason" in func or "finishReason" in func or "FinishReason" in display:
            scenario = "FinishReasonMatrix"
        elif "Smoke" in func or "smoke" in func or "Smoke" in display:
            scenario = "Smoke"
        elif "Routing" in func:
            scenario = "Routing"
        elif "Inventory" in func:
            scenario = "Inventory"
        elif "Dormancy" in func:
            scenario = "Dormancy"
        elif "Regression" in func:
            scenario = "HarnessRegression"

    # Profile matching
    if "OpenAINative" in func or "OpenAINative" in display:
        profile = "openAINativeChat"
    elif "OpenAICompatible" in func or "OpenAICompatible" in display:
        profile = "openAICompatiblePlain"
    elif "OpenRouter" in func or "OpenRouter" in display:
        profile = "openRouterReasoningDetails"
    elif "Anthropic" in func or "Anthropic" in display:
        profile = "anthropicNative"
    elif "Google" in func or "Google" in display or "Gemini" in func:
        profile = "googleNative"
    elif "OpenAI" in func or "OpenAI" in display:
        profile = "openAINativeChat"

    return scenario, profile


def main():
    parser = argparse.ArgumentParser(description="Generate provider conformance summary.")
    parser.add_argument("--repo-root", type=str, default=None, help="Root path of the repository")
    parser.add_argument("--log-dir", action="append", default=[], help="Directory to search for test logs")
    parser.add_argument("--log-file", action="append", default=[], help="Specific test log file to parse")
    parser.add_argument("--output", type=str, default="provider-conformance-summary.json", help="Output JSON path")
    parser.add_argument("--gate", action="store_true", help="Exit with code 1 if any test is NOT_RUN or FAIL")
    args = parser.parse_args()

    repo_root = Path(args.repo_root).resolve() if args.repo_root else Path(__file__).resolve().parent.parent.parent
    tests = scan_test_definitions(repo_root)

    # Collect log files
    log_paths = []
    if args.log_file:
        for lf in args.log_file:
            p = Path(lf)
            if not p.is_absolute():
                p = repo_root / p
            if p.exists():
                log_paths.append(p)
    else:
        search_dirs = args.log_dir if args.log_dir else DEFAULT_SEARCH_LOG_DIRS
        for sd in search_dirs:
            abs_sd = Path(sd) if Path(sd).is_absolute() else repo_root / sd
            if abs_sd.exists():
                for pat in DEFAULT_LOG_PATTERNS:
                    found = list(abs_sd.glob(f"**/{pat}"))
                    log_paths.extend(found)

    # De-duplicate log paths
    log_paths = sorted(list(set(log_paths)))

    passed_set, failed_set, failure_messages = parse_test_logs(log_paths)

    results = []
    passed_count = 0
    failed_count = 0
    not_run_count = 0

    for t in tests:
        status, err_msg = match_test_status(t, passed_set, failed_set, failure_messages)
        scenario, profile = classify_scenario_and_profile(t)

        if status == "PASS":
            passed_count += 1
        elif status == "FAIL":
            failed_count += 1
        else:
            not_run_count += 1

        results.append({
            "testIdentifier": f"{t['suite']}/{t['function']}",
            "scenario": scenario,
            "profile": profile,
            "sourceFile": t["file"],
            "status": status,
            "round": None,
            "failureCategory": ("TEST_FAILURE" if status == "FAIL" else None),
            "failureMessage": err_msg,
            "ownership": ("swiftAISDKDependency" if "AISDK" in t["suite"] else "hanlinAIProduction") if status == "FAIL" else None
        })

    provenance = {
        "commitSha": get_git_commit_sha(repo_root),
        "ciRunId": os.environ.get("GITHUB_RUN_ID"),
        "workflowName": os.environ.get("GITHUB_WORKFLOW"),
        "timestamp": datetime.datetime.now(datetime.timezone.utc).isoformat(),
        "logSources": [str(p.relative_to(repo_root)).replace("\\", "/") if p.is_relative_to(repo_root) else str(p) for p in log_paths]
    }

    summary = {
        "provenance": provenance,
        "totalTests": len(results),
        "passedCount": passed_count,
        "failedCount": failed_count,
        "notRunCount": not_run_count,
        "results": results
    }

    output_path = Path(args.output) if Path(args.output).is_absolute() else repo_root / args.output
    output_path.parent.mkdir(parents=True, exist_ok=True)
    with open(output_path, "w", encoding="utf-8") as f:
        json.dump(summary, f, indent=2)

    print(f"Provider Conformance Summary generated: {output_path}")
    print(f"  Provenance Commit: {provenance['commitSha']}")
    print(f"  Logs Parsed ({len(log_paths)}): {', '.join([str(p.name) for p in log_paths]) if log_paths else 'None'}")
    print(f"  Total: {len(results)} | PASS: {passed_count} | FAIL: {failed_count} | NOT_RUN: {not_run_count}")

    if args.gate and (failed_count > 0 or not_run_count > 0):
        print(f"GATE FAILED: Conformance summary has {failed_count} failures and {not_run_count} unexecuted tests.", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
