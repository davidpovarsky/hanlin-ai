"""Build-only acceptance after the exact ZIP pin; preserve all original outcomes."""
import copy
import hashlib
import json
from pathlib import Path
import re
import shutil

import verify_native_tool_cancellation_recheck as original

SELECTOR = "HanlinNativeToolPinBuildRecheck"
REFERENCE_PATH = "Scripts/CI/Tests/Fixtures/native-pin-build-07431"
REFERENCE_SHA256 = "658be86c8ca893b5b9fab37ab16df1e632304fdd82d2d7eb4369abe5ebfd77f0"
PRODUCER = original.PRODUCER
UNRELATED_FLAGS = original.UNRELATED_FLAGS
NULL_EXITS = original.OLD_NULL_EXITS + ("native_core_test_exit", "native_sdk_test_exit")
MANIFEST = "Packages/HanlinPlatform/Package.swift"
PROOF_PATH = "docs/agent-sdk/evidence/foundation-models-tool-candidate-20261123/apple-45292176348"


def read(path):
    return json.loads(path.read_text())


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def require(condition, message):
    if not condition:
        raise ValueError("Native pin-build admission rejected: " + message)


def safe(root, relative):
    path = Path(relative)
    require(not path.is_absolute() and ".." not in path.parts, "evidence path escaped root")
    return root / path


def graph(text, root):
    matches = re.findall(r"note: Target dependency graph \((\d+) targets\)", text)
    require(len(matches) == 1, "missing/ambiguous original target graph")
    segment = text.split("note: Target dependency graph", 1)[1].split("GatherProvisioningInputs", 1)[0]
    nodes, node = {}, None
    for line in segment.splitlines()[1:]:
        if not line.strip():
            continue
        target = re.fullmatch(r"    Target '([^']+)' in project '([^']+)'(?: \(no dependencies\))?", line)
        edge = re.fullmatch(r"        ➜ Explicit dependency on target '([^']+)' in project '([^']+)'", line)
        if target:
            node = target.groups()
            require(node not in nodes, "duplicate graph target")
            nodes[node] = []
        elif edge and node:
            nodes[node].append(edge.groups())
        else:
            raise ValueError("Unrecognized original graph row: " + line)
    require(len(nodes) == int(matches[0]) and root in nodes and
            all(dependency in nodes for edges in nodes.values() for dependency in edges),
            "incomplete target graph")
    pending, closure = [root], set()
    while pending:
        node = pending.pop()
        if node not in closure:
            closure.add(node)
            pending.extend(nodes[node])
    return dict(nodes=[dict(target=list(node), dependencies=[list(edge) for edge in edges])
                       for node, edges in sorted(nodes.items())],
                closure=[list(node) for node in sorted(closure)])


def reference(evidence):
    folder = evidence / "pin-build-reference"
    require(sha(folder / "reference.json") == REFERENCE_SHA256, "frozen pin reference changed")
    manifest = read(folder / "reference.json")
    before, after = (folder / "manifest-before.swift").read_bytes(), (folder / "manifest-after.swift").read_bytes()
    require(hashlib.sha256(before).hexdigest() == manifest["manifest_before_sha256"] and
            hashlib.sha256(after).hexdigest() == manifest["manifest_after_sha256"] and
            before.count(b'.upToNextMinor(from: "0.9.19")') == 1 and
            before.replace(b'.upToNextMinor(from: "0.9.19")', b'exact: "0.9.19"') == after,
            "pin is not the exact reviewed one-line constraint change")
    proof = evidence / "pin-build-original"
    for relative, digest in manifest["proof_files_sha256"].items():
        require(sha(safe(proof, relative)) == digest, "original proof file changed: " + relative)
    actual = {str(path.relative_to(proof)) for path in proof.rglob("*") if path.is_file()
              and "cancellation-reuse-original" not in path.relative_to(proof).parts}
    require(actual == set(manifest["proof_files_sha256"]), "original proof inventory differs")
    original.frozen_reference(proof / "original/cancellation-reuse-original")
    return manifest, proof


def command(evidence, name):
    matching = [item for item in read(evidence / "commands.json") if item["name"] == name]
    require(len(matching) == 1, "missing/duplicate command: " + name)
    item = matching[0]
    for stream in ("stdout", "stderr"):
        record = item[stream]
        require(sha(safe(evidence, record["file"])) == record["sha256"], "command output changed: " + name)
    return item


def expected_source(manifest, proof):
    expected = read(proof / "original/tested-source-sha256.json")
    require(len(expected) == 404 and expected[MANIFEST] == manifest["manifest_before_sha256"],
            "original complete source map differs")
    expected[MANIFEST] = manifest["manifest_after_sha256"]
    return expected


def pins(evidence, name, expected):
    path = evidence / (name + "-Package.resolved")
    value = read(path)
    require(set(value) == {"originHash", "pins", "version"} and
            re.fullmatch(r"[0-9a-f]{64}", value["originHash"]) is not None and
            value["version"] == expected["version"] == 3 and value["pins"] == expected["pins"],
            "actual pre-build resolver pins differ: " + name)
    return dict(file=path.name, sha256=sha(path), originHash=value["originHash"], pins=value["pins"])


def validate_reuse(evidence):
    manifest, proof = reference(evidence)
    old = proof / "original"
    run, artifact = read(proof / "terminal-run.json"), read(proof / "artifact-receipt.json")
    require(run["id"] == manifest["original_run_id"] and run["run_attempt"] == 1 and
            run["head_sha"] == manifest["original_source"] and run["status"] == "completed" and
            run["conclusion"] == "failure", "original run binding changed")
    require(artifact["artifact_id"] == manifest["original_artifact_id"] and
            artifact["source"] == manifest["original_source"] and artifact["run_id"] == run["id"] and
            artifact["zip_sha256"] == manifest["original_zip_sha256"] and artifact["acquisition_count"] == 1 and
            artifact["api_digest_verified"] is True and artifact["zip_crc"] == "PASS",
            "original artifact custody differs")
    reproduced = json.loads(json.dumps(original.summarize(old)))
    require(reproduced == read(old / "summary.json") and reproduced["status"] == "BLOCKED" and
            reproduced["errors"] == ["Native cancellation admission rejected: post-build lock changed"] and
            len(reproduced["cases"]) == 15 and len(reproduced["methods"]) == 7 and
            all(case["status"] == "PASS" and case["execution"] == "EXECUTED" for case in reproduced["cases"]),
            "original 15 complete accepted leaves or strict failure differ")
    require(reproduced["ios_agent_core_compile"] == "BLOCKED" and
            reproduced["process_status"]["ios_build_exit"] == 0 and
            reproduced["process_status"]["native_core_test_exit"] == 0 and
            reproduced["process_status"]["native_sdk_test_exit"] == 0,
            "original command attribution differs")
    for label in ("NativeCoreTests", "NativeSDKTests"):
        item = command(old, label)
        require(item["exit_code"] == 0 and b"** TEST SUCCEEDED **" in safe(old, item["stdout"]["file"]).read_bytes(),
                "original test command did not succeed")
    old_ios = command(old, "IOSBuild")
    require(old_ios["exit_code"] == 0 and b"** BUILD SUCCEEDED **" in safe(old, old_ios["stdout"]["file"]).read_bytes(),
            "original successful build command lost")
    graphs = {}
    for label, root, counts in (
        ("NativeCoreTests", ("HanlinChatCoreTests-product", "HanlinPlatform"), (73, 22)),
        ("NativeSDKTests", ("HanlinAgentCoreTests-product", "HanlinAgentSDK"), (40, 32)),
        ("IOSBuild", ("HanlinAgentCore-product", "HanlinAgentSDK"), (30, 30)),
    ):
        item = command(old, label)
        parsed = graph(safe(old, item["stdout"]["file"]).read_text(), root)
        require((len(parsed["nodes"]), len(parsed["closure"])) == counts and
                not any(node[1] == "ZIPFoundation" for node in parsed["closure"]),
                "ZIP enters an original selected source closure")
        if label != "NativeCoreTests":
            require(not any(node["target"][1] == "ZIPFoundation" for node in parsed["nodes"]),
                    "ZIP enters the original SDK build graph")
        graphs[label] = parsed
    old_posts = read(old / "post-build-resolution.json")
    require(len(old_posts) == 2, "original raw post-lock inventory changed")
    for name, directory in (("sdk", "HanlinAgentSDK"), ("core", "HanlinPlatform")):
        entries = [row for row in old_posts if row["source_path"].endswith("/Packages/" + directory + "/Package.resolved")]
        require(len(entries) == 1, "original raw package path changed")
        row = entries[0]
        raw = safe(old, row["raw_file"])
        require(sha(raw) == row["sha256"] and read(raw) == row["resolved"], "original raw post-lock not bound")
        before, after = read(old / (name + "-Package.resolved")), read(raw)
        if name == "core":
            require(raw.read_bytes() == (old / "core-Package.resolved").read_bytes(), "original Core raw lock changed")
        else:
            expected = copy.deepcopy(before)
            zip_pin = next(pin for pin in expected["pins"] if pin["identity"] == "zipfoundation")
            require(zip_pin["state"] == dict(revision="02b6abe5f6eef7e3cbd5f247c5cc24e246efcfe0", version="0.9.19"),
                    "original intended ZIP pin differs")
            zip_pin["state"] = dict(revision="e7048f0569f0ba37df26f8357f560b9d25e9a284", version="0.9.21")
            expected["originHash"] = after["originHash"]
            require(after == expected, "original SDK drift exceeds the authenticated ZIP change")
    source = (evidence / "tested-source-commit.txt").read_text().strip()
    require(source == (evidence / "workflow-commit.txt").read_text().strip() and
            (evidence / "producer-commit.txt").read_text().strip() == PRODUCER,
            "current source/workflow/producer differs")
    require(read(evidence / "tested-source-sha256.json") == expected_source(manifest, proof),
            "current source differs beyond the exact ZIP constraint")
    common = ("Scripts/CI/IntegrationValidation/verify_native_tool_candidate.py",
              "Scripts/CI/IntegrationValidation/verify_native_tool_cancellation_recheck.py",
              "Scripts/CI/IntegrationValidation/xcresult_to_xunit.py", "Scripts/CI/select_stable_xcode.py")
    current_workflow, prior_workflow = read(evidence / "workflow-sha256.json"), read(old / "workflow-sha256.json")
    require(all(current_workflow[path] == prior_workflow[path] for path in common), "old strict guard/toolchain selector changed")
    for name in original.TOOLCHAIN:
        current, prior = command(evidence, name), command(old, name)
        require(current["exit_code"] == prior["exit_code"] == 0 and
                safe(evidence, current["stdout"]["file"]).read_bytes() ==
                safe(old, prior["stdout"]["file"]).read_bytes(), "toolchain/OS observation changed: " + name)
    intended = read(old / "sdk-Package.resolved")
    actual_pins = {name: pins(evidence, name, intended) for name in ("sdk", "core")}
    cli = read(evidence / "cli-resolution.json")
    require(len(cli) == 2 and {row["package"] for row in cli} == {"sdk", "core"}, "two CLI resolver observations required")
    for row in cli:
        raw = safe(evidence, row["file"])
        value = read(raw)
        require(sha(raw) == row["sha256"] and value == row["resolved"] and
                set(value) == {"originHash", "pins", "version"} and
                re.fullmatch(r"[0-9a-f]{64}", value["originHash"]) is not None and
                value["pins"] == intended["pins"] and value["version"] == intended["version"],
                "CLI resolution changed an intended pin")
        resolved = command(evidence, row["package"] + "-resolve")
        require(resolved["exit_code"] == 0 and resolved["argv"][:5] == ["xcrun", "swift", "package", "--package-path", str(Path(row["source_path"]).parent)] and
                resolved["argv"][5:] == ["resolve"], "CLI resolver provenance differs")
    resolve = command(evidence, "XcodeResolve")
    argv = resolve["argv"]
    require(len(argv) == 8 and argv[:7] == ["xcodebuild", "-resolvePackageDependencies", "-scheme", "HanlinAgentCore",
            "-destination", "generic/platform=iOS Simulator", "-derivedDataPath"] and
            Path(argv[7]).name == "IOSDerivedData" and
            resolve["cwd"].endswith("/Packages/HanlinAgentSDK") and resolve["exit_code"] == 0,
            "wrong explicit Xcode resolver command")
    require("ZIPFoundation: https://github.com/weichsel/ZIPFoundation.git @ 0.9.19" in
            safe(evidence, resolve["stdout"]["file"]).read_text(), "resolver did not report intended ZIP version")
    pre = read(evidence / "pre-build-resolution.json")
    require(pre["resolver_command"] == "XcodeResolve" and
            pre["captured_utc"] >= resolve["finished_utc"] and len(pre["locks"]) == 2,
            "actual pre-build raw locks were not captured after the resolver")
    for name, directory in (("sdk", "HanlinAgentSDK"), ("core", "HanlinPlatform")):
        entries = [row for row in pre["locks"] if row["package"] == name]
        require(len(entries) == 1 and entries[0]["source_path"].endswith("/Packages/" + directory + "/Package.resolved") and
                entries[0]["file"] == name + "-Package.resolved" and
                entries[0]["sha256"] == actual_pins[name]["sha256"],
                "actual resolver raw lock provenance differs")
    checkout_proof(evidence, "before")
    native15 = copy.deepcopy(reproduced["cases"])
    for case in native15:
        case.update(execution="REUSED_VERIFIED", original_execution="EXECUTED",
                    run_id=manifest["original_run_id"], run_attempt=1,
                    source_commit=manifest["original_source"], producer_commit=PRODUCER,
                    artifact_id=manifest["original_artifact_id"])
    prior21 = reproduced["reused_cases"]
    require(len(native15) == 15 and len(prior21) == 21 and
            len({case["id"] for case in native15 + prior21}) == 36, "complete reused case partition differs")
    return dict(mode="REUSED_VERIFIED", current_source_commit=source, producer_commit=PRODUCER,
                reference_sha256=REFERENCE_SHA256, original_summary_status="BLOCKED",
                original_strict_error=reproduced["errors"], original_reproduction="PASS",
                source_difference={MANIFEST: dict(before=manifest["manifest_before_sha256"],
                                                  after=manifest["manifest_after_sha256"])},
                native15_cases=native15, prior21_cases=prior21,
                historical_baseline_cases=reproduced["reuse_admission"]["historical_baseline_cases"],
                historical_baseline_current_equivalence=False, original_target_graphs=graphs,
                current_pre_build_locks=actual_pins)


def checkout_proof(evidence, phase):
    proof = read(evidence / ("producer-checkouts-" + phase + ".json"))
    expected = read(evidence / "pin-build-original/original/cancellation-reuse-original/producer-07431-sha256.json")
    require(set(proof) == {"sdk", "core", "xcode"}, "all actual producer checkouts are required")
    suffixes = {
        "sdk": "/Packages/HanlinAgentSDK/.build/checkouts/swift-ai-sdk",
        "core": "/Packages/HanlinPlatform/.build/checkouts/swift-ai-sdk",
        "xcode": "/IOSDerivedData/SourcePackages/checkouts/swift-ai-sdk",
    }
    for name, entry in proof.items():
        require(entry["path"].endswith(suffixes[name]) and entry["commit"] == PRODUCER and
                entry["status"] == "" and entry["source_sha256"] == expected,
                "actual producer checkout changed: " + phase + "/" + name)
        item = command(evidence, name + "-" + phase + "-producer-status")
        require(item["argv"] == ["git", "status", "--porcelain", "--untracked-files=all", "--", "Package.swift", "Sources"] and
                item["cwd"] == entry["path"] and item["exit_code"] == 0 and
                safe(evidence, item["stdout"]["file"]).read_bytes() == b"", "checkout cleanliness command differs")
    return proof


def prepare_reference(repository, evidence):
    source = repository / REFERENCE_PATH
    shutil.copytree(source, evidence / "pin-build-reference")
    manifest = read(source / "reference.json")
    shutil.copytree(repository / manifest["proof_repository_path"], evidence / "pin-build-original")
    shutil.copytree(repository / manifest["prior_reference_repository_path"],
                    evidence / "pin-build-original/original/cancellation-reuse-original")


def validate_execution(evidence, statuses, reuse):
    route = read(evidence / "selected-route.json")
    require(route["exact_test_selector"] == SELECTOR and route["target_validation_group"] == "agent_sdk_exact_source_proof" and
            type(route["current_test_invocations"]) is int and route["current_test_invocations"] == 0 and route["baseline"] == "HISTORICAL_REFERENCE_ONLY",
            "wrong build-only opt-in route")
    require(set(route["unrelated_flags"]) == set(UNRELATED_FLAGS) and
            all(value is False or value == "false" for value in route["unrelated_flags"].values()),
            "unrelated workflow flag enabled/missing")
    require(all(key in statuses and statuses[key] is None for key in NULL_EXITS) and
            type(statuses["current_test_invocations"]) is int and statuses["current_test_invocations"] == 0 and
            statuses["native15_execution"] == statuses["accepted_cases_execution"] == "REUSED_VERIFIED" and
            statuses["baseline_execution"] == "HISTORICAL_REFERENCE_ONLY",
            "unexecuted tests were attributed as current execution")
    commands = read(evidence / "commands.json")
    for item in commands:
        argv = item["argv"]
        require(not any(value in {"test", "test-without-building", "build-for-testing", "simctl"} or
                        value.startswith("-only-testing:") for value in argv), "build-only route invoked tests/simulator")
        command(evidence, item["name"])
    resolves = [item for item in commands if item["argv"][:2] == ["xcodebuild", "-resolvePackageDependencies"]]
    builds = [item for item in commands if item["argv"][:2] == ["xcodebuild", "build"]]
    require(len(resolves) == len(builds) == 1 and builds[0]["name"] == "IOSBuild", "one resolver and one current build required")
    require(type(statuses.get("ios_resolve_exit")) is int and statuses["ios_resolve_exit"] == resolves[0]["exit_code"] == 0,
            "current resolver exit was not preserved")
    item = builds[0]
    argv = item["argv"]
    expected = ["xcodebuild", "build", "-scheme", "HanlinAgentCore", "-destination",
                "generic/platform=iOS Simulator", "-derivedDataPath", None, "-resultBundlePath", None,
                "-disableAutomaticPackageResolution", "-skipPackagePluginValidation", "-skipMacroValidation",
                "CODE_SIGNING_ALLOWED=NO"]
    require(len(argv) == len(expected) and all(value is None or argv[index] == value for index, value in enumerate(expected)) and
            Path(argv[7]).name == "IOSDerivedData" and Path(argv[9]).name == "IOSBuild.xcresult" and
            item["cwd"].endswith("/Packages/HanlinAgentSDK") and
            argv[7] == resolves[0]["argv"][7] and item["cwd"] == resolves[0]["cwd"], "wrong current iOS build command")
    require(type(statuses.get("ios_build_exit")) is int and statuses["ios_build_exit"] == item["exit_code"] == 0 and
            statuses["ios_build_execution"] == "EXECUTED", "fresh affected iOS build did not succeed")
    pre = read(evidence / "pre-build-resolution.json")
    require(pre["captured_utc"] <= item["started_utc"], "pre-build lock was captured after the build")
    stdout = safe(evidence, item["stdout"]["file"]).read_text()
    require("** BUILD SUCCEEDED **" in stdout, "current successful build marker absent")
    require("ZIPFoundation: https://github.com/weichsel/ZIPFoundation.git @ 0.9.19" in stdout,
            "current build did not resolve intended ZIP version")
    current_graph = graph(stdout, ("HanlinAgentCore-product", "HanlinAgentSDK"))
    require(current_graph == reuse["original_target_graphs"]["IOSBuild"], "current compiled target graph changed")
    posts = read(evidence / "post-build-resolution.json")
    require(len(posts) == 2 and len({row["raw_file"] for row in posts}) == 2, "two distinct actual post-build raw locks required")
    for name, directory in (("sdk", "HanlinAgentSDK"), ("core", "HanlinPlatform")):
        rows = [row for row in posts if row["source_path"].endswith("/Packages/" + directory + "/Package.resolved")]
        require(len(rows) == 1, "wrong post-build package lock")
        row = rows[0]
        path = safe(evidence, row["raw_file"])
        require(sha(path) == row["sha256"] and read(path) == row["resolved"] and
                path.read_bytes() == (evidence / (name + "-Package.resolved")).read_bytes(),
                "post-build raw dependency lock changed")
    after = checkout_proof(evidence, "after")
    before = checkout_proof(evidence, "before")
    require(after == before, "producer source changed across the build")
    return dict(mode="EXECUTED", command=item, raw_locks="BYTE_IDENTICAL_BEFORE_AND_AFTER_BUILD",
                producer_checkouts=["core", "sdk", "xcode"], target_graph=current_graph)


def summarize(evidence):
    errors, reuse, build = [], None, None
    try:
        statuses = read(evidence / "process-status.json")
    except (OSError, ValueError):
        statuses = {}
    try:
        reuse = validate_reuse(evidence)
        require(read(evidence / "pin-build-reuse.json") == reuse, "reuse receipt differs")
        build = validate_execution(evidence, statuses, reuse)
    except (OSError, ValueError, KeyError, TypeError, IndexError) as error:
        errors.append(str(error))
    passed = not errors and reuse is not None and build is not None and type(statuses.get("preparation_exit")) is int and statuses["preparation_exit"] == 0
    return dict(scope="Exact ZIP pin; fresh dependent iOS build; zero current tests",
                status="PASS" if passed else "BLOCKED", errors=errors,
                current_test_invocations=0, current_test_cases=[],
                reuse_admission=reuse, process_status=statuses,
                reused_native15_cases=[] if reuse is None else reuse["native15_cases"],
                reused_prior21_cases=[] if reuse is None else reuse["prior21_cases"],
                historical_baseline_execution="HISTORICAL_REFERENCE_ONLY",
                historical_baseline_current_equivalence=False,
                ios_agent_core_compile="PASS" if build is not None else
                    "NOT_RUN" if statuses.get("ios_build_exit") is None else
                    "BLOCKED" if statuses.get("ios_build_exit") == 0 else "FAIL",
                current_ios_build=build, shipping_native_tool_capability=False, system_model_generation="NOT_RUN")
