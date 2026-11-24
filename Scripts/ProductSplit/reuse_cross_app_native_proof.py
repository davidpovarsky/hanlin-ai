#!/usr/bin/env python3
"""Authenticate and reuse individual CrossAppInvocationTests, never a failed run.

The caller supplies the current observed native environment and receives exact
method selectors to reuse or execute. No test is run by this module. The original
nine passes, four failures and missing modal suite keep their original identity.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import runpy
import subprocess
import zipfile

DESCRIPTOR = Path("docs/product-split/evidence/cross-app-20261123/native-nine-origin-45294462656.json")
TEST_FILE = "HanlinMiniAppsTests/CrossAppInvocationTests.swift"
PROJECT = "AI_HLY.xcodeproj/project.pbxproj"
PREFIX = "HanlinMiniAppsTests/CrossAppInvocationTests/"


class ProofError(RuntimeError):
    pass


def require(condition, message):
    if not condition:
        raise ProofError(message)


def digest(data):
    return hashlib.sha256(data).hexdigest()


def file_digest(path):
    h = hashlib.sha256()
    with Path(path).open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def command(root, *args):
    return subprocess.check_output(args, cwd=root, text=True, timeout=120).strip()


def description(root):
    return json.loads((Path(root) / DESCRIPTOR).read_text())


def download_origin(root, cache_directory):
    """Use the already downloaded exact ZIP when present; otherwise fetch by ID."""
    spec = description(root)["origin"]
    cache = Path(cache_directory)
    cache.mkdir(parents=True, exist_ok=True)
    archive = cache / ("app-split-" + str(spec["run_id"]) + ".zip")
    if archive.exists():
        require(archive.stat().st_size == spec["artifact_bytes"]
                and file_digest(archive) == spec["artifact_sha256"],
                "Cached original artifact has different bytes")
        return archive
    endpoint = f"repos/{spec['repository']}/actions/artifacts/{spec['artifact_id']}"
    metadata = json.loads(command(root, "gh", "api", endpoint))
    require(metadata["id"] == spec["artifact_id"] and metadata["name"] == spec["artifact_name"]
            and metadata["size_in_bytes"] == spec["artifact_bytes"] and not metadata["expired"],
            "Original GitHub artifact identity changed")
    workflow = metadata.get("workflow_run", {})
    require(workflow.get("id") == spec["run_id"] and workflow.get("head_sha") == spec["source_sha"],
            "Artifact does not belong to the original executed source/run")
    partial = archive.with_suffix(".partial")
    try:
        with partial.open("wb") as stream:
            subprocess.run(["gh", "api", endpoint + "/zip"], cwd=root, stdout=stream,
                           check=True, timeout=600)
        require(partial.stat().st_size == spec["artifact_bytes"]
                and file_digest(partial) == spec["artifact_sha256"],
                "Downloaded original artifact digest differs")
        partial.replace(archive)
    finally:
        partial.unlink(missing_ok=True)
    return archive


def normalized_build_options(argv):
    """Ignore output locations and disposable UDIDs, retain actual compiler flags."""
    ignored_values = {"-derivedDataPath", "-clonedSourcePackagesDirPath", "-resultBundlePath"}
    data, i = {}, 1
    extras = []
    while i < len(argv):
        word = argv[i]
        if word in ignored_values:
            i += 2
            continue
        if word == "-destination":
            parts = dict(p.split("=", 1) for p in argv[i + 1].split(",") if "=" in p)
            data["destination"] = {k: v for k, v in parts.items() if k != "id"}
            i += 2
            continue
        if word in {"-project", "-scheme", "-configuration", "-parallel-testing-enabled", "-sdk"}:
            value = argv[i + 1]
            data[word] = Path(value).name if word == "-project" else value
            i += 2
            continue
        if word not in {"build-for-testing", "test-without-building"} and not word.startswith("-only-testing:"):
            extras.append(word)
        i += 1
    data.setdefault("-configuration", "Debug")
    data["remaining_options"] = extras
    return data


def capture_current_environment(runtime, device, architecture, build_command):
    """Cheap installed-tool probes; runtime/device and command are the runner's actual choices."""
    xcode = subprocess.check_output(["xcodebuild", "-version"], text=True, timeout=30).strip()
    swift = subprocess.check_output(["xcrun", "--find", "swiftc"], text=True, timeout=30).strip()
    toolchain = next((part for part in Path(swift).parts if part.endswith(".xctoolchain")), "")
    overrides = {key: os.environ[key] for key in ("TOOLCHAINS", "SWIFT_EXEC", "XCODE_XCCONFIG_FILE")
                 if os.environ.get(key) and os.environ[key] != "com.apple.dt.toolchain.XcodeDefault"}
    return {
        "xcode": xcode,
        "macos_version": subprocess.check_output(["sw_vers", "-productVersion"], text=True, timeout=30).strip(),
        "macos_build": subprocess.check_output(["sw_vers", "-buildVersion"], text=True, timeout=30).strip(),
        "sdk": subprocess.check_output(["xcrun", "--sdk", "iphonesimulator", "--show-sdk-version"],
                                       text=True, timeout=30).strip(),
        "architecture": architecture,
        "simulator_os": runtime["version"],
        "simulator_build": runtime["buildversion"],
        "device_type": device["identifier"],
        "compiler_toolchain": toolchain,
        "compiler_overrides": overrides,
        "build_options": normalized_build_options(build_command),
    }


def nodes(tree):
    if isinstance(tree, dict):
        if tree.get("nodeType") == "Test Case":
            yield tree
        for value in tree.values():
            if isinstance(value, (dict, list)):
                yield from nodes(value)
    elif isinstance(tree, list):
        for value in tree:
            yield from nodes(value)


def authenticate(root, archive_path, spec):
    origin = spec["origin"]
    archive = Path(archive_path)
    require(archive.stat().st_size == origin["artifact_bytes"]
            and file_digest(archive) == origin["artifact_sha256"],
            "Full original artifact size/SHA256 differs")
    with zipfile.ZipFile(archive) as packed:
        values = {}
        for name, expected in spec["members"].items():
            require(packed.namelist().count(name) == 1, "Ambiguous original member: " + name)
            raw = packed.read(name)
            require(digest(raw) == expected, "Original member digest differs: " + name)
            values[Path(name).name] = json.loads(raw)
        preflight = packed.read("app-split-evidence/preflight.log").decode()
        require(spec["environment"]["xcode"] in preflight, "Original Xcode identity is absent")
        require(spec["environment"]["macos_build"] in preflight
                and spec["environment"]["macos_version"] in preflight,
                "Original host platform identity is absent")
    acceptance, summary, manifest = (values[name] for name in
                                     ("acceptance.json", "test-summary.json", "producer-manifest.json"))
    require(acceptance["sha"] == origin["source_sha"] and acceptance["build"] == "EXECUTED_PASS",
            "Original actual build/source identity differs")
    require(manifest["producer_sha"] == origin["source_sha"]
            and str(manifest["run_id"]) == str(origin["run_id"])
            and manifest["build_status"] == "EXECUTED_PASS",
            "Original product manifest identity differs")
    require(summary["result"] == "Failed" and summary["passedTests"] == 9
            and summary["failedTests"] == 4 and summary["skippedTests"] == 0
            and summary["totalTestCount"] == 13,
            "Original aggregate outcome must remain the authentic failed 9/4/0 run")
    require(acceptance["summary"] == summary, "Original summary and acceptance disagree")
    require(normalized_build_options(acceptance["build_command"]) == spec["environment"]["build_options"],
            "Original build options do not match the descriptor")
    observed = list(nodes(values["test-nodes.json"]))
    passed = {}
    for case in spec["cases"]:
        identifier = "CrossAppInvocationTests/" + case["method"] + "()"
        matching = [node for node in observed if node.get("nodeIdentifier") == identifier
                    and "/HanlinMiniAppsTests/CrossAppInvocationTests/" in node.get("nodeIdentifierURL", "")]
        require(len(matching) == 1 and matching[0]["result"] == "Passed",
                "Missing, repeated or nonpassing original case: " + identifier)
        passed[case["method"]] = matching[0]
    failed = [node for node in observed if node.get("result") == "Failed"]
    require(len(observed) == 13 and len(failed) == 4,
            "Raw nodes do not prove the expected actual execution count")
    require(not any("MiniAppsExternalModalLifetimeUITests/" in node.get("nodeIdentifier", "")
                    for node in observed), "Original missing-modal evidence unexpectedly changed")
    return values, passed, failed


def code_mask(source):
    """Blank strings and comments while preserving positions for brace ownership."""
    chars = list(source)
    i = 0
    quotes = re.compile(r'(#{0,})("""|")')
    while i < len(source):
        start = i
        if source.startswith("//", i):
            i = source.find("\n", i)
            if i < 0:
                i = len(source)
        elif source.startswith("/*", i):
            depth, i = 1, i + 2
            while i < len(source) and depth:
                if source.startswith("/*", i):
                    depth, i = depth + 1, i + 2
                elif source.startswith("*/", i):
                    depth, i = depth - 1, i + 2
                else:
                    i += 1
            require(depth == 0, "Unterminated source comment")
        else:
            quote = quotes.match(source, i)
            if not quote:
                i += 1
                continue
            hashes, marks = quote.groups()
            end = marks + hashes
            i += len(quote.group())
            while i < len(source):
                if source.startswith("\\" + hashes, i):
                    i += len(hashes) + 2
                elif source.startswith(end, i):
                    i += len(end)
                    break
                else:
                    i += 1
            else:
                raise ProofError("Unterminated source string")
        for j in range(start, i):
            if chars[j] != "\n":
                chars[j] = " "
    return "".join(chars)


def brace_end(mask, opening):
    depth = 0
    for i in range(opening, len(mask)):
        if mask[i] == "{":
            depth += 1
        elif mask[i] == "}":
            depth -= 1
            if depth == 0:
                return i + 1
    raise ProofError("Unbalanced source declaration")


def test_parts(source):
    mask = code_mask(source)
    result, pieces, previous = {}, [], 0
    for match in re.finditer(r"(?m)^    (?:[a-zA-Z]+ )*func (test[A-Za-z0-9_]+)\s*\(\s*\)", mask):
        name = match.group(1)
        require(name not in result, "Repeated native test method")
        opening = mask.find("{", match.end())
        require(opening >= 0, "Native test body missing")
        ending = brace_end(mask, opening)
        start = match.start()
        # Attributes belong to the assertion semantics of the following method.
        while start > 0:
            prior = source.rfind("\n", 0, start - 1) + 1
            if source[prior:start].strip().startswith("@"):
                start = prior
            else:
                break
        pieces.append(source[previous:start].strip())
        result[name] = digest(source[start:ending].encode())
        previous = ending
    pieces.append(source[previous:].strip())
    return result, digest("\n".join(piece for piece in pieces if piece).encode())


def project_configuration_matches(old, new):
    """Keep the entire project graph exact except independent new UI test files.

    Original build-file, file-reference and group objects are never removed from
    the comparison: changing their path, sourceTree, fileRef or productRef changes
    the configuration even when a Sources phase still has identical raw IDs.
    """
    try:
        parser_path = Path(__file__).resolve().parents[1] / "CI/IntegrationValidation/project_graph.py"
        parse_project = runpy.run_path(str(parser_path))["parse_project"]
        original, current = parse_project(old), parse_project(new)
        old_objects, new_objects = original["objects"], current["objects"]
        targets = [value for value in old_objects.values()
                   if value.get("isa") == "PBXNativeTarget"
                   and value.get("name") == "HanlinMiniAppsUITests"]
        require(len(targets) == 1, "Original UI test target is missing or ambiguous")
        phases = [identifier for identifier in targets[0]["buildPhases"]
                  if old_objects[identifier].get("isa") == "PBXSourcesBuildPhase"]
        require(len(phases) == 1, "Original UI test source phase is missing or ambiguous")
        phase_id = phases[0]
        old_files = old_objects[phase_id]["files"]
        new_files = new_objects.get(phase_id, {}).get("files")
        if not isinstance(new_files, list) or len(new_files) != len(set(new_files)):
            return False
        additions = set(new_files) - set(old_files)
        if [value for value in new_files if value not in additions] != old_files:
            return False
        removable = set()
        for build_id in additions:
            build = new_objects.get(build_id, {})
            if build_id in old_objects or set(build) != {"isa", "fileRef"}:
                return False
            if build["isa"] != "PBXBuildFile":
                return False
            file_id = build["fileRef"]
            reference = new_objects.get(file_id, {})
            if file_id in old_objects or file_id in removable:
                return False
            if set(reference) != {"isa", "lastKnownFileType", "path", "sourceTree"}:
                return False
            if (reference["isa"] != "PBXFileReference"
                    or reference["lastKnownFileType"] != "sourcecode.swift"
                    or reference["sourceTree"] != "SOURCE_ROOT"
                    or not re.fullmatch(r"HanlinMiniAppsUITests/[A-Za-z0-9_][A-Za-z0-9_.-]*\.swift",
                                        reference["path"])):
                return False
            removable.update((build_id, file_id))
        # No new framework, configuration, group, package or other object is exempt.
        if set(new_objects) - set(old_objects) != removable:
            return False
        for identifier in removable:
            del new_objects[identifier]
        new_objects[phase_id]["files"] = [value for value in new_files if value not in additions]
        return current == original
    except (ValueError, IndexError, KeyError, TypeError) as error:
        raise ProofError("Cannot compare complete project graph: " + str(error)) from error


def ensure_origin_history(root, origin_sha, target_sha):
    """Materialize one bounded ancestry range in a shallow CI checkout if needed."""
    require(re.fullmatch(r"[a-f0-9]{40}", origin_sha)
            and re.fullmatch(r"[a-f0-9]{40}", target_sha), "Source identities must be full commit IDs")
    require(command(root, "git", "rev-parse", "HEAD") == target_sha, "Checkout moved before ancestry admission")
    check = subprocess.run(["git", "merge-base", "--is-ancestor", origin_sha, target_sha],
                           cwd=root, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=30)
    fetched = False
    if check.returncode != 0:
        require(command(root, "git", "rev-parse", "--is-shallow-repository") == "true",
                "Original executed source is not an ancestor of the target")
        # Fetch the exact current target once, never a moving branch or all history.
        subprocess.run(["git", "fetch", "--no-tags", "--deepen=64", "origin", target_sha],
                       cwd=root, check=True, timeout=180)
        fetched = True
        require(command(root, "git", "rev-parse", "HEAD") == target_sha, "Checkout moved while fetching ancestry")
        check = subprocess.run(["git", "merge-base", "--is-ancestor", origin_sha, target_sha],
                               cwd=root, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=30)
    require(check.returncode == 0, "Original executed source ancestry remains unproven after bounded admission")
    return {"origin_sha": origin_sha, "target_sha": target_sha,
            "status": "EXACT_ORIGINAL_ANCESTOR_VERIFIED", "fetched_exact_target_once": fetched,
            "maximum_added_depth": 64 if fetched else 0}


def plan_reuse(root, archive_path, current_environment):
    """Return exact selectors. Missing/changed inputs invalidate individual passes."""
    root = Path(root).resolve()
    spec = description(root)
    values, raw_passed, raw_failed = authenticate(root, archive_path, spec)
    origin = spec["origin"]
    source_inputs = values["source-inputs.json"]
    target_sha = command(root, "git", "rev-parse", "HEAD")
    ancestry = ensure_origin_history(root, origin["source_sha"], target_sha)
    source = subprocess.check_output(["git", "show", origin["source_sha"] + ":" + TEST_FILE],
                                     cwd=root, timeout=30)
    require(digest(source) == source_inputs[TEST_FILE], "Original test source is not the executed input")
    old_methods, old_scaffold = test_parts(source.decode())
    current_source = (root / TEST_FILE).read_text()
    current_methods, current_scaffold = test_parts(current_source)
    status_lines = command(root, "git", "ls-files", "-v").splitlines()
    sparse = {line[2:] for line in status_lines if line.startswith("S ")}
    current_paths = set(command(root, "git", "ls-files", "--cached", "--others", "--exclude-standard").splitlines())
    baseline_paths = set(command(root, "git", "ls-tree", "-r", "--name-only", origin["source_sha"]).splitlines())
    cache = {}
    def current_hash(path):
        if path not in cache:
            file = root / path
            if file.is_file():
                cache[path] = file_digest(file)
            elif path in sparse:
                try:
                    cache[path] = digest(subprocess.check_output(["git", "show", "HEAD:" + path],
                                                                 cwd=root, timeout=30))
                except subprocess.CalledProcessError:
                    cache[path] = None
            else:
                cache[path] = None
        return cache[path]
    env_errors = ["environment:" + key for key, value in spec["environment"].items()
                  if current_environment.get(key) != value]
    original_project = subprocess.check_output(["git", "show", origin["source_sha"] + ":" + PROJECT],
                                                cwd=root, timeout=30)
    require(digest(original_project) == source_inputs[PROJECT], "Original project is not the executed input")
    configuration_errors = []
    try:
        if not project_configuration_matches(original_project.decode(), (root / PROJECT).read_text()):
            configuration_errors.append("project:app-sources-or-target-configuration-changed")
    except ProofError as error:
        configuration_errors.append("project:" + str(error))
    results = []
    for case in spec["cases"]:
        reasons = list(env_errors) + list(configuration_errors)
        if current_methods.get(case["method"]) != old_methods.get(case["method"]):
            reasons.append("test:method-assertions-or-attributes-changed")
        if current_scaffold != old_scaffold:
            reasons.append("test:shared-fixtures-imports-or-class-context-changed")
        paths = set(spec["common_files"])
        prefixes = []
        for group in case["groups"]:
            definition = spec["dependency_groups"][group]
            paths.update(definition.get("files", []))
            prefixes.extend(definition.get("prefixes", []))
        paths.update(path for path in source_inputs if any(path.startswith(prefix) for prefix in prefixes))
        additions = sorted(path for path in current_paths - baseline_paths
                           if any(path.startswith(prefix) for prefix in prefixes))
        reasons.extend("source-added:" + path for path in additions)
        records = {}
        for path in sorted(paths):
            expected = source_inputs.get(path)
            actual = current_hash(path)
            records[path] = {"expected": expected, "actual": actual}
            if expected is None or actual != expected:
                reasons.append("source:" + path)
        status = "INVALIDATED" if reasons else "REUSED_VERIFIED_PASS"
        results.append({
            "selector": PREFIX + case["method"], "status": status,
            "original_status": "EXECUTED_PASS", "original_node": raw_passed[case["method"]],
            "origin_run_id": origin["run_id"], "origin_sha": origin["source_sha"],
            "assertion_sha256": old_methods[case["method"]], "dependency_groups": case["groups"],
            "input_fingerprint": digest(json.dumps(records, sort_keys=True).encode()),
            "dependency_input_count": len(records), "invalidation_reasons": reasons,
            "scope": case["scope"],
        })
    reusable = [entry["selector"] for entry in results if entry["status"] == "REUSED_VERIFIED_PASS"]
    rerun = [entry["selector"] for entry in results if entry["status"] != "REUSED_VERIFIED_PASS"]
    return {
        "schema_version": 1, "status": "VERIFIED_INDIVIDUAL_CASE_REUSE_PLAN",
        "target_sha": target_sha, "source_ancestry": ancestry, "origin": origin, "artifact_path": str(Path(archive_path).resolve()),
        "origin_overall_status": values["acceptance.json"]["status"],
        "origin_test_plan_result": values["test-summary.json"]["result"],
        "origin_failed_test_count": 4, "origin_missing_modal_status": "NOT_RUN",
        "origin_failed_nodes": raw_failed,
        "origin_missing_selector": "HanlinMiniAppsUITests/MiniAppsExternalModalLifetimeUITests",
        "current_environment": current_environment, "cases": results,
        "reusable_selectors": reusable, "rerun_selectors": rerun,
        "reused_count": len(reusable), "must_execute_count": len(rerun),
        "fresh_tests_executed_by_verifier": 0,
        "acceptance_scope": "Nine individual native cases only; four original UI failures and omitted modal still require execution. No workflow, whole-app, signing or consumer acceptance is granted.",
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[2])
    parser.add_argument("--artifact", type=Path)
    parser.add_argument("--cache", type=Path)
    parser.add_argument("--environment-json", type=Path, required=True)
    parser.add_argument("--out", type=Path, required=True)
    args = parser.parse_args()
    if args.artifact:
        artifact = args.artifact
    else:
        require(args.cache is not None, "Provide an authenticated artifact or an explicit download cache")
        artifact = download_origin(args.root, args.cache)
    result = plan_reuse(args.root, artifact, json.loads(args.environment_json.read_text()))
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(json.dumps(result, indent=2, ensure_ascii=False) + "\n")
    print(json.dumps({key: result[key] for key in ("status", "reused_count", "must_execute_count",
                                                "reusable_selectors", "rerun_selectors")}))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
