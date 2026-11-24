#!/usr/bin/env python3
"""Focused public bridge input controls against the complete original module and CLI.

Uses the installed compiler's real SwiftSyntax host modules, not substitutes.
This is not a claim about the package's pinned SwiftPM/Xcode dependency graph.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import resource
import signal
import subprocess
import time

ROOT = Path(__file__).resolve().parents[2]
PACKAGE = ROOT / "Packages/HanlinSwiftUIBridgeGenerator"
FIXTURES = PACKAGE / "Tests/HanlinSwiftUIBridgeCoreTests/Fixtures"
INPUTS = ROOT / "Scripts/SDK/Fixtures/BridgeInputAdmission"
CORE = PACKAGE / "Sources/HanlinSwiftUIBridgeCore"
CLI = PACKAGE / "Sources/HanlinSwiftUIBridgeGenerator/main.swift"
CONFIGURATION = FIXTURES / "configuration.json"


def sha(data):
    return hashlib.sha256(data).hexdigest()


def no_core():
    resource.setrlimit(resource.RLIMIT_CORE, (0, 0))


def run(command, timeout=30):
    start = time.monotonic()
    process = subprocess.run(
        [str(x) for x in command], cwd=ROOT, capture_output=True,
        text=True, timeout=timeout, preexec_fn=no_core,
    )
    return process, round(time.monotonic() - start, 4)


def file_hashes(directory):
    return {
        str(p.relative_to(directory)): sha(p.read_bytes())
        for p in sorted(directory.rglob("*")) if p.is_file()
    } if directory.exists() else {}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--expect", choices=["original", "fixed"], required=True)
    parser.add_argument("--reuse-binaries", type=Path)
    parser.add_argument("--original-ref", help="Source attribution for retained original binaries only")
    parser.add_argument("--cases", nargs="+", choices=["cli", "public", "valid"], default=["cli", "public", "valid"])
    parser.add_argument("--baseline", type=Path, help="Retained original valid fixture result.json")
    args = parser.parse_args()
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    info_result, _ = run(["swiftc", "-print-target-info"])
    assert info_result.returncode == 0, info_result.stderr
    target = json.loads(info_result.stdout)
    host = Path(target["paths"]["runtimeResourcePath"]) / "host"
    assert host.is_dir(), host
    binaries = (args.reuse_binaries or output).resolve()
    sources = sorted(CORE.glob("*.swift"))
    compile_results = []

    def compile_step(label, command):
        process, elapsed = run(command, timeout=60)
        (output / (label + ".log")).write_text(process.stdout + process.stderr)
        compile_results.append({"label": label, "command": [str(x) for x in command],
                                "exit": process.returncode, "seconds": elapsed})
        assert process.returncode == 0, process.stdout + process.stderr

    if args.reuse_binaries is None:
        assert args.original_ref is None
        compile_step("core-compile", [
            "swiftc", "-swift-version", "6", "-strict-concurrency=complete",
            "-emit-library", "-emit-module", "-module-name", "HanlinSwiftUIBridgeCore",
            "-I", host, "-L", host, "-Xlinker", "-rpath", "-Xlinker", host,
            "-lSwiftSyntax", "-lSwiftParser", "-lSwiftParserDiagnostics", "-lSwiftDiagnostics",
            *sources, "-emit-module-path", binaries / "HanlinSwiftUIBridgeCore.swiftmodule",
            "-o", binaries / "libHanlinSwiftUIBridgeCore.so",
        ])
        compile_step("cli-compile", [
            "swiftc", "-swift-version", "6", "-strict-concurrency=complete",
            "-I", binaries, "-I", host, "-L", binaries, "-L", host,
            "-lHanlinSwiftUIBridgeCore", "-Xlinker", "-rpath", "-Xlinker", binaries,
            "-Xlinker", "-rpath", "-Xlinker", host, CLI,
            "-o", binaries / "hanlin-swiftui-bridge",
        ])
    else:
        assert args.original_ref, "Retained binaries need exact original source attribution"
        assert (binaries / "libHanlinSwiftUIBridgeCore.so").is_file()
        assert (binaries / "hanlin-swiftui-bridge").is_file()

    client = output / "public-client"
    if "public" in args.cases:
        compile_step("public-client-compile", [
            "swiftc", "-swift-version", "6", "-strict-concurrency=complete",
            "-I", binaries, "-I", host, "-L", binaries, "-L", host,
            "-lHanlinSwiftUIBridgeCore", "-Xlinker", "-rpath", "-Xlinker", binaries,
            "-Xlinker", "-rpath", "-Xlinker", host, INPUTS / "PublicClient.swift", "-o", client,
        ])
    plans = []
    duplicate = [("SwiftUI", FIXTURES / "SwiftUI.swiftinterface")] * 2
    enum = [("ModuleA", INPUTS / "EnumA.swiftinterface"), ("ModuleB", INPUTS / "EnumB.swiftinterface")]
    option = [("ModuleA", INPUTS / "OptionSetA.swiftinterface"), ("ModuleB", INPUTS / "OptionSetB.swiftinterface")]
    if "cli" in args.cases:
        plans += [("cli-duplicate-module", "cli", duplicate, "Repeated interface module"),
                  ("cli-cross-module-enum", "cli", enum, "Ambiguous enum/OptionSet"),
                  ("cli-cross-module-optionset", "cli", option, "Ambiguous enum/OptionSet")]
        if args.expect == "fixed":
            plans.append(("cli-before-parse", "cli", [("Missing", output / "not-present.swiftinterface")] * 2,
                          "Repeated interface module"))
    if "public" in args.cases:
        plans += [("api-write-duplicate-module", "write", duplicate, "Repeated interface module"),
                  ("api-write-enum", "write", enum, "Ambiguous enum/OptionSet"),
                  ("api-write-optionset", "write", option, "Ambiguous enum/OptionSet"),
                  ("api-classify-enum", "classify", enum, "Ambiguous enum/OptionSet"),
                  ("api-classify-optionset", "classify", option, "Ambiguous enum/OptionSet"),
                  ("api-classify-identical-repeat", "classify", [enum[0], enum[0]], "Ambiguous enum/OptionSet")]
    if "valid" in args.cases:
        plans.append(("valid-original-fixtures", "valid", [
            ("SwiftUI", FIXTURES / "SwiftUI.swiftinterface"),
            ("SwiftUICore", FIXTURES / "SwiftUICore.swiftinterface")], None))

    results = []
    for name, operation, interfaces, diagnostic in plans:
        destination = output / name
        if operation == "write":
            destination.mkdir()
            (destination / "swiftui-inventory.json").write_text("existing inventory must remain intact\n")
            (destination / "coverage.json").write_text("existing coverage must remain intact\n")
            (destination / "sentinel.txt").write_text("unrelated existing file\n")
        previous = file_hashes(destination)
        if operation in ["cli", "valid"]:
            command = [binaries / "hanlin-swiftui-bridge", "--sdk-identity",
                       "bridge-input-admission-control", "--configuration", CONFIGURATION,
                       "--output", destination]
            for module, source in interfaces:
                command += ["--interface", module + "=" + str(source)]
        else:
            command = [client, operation, CONFIGURATION]
            for module, source in interfaces:
                command += [module, source]
            command.append(destination)
        process, elapsed = run(command, timeout=15)
        (output / (name + ".stdout.log")).write_text(process.stdout)
        (output / (name + ".stderr.log")).write_text(process.stderr)
        current = file_hashes(destination)
        result = {"case": name, "operation": operation, "exit": process.returncode,
                  "seconds": elapsed, "command": [str(x) for x in command],
                  "output_before": previous, "output_after": current,
                  "stdout_sha256": sha(process.stdout.encode()), "stderr_sha256": sha(process.stderr.encode())}
        if operation == "valid":
            assert process.returncode == 0, process.stderr
            assert len(current) == 8, current
            if args.baseline:
                original = next(x for x in json.loads(args.baseline.read_text()) if x["case"] == name)
                assert current == original["sha256"], "Valid original fixture output changed"
                result["original_eight_outputs_byte_identical"] = True
        elif args.expect == "original":
            assert process.returncode == -signal.SIGTRAP, process.stderr
            assert "Duplicate values for key" in process.stderr, process.stderr
        elif operation == "classify":
            assert process.returncode == 0, process.stderr
            declarations = json.loads(process.stdout)
            assert len(declarations) >= 3
            for declaration in declarations:
                assert declaration["status"] == "unsupported"
                assert declaration["aggregateStatus"] == "unsupported"
                assert declaration["publicSurface"] == "unsupported"
                assert not declaration["exportedToHanlin"]
                assert diagnostic in declaration["reason"]
                for signature in declaration["signatures"]:
                    assert signature["status"] == "unsupported"
                    assert signature["publicSurface"] == "unsupported"
                    assert not signature["exportedToHanlin"]
                    assert signature["reason"] == declaration["reason"]
            result["classified_without_export"] = True
        else:
            assert process.returncode == 1, process.stderr
            assert diagnostic in process.stderr, process.stderr
            assert "Fatal error" not in process.stderr
            assert previous == current, "Rejected write changed or left partial output"
            if operation == "cli":
                assert not destination.exists(), "Rejected CLI created output directory"
            result["controlled_diagnostic"] = process.stderr.strip()
            result["destination_unchanged"] = True
        results.append(result)

    source_hashes = {}
    for source in [*sources, CLI]:
        relative = str(source.relative_to(ROOT))
        if args.original_ref:
            data = subprocess.check_output(["git", "show", args.original_ref + ":" + relative], cwd=ROOT)
        else:
            data = source.read_bytes()
        source_hashes[relative] = sha(data)
    inputs = [CONFIGURATION, FIXTURES / "SwiftUI.swiftinterface", FIXTURES / "SwiftUICore.swiftinterface",
              *sorted(INPUTS.iterdir())]
    receipt = {
        "expectation": args.expect, "result": "PASS", "target": target,
        "scope": "Complete actual core plus actual CLI/public client; real installed SwiftSyntax host modules. No pinned SwiftPM/Xcode graph or generated UIKit code execution claimed.",
        "source_ref": args.original_ref, "source_sha256": source_hashes,
        "input_sha256": {str(p.relative_to(ROOT)): sha(p.read_bytes()) for p in inputs},
        "driver_sha256": sha(Path(__file__).read_bytes()),
        "host_library_sha256": {p.name: sha(p.read_bytes()) for p in sorted(host.glob("libSwift*.so"))
                               if p.stem in ["libSwiftSyntax", "libSwiftParser", "libSwiftParserDiagnostics",
                                             "libSwiftDiagnostics", "libSwiftBasicFormat"]},
        "binary_sha256": {p.name: sha(p.read_bytes()) for p in [
            binaries / "hanlin-swiftui-bridge", binaries / "libHanlinSwiftUIBridgeCore.so"]},
        "compilations": compile_results, "cases": results,
    }
    (output / "receipt.json").write_text(json.dumps(receipt, indent=2, sort_keys=True) + "\n")
    print(json.dumps({"result": "PASS", "expectation": args.expect,
                      "cases": [{"case": r["case"], "exit": r["exit"]} for r in results],
                      "receipt": str(output / "receipt.json")}, indent=2))


if __name__ == "__main__":
    main()
