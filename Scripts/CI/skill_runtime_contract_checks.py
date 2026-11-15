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


def main():
    if sys.platform != "darwin" or platform.machine() != "arm64":
        raise RuntimeError("Actual macOS arm64 compiler required")
    OUTPUT.mkdir(parents=True, exist_ok=False)
    compiler = subprocess.check_output(["xcrun", "--find", "swiftc"], text=True).strip()
    sdk = subprocess.check_output(["xcrun", "--sdk", "iphonesimulator", "--show-sdk-path"], text=True).strip()
    result = {"schemaVersion": 1, "status": "FAILED", "sourceSHA": subprocess.check_output(
        ["git", "rev-parse", "HEAD"], text=True).strip(), "compiler": compiler,
        "swiftVersion": subprocess.check_output([compiler, "--version"], text=True).strip(),
        "xcode": subprocess.check_output(["xcodebuild", "-version"], text=True).strip(),
        "sdk": sdk, "sourceFiles": {str(p.relative_to(ROOT)): sha(p) for p in [*SOURCES, CHECKS]},
        "commands": [], "boundary": "Original passive contract/planner/registry sources only. Synthetic cases; no real Skill, engine, app, JobStore, UI or physical-device execution."}

    def run(label, argv):
        completed = subprocess.run([str(v) for v in argv], cwd=ROOT, capture_output=True, timeout=180)
        (OUTPUT / (label + ".stdout")).write_bytes(completed.stdout)
        (OUTPUT / (label + ".stderr")).write_bytes(completed.stderr)
        result["commands"].append({"label": label, "arguments": [str(v) for v in argv], "exitCode": completed.returncode})
        if completed.returncode:
            print(completed.stderr.decode("utf-8", errors="replace")[-16000:], file=sys.stderr, flush=True)
            raise RuntimeError("Focused actual Swift check failed: " + label)
        return completed.stdout

    try:
        binary = OUTPUT / "SkillRuntimeContractChecks"
        run("compile-macos", [compiler, "-swift-version", "6", *SOURCES, CHECKS, "-o", binary])
        checks = json.loads(run("execute-macos", [binary]))
        if checks.get("status") != "EXECUTED_PASS" or len(checks.get("cases", [])) != 38:
            raise RuntimeError("Original focused test result/case identity mismatch")
        result["portableChecks"] = checks
        for deployment in ["26.0", "27.0"]:
            run("typecheck-ios" + deployment, [compiler, "-swift-version", "6", "-sdk", sdk,
                "-target", "arm64-apple-ios" + deployment + "-simulator", "-typecheck", *SOURCES])
        if any(sha(ROOT / p) != digest for p, digest in result["sourceFiles"].items()):
            raise RuntimeError("Contract sources changed during actual checks")
        result["status"] = "EXECUTED_PASS"
    finally:
        (OUTPUT / "result.json").write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
        manifest = [{"path": p.relative_to(OUTPUT).as_posix(), "sha256": sha(p), "bytes": p.stat().st_size}
                    for p in sorted(OUTPUT.rglob("*")) if p.is_file()]
        (OUTPUT / "artifact-manifest.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"status": result["status"], "cases": len(result["portableChecks"]["cases"]),
                      "iOSDeploymentTargets": ["26.0", "27.0"], "boundary": result["boundary"]}))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
