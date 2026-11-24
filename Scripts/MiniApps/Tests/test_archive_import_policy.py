#!/usr/bin/env python3
"""Execute actual production Swift archive policy/parser in a portable package.

Only unrelated native-module imports are avoided: the archive contracts and
PackageCenter's private ZIP directory parser are extracted verbatim. This does
not claim to run ZIPFoundation extraction or the Darwin shared store.
"""
from pathlib import Path
import argparse
import hashlib
import json
import os
import shutil
import struct
import subprocess
import tempfile
import zipfile

ROOT = Path(__file__).resolve().parents[3]
parser = argparse.ArgumentParser()
parser.add_argument("--output", type=Path, required=True)
args = parser.parse_args()
args.output.mkdir(parents=True, exist_ok=True)
compiler_root = ROOT / "Packages/HanlinPlatform/Sources/HanlinScriptCompiler"
contracts_file = ROOT / "Packages/HanlinPlatform/Sources/HanlinScriptContracts/HanlinPackageContracts.swift"
policy_file = compiler_root / "HanlinArchivePolicy.swift"
path_file = ROOT / "Packages/HanlinPlatform/Sources/HanlinPlatformContracts/HanlinPackagePath.swift"
center_file = compiler_root / "HanlinPackageCenter.swift"
tests_file = ROOT / "Packages/HanlinPlatform/Tests/HanlinScriptCompilerTests/HanlinArchivePolicyTests.swift"

with tempfile.TemporaryDirectory(prefix="hanlin-archive-policy-", dir=os.environ.get("HANLIN_AUTHORING_TMP")) as temporary:
    package = Path(temporary)
    contracts = contracts_file.read_text()
    contract_body = contracts[contracts.index("public enum HanlinArchiveFindingCode"):
                              contracts.index("public struct HanlinScriptingAuthor")]
    center = center_file.read_text()
    error_body = center[center.index("public enum HanlinPackageCenterError"):
                        center.index("public struct HanlinStagedPackage")]
    parser_body = center[center.index("    private static func centralDirectoryEntryCount"):
                         center.rfind("\n}")]
    production = {
        "Sources/HanlinPlatformContracts/HanlinPackagePath.swift": path_file.read_text(),
        "Sources/HanlinScriptContracts/ArchiveContracts.swift": "import Foundation\n" + contract_body,
        "Sources/HanlinScriptCompiler/HanlinArchivePolicy.swift": policy_file.read_text(),
        "Sources/HanlinScriptCompiler/DirectoryParser.swift":
            "import Foundation\nimport HanlinScriptContracts\n" + error_body +
            "\nstruct DirectoryParser {\n" + parser_body +
            "\nstatic func count(_ data: Data) throws -> Int { try centralDirectoryEntryCount(in: data) }\n}\n",
        "Tests/ArchiveImportPolicyTests/HanlinArchivePolicyTests.swift": tests_file.read_text(),
    }
    for name, source in production.items():
        target = package / name
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(source)
    (package / "Package.swift").write_text("""// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "ArchiveImportPolicyProbe", targets: [
    .target(name: "HanlinPlatformContracts"),
    .target(name: "HanlinScriptContracts"),
    .target(name: "HanlinScriptCompiler", dependencies: ["HanlinPlatformContracts", "HanlinScriptContracts"]),
    .testTarget(name: "ArchiveImportPolicyTests", dependencies: ["HanlinScriptCompiler", "HanlinScriptContracts"])
])
""")
    fixtures = package / "fixtures"
    fixtures.mkdir()
    with zipfile.ZipFile(fixtures / "ordinary.zip", "w", compression=zipfile.ZIP_DEFLATED) as archive:
        archive.writestr("script.json", '{"name":"Source archive","version":"1.0.0"}')
        archive.writestr("source/script.json", '{"name":"Retained source","version":"1.0.0"}')
        for name in ["assets/font.ttf", "assets/module.wasm", "bundle.js.map", "data/config.yaml", "LICENSE"]:
            archive.writestr(name, b"x" * 200_000)
    with zipfile.ZipFile(fixtures / "comment.zip", "w", compression=zipfile.ZIP_STORED) as archive:
        archive.writestr("script.json", '{"name":"Comment","version":"1.0.0"}')
        archive.comment = b"signature in a comment: PK\x05\x06" + b"x" * 24
    with zipfile.ZipFile(fixtures / "zip64.zip", "w", compression=zipfile.ZIP_STORED) as archive:
        archive.writestr("script.json", '{"name":"Many resources","version":"1.0.0"}')
        for index in range(65_535):
            archive.writestr(f"assets/{index}.bin", b"")
    with zipfile.ZipFile(fixtures / "ordinary.zip") as archive:
        metadata = [{"path": item.filename, "kind": "file",
                     "compressedBytes": item.compress_size, "uncompressedBytes": item.file_size}
                    for item in archive.infolist()]
    (fixtures / "ordinary.json").write_text(json.dumps(metadata))
    valid = (fixtures / "zip64.zip").read_bytes()
    eocd = valid.rfind(b"PK\x05\x06")
    locator = eocd - 20
    record = struct.unpack_from("<Q", valid, locator + 8)[0]
    corruptions = {
        "zip64-invalid-offset.zip": (locator + 8, "<Q", len(valid) + 1),
        "zip64-multiple-disks.zip": (locator + 16, "<I", 2),
        "zip64-count-mismatch.zip": (record + 24, "<Q", 1),
        "zip64-count-overflow.zip": (record + 32, "<Q", (1 << 64) - 1),
        "zip64-invalid-record-size.zip": (record + 4, "<Q", (1 << 64) - 1),
    }
    for name, (offset, format_, value) in corruptions.items():
        data = bytearray(valid)
        struct.pack_into(format_, data, offset, value)
        if name == "zip64-count-overflow.zip":
            struct.pack_into("<Q", data, record + 24, value)
        (fixtures / name).write_bytes(data)
    with zipfile.ZipFile(fixtures / "classic-count-sentinel.zip", "w", compression=zipfile.ZIP_STORED) as archive:
        archive.writestr("script.json", '{"name":"Classic count boundary","version":"1.0.0"}')
        for index in range(65_534):
            archive.writestr(f"assets/{index}.bin", b"")

    tests = r'''
import Foundation
import HanlinScriptContracts
import Testing
@testable import HanlinScriptCompiler

struct HanlinArchiveDirectoryTests {
    private let fixtureRoot = URL(fileURLWithPath: FIXTURE_DIRECTORY)
    private func bytes(_ name: String) throws -> Data {
        try Data(contentsOf: fixtureRoot.appendingPathComponent(name))
    }

    @Test func realSourceArchiveIncludesRetainedManifestAndOrdinaryAssets() throws {
        let data = try bytes("ordinary.zip")
        let count = try DirectoryParser.count(data)
        let metadata = try JSONDecoder().decode([HanlinArchiveEntryMetadata].self, from: bytes("ordinary.json"))
        #expect(count == metadata.count)
        #expect(try DirectoryParser.count(bytes("comment.zip")) == 1)
        #expect(metadata.contains { $0.uncompressedBytes / max(1, $0.compressedBytes) > 100 })
        let result = HanlinArchivePolicy().inspect(entries: metadata,
            centralDirectoryEntryCount: count, archiveBytes: Int64(data.count))
        #expect(result.isInstallable)
        #expect(result.manifestPath == "script.json")
    }

    @Test func realZip64ArchiveKeepsTheEntireDirectoryCount() throws {
        #expect(try DirectoryParser.count(bytes("zip64.zip")) == 65_536)
        #expect(try DirectoryParser.count(bytes("classic-count-sentinel.zip")) == 65_535)
    }

    @Test(arguments: [
        "zip64-invalid-offset.zip", "zip64-multiple-disks.zip",
        "zip64-count-mismatch.zip", "zip64-count-overflow.zip",
        "zip64-invalid-record-size.zip"
    ])
    func rejectsMalformedZip64Directory(name: String) throws {
        let data = try bytes(name)
        #expect(throws: HanlinPackageCenterError.unreadableArchive) { try DirectoryParser.count(data) }
    }
}
'''
    tests = tests.replace("FIXTURE_DIRECTORY", json.dumps(str(fixtures)))
    (package / "Tests/ArchiveImportPolicyTests/HanlinArchiveDirectoryTests.swift").write_text(tests)
    swift = shutil.which("swift")
    if not swift:
        raise SystemExit("Swift is required to execute the actual production archive policy.")
    toolchain = subprocess.run([swift, "--version"], capture_output=True, text=True, check=True).stdout.strip()
    completed = subprocess.run([swift, "test", "--package-path", str(package),
                                "--scratch-path", str(package / ".build")],
                               capture_output=True, text=True, timeout=180)
    output = completed.stdout + completed.stderr
    (args.output / "archive-import-policy.txt").write_text(output)
    receipt = {
        "schemaVersion": 1,
        "status": "EXECUTED_PASS" if completed.returncode == 0 else "FAILED",
        "toolchain": toolchain,
        "command": "swift test (isolated portable package; production policy and private parser verbatim)",
        "inputs": [{"path": str(file.relative_to(ROOT)), "sha256": hashlib.sha256(file.read_bytes()).hexdigest()}
                   for file in [contracts_file, policy_file, path_file, center_file, tests_file, Path(__file__)]],
        "parserBodySHA256": hashlib.sha256(parser_body.encode()).hexdigest(),
        "rawLog": "archive-import-policy.txt",
        "fixtures": {"ordinaryZIPEntries": len(metadata), "ZIP64Entries": 65_536, "classicZIPEntries": 65_535,
                     "malformedZIP64Cases": len(corruptions)},
        "notRun": ["ZIPFoundation extraction", "Darwin shared store", "Apple SDK compilation"],
    }
    (args.output / "archive-import-policy.json").write_text(json.dumps(receipt, indent=2) + "\n")
    print(output[-16_000:])
    print(json.dumps(receipt, indent=2))
    raise SystemExit(completed.returncode)
