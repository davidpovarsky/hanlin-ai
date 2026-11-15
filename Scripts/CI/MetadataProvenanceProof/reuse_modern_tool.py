#!/usr/bin/env python3
"""Reuse only the previously compiled, source-identical candidate tool image."""
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[3]


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    reference = ROOT / "build/modern-compile-reference/nativescript-modern-metadata-tool"
    receipt = reference / "provenance.json"
    if not receipt.is_file():
        print("NEEDS_BUILD: original compiled artifact unavailable")
        return
    evidence = json.loads(receipt.read_text())
    expected = {"basePatchSourceSHA256": "Scripts/NativeScript/build-metadata-tool.py",
        "modernPatchSourceSHA256": "Scripts/NativeScript/build-modern-metadata-tool.py",
        "frontendLockSHA256": "Scripts/NativeScript/metadata-frontend-lock.json"}
    if evidence.get("status") != "BUILT_NOT_ACCEPTED" or any(evidence.get(key) != sha(ROOT / path) for key, path in expected.items()):
        print("NEEDS_BUILD: candidate build source/lock changed")
        return
    if evidence["xcode"] != subprocess.check_output(["xcodebuild", "-version"], text=True).strip():
        print("NEEDS_BUILD: actual Xcode compiler changed")
        return
    if not evidence.get("externalCompileInputs") or not evidence.get("buildTools") or not evidence.get("compilerEnvironment"):
        print("NEEDS_BUILD: original compile/toolchain input closure unavailable")
        return
    if any(os.environ.get(key) != value for key, value in evidence["compilerEnvironment"].items()) or any(
        not Path(path).is_file() or sha(Path(path)) != digest for path, digest in evidence["externalCompileInputs"].items()) or any(
        not Path(tool["path"]).is_file() or sha(Path(tool["path"])) != tool["sha256"] for tool in evidence["buildTools"].values()):
        print("NEEDS_BUILD: actual host compiler/linker/SDK/environment changed")
        return
    frontend = Path(evidence["frontendRoot"])
    inputs = {**evidence["frontendInputs"], **{"lib/" + name: digest for name, digest in evidence["libraries"].items()}}
    if not inputs or any(not (frontend / path).is_file() or sha(frontend / path) != digest for path, digest in inputs.items()):
        print("NEEDS_BUILD: actual frontend headers/resources/libraries changed")
        return
    if sha(reference / "bin/objc-metadata-generator") != evidence["generatorSHA256"]:
        raise RuntimeError("Original compiled image digest mismatch")
    destination = ROOT / "build/nativescript-modern-metadata-tool"
    shutil.copytree(reference / "bin", destination / "bin")  # Exclusive; never overwrite owned outputs.
    # GitHub artifact transport preserves bytes but normalizes file modes.
    # Restore only this verified, newly owned executable's original launch mode.
    (destination / "bin/objc-metadata-generator").chmod(0o755)
    shutil.copy2(receipt, destination / "provenance.json")
    (destination / "compile-reuse.json").write_text(json.dumps({"status": "REUSED_VERIFIED_COMPILE_PASS",
        "originalRun": 43729552849, "originalSourceSHA": "18538343a021d5eb0a1b5d9ad2f35d949c9826fd", "generatorSHA256": evidence["generatorSHA256"],
        "originalReceiptSHA256": sha(receipt), "verifiedFrontendInputs": len(inputs),
        "boundary": "Original compile step passed; original aggregate run failed. No new compilation or metadata acceptance claimed."}, indent=2) + "\n")
    print("REUSED_VERIFIED_COMPILE_PASS: original source, binary, Xcode and complete frontend input hashes match")


if __name__ == "__main__":
    main()
