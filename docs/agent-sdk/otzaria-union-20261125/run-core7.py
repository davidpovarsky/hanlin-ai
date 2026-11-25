#!/usr/bin/env python3
"""Run the unchanged original Core continuation tests against the complete pinned SDK.

This is a focused downstream proof package, not an alternative SDK or a live
provider test. It copies only two original test files after verifying their Git
blobs. All implementation products come from the original remote dependency.
"""
import argparse
import datetime
import hashlib
import json
import os
from pathlib import Path
import platform
import shutil
import signal
import subprocess
import sys
import time
import traceback
import xml.etree.ElementTree as ET

CORE = "abf0921c6e89e6521cc2b510ff11016b45a0ef08"
CORE_TREE = "f094f58f7956903e740a5188cf1e9d43c126248e"
ARGUMENT_PARSER = "6a52f3251125d74daf04fcbd5e6f08a75d074382"
TESTS = [
    "Tests/SwiftAISDKTests/GenerateText/StreamTextThoughtSignatureContinuationTests.swift",
    "Tests/SwiftAISDKTests/GenerateText/StreamTextToolResultContinuationTests.swift",
]
EXPECTED = {
    ("SwiftAISDKTests.StreamTextThoughtSignatureContinuationTests", "signedSequentialContinuation()"),
    ("SwiftAISDKTests.StreamTextToolResultContinuationTests", "twoToolConversation(reason:)"),
    ("SwiftAISDKTests.StreamTextToolResultContinuationTests", "toolErrorContinuesWithoutReexecution()"),
    ("SwiftAISDKTests.StreamTextToolResultContinuationTests", "budgetStopsContinuation()"),
    ("SwiftAISDKTests.StreamTextToolResultContinuationTests", "missingToolOutputStopsContinuation()"),
    ("SwiftAISDKTests.StreamTextToolResultContinuationTests", "textCompletionStopsNormally()"),
}
PACKAGE = '''// swift-tools-version: 6.2
import PackageDescription
let package = Package(
    name: "OtzariaCoreContinuationProof",
    platforms: [.macOS(.v26)],
    dependencies: [
        .package(url: "https://github.com/davidpovarsky/swift-ai-sdk.git",
                 revision: "abf0921c6e89e6521cc2b510ff11016b45a0ef08"),
        .package(url: "https://github.com/apple/swift-argument-parser", exact: "1.8.2")
    ],
    targets: [
        .testTarget(
            name: "SwiftAISDKTests",
            dependencies: [
                .product(name: "SwiftAISDK", package: "swift-ai-sdk"),
                .product(name: "AISDKProvider", package: "swift-ai-sdk"),
                .product(name: "AISDKProviderUtils", package: "swift-ai-sdk"),
                .product(name: "OpenAICompatibleProvider", package: "swift-ai-sdk")
            ],
            path: "OriginalTests"
        )
    ],
    swiftLanguageModes: [.v6]
)
'''

def require(condition, message):
    if not condition:
        raise RuntimeError(message)

def sha(raw):
    return hashlib.sha256(raw).hexdigest()

def git(repository, *arguments):
    return subprocess.check_output(["git", "-C", str(repository), *arguments])

def write(path, value):
    path.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n")

def inventory(repository):
    require(git(repository, "rev-parse", "HEAD").decode().strip() == CORE, "Wrong Core checkout")
    require(git(repository, "rev-parse", "HEAD^{tree}").decode().strip() == CORE_TREE, "Wrong Core tree")
    require(not git(repository, "status", "--porcelain=v1", "--untracked-files=all"), "Core checkout is dirty")
    rows = []
    for item in git(repository, "ls-tree", "-rz", CORE, "--",
                    "Package.swift", "Package.resolved", "Sources", *TESTS).split(b"\0"):
        if not item:
            continue
        description, raw_path = item.split(b"\t", 1)
        mode, kind, blob = description.decode().split()
        relative = raw_path.decode()
        require(kind == "blob" and mode in {"100644", "100755", "120000"},
                "Unsupported source input: " + relative)
        path = repository / relative
        raw = os.fsencode(os.readlink(path)) if mode == "120000" else path.read_bytes()
        require(hashlib.sha1(b"blob " + str(len(raw)).encode() + b"\0" + raw).hexdigest() == blob,
                "Core source differs from its exact commit: " + relative)
        rows.append(dict(path=relative, mode=mode, git_blob=blob, bytes=len(raw), sha256=sha(raw)))
    require(len(rows) > 100 and set(TESTS).issubset({r["path"] for r in rows}), "Incomplete Core inputs")
    return dict(source=CORE, tree=CORE_TREE, files=rows)

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--hanlin-source", required=True)
    parser.add_argument("--core-checkout", required=True, type=Path)
    parser.add_argument("--warm-cache", required=True, type=Path)
    parser.add_argument("--proof-root", required=True, type=Path)
    parser.add_argument("--scratch", required=True, type=Path)
    parser.add_argument("--anticipated-concurrent-growth-gib", required=True, type=float)
    parser.add_argument("--os-margin-gib", required=True, type=float)
    args = parser.parse_args()
    require(platform.system() == "Darwin" and platform.machine() == "arm64", "Real Apple arm64 runner required")
    require(len(args.hanlin_source) == 40 and all(c in "0123456789abcdef" for c in args.hanlin_source),
            "Exact Hanlin source is required")
    require(not args.proof_root.exists() and not args.scratch.exists(), "Proof/cache path already exists")
    require(args.anticipated_concurrent_growth_gib >= 0 and args.os_margin_gib >= 0, "Invalid resource budget")
    available = shutil.disk_usage(args.proof_root.parent).free
    need = int((1 + args.anticipated_concurrent_growth_gib + args.os_margin_gib) * 1024**3)
    require(available >= need, "Storage admission failed: actual free bytes are below this explicit incremental plan")
    args.proof_root.mkdir()
    evidence = args.proof_root / "evidence"
    evidence.mkdir()
    result = dict(
        status="NOT_RUN", hanlin_source=args.hanlin_source, core_source=CORE,
        original_test_methods=6, expected_scenario_invocations=7,
        live_provider_test=False, original_full_suite_reexecuted=False,
        prior_core48_reexecuted=False, runner_sha256=sha(Path(__file__).read_bytes()),
        disk_admission=dict(free_bytes=available, own_incremental_budget_bytes=1024**3,
                            anticipated_concurrent_growth_gib=args.anticipated_concurrent_growth_gib,
                            os_margin_gib=args.os_margin_gib, required_free_bytes=need),
        started_utc=datetime.datetime.now(datetime.timezone.utc).isoformat(), commands=[])
    write(evidence / "receipt.json", result)

    def run(name, argv, timeout=1800):
        log = evidence / (name + ".log")
        start = time.monotonic()
        with log.open("wb") as output:
            process = subprocess.Popen(list(map(str, argv)), cwd=args.proof_root,
                                       stdout=output, stderr=subprocess.STDOUT, start_new_session=True)
            write(evidence / "active-process.json", dict(name=name, pid=process.pid, argv=list(map(str, argv))))
            try:
                code = process.wait(timeout=timeout)
            except subprocess.TimeoutExpired:
                os.killpg(process.pid, signal.SIGTERM)
                try:
                    process.wait(timeout=10)
                except subprocess.TimeoutExpired:
                    os.killpg(process.pid, signal.SIGKILL)
                    process.wait()
                code = 124
        entry = dict(name=name, argv=list(map(str, argv)), exit_code=code,
                     seconds=round(time.monotonic() - start, 3),
                     log=log.name, log_sha256=sha(log.read_bytes()))
        result["commands"].append(entry)
        write(evidence / "receipt.json", result)
        require(code == 0, "Actual command failed: " + name)
        return log

    original = None
    try:
        original = inventory(args.core_checkout)
        write(evidence / "original-core-inputs-before.json", original)
        # APFS clones retain compatibility without writing into another owner's cache.
        run("clone-compatible-cache", ["cp", "-c", "-R", args.warm_cache, args.scratch], 120)
        # Clang PCM files embed their original absolute ModuleCache path.
        # Preserve the donor and quarantine only those cloned cache directories.
        nonportable = sorted((p for p in args.scratch.rglob("*")
                              if p.is_dir() and not p.is_symlink()
                              and p.name in {"ModuleCache", "ModuleCache.noindex"}),
                             key=lambda p: len(p.parts))
        quarantine = args.proof_root / "cloned-nonportable-cache-quarantine"
        moved = []
        for p in nonportable:
            if not p.exists():
                continue
            quarantine.mkdir(exist_ok=True)
            target = quarantine / str(len(moved))
            moved.append(dict(original_clone_path=str(p), quarantine_path=str(target)))
            p.rename(target)
        write(evidence / "cloned-cache-quarantine.json", moved)
        fixture = args.proof_root / "OriginalTests"
        fixture.mkdir()
        for relative in TESTS:
            (fixture / Path(relative).name).write_bytes((args.core_checkout / relative).read_bytes())
        (args.proof_root / "Package.swift").write_text(PACKAGE)
        write(evidence / "test-selection.json", dict(
            original_source=CORE, test_files=TESTS, identities=sorted(EXPECTED),
            production_source_copied=False, original_tests_changed=False,
            fixture="Original provider fetch fixture and original public MockLanguageModelV3"))
        for name, argv in [
            ("swift-version", ["xcrun", "swift", "--version"]),
            ("xcode-version", ["xcodebuild", "-version"]),
            ("sdk-version", ["xcrun", "--sdk", "macosx", "--show-sdk-version"]),
            ("os-version", ["sw_vers"]),
        ]:
            run(name, argv, 60)
        run("resolve", ["xcrun", "swift", "package", "--package-path", args.proof_root,
                       "--scratch-path", args.scratch, "--skip-update", "resolve"], 300)
        lock = json.loads((args.proof_root / "Package.resolved").read_text())
        pins = {pin["identity"]: pin["state"]["revision"] for pin in lock["pins"]}
        require(pins == {"swift-ai-sdk": CORE, "swift-argument-parser": ARGUMENT_PARSER},
                "Focused proof resolved a different dependency closure")
        resolved = args.scratch / "checkouts/swift-ai-sdk"
        require(inventory(resolved) == original, "Resolved original product source differs")
        (evidence / "Package.resolved").write_bytes((args.proof_root / "Package.resolved").read_bytes())
        (evidence / "Package.swift").write_text(PACKAGE)
        raw = run("original-core7", [
            "xcrun", "swift", "test", "--package-path", args.proof_root,
            "--scratch-path", args.scratch, "--jobs", "2", "--disable-automatic-resolution",
            "--filter", "StreamTextThoughtSignatureContinuationTests|StreamTextToolResultContinuationTests",
            "--xunit-output", evidence / "focused-suite.xml",
        ], 2400)
        xml = evidence / "focused-suite-swift-testing.xml"
        cases = list(ET.fromstring(xml.read_bytes()).iter("testcase"))
        identities = [(x.get("classname"), x.get("name")) for x in cases]
        require(len(cases) == 6 and len(set(identities)) == 6 and set(identities) == EXPECTED,
                "Actual executed test inventory differs from the six original methods")
        require(not any(x.find("failure") is not None or x.find("error") is not None or
                        x.find("skipped") is not None for x in cases), "A test failed, errored, or was skipped")
        log = raw.read_text()
        title = '"Completed client tools reach subsequent model steps with original result identities"'
        for reason in (".stop", ".toolCalls"):
            marker = "Test case passing 1 argument reason \u2192 " + reason + " to " + title + " started."
            require(log.count(marker) == 1, "Missing or duplicate actual parameter invocation: " + reason)
        for relative in TESTS:
            require((fixture / Path(relative).name).read_bytes() == (args.core_checkout / relative).read_bytes(),
                    "Original test source changed")
        require(inventory(resolved) == original and inventory(args.core_checkout) == original,
                "Production source changed during execution")
        write(evidence / "original-core-inputs-after.json", inventory(resolved))
        binaries = {p.resolve() for p in args.scratch.glob(
            "**/OtzariaCoreContinuationProofPackageTests.xctest/Contents/MacOS/OtzariaCoreContinuationProofPackageTests")}
        require(len(binaries) == 1, "Ambiguous or missing actual test binary")
        binary = next(iter(binaries))
        result["binary"] = dict(path=str(binary), bytes=binary.stat().st_size, sha256=sha(binary.read_bytes()))
        run("test-binary-uuid", ["xcrun", "dwarfdump", "--uuid", binary], 60)
        result.update(status="EXECUTED_PASS", executed_original_methods=6, executed_original_scenarios=7,
                      failed_methods=0, skipped_methods=0, actual_identities=sorted(identities),
                      actual_argument_invocations=[".stop", ".toolCalls"],
                      original_source_before_after_identical=True)
    except Exception as error:
        result.update(status="FAILED", error=str(error))
        (evidence / "failure.txt").write_text(traceback.format_exc())
    finally:
        if original is not None:
            try:
                write(evidence / "original-checkout-after.json", inventory(args.core_checkout))
            except Exception as error:
                result.update(status="FAILED", post_source_error=str(error))
        result.update(finished_utc=datetime.datetime.now(datetime.timezone.utc).isoformat(),
                      free_bytes_after=shutil.disk_usage(args.proof_root).free)
        write(evidence / "receipt.json", result)
        print(json.dumps(result, indent=2, sort_keys=True))
    return 0 if result["status"] == "EXECUTED_PASS" else 1

if __name__ == "__main__":
    sys.exit(main())
