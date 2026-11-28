#!/usr/bin/env python3
"""Stage byte-identical production renderer sources for focused iOS WebKit tests."""
import hashlib
import json
import pathlib
import shutil


def stage(root: pathlib.Path, output: pathlib.Path) -> None:
    presentation = root / "Packages/HanlinPresentationSDK/Sources"
    source = presentation / "HanlinChatUI/CodeFences"
    destination = output / "Sources/HanlinCodeFenceProof"
    destination.mkdir(parents=True, exist_ok=True)
    files = list(source.glob("*.swift")) + [
        presentation / "HanlinChatUI/HanlinPresentationDiagnostics.swift",
    ]
    evidence = []
    for file in files:
        shutil.copy2(file, destination / file.name)
        evidence.append({"path": file.relative_to(root).as_posix(), "sha256": hashlib.sha256(file.read_bytes()).hexdigest()})
    shutil.copytree(source / "Resources", destination / "Resources", dirs_exist_ok=True)
    # Compile the exact canonical typography/profile module used by the renderer;
    # the focused package neither copies an app logger nor invents a typography stub.
    kit = output / "Sources/HanlinPresentationKit"
    kit.mkdir(parents=True, exist_ok=True)
    for file in sorted((presentation / "HanlinPresentationKit").glob("*.swift")):
        shutil.copy2(file, kit / file.name)
        evidence.append({"path": file.relative_to(root).as_posix(), "sha256": hashlib.sha256(file.read_bytes()).hexdigest()})
    localization = presentation / "HanlinLocalization"
    for file in sorted(localization.rglob("*")):
        if not file.is_file():
            continue
        target = output / "Sources/HanlinLocalization" / file.relative_to(localization)
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(file, target)
        evidence.append({"path": file.relative_to(root).as_posix(), "sha256": hashlib.sha256(file.read_bytes()).hexdigest()})
    tests = output / "Tests/HanlinCodeFenceProofTests"
    tests.mkdir(parents=True, exist_ok=True)
    shutil.copy2(root / "AI_HLYTests/ChatCodeFenceTests.swift", tests / "ChatCodeFenceTests.swift")
    for file in sorted((source / "Resources").glob("*")) + [root / "AI_HLYTests/ChatCodeFenceTests.swift"]:
        evidence.append({"path": file.relative_to(root).as_posix(), "sha256": hashlib.sha256(file.read_bytes()).hexdigest()})
    (output / "Package.swift").write_text('''// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "HanlinCodeFenceProof", defaultLocalization: "zh-Hans", platforms: [.iOS("27.0")],
    products: [.library(name: "HanlinCodeFenceProof", targets: ["HanlinCodeFenceProof"])],
    targets: [
        .target(name: "HanlinPresentationKit"),
        .target(name: "HanlinLocalization", resources: [.process("Resources")]),
        .target(name: "HanlinCodeFenceProof", dependencies: ["HanlinPresentationKit", "HanlinLocalization"],
                resources: [.copy("Resources/HanlinCodeFenceAssets.json"),
                            .copy("Resources/HanlinCodeFenceRenderer.js"),
                            .copy("Resources/HanlinCodeFenceRenderer.css"),
                            .copy("Resources/HanlinCodeFenceRenderer.js.LEGAL.txt"),
                            .copy("Resources/HanlinCodeFenceThirdPartyLicenses.txt")]),
        .testTarget(name: "HanlinCodeFenceProofTests", dependencies: ["HanlinCodeFenceProof"])
    ])
''', encoding="utf8", newline="\n")
    (output / "production-inputs.json").write_text(json.dumps(evidence, indent=2) + "\n", encoding="utf8", newline="\n")


if __name__ == "__main__":
    root = pathlib.Path(__file__).resolve().parents[2]
    stage(root, root / "build/ChatCodeFenceProof")
