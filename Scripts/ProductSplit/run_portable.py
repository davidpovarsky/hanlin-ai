"""Compile actual scoped Swift and retain raw, hash-linked execution evidence."""
from pathlib import Path
import argparse
import hashlib
import json
import os
import shutil
import subprocess
import sys
import uuid
from provenance import EvidenceRun, digest

ROOT = Path(__file__).resolve().parents[2]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--suite", choices=["initial", "durable", "correction", "foreground"], default="initial")
    parser.add_argument("--rebuild-canonical", action="store_true")
    args = parser.parse_args()
    report_name = {"initial": "portable-results.json", "durable": "durable-results.json",
                   "correction": "durable-correction-results.json", "foreground": "foreground-results.json"}[args.suite]
    evidence = ROOT / "docs/product-split" / report_name
    run = EvidenceRun(ROOT, args.suite)
    evidence.write_text(json.dumps({"status": "IN_PROGRESS", "raw_evidence_directory": str(run.directory)}) + "\n", encoding="utf-8", newline="\n")
    build = ROOT / "Tests/ProductSplit/.build"
    build.mkdir(exist_ok=True)
    compiler = shutil.which("swiftc")
    if not compiler:
        raise RuntimeError("swiftc unavailable; no execution claimed")
    flags = ["-v", "-swift-version", "6", "-strict-concurrency=complete", "-warnings-as-errors"]
    toolchain, _ = run.execute([compiler, "--version"], "toolchain")
    # Hash the actual frontend too; verbose compiler logs retain frontend/link argv.
    frontend = Path(compiler).with_name("swift-frontend" + (".exe" if os.name == "nt" else ""))
    compiler_tools = [digest(compiler)] + ([digest(frontend)] if frontend.exists() else [])
    suffix = ".dll" if os.name == "nt" else ".dylib" if sys.platform == "darwin" else ".so"
    prefix = "" if os.name == "nt" else "lib"
    contracts_library = build / (prefix + "HanlinPlatformContracts" + suffix)
    contracts_module = build / "HanlinPlatformContracts.swiftmodule"
    contracts = sorted(p for p in (ROOT / "Packages/HanlinPlatform/Sources/HanlinPlatformContracts").glob("*.swift")
                       if p.name != "HanlinManifestSchema.swift")
    contracts_command = [compiler, *flags, "-parse-as-library", "-emit-library", "-emit-module",
        "-module-name", "HanlinPlatformContracts", *map(str, contracts),
        "-emit-module-path", str(contracts_module), "-o", str(contracts_library)]
    contract_proof = run.module("contracts", contracts, contracts_command, [contracts_library, contracts_module],
        compiler, toolchain, compiler_tools, force=args.rebuild_canonical)
    core = ROOT / "Packages/HanlinPlatform/Sources/HanlinMiniAppCore"
    core_inputs = [core / "HanlinMiniAppRequestBroker.swift", core / "HanlinCanonicalMiniAppCatalog.swift"]
    core_library = build / (prefix + "HanlinMiniAppCore" + suffix)
    core_module = build / "HanlinMiniAppCore.swiftmodule"
    core_command = [compiler, *flags, "-parse-as-library", "-emit-library", "-emit-module",
        "-module-name", "HanlinMiniAppCore", "-I", str(build), "-L", str(build), "-lHanlinPlatformContracts",
        *map(str, core_inputs), "-emit-module-path", str(core_module), "-o", str(core_library)]
    core_proof = run.module("core", core_inputs, core_command, [core_library, core_module], compiler, toolchain,
        compiler_tools + contract_proof["outputs"], force=args.rebuild_canonical)
    sources = sorted((ROOT / "Packages/HanlinProductSplit/Sources/HanlinProductSplit").glob("*.swift"))
    env = dict(os.environ)
    env["PATH"] = str(build) + os.pathsep + env.get("PATH", "")
    env["LD_LIBRARY_PATH"] = str(build) + os.pathsep + env.get("LD_LIBRARY_PATH", "")
    groups = ["durable", "correction"] if args.suite == "correction" else [args.suite]
    reports = []
    test_sources = []
    binary_proofs = []
    for group in groups:
        binary_name, file_name = {"initial": ("ProductSplitTests", "PortableSplitTests.swift"),
            "durable": ("DurableSplitTests", "DurableSplitTests.swift"),
            "correction": ("DurabilityCorrectionTests", "DurabilityCorrectionTests.swift"),
            "foreground": ("ForegroundSchemeTests", "ForegroundSchemeTests.swift")}[group]
        test_source = ROOT / "Packages/HanlinProductSplit/Tests" / file_name
        test_sources.append(test_source)
        executable = build / (binary_name + (".exe" if os.name == "nt" else ""))
        command = [compiler, *flags, "-parse-as-library", "-I", str(build), "-L", str(build),
            "-lHanlinPlatformContracts", "-lHanlinMiniAppCore", *map(str, sources), str(test_source), "-o", str(executable)]
        compile_inputs = [digest(p) for p in sources + [test_source]]
        _, compile_event = run.execute(command, "link-" + group)
        if compile_inputs != [digest(p) for p in sources + [test_source]]:
            raise RuntimeError("owned compiler inputs changed during compilation")
        binary_proof = {"group": group, "binary": digest(executable), "compile_event": compile_event,
            "source_inputs": compile_inputs, "compiler_tools": compiler_tools,
            "linked_canonical_outputs": contract_proof["outputs"] + core_proof["outputs"]}
        binary_proofs.append(binary_proof)
        (run.directory / (group + "-binary-provenance.json")).write_text(
            json.dumps(binary_proof, indent=2) + "\n", encoding="utf-8", newline="\n")
        fixture = build / "fixture-store" / str(uuid.uuid4())
        fixture.mkdir(parents=True)
        (fixture / ".hanlin-product-split-fixture").write_bytes(b"synthetic-fixture-only-v1\n")
        stdout, _ = run.execute([str(executable), str(fixture)], "tests-" + group, env=env, timeout=240)
        report = json.loads(stdout)
        if report.get("status") != "EXECUTED_PASS" or report.get("count") != len(report.get("tests", [])):
            raise RuntimeError("Swift suite failed: " + stdout[-2500:])

        def owned_path(value):
            path = Path(value)
            if not path.resolve().is_relative_to(fixture.resolve()):
                raise RuntimeError("child fixture escaped owned run root")
            return str(path)

        if group == "durable":
            child = report.pop("cross_process_fixture")
            command = [str(executable), "--claim", owned_path(child["root"]), owned_path(child["request"]), str(child["time"])]
            processes = []
            for index in range(2):
                process = subprocess.Popen(command, cwd=ROOT, env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
                processes.append(process)
                run.event({"kind": "spawn", "argv": command, "pid": process.pid, "race_index": index})
            outcomes = []
            try:
                for index, process in enumerate(processes):
                    out, err = process.communicate(timeout=30)
                    run.record(command, "race-" + str(index), process.returncode, out, err, pid=process.pid)
                    if process.returncode:
                        raise RuntimeError("receiver child failed")
                    outcomes.append(json.loads(out))
            finally:
                for process in processes:
                    if process.poll() is None:
                        process.kill(); process.communicate()
            if sum(v.get("status") == "CLAIMED" for v in outcomes) != 1 or any(v.get("status") not in {"CLAIMED", "BUSY", "OUT_OF_ORDER"} for v in outcomes):
                raise RuntimeError("duplicate cross-process attempt: " + json.dumps(outcomes))
            replay, _ = run.execute(command, "race-restart", env=env, timeout=30)
            replay = json.loads(replay)
            if replay.get("status") != "OUT_OF_ORDER":
                raise RuntimeError("restarted receiver granted a second attempt")
            report["cross_process_outcomes"] = outcomes + [replay]
            report["tests"].append("receiver.concurrentProcesses.uniqueAttemptAndRestartReplay")
        if group == "correction":
            outcomes = []
            for index, child in enumerate(report.pop("recovery_process_fixtures")):
                if child["next"] not in {"apply", "rollback"}:
                    raise RuntimeError("invalid fixture continuation")
                command = [str(executable), "--recover-next", owned_path(child["root"]), child["next"]]
                value, _ = run.execute(command, "recovery-restart-" + str(index), env=env, timeout=30)
                value = json.loads(value)
                if value.get("status") != "RECOVERED":
                    raise RuntimeError("process recovery failed: " + json.dumps(value))
                outcomes.append({"case": child["name"], "result": value})
                report["tests"].append(child["name"])
            report["recovery_process_outcomes"] = outcomes
        report["count"] = len(report["tests"])
        report["group"] = group
        reports.append(report)
        print(json.dumps({"group": group, "status": report["status"], "count": report["count"]}))
    head, _ = run.execute(["git", "rev-parse", "HEAD"], "commit-base")
    status, _ = run.execute(["git", "status", "--short"], "working-tree")
    source_files = contracts + core_inputs + sources + test_sources
    report = {"status": "EXECUTED_PASS", "count": sum(r["count"] for r in reports), "groups": reports,
        "commit_base_at_execution": head.strip(), "working_tree_at_execution": status.splitlines(),
        "source_sha256": {p.relative_to(ROOT).as_posix(): hashlib.sha256(p.read_bytes()).hexdigest() for p in source_files},
        "runner_sources": [digest(Path(__file__)), digest(ROOT / "Scripts/ProductSplit/provenance.py")],
        "toolchain": toolchain.strip(), "compiler_tools": compiler_tools,
        "canonical_provenance": {"contracts": contract_proof, "catalog_request": core_proof},
        "binaries": binary_proofs, "raw_evidence_manifest": run.finish(),
        "scope": "Actual local Swift and owned disk/process fixtures; Apple apps/SDK/device and production stores NOT_RUN",
        "excluded_contract_source": "Unused HanlinManifestSchema.swift requires SwiftPM Bundle.module; no replacement stub"}
    evidence.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8", newline="\n")
    print(json.dumps({"status": report["status"], "count": report["count"], "report": str(evidence)}))


if __name__ == "__main__":
    try:
        main()
    except Exception as error:
        target = "foreground-results.json" if "foreground" in sys.argv else "durable-correction-results.json" if "correction" in sys.argv else "durable-results.json" if "durable" in sys.argv else "portable-results.json"
        path = ROOT / "docs/product-split" / target
        previous = json.loads(path.read_text(encoding="utf-8")) if path.exists() else {}
        path.write_text(json.dumps({**previous, "status": "FAILED", "error": str(error)}, indent=2) + "\n", encoding="utf-8", newline="\n")
        raise
