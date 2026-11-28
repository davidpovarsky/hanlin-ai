"""Create a fresh test-only package with byte-identical bootstrap source/tests."""
import argparse
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
SOURCES = ["AI_HLY/Downstream/ProductSplitIntegration/HanlinMiniAppsBootstrap.swift",
           "Scripts/CI/IntegrationValidation/MiniAppsBootstrapTests.swift"]
MANIFEST = '''// swift-tools-version: 6.2
import PackageDescription
let package = Package(
    name: "MiniAppsBootstrapProof",
    platforms: [.iOS("27.0"), .macOS("27.0")],
    targets: [.testTarget(name: "MiniAppsBootstrapTests", path: "Tests")],
    swiftLanguageModes: [.v6]
)
'''

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=False)
    (output / "Tests").mkdir()
    hashes = {}
    for relative in SOURCES:
        data = (ROOT / relative).read_bytes()
        (output / "Tests" / Path(relative).name).write_bytes(data)
        hashes[relative] = hashlib.sha256(data).hexdigest()
    (output / "Package.swift").write_text(MANIFEST, encoding="utf-8", newline="\n")
    (output / "proof-inputs.json").write_text(json.dumps(hashes, indent=2), encoding="utf-8", newline="\n")
    print(output)
