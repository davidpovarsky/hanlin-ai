#!/usr/bin/env python3
"""Build and execute only the proposed native export-authority counterexamples."""
import hashlib
import json
from pathlib import Path
import shlex
import os
import sys
import subprocess

ROOT = Path(__file__).resolve().parents[3]
OUTPUT = ROOT / "build/acceptance/metadata-sdk-export-audit"
REFERENCE = ROOT / "build/sdk-export-compile-reference/acceptance/metadata-sdk-linkage-controls"


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    OUTPUT.mkdir(parents=True, exist_ok=False)
    original = json.loads((REFERENCE / "result.json").read_text())
    for record in json.loads((REFERENCE / "artifact-manifest.json").read_text()):
        if sha(REFERENCE / record["path"]) != record["sha256"]:
            raise RuntimeError("Original compiler/link evidence hash mismatch")
    sdk = Path(subprocess.check_output(["xcrun", "--sdk", "iphonesimulator", "--show-sdk-path"], text=True).strip())
    xcode = subprocess.check_output(["xcodebuild", "-version"], text=True).strip()
    if str(sdk) != original["sdk"] or xcode != original["xcode"]:
        raise RuntimeError("Original SDK/compiler identity changed")
    for item in original["files"]:
        if sha(Path(item["path"])) != item["sha256"]:
            raise RuntimeError("Original SDK source/export bytes changed")
    symbols = {}
    for case in original["cases"]:
        declaration = json.loads((REFERENCE / case["declaration"]["stdout"]).read_text())
        if case["compile"]["exitCode"] != 0 or case["link"]["exitCode"] != (0 if case["language"] == "objective-c" else 1):
            raise RuntimeError("Original focused compile/link condition not proven")
        if sha(Path(case["compilerPath"])) != case["compilerSHA256"]:
            raise RuntimeError("Original compiler bytes changed")
        symbol = declaration["mangledName"]
        if case["language"] in symbols and symbols[case["language"]] != symbol:
            raise RuntimeError("Apple and locked compiler symbol disagreement")
        symbols[case["language"]] = symbol
    lock = json.loads((ROOT / "Scripts/NativeScript/metadata-frontend-lock.json").read_text())
    frontend = Path(lock["installedPrefix"])
    for relative, digest in lock["files"].items():
        if sha(frontend / relative) != digest:
            raise RuntimeError("Locked LLVM library/compiler changed")
    source = ROOT / "Scripts/CI/MetadataProvenanceProof/SDKExportAudit.cpp"
    binary = OUTPUT / "SDKExportAudit"
    dependency = OUTPUT / "SDKExportAudit.d"
    compiler = Path(subprocess.check_output(["xcrun", "--find", "clang++"], text=True).strip())
    host_sdk = Path(subprocess.check_output(["xcrun", "--sdk", "macosx", "--show-sdk-path"], text=True).strip())
    command = ["xcrun", "--sdk", "macosx", "clang++", "-std=c++17", "-isysroot", str(host_sdk), "-isystem", str(host_sdk / "usr/include/c++/v1"), "-I" + str(frontend / "include"), str(source), "-L" + str(frontend / "lib"),
        "-Wl,-rpath," + str(frontend / "lib"), "-lLLVM", "-MD", "-MF", str(dependency), "-o", str(binary)]
    receipt = {"sourceSHA256": sha(source), "compileCommand": command, "compilerSHA256": sha(compiler),
        "originalCompilerLinkRun": 43753808737, "originalResultSHA256": sha(REFERENCE / "result.json"),
        "sdk": str(sdk), "hostSDK": str(host_sdk), "xcode": xcode, "target": original["target"], "runtimeAcceptance": "NOT_RUN"}
    with (OUTPUT / "compile.log").open("wb") as log:
        built = subprocess.run(command, stdout=log, stderr=subprocess.STDOUT, timeout=90)
    receipt["compileExitCode"] = built.returncode
    if built.returncode:
        (OUTPUT / "provenance.json").write_text(json.dumps(receipt, indent=2) + "\n")
        return 1
    dependencies = [Path(value) for value in shlex.split(dependency.read_text().replace("\\\n", " ").partition(":")[2])]
    receipt["compileInputs"] = {str(path.resolve()): sha(path) for path in dependencies if path.is_file()}
    receipt["binarySHA256"] = sha(binary)
    stub = sdk / "System/Library/Frameworks/AVFoundation.framework/AVFoundation.tbd"
    # Preserve the full bound deployment triple separately. TAPI slice identity
    # is architecture + platform, as specified by LLVM Target::operator==.
    target = "arm64-ios-simulator"
    command = [str(binary), str(sdk), str(stub), target, symbols["objective-c"], symbols["objective-c++"], str(OUTPUT / "result.json")]
    receipt["executeCommand"] = command
    with (OUTPUT / "execute.log").open("wb") as log:
        executed = subprocess.run(command, stdout=log, stderr=subprocess.STDOUT, timeout=30)
    receipt["executeExitCode"] = executed.returncode
    (OUTPUT / "provenance.json").write_text(json.dumps(receipt, indent=2) + "\n")
    manifest = [{"path": p.relative_to(OUTPUT).as_posix(), "sha256": sha(p), "bytes": p.stat().st_size} for p in sorted(OUTPUT.rglob("*")) if p.is_file()]
    (OUTPUT / "artifact-manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    print(json.dumps({"compileExitCode": built.returncode, "executeExitCode": executed.returncode, "scope": "EXPORT_AUTHORITY_PROTOTYPE_ONLY"}))
    return executed.returncode


def verify_unchanged_prior_pass():
    """Revalidate exact native test, fixtures and transitive inputs; do not execute."""
    previous = ROOT / "build/sdk-export-original-pass-reference/acceptance/metadata-sdk-export-audit"
    result = json.loads((previous / "result.json").read_text())
    provenance = json.loads((previous / "provenance.json").read_text())
    for item in json.loads((previous / "artifact-manifest.json").read_text()):
        if sha(previous / item["path"]) != item["sha256"]:
            raise RuntimeError("Original native export test artifact changed")
    if result.get("status") != "EXECUTED_PASS" or len(result.get("cases", [])) != 9 or any(c.get("status") != "EXECUTED_PASS" for c in result["cases"]) or provenance.get("compileExitCode") != 0 or provenance.get("executeExitCode") != 0:
        raise RuntimeError("Original exact9-case native export test did not pass")
    if sha(previous / "SDKExportAudit") != provenance["binarySHA256"]:
        raise RuntimeError("Original passing native export image differs from provenance")
    if provenance.get("sourceSHA256") != sha(ROOT / "Scripts/CI/MetadataProvenanceProof/SDKExportAudit.cpp"):
        raise RuntimeError("Native export assertions/fixtures changed; rerun required")
    for path, digest in provenance["compileInputs"].items():
        if not Path(path).is_file() or sha(Path(path)) != digest:
            raise RuntimeError("Native export transitive compiler/source input changed; rerun required")
    if subprocess.check_output(["xcrun", "--sdk", "iphonesimulator", "--show-sdk-path"], text=True).strip() != provenance["sdk"]:
        raise RuntimeError("Original SDK export fixture selection changed; rerun required")
    apple = Path(subprocess.check_output(["xcrun", "--find", "clang++"], text=True).strip())
    if sha(apple) != provenance["compilerSHA256"] or subprocess.check_output(["xcodebuild", "-version"], text=True).strip() != provenance["xcode"]:
        raise RuntimeError("Native export Apple toolchain changed; rerun required")
    original_tool = json.loads((ROOT / "build/sdk-export-original-pass-reference/nativescript-modern-metadata-tool/provenance.json").read_text())
    if any(os.environ.get(key) != value for key, value in original_tool["compilerEnvironment"].items()):
        raise RuntimeError("Original native export environment changed; rerun required")
    frontend = Path(original_tool["frontendRoot"])
    for name, digest in original_tool["libraries"].items():
        if sha(frontend / "lib" / name) != digest:
            raise RuntimeError("Native export original LLVM library changed; rerun required")
    positive = next(c for c in result["cases"] if c["case"] == "actual-sdk-single-C-export")
    for path, digest in positive["decision"]["consumedExportFiles"].items():
        if sha(Path(path)) != digest:
            raise RuntimeError("Native export target fixture changed; rerun required")
    binding_path = ROOT / "build/modern-compile-reference/acceptance/nativescript-sdk-probe-dual/textual-public/sdk-export-evidence/binding-evidence.json"
    binding = json.loads(binding_path.read_text())
    if binding.get("target") != provenance["target"] or any(sha(Path(f["source"])) != f["sourceSHA256"] for f in binding["functions"]):
        raise RuntimeError("Original SDK source/target fixture changed; rerun required")
    OUTPUT.mkdir(parents=True, exist_ok=False)
    receipt = {"status": "REUSED_VERIFIED_PASS", "originalRun": 43757087726,
        "originalResultSHA256": sha(previous / "result.json"), "originalSourceSHA": "1191af99",
        "caseCount": 9, "verifiedCompileInputs": len(provenance["compileInputs"]),
        "scope": "EXACT_NATIVE_EXPORT_AND_TARGET_COUNTEREXAMPLES", "newTestExecution": "NOT_RUN",
        "boundary": "Original native9-case pass reused after complete source/assertion/fixture/compiler/dependency/library/environment checks; not SDK/VM acceptance."}
    (OUTPUT / "result.json").write_text(json.dumps(receipt, indent=2) + "\n")
    (OUTPUT / "artifact-manifest.json").write_text(json.dumps([{"path": "result.json", "sha256": sha(OUTPUT / "result.json"), "bytes": (OUTPUT / "result.json").stat().st_size}], indent=2) + "\n")
    print(json.dumps(receipt))
    return 0


if __name__ == "__main__":
    raise SystemExit(verify_unchanged_prior_pass() if "--verify-unchanged-prior-pass" in sys.argv else main())
