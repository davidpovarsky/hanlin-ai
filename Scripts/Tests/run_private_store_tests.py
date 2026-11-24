#!/usr/bin/env python3
"""Run the original persistence source closure on the installed native Swift toolchain."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess

parser = argparse.ArgumentParser()
parser.add_argument("--output", type=Path, required=True)
parser.add_argument("--filter", default="versionOneCheckpointCanBeRestoredWithoutDestructiveMigration|StoreSystemPathTests")
parser.add_argument("--source-sha", help="Exact Git revision when testing an exported source closure")
args = parser.parse_args()
root = Path(__file__).resolve().parents[2]
output = args.output.resolve()
output.mkdir(parents=True, exist_ok=False)
closure = {
    "HanlinPlatformContracts": "Packages/HanlinPlatform/Sources/HanlinPlatformContracts",
    "HanlinHostContracts": "Packages/HanlinAgentSDK/Sources/HanlinHostContracts",
    "HanlinPersistenceAdapters": "Packages/HanlinAgentSDK/Sources/HanlinPersistenceAdapters",
    "HanlinPersistenceAdaptersTests": "Packages/HanlinAgentSDK/Tests/HanlinPersistenceAdaptersTests",
}
hashes = {}
for target, source in closure.items():
    source = root / source
    shutil.copytree(source, output / "Sources" / target)
    for file in source.rglob("*"):
        if file.is_file():
            hashes[file.relative_to(root).as_posix()] = hashlib.sha256(file.read_bytes()).hexdigest()
manifest = """// swift-tools-version: 6.2
import PackageDescription
let package = Package(name: "HanlinPrivateStoreProof", platforms: [.macOS(.v26), .iOS("27.0")],
    targets: [
        .target(name: "HanlinPlatformContracts", resources: [.process("Resources")]),
        .target(name: "HanlinHostContracts", dependencies: ["HanlinPlatformContracts"]),
        .target(name: "HanlinPersistenceAdapters", dependencies: ["HanlinHostContracts"]),
        .testTarget(name: "HanlinPersistenceAdaptersTests", dependencies: ["HanlinPersistenceAdapters"],
                    path: "Sources/HanlinPersistenceAdaptersTests")
    ], swiftLanguageModes: [.v6])
"""
(output / "Package.swift").write_text(manifest)
command = ["swift", "test", "--package-path", str(output), "--jobs", "2", "--filter", args.filter]
receipt = {
    "sourceSHA": args.source_sha or subprocess.check_output(["git", "-C", str(root), "rev-parse", "HEAD"], text=True).strip(),
    "sourceStatus": "exported source closure; input hashes below" if args.source_sha else subprocess.check_output(["git", "-C", str(root), "status", "--porcelain"], text=True),
    "inputs": hashes, "command": command,
    "toolchain": subprocess.check_output(["swift", "--version"], text=True).strip(),
    "manifestSHA256": hashlib.sha256(manifest.encode()).hexdigest(),
}
with (output / "native-test.log").open("w") as log:
    result = subprocess.run(command, stdout=log, stderr=subprocess.STDOUT)
receipt["exitCode"] = result.returncode
(output / "receipt.json").write_text(json.dumps(receipt, indent=2, sort_keys=True) + "\n")
print(json.dumps({k: v for k, v in receipt.items() if k != "inputs"}, indent=2))
print((output / "native-test.log").read_text()[-16000:])
raise SystemExit(result.returncode)
