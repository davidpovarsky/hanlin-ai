"""Prepare the actual three YouTube sources and eight controls for iOS SDK compilation.

This is component verification, not playback, provider, transcript or XCUITest acceptance.
"""
import argparse
import json
from pathlib import Path
import re
import sys
from prepare_exact_pin_proof import sha

ROOT = Path(__file__).resolve().parents[2]
SOURCES = "AI_HLY/Downstream/ChatPresentation/Media"
TEST = "AI_HLYTests/HanlinYouTubeTests.swift"
PACKAGE = '''// swift-tools-version: 6.1
import PackageDescription
let package = Package(name: "HanlinChatMediaProof", platforms: [.iOS("27.0")], targets: [
    .target(name: "HanlinChatMediaProof"),
    .testTarget(name: "HanlinChatMediaProofTests", dependencies: ["HanlinChatMediaProof"],
                swiftSettings: [.define("HANLIN_MEDIA_ISOLATED_PROOF")])
], swiftLanguageModes: [.v6])
'''


def plan():
    paths = sorted((ROOT / SOURCES).glob("HanlinYouTube*.swift")) + [ROOT / TEST]
    names = re.findall(r"@Test func (\w+)\(", (ROOT / TEST).read_text(encoding="utf-8"))
    if len(paths) != 4 or len(set(names)) != 8:
        raise ValueError("Expected three production YouTube files and eight controls")
    return {"scope": "iOS27 SDK component; playback/full-app XCUITest NOT_RUN", "cases": names,
            "files": [{"path": p.relative_to(ROOT).as_posix(), "sha256": sha(p.read_bytes())} for p in paths],
            "manifest_sha256": sha(PACKAGE.encode())}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    inputs = plan()
    if args.output:
        destination = args.output.resolve()
        if sys.platform != "darwin" or destination.exists() or destination.is_relative_to(ROOT):
            raise ValueError("Use a fresh macOS scratch path outside the checkout")
        destination.mkdir()
        for row in inputs["files"]:
            original = ROOT / row["path"]
            data = original.read_bytes()
            if sha(data) != row["sha256"]:
                raise ValueError("Source changed during preparation")
            folder = "Tests/HanlinChatMediaProofTests" if row["path"] == TEST else "Sources/HanlinChatMediaProof"
            target = destination / folder / original.name
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(data)
        (destination / "Package.swift").write_text(PACKAGE)
        (destination / "proof-inputs.json").write_text(json.dumps(inputs, indent=2) + "\n")
    print(json.dumps(inputs, indent=2))


if __name__ == "__main__":
    main()
