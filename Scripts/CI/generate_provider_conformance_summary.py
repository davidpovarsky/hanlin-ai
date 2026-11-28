#!/usr/bin/env python3
"""
generate_provider_conformance_summary.py
Generates machine-checkable provider conformance summary artifact conforming to Section 24.
Parses actual executed test logs to determine PASS / FAIL / NOT_RUN / EVIDENCE_ERROR status with full provenance.
Enforces fail-safe exact identity matching:
- Canonical function identity (e.g. from aka 'funcName()' or funcName())
- Exact complete display name equality ONLY when unambiguous across source definitions
- Rejects prefix, substring, and scenario-tag fallbacks
- Fails closed on ambiguous evidence or missing execution
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
    "*test*.log",
    "xcodebuild.log"
]


class TestExecutionRecord:
    def __init__(self, function_name=None, display_name=None, suite_name=None, status="PASS", cases=None, message=""):
        self.function_name = function_name
        self.display_name = display_name
        self.suite_name = suite_name
        self.status = status  # "PASS" or "FAIL"
        self.cases = cases  # Optional[int] for parameterized tests
        self.message = message

    def __repr__(self):
        return (f"TestExecutionRecord(fn={self.function_name!r}, dn={self.display_name!r}, "
                f"suite={self.suite_name!r}, status={self.status}, cases={self.cases})")


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
    func_pattern = re.compile(r'func\s+(test\w+)\s*\(')

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

                    for fm in func_pattern.finditer(content):
                        func_name = fm.group(1)
                        func_start = fm.start()
                        lookback_start = max(0, func_start - 2000)
                        prefix = content[lookback_start:func_start]
                        last_delim = max(prefix.rfind("func "), prefix.rfind("}\n"))
                        if last_delim != -1:
                            prefix = prefix[last_delim:]

                        display_name = None
                        test_attr_m = re.search(r'@Test\s*\(\s*"([^"]+)"', prefix)
                        if test_attr_m:
                            display_name = test_attr_m.group(1)

                        tests.append({
                            "suite": current_suite,
                            "function": func_name,
                            "displayName": display_name,
                            "file": str(file_path.relative_to(repo_root)).replace("\\", "/")
                        })
    return tests


def parse_test_logs(log_paths):
    records = []

    # Swift Testing pass
    swift_test_pass_pattern = re.compile(
        r"✔\s+Test\s+(?:\"(?P<display>[^\"]+)\"|(?P<raw_func>\w+)(?:\(\))?)"
        r"(?:\s+\(aka\s+'(?P<aka_func>\w+)(?:\(\))?'\))?"
        r"(?:\s+with\s+(?P<cases>\d+)\s+test\s+cases)?"
        r"\s+passed(?:\s+after\b.*)?",
        re.UNICODE
    )
    # Swift Testing fail
    swift_test_fail_pattern = re.compile(
        r"✘\s+Test\s+(?:\"(?P<display>[^\"]+)\"|(?P<raw_func>\w+)(?:\(\))?)"
        r"(?:\s+\(aka\s+'(?P<aka_func>\w+)(?:\(\))?'\))?"
        r"(?:\s+with\s+(?P<cases>\d+)\s+test\s+cases)?"
        r"\s+failed(?:\s+after\b.*)?",
        re.UNICODE
    )
    # XCTest pass
    xctest_pass_pattern = re.compile(
        r"Test\s+[Cc]ase\s+'(?:-\[(?P<oc_suite>\w+)\s+(?P<oc_func>\w+)\]|(?P<swift_suite>\w+)\.(?P<swift_func>\w+)|(?P<bare_func>\w+))'\s+passed"
    )
    # XCTest fail
    xctest_fail_pattern = re.compile(
        r"Test\s+[Cc]ase\s+'(?:-\[(?P<oc_suite>\w+)\s+(?P<oc_func>\w+)\]|(?P<swift_suite>\w+)\.(?P<swift_func>\w+)|(?P<bare_func>\w+))'\s+failed"
    )

    for log_path in log_paths:
        if not log_path.exists():
            continue
        try:
            with open(log_path, "r", encoding="utf-8", errors="replace") as f:
                content = f.read()

            # Strip interleaved OS log lines
            content = re.sub(r'\d{4}-\d{2}-\d{2}\s+\d{2}:\d{2}:\d{2}\.\d+[+-]\d{4}\s+[^\n]*\n?', '', content)

            for line in content.splitlines():
                # Swift Testing pass
                m = swift_test_pass_pattern.search(line)
                if m:
                    aka = m.group("aka_func")
                    raw = m.group("raw_func")
                    disp = m.group("display")
                    cases = int(m.group("cases")) if m.group("cases") else None
                    func = aka or raw
                    records.append(TestExecutionRecord(
                        function_name=func,
                        display_name=disp.strip() if disp else None,
                        status="PASS",
                        cases=cases,
                        message=line.strip()
                    ))
                    continue

                # Swift Testing fail
                m = swift_test_fail_pattern.search(line)
                if m:
                    aka = m.group("aka_func")
                    raw = m.group("raw_func")
                    disp = m.group("display")
                    cases = int(m.group("cases")) if m.group("cases") else None
                    func = aka or raw
                    records.append(TestExecutionRecord(
                        function_name=func,
                        display_name=disp.strip() if disp else None,
                        status="FAIL",
                        cases=cases,
                        message=line.strip()
                    ))
                    continue

                # XCTest pass
                m = xctest_pass_pattern.search(line)
                if m:
                    suite = m.group("oc_suite") or m.group("swift_suite")
                    func = m.group("oc_func") or m.group("swift_func") or m.group("bare_func")
                    records.append(TestExecutionRecord(
                        function_name=func,
                        suite_name=suite,
                        status="PASS",
                        message=line.strip()
                    ))
                    continue

                # XCTest fail
                m = xctest_fail_pattern.search(line)
                if m:
                    suite = m.group("oc_suite") or m.group("swift_suite")
                    func = m.group("oc_func") or m.group("swift_func") or m.group("bare_func")
                    records.append(TestExecutionRecord(
                        function_name=func,
                        suite_name=suite,
                        status="FAIL",
                        message=line.strip()
                    ))
                    continue
        except Exception as e:
            print(f"Warning: Failed to parse log {log_path}: {e}", file=sys.stderr)

    return records


def match_test_status(test, execution_records, tests_by_display):
    """
    Matches an individual source test against execution records with fail-safe exact identity.
    Returns: (status: str, error_message: Optional[str], parameterized_cases: Optional[int])
    Status is one of: PASS, FAIL, NOT_RUN, EVIDENCE_ERROR.
    """
    target_func = test["function"]
    target_display = test.get("displayName")
    target_suite = test.get("suite")

    matching_records = []
    has_ambiguity = False

    for rec in execution_records:
        # Case 1: Exact canonical function name available
        if rec.function_name:
            if rec.function_name == target_func:
                if rec.suite_name and target_suite and rec.suite_name != target_suite:
                    continue  # Suite mismatch
                matching_records.append(rec)
            else:
                # Record explicitly names a different function. It CANNOT match this test.
                continue

        # Case 2: No function name on record, but display name available
        elif rec.display_name and target_display:
            # Exact complete display name equality required
            if rec.display_name == target_display:
                # Check for ambiguity among source definitions
                candidates = tests_by_display.get(target_display, [])
                if len(candidates) > 1:
                    has_ambiguity = True
                else:
                    matching_records.append(rec)
            # Prefix, substring, or fuzzy matches are strictly forbidden

    if has_ambiguity and not matching_records:
        return "EVIDENCE_ERROR", f"Ambiguous display name '{target_display}' matches multiple source tests without canonical function identity", None

    if not matching_records:
        return "NOT_RUN", None, None

    # Check for FAIL first
    failing_records = [r for r in matching_records if r.status == "FAIL"]
    if failing_records:
        return "FAIL", failing_records[0].message, None

    # Check for PASS
    passing_records = [r for r in matching_records if r.status == "PASS"]
    if passing_records:
        cases = max((r.cases for r in passing_records if r.cases is not None), default=None)
        return "PASS", None, cases

    return "NOT_RUN", None, None


def classify_scenario_and_profile(test):
    func = test["function"]
    display = test.get("displayName") or ""
    scenario = "Unknown"
    profile = "allApplicable"

    # Scenario matching
    for tag in [
        "S01", "S02", "S03", "S04", "S05", "S06", "S07", "S08", "S09", "S10",
        "S11", "S12", "S13", "S14", "S15", "S16",
        "F01", "F02", "F03", "F04", "F05", "F06", "F07", "F08", "F09",
        "P01", "P02", "P03", "P04", "P05", "P06", "P07", "P08", "P09", "P10",
        "P11", "P12A", "P12B", "P12"
    ]:
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
    parser.add_argument("--gate", action="store_true", help="Exit with code 1 if any test is NOT_RUN or FAIL or EVIDENCE_ERROR")
    parser.add_argument("--allow-unexecuted", action="store_true", help="Allow NOT_RUN tests when gating (fail only on FAIL or EVIDENCE_ERROR)")
    args = parser.parse_args()

    repo_root = Path(args.repo_root).resolve() if args.repo_root else Path(__file__).resolve().parent.parent.parent
    tests = scan_test_definitions(repo_root)

    # Index tests by display name for ambiguity detection
    tests_by_display = {}
    for t in tests:
        dn = t.get("displayName")
        if dn:
            tests_by_display.setdefault(dn, []).append(t)

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

    execution_records = parse_test_logs(log_paths)

    results = []
    passed_count = 0
    failed_count = 0
    not_run_count = 0
    evidence_error_count = 0
    total_parameterized_cases = 0

    for t in tests:
        status, err_msg, cases = match_test_status(t, execution_records, tests_by_display)
        scenario, profile = classify_scenario_and_profile(t)

        if status == "PASS":
            passed_count += 1
            if cases is not None:
                total_parameterized_cases += cases
        elif status == "FAIL":
            failed_count += 1
        elif status == "EVIDENCE_ERROR":
            evidence_error_count += 1
        else:
            not_run_count += 1

        results.append({
            "testIdentifier": f"{t['suite']}/{t['function']}",
            "scenario": scenario,
            "profile": profile,
            "sourceFile": t["file"],
            "status": status,
            "round": None,
            "parameterizedCases": cases,
            "failureCategory": ("TEST_FAILURE" if status == "FAIL" else ("EVIDENCE_ERROR" if status == "EVIDENCE_ERROR" else None)),
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
        "sourceTestFunctionCount": len(results),
        "totalTests": len(results),
        "passedCount": passed_count,
        "failedCount": failed_count,
        "notRunCount": not_run_count,
        "evidenceErrorCount": evidence_error_count,
        "parameterizedCaseCount": total_parameterized_cases,
        "results": results
    }

    output_path = Path(args.output) if Path(args.output).is_absolute() else repo_root / args.output
    output_path.parent.mkdir(parents=True, exist_ok=True)
    with open(output_path, "w", encoding="utf-8") as f:
        json.dump(summary, f, indent=2)

    print(f"Provider Conformance Summary generated: {output_path}")
    print(f"  Provenance Commit: {provenance['commitSha']}")
    print(f"  Logs Parsed ({len(log_paths)}): {', '.join([str(p.name) for p in log_paths]) if log_paths else 'None'}")
    print(f"  Conformance Test Functions: {len(results)} | PASS: {passed_count} | FAIL: {failed_count} | NOT_RUN: {not_run_count} | EVIDENCE_ERROR: {evidence_error_count}")
    if total_parameterized_cases > 0:
        print(f"  Parameterized Cases Counted: {total_parameterized_cases}")

    gate_failed = (failed_count > 0 or evidence_error_count > 0 or (not_run_count > 0 and not args.allow_unexecuted))
    if args.gate and gate_failed:
        print(f"GATE FAILED: Conformance summary has {failed_count} failures, {not_run_count} unexecuted tests, and {evidence_error_count} evidence errors.", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
