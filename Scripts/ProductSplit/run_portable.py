"""Compile actual bridge/migration Swift against the committed canonical contracts.

No generated Package.swift, dependency downloads, CI, Apple frameworks or app builds.
Build products stay under the owned Tests/ProductSplit/.build directory.
"""
from pathlib import Path
import json
import os
import shutil
import subprocess
import sys
import argparse
import hashlib
import uuid

ROOT = Path(__file__).resolve().parents[2]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--suite", choices=["initial", "durable"], default="initial")
    args = parser.parse_args()
    evidence = ROOT / "docs/product-split" / ("durable-results.json" if args.suite == "durable" else "portable-results.json")
    evidence.parent.mkdir(exist_ok=True)
    evidence.write_text('{"status":"IN_PROGRESS","scope":"portable Swift only"}\n', encoding="utf-8", newline="\n")
    build = ROOT / "Tests/ProductSplit/.build"
    build.mkdir(exist_ok=True)
    compiler = shutil.which("swiftc")
    if not compiler:
        raise SystemExit("swiftc unavailable; no test execution claimed")
    flags = ["-swift-version", "6", "-strict-concurrency=complete", "-warnings-as-errors"]
    toolchain = subprocess.check_output([compiler, "--version"], text=True).strip()

    def compile_module(name, inputs, command, outputs):
        signature = hashlib.sha256((toolchain + json.dumps(command)).encode())
        for path in inputs:
            signature.update(path.read_bytes())
        fingerprint = signature.hexdigest()
        stamp = build / (name + ".inputs.sha256")
        if stamp.exists() and stamp.read_text() == fingerprint and all(p.exists() for p in outputs):
            return "UNCHANGED_SOURCE_CACHE"
        subprocess.run(command, check=True, cwd=ROOT)
        stamp.write_text(fingerprint, encoding="ascii")
        return "COMPILED"
    library_suffix = ".dylib" if sys.platform == "darwin" else ".so"
    library = build / ("HanlinPlatformContracts.dll" if os.name == "nt" else "libHanlinPlatformContracts" + library_suffix)
    # The resource-only helper needs SwiftPM's generated Bundle.module. None of
    # the exercised types uses it; omit it rather than stub production behavior.
    contracts = sorted(p for p in (ROOT / "Packages/HanlinPlatform/Sources/HanlinPlatformContracts").glob("*.swift")
                       if p.name != "HanlinManifestSchema.swift")
    contracts_command = [compiler, *flags, "-parse-as-library", "-emit-library", "-emit-module",
                    "-module-name", "HanlinPlatformContracts", *map(str, contracts),
                    "-emit-module-path", str(build / "HanlinPlatformContracts.swiftmodule"),
                    "-o", str(library)]
    contract_compilation = compile_module("contracts", contracts, contracts_command,
        [library, build / "HanlinPlatformContracts.swiftmodule"])
    # Actual canonical request and launch implementations, not replacement stubs.
    core = ROOT / "Packages/HanlinPlatform/Sources/HanlinMiniAppCore"
    core_library = build / ("HanlinMiniAppCore.dll" if os.name == "nt" else "libHanlinMiniAppCore" + library_suffix)
    core_inputs = [core / "HanlinMiniAppRequestBroker.swift", core / "HanlinCanonicalMiniAppCatalog.swift"]
    core_command = [compiler, *flags, "-parse-as-library", "-emit-library", "-emit-module",
                    "-module-name", "HanlinMiniAppCore", "-I", str(build), "-L", str(build),
                    "-lHanlinPlatformContracts", str(core / "HanlinMiniAppRequestBroker.swift"),
                    str(core / "HanlinCanonicalMiniAppCatalog.swift"),
                    "-emit-module-path", str(build / "HanlinMiniAppCore.swiftmodule"),
                    "-o", str(core_library)]
    core_compilation = compile_module("core", contracts + core_inputs, core_command,
        [core_library, build / "HanlinMiniAppCore.swiftmodule"])
    sources = sorted((ROOT / "Packages/HanlinProductSplit/Sources/HanlinProductSplit").glob("*.swift"))
    binary_name = "DurableSplitTests" if args.suite == "durable" else "ProductSplitTests"
    test_source = ROOT / "Packages/HanlinProductSplit/Tests" / (binary_name.replace("ProductSplitTests", "PortableSplitTests") + ".swift")
    executable = build / (binary_name + (".exe" if os.name == "nt" else ""))
    subprocess.run([compiler, *flags, "-parse-as-library", "-I", str(build), "-L", str(build),
                    "-lHanlinPlatformContracts", "-lHanlinMiniAppCore", *map(str, sources),
                    str(test_source),
                    "-o", str(executable)], check=True, cwd=ROOT)
    env = dict(os.environ)
    env["PATH"] = str(build) + os.pathsep + env.get("PATH", "")
    env["LD_LIBRARY_PATH"] = str(build) + os.pathsep + env.get("LD_LIBRARY_PATH", "")
    fixture = build / "fixture-store" / str(uuid.uuid4())
    fixture.mkdir(parents=True)
    (fixture / ".hanlin-product-split-fixture").write_bytes(b"synthetic-fixture-only-v1\n")
    result = subprocess.run([str(executable), str(fixture)], check=True, cwd=ROOT, env=env, capture_output=True, text=True)
    print(result.stdout, end="")
    report = json.loads(result.stdout)
    if args.suite == "durable" and report.get("status") == "EXECUTED_PASS":
        process_fixture = report.pop("cross_process_fixture")
        child_root = Path(process_fixture["root"])
        child_request = Path(process_fixture["request"])
        if not child_root.resolve().is_relative_to(fixture.resolve()) or not child_request.resolve().is_relative_to(fixture.resolve()):
            raise RuntimeError("child fixture escaped owned run root")
        command = [str(executable), "--claim", str(child_root), str(child_request), str(process_fixture["time"])]
        children = [subprocess.Popen(command, cwd=ROOT, env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True) for _ in range(2)]
        outcomes = []
        try:
            for child in children:
                out, err = child.communicate(timeout=30)
                if child.returncode != 0:
                    raise RuntimeError("child receiver failed: " + err[-1000:])
                outcomes.append(json.loads(out))
        finally:
            for child in children:
                if child.poll() is None:
                    child.kill()
                    child.communicate()
        if sum(v.get("status") == "CLAIMED" for v in outcomes) != 1 or any(v.get("status") not in {"CLAIMED", "BUSY", "OUT_OF_ORDER"} for v in outcomes):
            raise RuntimeError("cross-process duplicate attempt: " + json.dumps(outcomes))
        replay = json.loads(subprocess.check_output(command, cwd=ROOT, env=env, text=True, timeout=30))
        if replay.get("status") != "OUT_OF_ORDER":
            raise RuntimeError("restarted receiver granted a second attempt")
        report["tests"].append("receiver.concurrentProcesses.uniqueAttemptAndRestartReplay")
        report["count"] += 1
        report["cross_process_outcomes"] = outcomes + [replay]
    report["toolchain"] = toolchain
    report["canonical_compilation"] = {"contracts": contract_compilation, "catalog_request": core_compilation}
    report["source_sha256"] = {str(p.relative_to(ROOT)).replace("\\", "/"): hashlib.sha256(p.read_bytes()).hexdigest() for p in contracts + core_inputs + sources + [test_source]}
    report["baseline"] = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip()
    report["scope"] = "Portable Swift and owned disk/process fixtures; no Apple app/SDK/device execution"
    report["excluded_contract_source"] = "HanlinManifestSchema.swift (SwiftPM resource helper, not exercised)"
    evidence.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8", newline="\n")
    print(json.dumps({"status": report["status"], "count": report.get("count"), "suite": args.suite}))
    if report.get("status") != "EXECUTED_PASS":
        raise SystemExit(1)


if __name__ == "__main__":
    try:
        main()
    except Exception as error:
        failure = {"status": "FAILED", "error": str(error), "scope": "portable Swift harness"}
        target = "durable-results.json" if "durable" in sys.argv else "portable-results.json"
        (ROOT / "docs/product-split" / target).write_text(json.dumps(failure, indent=2) + "\n", encoding="utf-8", newline="\n")
        raise
