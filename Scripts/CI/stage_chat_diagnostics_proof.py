#!/usr/bin/env python3
"""Stage byte-identical production diagnostics for focused real iOS tests."""
import hashlib
import json
from pathlib import Path
import shutil


def stage(root: Path) -> None:
    output = root / "build/ChatDiagnosticsProof"
    sources = output / "Sources/HanlinChatDiagnosticsProof"
    tests = output / "Tests/HanlinChatDiagnosticsProofTests"
    sources.mkdir(parents=True, exist_ok=True)
    tests.mkdir(parents=True, exist_ok=True)
    evidence = []
    for name in ["AgentDiagnosticsConfiguration", "AgentDiagnosticsExport", "AgentDiagnosticsJournal",
                 "AgentDiagnosticsRawReview", "AgentDiagnosticsRedactor", "AgentDiagnosticsSession", "AgentTokenUsage"]:
        source = root / f"AI_HLY/Downstream/AgentDiagnostics/{name}.swift"
        shutil.copy2(source, sources / source.name)
        evidence.append(source)
    logger = root / "AI_HLY/NativeAgentExtensions/Diagnostics/NativeToolTraceLogger.swift"
    shutil.copy2(logger, sources / logger.name)
    evidence.append(logger)
    for name in ["AgentDiagnosticsExportTests", "AgentDiagnosticsJournalTests", "AgentDiagnosticsRawReviewTests", "AgentDiagnosticsSessionPersistenceTests"]:
        source = root / f"AI_HLYTests/{name}.swift"
        shutil.copy2(source, tests / source.name)
        evidence.append(source)
    evidence += [root / "Packages/HanlinPlatform/Package.swift"]
    evidence += sorted((root / "Packages/HanlinPlatform/Sources/HanlinChatCore").rglob("*.swift"))
    evidence += [p for p in sorted((root / "Packages/HanlinPlatform/Sources/HanlinPlatformContracts").rglob("*")) if p.is_file()]
    (output / "Package.swift").write_text('''// swift-tools-version: 6.2
import PackageDescription
let package = Package(name: "HanlinChatDiagnosticsProof", platforms: [.iOS("27.0")],
    products: [.library(name: "HanlinChatDiagnosticsProof", targets: ["HanlinChatDiagnosticsProof"])],
    dependencies: [
        .package(path: "../../Packages/HanlinPlatform"),
        .package(url: "https://github.com/weichsel/ZIPFoundation.git", exact: "0.9.19")
    ],
    targets: [
        .target(name: "HanlinChatDiagnosticsProof", dependencies: [
            .product(name: "HanlinChatCore", package: "HanlinPlatform"),
            .product(name: "ZIPFoundation", package: "ZIPFoundation")]),
        .testTarget(name: "HanlinChatDiagnosticsProofTests", dependencies: ["HanlinChatDiagnosticsProof"])
    ])
''', encoding="utf-8", newline="\n")
    records = [{"path": p.relative_to(root).as_posix(), "sha256": hashlib.sha256(p.read_bytes()).hexdigest()} for p in evidence]
    (output / "production-inputs.json").write_text(json.dumps(records, indent=2) + "\n", encoding="utf-8", newline="\n")


if __name__ == "__main__":
    stage(Path(__file__).resolve().parents[2])
