#!/usr/bin/env python3
"""Execute the retained 26-invocation contract against the actual pinned tool.

Control success is not combined metadata, UI, ABI or device acceptance.
"""
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import platform
import shutil
import subprocess
import sys
import time
import unittest

ROOT = Path(__file__).resolve().parents[3]
OUTPUT = ROOT / "build/acceptance/metadata-provenance-proof"


def write(name, data):
    (OUTPUT / name).write_text(json.dumps(data, indent=2) + "\n")


def command(label, argv):
    write(label + ".command.json", {"argv": argv, "cwd": str(ROOT)})
    result = subprocess.run(argv, cwd=ROOT, capture_output=True, timeout=60)
    (OUTPUT / (label + ".stdout")).write_bytes(result.stdout)
    (OUTPUT / (label + ".stderr")).write_bytes(result.stderr)
    write(label + ".exit.json", {"returncode": result.returncode})
    result.check_returncode()
    return result.stdout.decode().strip()


def main():
    OUTPUT.mkdir(parents=True, exist_ok=False)
    started = time.monotonic()
    if sys.platform != "darwin":
        write("result.json", {"status": "INFRA_ERROR", "reason": "Actual macOS required", "cases": []})
        return 2
    sdk = command("sdk-path", ["xcrun", "--sdk", "iphonesimulator", "--show-sdk-path"])
    arch = platform.machine()
    preflight = {"sourceSHA": command("git-sha", ["git", "rev-parse", "HEAD"]),
        "xcode": command("xcode", ["xcodebuild", "-version"]),
        "sdk": command("sdk-version", ["xcrun", "--sdk", "iphonesimulator", "--show-sdk-version"]),
        "clang": command("xcode-clang", ["xcrun", "clang", "--version"]),
        "runtimes": command("runtimes", ["xcrun", "simctl", "list", "runtimes", "--json"]),
        "architecture": arch, "python": sys.version, "freeBytes": shutil.disk_usage(ROOT).free,
        "idb": shutil.which("idb"), "maestro": shutil.which("maestro"),
        "boundary": "Generator controls only; no simulator boot/UI test requested."}
    write("preflight.json", preflight)
    if arch not in {"arm64", "x86_64"} or preflight["freeBytes"] < 8 * 1024**3:
        raise RuntimeError("Insufficient disk or unsupported native architecture")
    flags = ["-x", "objective-c", "-target", f"{arch}-apple-ios27.0-simulator", "-isysroot", sdk, "-fno-modules"]
    modern = os.environ.get("HANLIN_METADATA_PROOF_FRONTEND") == "modern"
    if modern:
        spec = importlib.util.spec_from_file_location("metadata_probe_context", ROOT / "Scripts/NativeScript/probe-sdk-metadata.py")
        probe = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(probe)
        flags.extend(probe.CANDIDATE_CPP_ARGUMENTS)
    tool_root = ROOT / ("build/nativescript-modern-metadata-tool" if modern else "build/nativescript-metadata-tool")
    tool = tool_root / "bin/objc-metadata-generator"
    receipt = tool_root / "provenance.json"
    cases = OUTPUT / "cases"
    cases.mkdir(mode=0o700)
    os.environ.update(HANLIN_RUN_PROVENANCE_NATIVE_CONTROLS="1",
        HANLIN_PROVENANCE_CONTROL_EVIDENCE_DIR=str(cases.resolve()),
        HANLIN_PREPROCESS_PROVENANCE_NATIVE_TOOL=str(tool.resolve(strict=True)),
        HANLIN_PREPROCESS_PROVENANCE_TOOL_RECEIPT=str(receipt.resolve(strict=True)),
        HANLIN_PREPROCESS_PROVENANCE_CLANG_ARGS_JSON=json.dumps(flags))
    contract = json.loads((ROOT / "docs/miniapp-sdk/evidence/METADATA_FRAMEWORK_DEDUP_2026-11-15.json").read_text())
    rows = contract.get("activeWave20261115", {}).get("matrixV2") or contract["sourceOnlyPreprocessingProvenance"]["testHarnessPreparation"]["matrix"]
    write("plan.json", {"obligations": rows, "sourceSHA": preflight["sourceSHA"], "flags": flags,
        "reuse": [], "reason": "Changed frontend/context/source: execute affected fixture controls. No legacy compiler pass confers a modern pass."})
    spec = importlib.util.spec_from_file_location("metadata_controls", ROOT / "Scripts/CI/Tests/test_nativescript_metadata_wrapper.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    results = []
    for row in rows:
        key = row["selector"] + "--" + row["variant"]
        if modern and ("cancelled_native_process" in row["selector"] or "normal_sdk31_" in row["selector"]):
            reason = "Existing one-attempt observer does not establish PP Lex; no unchanged infrastructure retry" if "cancelled_native_process" in row["selector"] else "Modern combined production wrapper is not adopted; separate SDK/combined/runtime obligations remain open"
            results.append({**row, "status": "NOT_RUN", "testsRun": 0, "reason": reason})
            continue
        if time.monotonic() - started > 24 * 60:
            results.append({**row, "status": "NOT_RUN", "reason": "Aggregate time reserve"})
            continue
        for name in ["HANLIN_PROVENANCE_SERIALIZED_VARIANT", "HANLIN_PROVENANCE_NEGATIVE_VARIANT", "HANLIN_RUN_PROVENANCE_FULL_NATIVE_CONTROLS"]:
            os.environ.pop(name, None)
        os.environ.update(row["envOverrides"])
        suite = unittest.defaultTestLoader.loadTestsFromName(row["selector"], module)
        then = time.monotonic()
        with (OUTPUT / (key + ".log")).open("w") as log:
            result = unittest.TextTestRunner(stream=log, verbosity=2).run(suite)
        status = "TEST_FAILED" if result.errors or result.failures else "NOT_OBSERVED" if result.skipped else "EXECUTED_PASS"
        retained = cases / key / "control-result.json"
        if row["category"] == "NATIVE":
            if not retained.is_file():
                status = "INFRA_ERROR"
            elif json.loads(retained.read_text())["status"] != "PASS" and status == "EXECUTED_PASS":
                status = "INFRA_ERROR"
        results.append({**row, "status": status, "testsRun": result.testsRun,
            "seconds": time.monotonic() - then, "skipped": [why for _, why in result.skipped]})
        write("result.json", {"status": "RUNNING", "cases": results})
        print(key + ": " + status, flush=True)
    passed = len(results) == 26 and all(row["status"] == "EXECUTED_PASS" and row["testsRun"] == 1 for row in results)
    write("result.json", {"status": "EXECUTED_PASS" if passed else "INCOMPLETE", "cases": results,
        "seconds": time.monotonic() - started, "metadataAcceptance": "NOT_ESTABLISHED"})
    manifest = [{"path": p.relative_to(OUTPUT).as_posix(), "bytes": p.stat().st_size,
        "sha256": hashlib.sha256(p.read_bytes()).hexdigest()} for p in sorted(OUTPUT.rglob("*")) if p.is_file() and not p.is_symlink()]
    write("artifact-manifest.json", manifest)
    return 0 if passed else 1


if __name__ == "__main__":
    sys.exit(main())
