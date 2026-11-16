#!/usr/bin/env python3
"""Focused real Swift compilation of passive Skill Runtime contracts only."""
import hashlib
import json
from pathlib import Path
import platform
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
OUTPUT = ROOT / "build/acceptance/skill-runtime-contracts"
SOURCES = [ROOT / "AI_HLY/Downstream/RuntimeCore/Core/Skills" / name for name in
           ["SkillRuntimeContract.swift", "SkillRuntimePlanner.swift", "SkillRuntimeRegistry.swift"]]
CHECKS = ROOT / "Scripts/CI/SkillRuntimeContractChecks.swift"


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main(node_facts=False):
    if sys.platform != "darwin" or platform.machine() != "arm64":
        raise RuntimeError("Actual macOS arm64 compiler required")
    output = OUTPUT.with_name("skill-runtime-node-facts") if node_facts else OUTPUT
    sources = [SOURCES[0], SOURCES[0].with_name("SkillRuntimeNodeCapabilityAdapter.swift")] if node_facts else SOURCES
    checks_source = CHECKS.with_name("SkillRuntimeNodeCapabilityAdapterChecks.swift") if node_facts else CHECKS
    expected_cases = 18 if node_facts else 38
    output.mkdir(parents=True, exist_ok=False)
    compiler = subprocess.check_output(["xcrun", "--find", "swiftc"], text=True).strip()
    sdk = subprocess.check_output(["xcrun", "--sdk", "iphonesimulator", "--show-sdk-path"], text=True).strip()
    host_sdk = subprocess.check_output(["xcrun", "--sdk", "macosx", "--show-sdk-path"], text=True).strip()
    result = {"schemaVersion": 1, "status": "FAILED", "sourceSHA": subprocess.check_output(
        ["git", "rev-parse", "HEAD"], text=True).strip(), "compiler": compiler,
        "swiftVersion": subprocess.check_output([compiler, "--version"], text=True).strip(),
        "xcode": subprocess.check_output(["xcodebuild", "-version"], text=True).strip(),
        "sdk": sdk, "hostSDK": host_sdk, "sourceFiles": {str(p.relative_to(ROOT)): sha(p) for p in [*sources, checks_source]},
        "commands": [], "scope": "NODE_FACT_ADAPTER_ONLY" if node_facts else "CONTRACT_PLANNER_REGISTRY_ONLY",
        "boundary": "Original passive production sources only. Synthetic cases; no real Skill, engine, app, JobStore, UI or physical-device execution."}

    def run(label, argv):
        completed = subprocess.run([str(v) for v in argv], cwd=ROOT, capture_output=True, timeout=180)
        (output / (label + ".stdout")).write_bytes(completed.stdout)
        (output / (label + ".stderr")).write_bytes(completed.stderr)
        result["commands"].append({"label": label, "arguments": [str(v) for v in argv], "exitCode": completed.returncode})
        if completed.returncode:
            print(completed.stderr.decode("utf-8", errors="replace")[-16000:], file=sys.stderr, flush=True)
            raise RuntimeError("Focused actual Swift check failed: " + label)
        return completed.stdout

    try:
        binary = output / "SkillRuntimeContractChecks"
        run("compile-macos", [compiler, "-swift-version", "6", "-sdk", host_sdk,
            "-target", "arm64-apple-macos26.0", *sources, checks_source, "-o", binary])
        checks = json.loads(run("execute-macos", [binary]))
        if checks.get("status") != "EXECUTED_PASS" or len(checks.get("cases", [])) != expected_cases:
            raise RuntimeError("Original focused test result/case identity mismatch")
        result["portableChecks"] = checks
        for deployment in ["26.0", "27.0"]:
            run("typecheck-ios" + deployment, [compiler, "-swift-version", "6", "-sdk", sdk,
                "-target", "arm64-apple-ios" + deployment + "-simulator", "-typecheck", *sources])
        if any(sha(ROOT / p) != digest for p, digest in result["sourceFiles"].items()):
            raise RuntimeError("Contract sources changed during actual checks")
        result["status"] = "EXECUTED_PASS"
    finally:
        (output / "result.json").write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
        manifest = [{"path": p.relative_to(output).as_posix(), "sha256": sha(p), "bytes": p.stat().st_size}
                    for p in sorted(output.rglob("*")) if p.is_file()]
        (output / "artifact-manifest.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"status": result["status"], "cases": len(result["portableChecks"]["cases"]),
                      "iOSDeploymentTargets": ["26.0", "27.0"], "boundary": result["boundary"]}))
    return 0


if __name__ == "__main__":
    raise SystemExit(main(node_facts="--node-facts" in sys.argv))
