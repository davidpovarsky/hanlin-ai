#!/usr/bin/env python3
"""Build and execute only the proposed native export-authority counterexamples."""
import hashlib
import json
from pathlib import Path
import shlex
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


if __name__ == "__main__":
    raise SystemExit(main())
