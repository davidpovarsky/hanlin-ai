"""Identity of the Node/CPython binary inputs, independent of Host JS packages.

An existing bundle still requires its exact archive SHA, native framework SHA,
successful producer and recorded ownership smoke. This additional identity
permits rebuilding the Host without pretending that old binaries were rebuilt.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess

NATIVE_SCRIPTS = (
    "Scripts/Runtime/build-node-slice.sh",
    "Scripts/Runtime/prepare-node-source.sh",
    "Scripts/Runtime/apply-node-source-patches.py",
    "Scripts/Runtime/prepare-python-runtime.sh",
)


def native_identity(repository: Path, revision: str | None = None) -> str:
    def read(name):
        if revision:
            return subprocess.check_output(["git", "show", f"{revision}:{name}"], cwd=repository)
        return (repository / name).read_bytes()

    lock = json.loads(read("RuntimeDependencies.lock.json"))
    node = {key: value for key, value in lock["node"].items()
            if key not in {"verificationStatus", "xcframeworkSha256"}}
    adapter = node.get("buildConfiguration", {}).get("adapter", {}).get("path")
    patch_files = set()
    for item in node.get("sourcePatches", []):
        patch_files.add(item["path"])
        manifest = json.loads(read(item["path"]))
        originals = ([manifest["upstreamPatch"]] if manifest.get("upstreamPatch") else []) + manifest.get("upstreamPatches", [])
        for upstream in originals:
            name = upstream["path"]
            if not re.fullmatch(r"Scripts/Runtime/Patches/[A-Za-z0-9._-]+\.patch", name):
                raise ValueError("Invalid original upstream patch evidence path")
            patch_files.add(name)
    files = sorted(set(NATIVE_SCRIPTS) | patch_files | ({adapter} if adapter else set()))
    def input_bytes(name):
        contents = read(name)
        # Git checks these text scripts out as LF on the macOS builder. A
        # Windows CRLF checkout must identify those same build instructions.
        return contents.replace(b"\r\n", b"\n") if name in NATIVE_SCRIPTS or name == adapter else contents

    identity = {"formatVersion": lock["runtimeBundle"]["formatVersion"],
                "node": node, "python": lock["python"],
                "files": {name: hashlib.sha256(input_bytes(name)).hexdigest() for name in files}}
    return hashlib.sha256(json.dumps(identity, sort_keys=True, separators=(",", ":")).encode()).hexdigest()


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repository", type=Path, default=Path(__file__).resolve().parents[2])
    parser.add_argument("--revision")
    parser.add_argument("--verify-reuse", action="store_true")
    args = parser.parse_args()
    identity = native_identity(args.repository, args.revision)
    if args.verify_reuse:
        lock = json.loads((args.repository / "RuntimeDependencies.lock.json").read_text(encoding="utf-8"))
        if lock["runtimeBundle"].get("nativeInputSHA256") != identity:
            raise SystemExit("Native runtime inputs differ from the verified artifact producer. Build and verify a new native bundle; Host-only reuse is not valid.")
    print(identity)
