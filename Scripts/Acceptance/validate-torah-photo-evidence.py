#!/usr/bin/env python3
"""
validate-torah-photo-evidence.py — Torah Photo Study Evidence Validator
Validates test-results.jsonl against schema, assertions, required tests, zero-tests check,
mock hygiene, and gate constraints per Section 15.2.
"""

import sys
import json
import argparse
from pathlib import Path

REQUIRED_PREFIXES = ["BASE", "SKL", "MCP", "LIB", "OCR", "MAT", "ENR", "AGT", "UI", "SEC", "PERF", "REG", "E2E"]


def main():
    parser = argparse.ArgumentParser(description="Torah Photo Study Evidence Validator")
    parser.add_argument("--input", default="test-results.jsonl", help="Input JSONL path")
    parser.add_argument("--fixtures", default="Tests/Fixtures/TorahPhotoStudy/manifest.json", help="Fixtures manifest")
    parser.add_argument("--allow-blocked", action="store_true", default=True, help="Allow BLOCKED status for tiers lacking physical device/live credentials")
    args = parser.parse_args()

    repo_dir = Path(__file__).resolve().parent.parent.parent
    input_path = repo_dir / args.input
    fixtures_path = repo_dir / args.fixtures

    errors = []
    warnings = []

    if not input_path.exists():
        print(f"FATAL: Evidence file not found at {input_path}")
        sys.exit(1)

    records = []
    with open(input_path, "r", encoding="utf-8") as f:
        for idx, line in enumerate(f, 1):
            line = line.strip()
            if not line:
                continue
            try:
                rec = json.loads(line)
                records.append((idx, rec))
            except Exception as e:
                errors.append(f"Line {idx}: JSON parse error: {e}")

    # Zero tests check
    if not records:
        print("FATAL: Evidence file contains 0 test records.")
        sys.exit(1)

    seen_keys = set()
    counts = {"PASS": 0, "BLOCKED": 0, "FAIL": 0, "NOT_RUN": 0, "NOT_APPLICABLE": 0}
    seen_prefixes = set()

    for line_num, rec in records:
        # Schema version check
        if rec.get("schemaVersion") != 1:
            errors.append(f"Line {line_num}: schemaVersion must be 1, found {rec.get('schemaVersion')}")

        test_id = rec.get("testID")
        tier = rec.get("tier")
        status = rec.get("status")

        if not test_id or not tier:
            errors.append(f"Line {line_num}: Missing testID or tier")
            continue

        prefix = test_id.split("-")[0]
        seen_prefixes.add(prefix)

        key = (test_id, tier)
        if key in seen_keys:
            errors.append(f"Line {line_num}: Duplicate record for ({test_id}, {tier})")
        seen_keys.add(key)

        counts[status] = counts.get(status, 0) + 1

        # Check PASS validity
        if status == "PASS":
            if not rec.get("startedAt") or not rec.get("finishedAt"):
                errors.append(f"{test_id} ({tier}): PASS status must have valid timestamps")
            if not rec.get("assertions") and tier in ["T1", "T2"]:
                errors.append(f"{test_id} ({tier}): PASS status in deterministic tier must have non-empty assertions")

        # Mock hygiene check
        if tier in ["T3", "T5"] and rec.get("status") == "PASS":
            mocks = rec.get("mocksUsed", [])
            if mocks:
                errors.append(f"{test_id} ({tier}): Mock used in live tier ({mocks}); violates live evidence rules")

        # BLOCKED validity
        if status == "BLOCKED":
            if not rec.get("blockers") and not rec.get("reason"):
                errors.append(f"{test_id} ({tier}): BLOCKED status must provide blockers or explicit reason")

    # Check for all required prefixes
    for req_p in REQUIRED_PREFIXES:
        if req_p not in seen_prefixes:
            errors.append(f"Missing required test prefix: {req_p}")

    # Fixture validation
    if fixtures_path.exists():
        with open(fixtures_path, "r", encoding="utf-8") as f:
            f_data = json.load(f)
            fixtures = f_data.get("fixtures", [])
            if len(fixtures) < 60:
                warnings.append(f"Fixture manifest has {len(fixtures)} items; recommended 60")
            calib = [f for f in fixtures if f.get("split") == "calibration"]
            holdout = [f for f in fixtures if f.get("split") == "holdout"]
            if not calib or not holdout:
                errors.append("Fixture manifest must have both calibration and holdout splits")
    else:
        warnings.append(f"Fixtures manifest not found at {fixtures_path}")

    # Print summary
    print("=" * 60)
    print("Torah Photo Study Evidence Validation Report")
    print("=" * 60)
    print(f"Total Records Validated: {len(records)}")
    print(f"Unique Test/Tier Pairs:  {len(seen_keys)}")
    print(f"PASS:                   {counts['PASS']}")
    print(f"BLOCKED:                {counts['BLOCKED']}")
    print(f"FAIL:                   {counts['FAIL']}")
    print(f"NOT_RUN:                {counts['NOT_RUN']}")
    print(f"NOT_APPLICABLE:         {counts['NOT_APPLICABLE']}")
    print("-" * 60)

    if warnings:
        print(f"WARNINGS ({len(warnings)}):")
        for w in warnings:
            print(f"  [WARN] {w}")

    if errors:
        print(f"ERRORS ({len(errors)}):")
        for e in errors:
            print(f"  [ERROR] {e}")
        print("\nGATE STATUS: FAILED")
        sys.exit(1)
    else:
        print("\nGATE STATUS: PASSED (All records valid and schema-compliant)")
        sys.exit(0)


if __name__ == "__main__":
    main()
