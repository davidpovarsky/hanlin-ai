"""Partition original UI selectors by real viewport; never build or replace tests."""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import plistlib
import re

if __package__:
    from .current_unit_xctestrun import bundle_files, contained, descriptors, product_path, sha256
    from .verify_selected_tests import missing_selectors
else:
    from current_unit_xctestrun import bundle_files, contained, descriptors, product_path, sha256
    from verify_selected_tests import missing_selectors

ROOT = Path(__file__).resolve().parents[2]
PROFILE = Path(__file__).with_suffix(".json")
BUNDLE = "AI_HLYUITests"


def checked_profile(root=ROOT, profile_path=PROFILE):
    profile = json.loads(Path(profile_path).read_text())
    if profile.get("schema_version") != 1:
        raise ValueError("Unsupported UI viewport profile")
    for suite, rule in profile["suites"].items():
        declared = re.findall(r"\bfunc (test\w+)\(", (Path(root) / rule["source"]).read_text())
        if set(declared) != set(rule["methods"]) or len(declared) != len(rule["methods"]):
            raise ValueError("Original viewport suite membership changed: " + suite)
        if not set(rule["methods"].values()) <= {"iPad", "iPhone"}:
            raise ValueError("Unknown original viewport family")
    return profile


def plan(selectors, profile=None):
    profile = checked_profile() if profile is None else profile
    requested = list(dict.fromkeys(s.strip().removesuffix("()") for s in selectors.split(",") if s.strip()))
    if any(not re.fullmatch(r"AI_HLYUITests(?:/[A-Za-z0-9_]+(?:/[A-Za-z0-9_]+)?)?", s) for s in requested):
        raise ValueError("Viewport cohorts accept only original UI selectors")
    rules = profile["suites"]
    expanded = []
    for selector in requested:
        if selector in rules:
            expanded.extend(selector + "/" + name for name in rules[selector]["methods"])
        else:
            expanded.append(selector)
    if BUNDLE in requested:
        # The original full-bundle request retains every unclassified test.
        # Its compact cases execute exactly once, in the second cohort.
        expanded.extend(suite + "/" + name for suite, rule in rules.items()
                        for name, family in rule["methods"].items() if family == "iPhone")
    expanded = list(dict.fromkeys(expanded))
    families = {"iPad": [], "iPhone": []}
    for selector in expanded:
        parts = selector.split("/")
        suite = "/".join(parts[:2])
        family = rules.get(suite, {}).get("methods", {}).get(parts[-1], "iPad")
        if len(parts) == 3 and suite in rules and parts[-1] not in rules[suite]["methods"]:
            raise ValueError("Unclassified viewport method: " + selector)
        families[family].append(selector)
    cohorts = []
    for family, label in [("iPad", "wide"), ("iPhone", "compact")]:
        if not families[family]:
            continue
        skip = families["iPhone"] if family == "iPad" and BUNDLE in families[family] else []
        first = not cohorts
        cohorts.append({
            "id": label, "family": family, "selectors": families[family], "skip_selectors": skip,
            "results_file": "08-nativescript-production-ui-test-results.json" if first else "08-compact-ui-test-results.json",
            "result_bundle": "NativeScriptProductionE2EResult.xcresult" if first else "CompactUITestsResult.xcresult",
            "log_file": "08-nativescript-production-ui-tests.log" if first else "08-compact-ui-tests.log",
        })
    return {"schema_version": 1, "requested_selectors": requested,
            "expanded_selectors": expanded, "cohorts": cohorts, "application_builds_planned": 1,
            "boundary": "Original app UI only; does not satisfy paired-product acceptance"}


def verify_union(plan_value, result_documents):
    combined = {"testNodes": []}
    missing = {}
    failed = []
    for cohort in plan_value["cohorts"]:
        result = result_documents.get(cohort["id"])
        if result is None:
            missing[cohort["id"]] = cohort["selectors"]
            continue
        absent = missing_selectors(result, cohort["selectors"])
        if absent:
            missing[cohort["id"]] = absent
        pending = list(result.get("testNodes", []))
        while pending:
            node = pending.pop()
            pending.extend(node.get("children", []))
            if node.get("nodeType") == "Test Case" and node.get("result") == "Failed":
                failed.append(node.get("nodeIdentifierURL") or node.get("nodeIdentifier", "unknown"))
        combined["testNodes"].extend(result.get("testNodes", []))
    union_missing = missing_selectors(combined, plan_value["expanded_selectors"])
    return {"status": "MISSING_COVERAGE" if missing or union_missing else ("FAILED_TESTS" if failed else "EXECUTED_COVERAGE"),
            "failed_cases": failed,
            "cohort_missing": missing, "union_missing": union_missing,
            "requested_selectors": plan_value["requested_selectors"],
            "qualification": "Execution membership only; xcodebuild retains every native failure"}


def product_snapshot(derived_data, admitted_manifest=None):
    products = (Path(derived_data) / "Build/Products").resolve(strict=True)
    candidates = descriptors(products)
    if len(candidates) != 1:
        raise ValueError("Expected one original current-build xctestrun")
    manifest = candidates[0]
    if admitted_manifest and Path(admitted_manifest).resolve(strict=True) != manifest:
        raise ValueError("UI cohorts must use the already admitted current-build xctestrun")
    document = plistlib.loads(manifest.read_bytes())
    version = document.get("__xctestrun_metadata__", {}).get("FormatVersion", 1)
    if version == 1:
        targets = [document[BUNDLE]] if BUNDLE in document else []
    elif version == 2:
        targets = [target for configuration in document.get("TestConfigurations", [])
                   if configuration.get("IsEnabled", True)
                   for target in configuration.get("TestTargets", [])
                   if target.get("BlueprintName") == BUNDLE and target.get("IsEnabled", True)]
    else:
        raise ValueError("Unsupported original xctestrun format")
    if (len(targets) != 1 or targets[0].get("IsUITestBundle") is not True
            or targets[0].get("BlueprintName", BUNDLE) != BUNDLE
            or targets[0].get("IsEnabled", True) is not True):
        raise ValueError("Original UI target is missing or ambiguous in current products")
    target = targets[0]
    host = product_path(target.get("TestHostPath"), products)
    test = product_path(target.get("TestBundlePath"), products, host)
    app = product_path(target.get("UITargetAppPath"), products)
    if test.name != BUNDLE + ".xctest" or app.name != "AI_Hanlin.app":
        raise ValueError("Current manifest does not use the original UI/app products")
    files = bundle_files(app, "com.itorah.chavrusachat", products)
    for bundle in [host, test]:
        info = plistlib.loads(contained(bundle / "Info.plist", products, kind="file").read_bytes())
        files.extend(bundle_files(bundle, info["CFBundleIdentifier"], products))
    return {"manifest": str(manifest), "manifest_sha256": sha256(manifest),
            "files": sorted(files, key=lambda item: item["path"])}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="action", required=True)
    p = sub.add_parser("plan")
    p.add_argument("--selectors", default="")
    p.add_argument("--output", type=Path, required=True)
    p.add_argument("--primary", action="store_true")
    p = sub.add_parser("rows")
    p.add_argument("--plan", type=Path, required=True)
    p = sub.add_parser("verify")
    p.add_argument("--plan", type=Path, required=True)
    p.add_argument("--log-dir", type=Path, required=True)
    p.add_argument("--output", type=Path, required=True)
    p = sub.add_parser("products")
    p.add_argument("--derived-data", type=Path, required=True)
    p.add_argument("--admitted-manifest")
    p.add_argument("--output", type=Path, required=True)
    p.add_argument("--match", type=Path)
    args = parser.parse_args()
    if args.action == "plan":
        result = plan(args.selectors)
        result["profile_sha256"] = hashlib.sha256(PROFILE.read_bytes()).hexdigest()
        args.output.write_text(json.dumps(result, indent=2) + "\n")
        if args.primary:
            print(",".join(result["cohorts"][0]["selectors"]) if result["cohorts"] else "")
    elif args.action == "rows":
        for cohort in json.loads(args.plan.read_text())["cohorts"]:
            print("\t".join([cohort["id"], cohort["family"], ",".join(cohort["selectors"]),
                             ",".join(cohort["skip_selectors"]) or "-", cohort["results_file"],
                             cohort["result_bundle"], cohort["log_file"]]))
    elif args.action == "products":
        result = product_snapshot(args.derived_data, args.admitted_manifest)
        args.output.write_text(json.dumps(result, indent=2) + "\n")
        if args.match and result != json.loads(args.match.read_text()):
            raise SystemExit("Original UI products changed between viewport cohorts")
        print(result["manifest"])
    else:
        value = json.loads(args.plan.read_text())
        documents = {cohort["id"]: json.loads((args.log_dir / cohort["results_file"]).read_text())
                     for cohort in value["cohorts"] if (args.log_dir / cohort["results_file"]).is_file()}
        result = verify_union(value, documents)
        args.output.write_text(json.dumps(result, indent=2) + "\n")
        if result["status"] != "EXECUTED_COVERAGE":
            raise SystemExit("Original UI viewport coverage is incomplete")


if __name__ == "__main__":
    main()
