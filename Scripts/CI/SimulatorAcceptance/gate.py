"""Fail-closed app UI acceptance. Component results cannot satisfy this contract."""
from __future__ import annotations

import argparse
from collections import Counter
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys

HERE = Path(__file__).resolve().parent
POLICY_PATH = HERE / "contract.json"
STATUSES = ("EXECUTED_PASS", "REUSED_VERIFIED_PASS", "FAILED", "SKIPPED", "NOT_RUN", "BLOCKED")


class GateError(ValueError):
    pass


def require(condition, message):
    if not condition:
        raise GateError(message)


def digest(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def read(path: Path):
    return json.loads(path.read_text(encoding="utf-8"))


def write(path: Path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, indent=2) + "\n", encoding="utf-8", newline="\n")


def safe_path(root: Path, relative: str) -> Path:
    require(isinstance(relative, str) and relative and "\\" not in relative, "Invalid evidence path")
    require(not Path(relative).is_absolute() and ".." not in Path(relative).parts, "Invalid relative evidence path")
    path = (root / relative).resolve()
    require(path.is_relative_to(root.resolve()) and path != root.resolve(), "Evidence path escapes its root")
    return path


def git(repo: Path, *args) -> str:
    return subprocess.check_output(["git", "-C", str(repo), *args], text=True).strip()


def required_tags(policy, locale):
    # RTL is an obligation of the Hebrew cohort; English is validated in LTR.
    return set(policy["required_coverage_tags"]) - ({"rtl"} if locale == "en" else set())


def prepare(repo: Path, build_number: str, policy_path: Path = POLICY_PATH, allow_incomplete=False):
    require(re.fullmatch(r"[0-9]+", build_number), "Exact candidate build number required")
    policy = read(policy_path)
    coverage_path = safe_path(repo, policy["coverage_file"])
    require(coverage_path.is_file(), "Frozen QA coverage contract is missing; no release UI acceptance")
    coverage = read(coverage_path)
    require(coverage.get("schema_version") == 1, "Unsupported QA coverage schema")
    require(coverage.get("cases"), "Empty QA coverage contract")
    require(allow_incomplete or not coverage.get("required_gaps"), "Required platform/coverage gaps remain open")
    inputs = {policy_path.relative_to(repo).as_posix(): digest(policy_path.read_bytes()),
              policy["coverage_file"]: digest(coverage_path.read_bytes())}
    variants = []
    gaps = list(coverage.get("required_gaps", []))
    all_selectors = []
    for case in coverage["cases"]:
        selector = case["selector"]
        require(re.fullmatch(r"AI_HLYUITests/[A-Za-z_][A-Za-z_0-9]*/test[A-Za-z_0-9]+", selector), "Actual app UI selector required")
        require(case.get("device_families") and set(case["device_families"]) <= set(policy["device_families"]), "Unknown/missing case device families")
        require(case.get("locales") and set(case["locales"]) <= set(policy["locales"]), "Unknown/missing case locales")
        require(case.get("coverage_tags"), "Case coverage mapping is missing")
        suite, method = selector.split("/")[1:]
        source = safe_path(repo, f"AI_HLYUITests/{suite}.swift")
        require(source.is_file(), f"Missing whole owner test file: {source.name}")
        text = source.read_text(encoding="utf-8-sig")
        require(re.search(r"\bclass\s+" + re.escape(suite) + r"\s*:\s*XCTestCase\b", text), "Selector is not in a real XCTest UI suite")
        require(len(re.findall(r"\bfunc\s+" + re.escape(method) + r"\s*\(", text)) == 1, "Missing/duplicate owner test method")
        inputs[source.relative_to(repo).as_posix()] = digest(source.read_bytes())
        for fixture in case.get("fixture_paths", []):
            path = safe_path(repo, fixture)
            require(path.is_file(), f"Missing QA fixture: {fixture}")
            inputs[fixture] = digest(path.read_bytes())
        all_selectors.append(selector)
    require(len(all_selectors) == len(set(all_selectors)), "Duplicate QA selector")
    for family in policy["device_families"]:
        for locale in policy["locales"]:
            selected = [case for case in coverage["cases"] if family in case["device_families"] and locale in case["locales"]]
            tags = {tag for case in selected for tag in case["coverage_tags"]}
            require(selected, f"No authored app UI cases for {family}/{locale}")
            missing = sorted(required_tags(policy, locale) - tags)
            if missing:
                gaps.append({"variant": f"{family}-{locale}", "missing_coverage_tags": missing})
            require(allow_incomplete or not missing, f"Incomplete required coverage for {family}/{locale}: {missing}")
            variants.append({"id": f"{family}-{locale}", "family": family, "locale": locale,
                             "selectors": [case["selector"] for case in selected]})
    sha = git(repo, "rev-parse", "HEAD")
    require(re.fullmatch(r"[0-9a-f]{40}", sha), "Exact candidate source SHA required")
    for relative, expected in inputs.items():
        try:
            committed = subprocess.check_output(["git", "-C", str(repo), "show", f"{sha}:{relative}"], stderr=subprocess.PIPE)
        except subprocess.CalledProcessError:
            raise GateError(f"Acceptance input must be frozen in candidate Git: {relative}") from None
        require(digest(committed) == expected, f"Dirty/unfrozen acceptance input: {relative}")
    return {"schema_version": 1, "scope": policy["scope"], "candidate_source_sha": sha,
            "candidate_tree": git(repo, "rev-parse", "HEAD^{tree}"), "build_number": build_number,
            "contract_sha256": digest(policy_path.read_bytes()), "configuration": policy["configuration"],
            "app_bundle_id": policy["app_bundle_id"], "inputs_sha256": inputs, "variants": variants,
            "release_eligible": not gaps, "coverage_gaps": gaps,
            "reuse": "NOT_REQUESTED", "execution": "NOT_RUN"}


def nodes(value):
    if isinstance(value, dict):
        yield value
        for child in value.values():
            yield from nodes(child)
    elif isinstance(value, list):
        for child in value:
            yield from nodes(child)


def test_identity(node):
    raw = node.get("nodeIdentifier") or node.get("nodeIdentifierURL", "")
    return "/".join(str(raw).rstrip("/").split("/")[-2:]).removesuffix("()")


def summarize(root: Path, plan, policy):
    """Recompute results from raw xcresult exports, never trust a caller's counts."""
    cases = []
    errors = []
    for variant in plan["variants"]:
        folder = safe_path(root, variant["id"])
        expected = [selector.split("/", 1)[1] for selector in variant["selectors"]]
        actual = []
        records = {}
        raw_path = folder / "tests.json"
        try:
            raw = read(raw_path)
            actual = [node for node in nodes(raw) if node.get("nodeType") == "Test Case"]
            require(Counter(test_identity(node) for node in actual) == Counter(expected), "Missing, duplicate or unexpected actual test cases")
            devices = raw.get("devices", [])
            require(devices, "Actual executed-device export is missing")
            require(all(str(d.get("osVersion", "")).split(".")[0] == str(policy["runtime_major"])
                        and str(d.get("modelName", "")).startswith(variant["family"]) for d in devices), "Wrong actual OS/device family")
            context = read(folder / "context.json")
            require(context["family"] == variant["family"] and context["locale"] == variant["locale"], "Matrix environment mismatch")
            require(context["configuration"] == policy["configuration"], "Non-publication configuration")
            require(context["source_sha"] == plan["candidate_source_sha"] and context["build_number"] == plan["build_number"], "Candidate/build mismatch")
            require(context["bundle_id"] == policy["app_bundle_id"], "Component/foreign app cannot satisfy app gate")
            require(str(context["sdk_version"]).split(".")[0] == str(policy["runtime_major"]), "Wrong simulator SDK")
            require(context["xcode_version"].startswith("Xcode 27.") and context["runner_os"] == "Darwin", "Actual stable Xcode 27 Mac required")
            require(isinstance(context.get("xcodebuild_exit_code"), int), "UI process result missing")
            if context["xcodebuild_exit_code"] != 0:
                errors.append(f"{variant['id']}: UI process exited {context['xcodebuild_exit_code']}")
            creation = read(folder / "device-creation.json")
            require(creation.get("created_by_this_run") is True and creation.get("was_in_original_inventory") is False
                    and creation.get("preexisting_app_container") is False, "Destructive fixtures require a fresh dedicated simulator/container")
            require(creation.get("device_udid") == context.get("device_udid") and context.get("device_udid"), "Simulator creation receipt does not match execution")
            normalize_id = lambda value: str(value).replace("-", "").lower()
            require(all(normalize_id(d.get("deviceId", "")) == normalize_id(context["device_udid"]) for d in devices), "Actual executed device is not the newly created simulator")
            require((folder / "Tests.xcresult/Info.plist").is_file(), "Raw xcresult missing")
            attachments = read(folder / "case-attachments.json")
            for identity in expected:
                require(attachments.get(identity), f"No retained screenshot for {identity}")
                for relative in attachments[identity]:
                    path = safe_path(folder, relative)
                    require(path.is_file() and path.stat().st_size > 0 and path.suffix.lower() in {".png", ".jpg", ".jpeg"}, "Missing screenshot bytes")
                    image_header = path.read_bytes()[:8]
                    require(image_header == b"\x89PNG\r\n\x1a\n" or image_header.startswith(b"\xff\xd8"), "Screenshot is not PNG/JPEG data")
            records = {test_identity(node): node for node in actual}
        except (OSError, ValueError, KeyError, TypeError) as error:
            errors.append(f"{variant['id']}: {error}")
        for identity in expected:
            node = records.get(identity)
            result = str(node.get("result", "")) if node else ""
            status = {"Passed": "EXECUTED_PASS", "Failed": "FAILED", "Skipped": "SKIPPED"}.get(result, "NOT_RUN")
            # Preserve observed failures even when provenance/attachments fail.
            observed = next((n for n in actual if test_identity(n) == identity), None)
            if not records and observed:
                status = {"Failed": "FAILED", "Skipped": "SKIPPED"}.get(observed.get("result"), "BLOCKED")
            cases.append({"variant": variant["id"], "selector": f"AI_HLYUITests/{identity}", "status": status})
    counts = {status: sum(case["status"] == status for case in cases) for status in STATUSES}
    passed = bool(cases) and not errors and not plan.get("coverage_gaps") and plan.get("release_eligible") is True and counts["EXECUTED_PASS"] == len(cases)
    return {"schema_version": 1, "status": "PASS" if passed else "BLOCKED", "scope": policy["scope"],
            "candidate_source_sha": plan["candidate_source_sha"], "build_number": plan["build_number"],
            "contract_sha256": plan["contract_sha256"], "counts": counts, "cases": cases, "errors": errors,
            "coverage_gaps": plan.get("coverage_gaps", []), "release_eligible": plan.get("release_eligible", False)}


def verify(root: Path, build_number: str, source_sha: str, policy_path: Path = POLICY_PATH):
    policy = read(policy_path)
    plan = read(root / "plan.json")
    require(plan.get("scope") == policy["scope"], "Component/isolated proof is not full app UI acceptance")
    require(plan.get("release_eligible") is True and not plan.get("coverage_gaps"), "Authored partial UI execution cannot satisfy comprehensive release coverage")
    require(plan.get("contract_sha256") == digest(policy_path.read_bytes()), "UI contract differs from current version")
    require(plan.get("configuration") == policy["configuration"], "Candidate configuration mismatch")
    require(plan.get("candidate_source_sha") == source_sha and plan.get("build_number") == build_number, "UI evidence is for another candidate/build")
    require(re.fullmatch(r"[0-9a-f]{40}", source_sha) and re.fullmatch(r"[0-9]+", build_number), "Invalid candidate identity")
    require(plan.get("variants"), "Empty acceptance matrix")
    require({(v["family"], v["locale"]) for v in plan["variants"]} ==
            {(f, l) for f in policy["device_families"] for l in policy["locales"]}, "Incomplete acceptance matrix")
    require(len(plan["variants"]) == len(policy["device_families"]) * len(policy["locales"]), "Duplicate acceptance matrix entry")
    for variant in plan["variants"]:
        require(variant["id"] == f"{variant['family']}-{variant['locale']}" and variant.get("selectors"), "Invalid/empty matrix entry")
        require(len(variant["selectors"]) == len(set(variant["selectors"])), "Duplicate required case")
    # The complete frozen coverage and test/fixture inputs are retained, including
    # cases' applicability. A claimed plan cannot silently shrink that contract.
    archived = root / "inputs"
    policy_relative = "Scripts/CI/SimulatorAcceptance/contract.json"
    require(plan.get("inputs_sha256", {}).get(policy_relative) == plan["contract_sha256"], "Current contract bytes not bound to source inputs")
    require(policy["coverage_file"] in plan["inputs_sha256"], "Coverage contract not bound to source inputs")
    for path, expected in plan["inputs_sha256"].items():
        require(digest(safe_path(archived, path).read_bytes()) == expected, "Retained source/fixture bytes differ")
    coverage = read(safe_path(archived, policy["coverage_file"]))
    require(coverage.get("schema_version") == 1 and coverage.get("cases") and not coverage.get("required_gaps"), "Invalid archived coverage")
    selectors = [case["selector"] for case in coverage["cases"]]
    require(len(selectors) == len(set(selectors)), "Duplicate archived required case")
    for case in coverage["cases"]:
        require(re.fullmatch(r"AI_HLYUITests/[A-Za-z_][A-Za-z_0-9]*/test[A-Za-z_0-9]+", case["selector"]), "Non-app archived selector")
        suite = case["selector"].split("/")[1]
        require(f"AI_HLYUITests/{suite}.swift" in plan["inputs_sha256"], "Whole owner test source not retained")
        require(all(path in plan["inputs_sha256"] for path in case.get("fixture_paths", [])), "Fixture inputs not retained")
    for variant in plan["variants"]:
        selected = [case for case in coverage["cases"] if variant["family"] in case["device_families"] and variant["locale"] in case["locales"]]
        require(variant["selectors"] == [case["selector"] for case in selected], "Required cases were omitted or substituted")
        require(required_tags(policy, variant["locale"]) <= {tag for case in selected for tag in case["coverage_tags"]}, "Coverage tags missing")
    require(all(str(item).startswith("AI_HLYUITests/") for v in plan["variants"] for item in v["selectors"]), "Wrong test target")
    result = summarize(root, plan, policy)
    write(root / "summary.json", result)
    require(result["status"] == "PASS", "Required actual app UI obligations did not all pass")
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=["plan", "verify"])
    parser.add_argument("--repo", type=Path, default=Path.cwd())
    parser.add_argument("--evidence", type=Path, required=True)
    parser.add_argument("--build-number", required=True)
    parser.add_argument("--source-sha")
    parser.add_argument("--allow-incomplete-coverage", action="store_true", help="Plan authored execution only; never enables publication")
    args = parser.parse_args()
    try:
        if args.action == "plan":
            plan = prepare(args.repo.resolve(), args.build_number, allow_incomplete=args.allow_incomplete_coverage)
            write(args.evidence / "plan.json", plan)
            for relative, expected in plan["inputs_sha256"].items():
                data = safe_path(args.repo, relative).read_bytes()
                require(digest(data) == expected, "Inputs changed during preparation")
                target = safe_path(args.evidence / "inputs", relative)
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_bytes(data)
            print(json.dumps({"status": "PREPARED_NOT_EXECUTED", "variants": len(plan["variants"]), "obligations": sum(len(v["selectors"]) for v in plan["variants"])}))
        else:
            require(args.source_sha, "Exact source SHA required")
            result = verify(args.evidence, args.build_number, args.source_sha)
            print(json.dumps({"status": result["status"], "counts": result["counts"]}))
    except (GateError, OSError, KeyError, TypeError) as error:
        write(args.evidence / "gate-rejection.json", {"status": "BLOCKED", "reason": str(error),
              "counts": {s: 0 for s in STATUSES}, "required_count": "UNKNOWN_UNTIL_VALID_CONTRACT"})
        sys.exit(str(error))


if __name__ == "__main__":
    main()
