#!/usr/bin/env python3
"""Stage byte-identical production renderer sources for focused iOS WebKit tests."""
import hashlib
import json
import pathlib
import shutil


def stage(root: pathlib.Path, output: pathlib.Path) -> None:
    source = root / "AI_HLY/Downstream/ChatPresentation/CodeFences"
    destination = output / "Sources/HanlinCodeFenceProof"
    destination.mkdir(parents=True, exist_ok=True)
    files = list(source.glob("*.swift")) + [
        root / "AI_HLY/NativeAgentExtensions/Diagnostics/NativeToolTraceLogger.swift",
        root / "AI_HLY/Downstream/AgentDiagnostics/AgentDiagnosticsRedactor.swift",
    ]
    evidence = []
    for file in files:
        shutil.copy2(file, destination / file.name)
        evidence.append({"path": file.relative_to(root).as_posix(), "sha256": hashlib.sha256(file.read_bytes()).hexdigest()})
    shutil.copytree(source / "Resources", destination / "Resources", dirs_exist_ok=True)
    tests = output / "Tests/HanlinCodeFenceProofTests"
    tests.mkdir(parents=True, exist_ok=True)
    shutil.copy2(root / "AI_HLYTests/ChatCodeFenceTests.swift", tests / "ChatCodeFenceTests.swift")
    for file in sorted((source / "Resources").glob("*")) + [root / "AI_HLYTests/ChatCodeFenceTests.swift"]:
        evidence.append({"path": file.relative_to(root).as_posix(), "sha256": hashlib.sha256(file.read_bytes()).hexdigest()})
    (output / "Package.swift").write_text('''// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "HanlinCodeFenceProof", platforms: [.iOS("26.0")],
    products: [.library(name: "HanlinCodeFenceProof", targets: ["HanlinCodeFenceProof"])],
    targets: [
        .target(name: "HanlinCodeFenceProof", resources: [.process("Resources")]),
        .testTarget(name: "HanlinCodeFenceProofTests", dependencies: ["HanlinCodeFenceProof"])
    ])
''', encoding="utf8", newline="\n")
    (output / "production-inputs.json").write_text(json.dumps(evidence, indent=2) + "\n", encoding="utf8", newline="\n")


if __name__ == "__main__":
    root = pathlib.Path(__file__).resolve().parents[2]
    stage(root, root / "build/ChatCodeFenceProof")
