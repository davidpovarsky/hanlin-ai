#!/usr/bin/env python3
"""Continue only the paid original Core7 proof after an owned storage interruption."""
import argparse
import datetime
import hashlib
import json
import os
from pathlib import Path
import platform
import runpy
import shutil
import signal
import subprocess
import sys
import time
import traceback
import xml.etree.ElementTree as ET

BASELINE_RUNNER_SHA256 = "a28aecadd9a30e58fe0a99bbea230e0e362f70bf4c3d3e2c6b90e6bf2e6de3b2"
PRIOR_RECEIPT_SHA256 = "9c91a94345466f2efc5659f853f309147f34f2370d5ee89f0645c8122b1cf065"
ORIGINAL_INPUT_SHA256 = "7373e51e659fb08f14127b7c54192bfc7bda184a9c3638a94557a8cae4213689"


def require(condition, message):
    if not condition:
        raise RuntimeError(message)


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def write(path, value):
    path.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--baseline-runner", required=True, type=Path)
    parser.add_argument("--proof-root", required=True, type=Path)
    parser.add_argument("--scratch", required=True, type=Path)
    parser.add_argument("--evidence-name", required=True)
    parser.add_argument("--anticipated-concurrent-growth-gib", required=True, type=float)
    parser.add_argument("--os-margin-gib", required=True, type=float)
    args = parser.parse_args()
    require(platform.system() == "Darwin" and platform.machine() == "arm64", "Real Apple arm64 runner required")
    require(args.evidence_name.startswith("evidence-resume") and "/" not in args.evidence_name and
            ".." not in args.evidence_name, "Fresh owned evidence child name required")
    require(args.anticipated_concurrent_growth_gib >= 0 and args.os_margin_gib >= 0, "Invalid phase budget")
    evidence = args.proof_root / args.evidence_name
    require(args.proof_root.is_dir() and args.scratch.is_dir() and not evidence.exists(),
            "Paid exact proof/cache and a fresh evidence path required")
    require(sha(args.baseline_runner) == BASELINE_RUNNER_SHA256, "Original proof controller changed")
    original = runpy.run_path(str(args.baseline_runner))
    prior_path = args.proof_root / "evidence/receipt.json"
    require(sha(prior_path) == PRIOR_RECEIPT_SHA256, "Original interrupted receipt changed")
    prior = json.loads(prior_path.read_text())
    require(prior["status"] == "FAILED" and prior["commands"][-1]["exit_code"] == 125 and
            prior["owned_command_stopped_reason"] == "concurrent growth consumed the recorded remaining disk reserve",
            "This continuation is only for the recorded owned resource interruption")
    before_path = args.proof_root / "evidence/original-core-inputs-before.json"
    require(sha(before_path) == ORIGINAL_INPUT_SHA256, "Original full source inventory changed")
    expected_inputs = json.loads(before_path.read_text())
    core = args.scratch / "checkouts/swift-ai-sdk"
    require(original["inventory"](core) == expected_inputs, "Paid Core sources differ from exact original inputs")
    require((args.proof_root / "Package.swift").read_text() == original["PACKAGE"],
            "Original focused package manifest changed")
    lock = args.proof_root / "Package.resolved"
    require(sha(lock) == sha(args.proof_root / "evidence/Package.resolved"), "Paid exact dependency lock changed")
    pins = {row["identity"]: row["state"]["revision"] for row in json.loads(lock.read_text())["pins"]}
    require(pins == {"swift-ai-sdk": original["CORE"], "swift-argument-parser": original["ARGUMENT_PARSER"]},
            "Dependency closure differs")
    for relative in original["TESTS"]:
        require((args.proof_root / "OriginalTests" / Path(relative).name).read_bytes() ==
                (core / relative).read_bytes(), "An original test file changed")
    evidence.mkdir()
    reserve = int((args.anticipated_concurrent_growth_gib + args.os_margin_gib) * 1024**3)
    # The source clone, module quarantine and dependency products already exist.
    # Actual product census showed a 15.3 MB Core object and 29.1 MB comparison
    # producer executable. This bounded remaining allowance covers remaining
    # module/test outputs, link temporaries and small result/log files.
    own_remaining = 512 * 1024**2
    free = shutil.disk_usage(args.proof_root).free
    result = {
        "status": "NOT_RUN", "source_union": prior["hanlin_source"], "core_source": original["CORE"],
        "prior_job": "job_723e56f227ee", "prior_receipt_sha256": PRIOR_RECEIPT_SHA256,
        "original_input_inventory_sha256": ORIGINAL_INPUT_SHA256,
        "runner_sha256": sha(Path(__file__)), "baseline_runner_sha256": BASELINE_RUNNER_SHA256,
        "started_at": datetime.datetime.now(datetime.timezone.utc).isoformat(), "commands": [],
        "original_methods_expected": 6, "original_invocations_expected": 7,
        "full_core48_reexecuted": False, "graph_reexecuted": False, "cache_cloned_again": False,
        "dependency_resolution_reexecuted": False, "live_provider_executed": False,
        "disk_admission": {"free_bytes": free, "own_remaining_peak_bytes": own_remaining,
                           "other_remaining_and_os_bytes": reserve, "required_free_bytes": reserve + own_remaining,
                           "anticipated_concurrent_growth_gib": args.anticipated_concurrent_growth_gib,
                           "os_margin_gib": args.os_margin_gib},
    }
    write(evidence / "receipt.json", result)
    lock_before = sha(lock)

    def run(name, argv, timeout):
        log = evidence / (name + ".log")
        started = time.monotonic()
        row = {"name": name, "argv": list(map(str, argv))}
        result["commands"].append(row)
        with log.open("wb") as output:
            process = subprocess.Popen(row["argv"], cwd=args.proof_root, stdout=output,
                                       stderr=subprocess.STDOUT, start_new_session=True)
            row["pid"] = process.pid
            write(evidence / "receipt.json", result)
            deadline = started + timeout
            while True:
                try:
                    code = process.wait(timeout=min(5, max(0.1, deadline - time.monotonic())))
                    break
                except subprocess.TimeoutExpired:
                    reason = None
                    if time.monotonic() >= deadline:
                        reason = "owned continuation timed out"
                    elif shutil.disk_usage(args.proof_root).free < reserve:
                        reason = "concurrent growth consumed this phase's recorded remaining reserve"
                    if reason is None:
                        continue
                    row["owned_process_stopped_reason"] = reason
                    os.killpg(process.pid, signal.SIGTERM)
                    try:
                        process.wait(timeout=10)
                    except subprocess.TimeoutExpired:
                        os.killpg(process.pid, signal.SIGKILL)
                        process.wait()
                    code = 124 if time.monotonic() >= deadline else 125
                    break
        row.update(exit_code=code, seconds=round(time.monotonic() - started, 3),
                   log=log.name, log_sha256=sha(log), free_bytes_after=shutil.disk_usage(args.proof_root).free)
        write(evidence / "receipt.json", result)
        require(code == 0, "Actual original continuation command failed: " + name)
        return log

    try:
        require(free >= reserve + own_remaining, "Fresh remaining-phase resource admission failed")
        write(evidence / "original-inputs-before.json", original["inventory"](core))
        raw = run("original-core7", [
            "xcrun", "swift", "test", "--package-path", args.proof_root,
            "--scratch-path", args.scratch, "--jobs", "2", "--disable-automatic-resolution",
            "--filter", "StreamTextThoughtSignatureContinuationTests|StreamTextToolResultContinuationTests",
            "--xunit-output", evidence / "focused-suite.xml",
        ], 900)
        xml = evidence / "focused-suite-swift-testing.xml"
        cases = list(ET.fromstring(xml.read_bytes()).iter("testcase"))
        identities = [(row.get("classname"), row.get("name")) for row in cases]
        require(len(cases) == len(set(identities)) == 6 and set(identities) == original["EXPECTED"],
                "Actual inventory differs from all six original methods")
        require(not any(row.find("failure") is not None or row.find("error") is not None or
                        row.find("skipped") is not None for row in cases),
                "A selected original method failed, errored or skipped")
        output = raw.read_text()
        title = '"Completed client tools reach subsequent model steps with original result identities"'
        for reason in (".stop", ".toolCalls"):
            marker = "Test case passing 1 argument reason \u2192 " + reason + " to " + title + " started."
            require(output.count(marker) == 1, "Original parameter invocation missing or duplicated: " + reason)
        for relative in original["TESTS"]:
            require((args.proof_root / "OriginalTests" / Path(relative).name).read_bytes() ==
                    (core / relative).read_bytes(), "Original test source changed")
        require(original["inventory"](core) == expected_inputs and sha(lock) == lock_before,
                "Original dependency source or lock changed")
        write(evidence / "original-inputs-after.json", original["inventory"](core))
        # Installed Swift 6.4's SwiftPM Xcode backend names this bundle after the
        # exact declared test target. The paid directory census observed this
        # target's empty bundle before continuation; old donor suites are excluded.
        binary = args.scratch / "debug/SwiftAISDKTests.xctest/Contents/MacOS/SwiftAISDKTests"
        require(binary.is_file() and binary.resolve().is_relative_to(args.scratch.resolve()),
                "Exact actual SwiftAISDKTests target executable missing or aliased outside owned cache")
        result["binary"] = {"path": str(binary.resolve()), "bytes": binary.stat().st_size, "sha256": sha(binary)}
        run("test-binary-uuid", ["xcrun", "dwarfdump", "--uuid", binary], 30)
        result.update(status="EXECUTED_PASS", original_methods_executed=6, original_invocations_executed=7,
                      failed_methods=0, skipped_methods=0, exact_method_identities=sorted(identities),
                      exact_parameter_invocations=[".stop", ".toolCalls"])
    except Exception as error:
        result["status"] = "FAILED" if result["commands"] else "BLOCKED_BEFORE_EXECUTION"
        result["error"] = repr(error)
        (evidence / "failure.txt").write_text(traceback.format_exc())
    finally:
        try:
            after = original["inventory"](core)
            write(evidence / "source-after.json", after)
            require(after == expected_inputs and sha(lock) == lock_before, "Source/lock changed during continuation")
            result["original_source_and_lock_unchanged"] = True
            require(sha(prior_path) == PRIOR_RECEIPT_SHA256, "Original failed receipt was overwritten")
        except Exception as error:
            result.update(status="FAILED", post_source_error=repr(error))
        result.update(finished_at=datetime.datetime.now(datetime.timezone.utc).isoformat(),
                      free_bytes_after=shutil.disk_usage(args.proof_root).free)
        write(evidence / "receipt.json", result)
        print(json.dumps(result, indent=2, sort_keys=True))
    return 0 if result["status"] == "EXECUTED_PASS" else 1


if __name__ == "__main__":
    sys.exit(main())
