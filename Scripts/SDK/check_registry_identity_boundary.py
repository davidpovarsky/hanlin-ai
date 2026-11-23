#!/usr/bin/env python3
"""Exercise exact registry load/snapshot declarations and original contracts.

The local package uses the complete original Platform/Script contract modules.
Only Foundation store declarations needed by cold loading/snapshots are selected;
unavailable Apple CryptoKit/OSLog, transfer and widget engines are not emulated.
The original dictionary expression is exercised after real malformed-file loading,
not as a claim that a live WidgetKit failure or a valid import creates corruption.
"""
from __future__ import annotations
import argparse
import hashlib
import json
from pathlib import Path
import resource
import subprocess
import textwrap

ROOT = Path(__file__).resolve().parents[2]
STORE = "Packages/HanlinPlatform/Sources/HanlinScriptStore/HanlinAtomicScriptStore.swift"
APP = "AI_HLY/Downstream/ScriptingPlatform/HanlinScriptingPlatform.swift"


def sha(raw):
    return hashlib.sha256(raw).hexdigest()


def declaration(source, marker):
    if source.count(marker) != 1:
        raise ValueError("Ambiguous exact production declaration: " + marker)
    start = source.index(marker)
    indent = source[source.rfind("\n", 0, start) + 1:start]
    start -= len(indent)
    end = source.index("\n" + indent + "}\n", source.index("{", start)) + len(indent) + 3
    return source[start:end]


def no_core():
    resource.setrlimit(resource.RLIMIT_CORE, (0, 0))


def main():
    parser = argparse.ArgumentParser(__doc__)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--expect", choices=("vulnerable", "fixed"), required=True)
    args = parser.parse_args()
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    package = output / "package"
    sources = package / "Sources"
    probe = sources / "RegistryBoundaryProbe"
    probe.mkdir(parents=True, exist_ok=True)
    for name in ("HanlinPlatformContracts", "HanlinScriptContracts"):
        path = sources / name
        original = ROOT / "Packages/HanlinPlatform/Sources" / name
        if not path.exists():
            path.symlink_to(original, target_is_directory=True)
        assert path.resolve() == original.resolve()
    (package / "Package.swift").write_text("""// swift-tools-version: 6.2
import PackageDescription
let package = Package(name: "RegistryBoundaryProof", products: [
    .executable(name: "RegistryBoundaryProbe", targets: ["RegistryBoundaryProbe"])
], targets: [
    .target(name: "HanlinPlatformContracts", resources: [.process("Resources")]),
    .target(name: "HanlinScriptContracts", dependencies: ["HanlinPlatformContracts"], resources: [.process("Resources")]),
    .executableTarget(name: "RegistryBoundaryProbe", dependencies: ["HanlinPlatformContracts", "HanlinScriptContracts"])
], swiftLanguageModes: [.v6])
""")
    source = (ROOT / STORE).read_text()
    markers = [
        "private struct Registry: Codable, Sendable",
        "private struct RegistryEntry: Codable, Sendable",
        "public init(\n        root: URL,",
        "public func snapshots() throws",
        "private func generations(for id:",
        "private func packageURL(_ id:",
        "private static func prepare(root:",
        "private static func loadRegistry(root:",
    ]
    selected = {marker: declaration(source, marker) for marker in markers}
    before_actor = source[source.index("public enum HanlinInstallFaultPoint"):source.index("public actor HanlinAtomicScriptStore")]
    properties = source[source.index("    public nonisolated let root:"):source.index("    public init(\n        root:")]
    actor = "public actor HanlinAtomicScriptStore {\n" + properties + "\n" + "\n".join(selected.values()) + "\n}\n"
    (probe / "ProductionDeclarations.swift").write_text(
        "import Foundation\nimport HanlinPlatformContracts\nimport HanlinScriptContracts\n\n" + before_actor + actor)
    app = (ROOT / APP).read_text()
    start = app.index("            let activeGenerations = Dictionary(\n")
    end = app.index("\n            )", start) + len("\n            )")
    fallback = app[start:end]
    harness = r"""
import Foundation
import HanlinPlatformContracts
import HanlinScriptContracts

@main struct RegistryBoundaryProbe {
    static func emit(_ value: [String: Any]) throws {
        let data = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
        FileHandle.standardOutput.write(data + Data([10]))
    }
    static func main() async throws {
        let scenario = CommandLine.arguments[1]
        let root = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
        try FileManager.default.createDirectory(at: root.appending(path: "registry"), withIntermediateDirectories: true)
        let primary = root.appending(path: "registry/catalog.json")
        let backup = root.appending(path: "registry/catalog.backup.json")
        let id = try HanlinInstalledPackageID(validating: "fixture-install")
        let alternate = try HanlinInstalledPackageID(validating: "fixture-alternate")
        func entry(_ installedID: HanlinInstalledPackageID) throws -> [String: Any] {
            let record = HanlinInstalledPackageRecord(
                installedPackageID: installedID, packageID: try HanlinPackageID(validating: "fixture-package"),
                version: try HanlinPackageVersion(validating: "1.0.0"),
                sourceDigest: String(repeating: "1", count: 64), artifactDigest: String(repeating: "2", count: 64),
                activeGeneration: 1, installedAt: Date(timeIntervalSince1970: 1_700_000_000),
                updatedAt: Date(timeIntervalSince1970: 1_700_000_000))
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .millisecondsSince1970
            return ["record": try JSONSerialization.jsonObject(with: encoder.encode(record)),
                    "entrypoints": [], "enabled": true]
        }
        let original = try entry(id)
        let valid = try JSONSerialization.data(withJSONObject: [
            "schemaVersion": 1, "revision": 4, "packages": [id.rawValue: original, alternate.rawValue: try entry(alternate)]
        ], options: [.sortedKeys])
        let duplicate = try JSONSerialization.data(withJSONObject: [
            "schemaVersion": 1, "revision": 4, "packages": [id.rawValue: original, alternate.rawValue: original]
        ], options: [.sortedKeys])
        let mismatch = try JSONSerialization.data(withJSONObject: [
            "schemaVersion": 1, "revision": 4, "packages": [alternate.rawValue: original]
        ], options: [.sortedKeys])
        let unsupported = try JSONSerialization.data(withJSONObject: [
            "schemaVersion": 2, "revision": 4, "packages": [id.rawValue: original]
        ], options: [.sortedKeys])
        let primaryData: Data
        let backupData: Data
        switch scenario {
        case "duplicate": primaryData = duplicate; backupData = valid
        case "mismatch": primaryData = mismatch; backupData = valid
        case "backup-invalid": primaryData = Data("not JSON".utf8); backupData = duplicate
        case "valid-primary": primaryData = valid; backupData = duplicate
        case "valid-backup": primaryData = Data("not JSON".utf8); backupData = valid
        case "unsupported": primaryData = unsupported; backupData = valid
        default: fatalError("Unknown fixture scenario")
        }
        try primaryData.write(to: primary)
        try backupData.write(to: backup)
        func unchanged() throws -> Bool {
            try Data(contentsOf: primary) == primaryData && Data(contentsOf: backup) == backupData
        }
        do {
            let store = try HanlinAtomicScriptStore(root: root)
            let installedPackages = try await store.snapshots()
            try emit(["case": scenario, "status": "ADMITTED_ORIGINAL_SNAPSHOTS",
                      "installedIDs": installedPackages.map { $0.record.installedPackageID.rawValue },
                      "registryBytesUnchanged": try unchanged()])
__ORIGINAL_FALLBACK__
            try emit(["case": scenario, "status": "FALLBACK_EXPRESSION_COMPLETED",
                      "identities": activeGenerations.count, "registryBytesUnchanged": try unchanged()])
        } catch {
            try emit(["case": scenario, "status": "THREW_EXISTING_ERROR",
                      "error": String(describing: error), "registryBytesUnchanged": try unchanged()])
        }
    }
}
"""
    (probe / "Probe.swift").write_text(textwrap.dedent(harness).replace("__ORIGINAL_FALLBACK__", fallback))
    contract_inputs = {}
    for name in ("HanlinPlatformContracts", "HanlinScriptContracts"):
        for file in (ROOT / "Packages/HanlinPlatform/Sources" / name).rglob("*"):
            if file.is_file():
                contract_inputs[str(file.relative_to(ROOT))] = sha(file.read_bytes())
    provenance = {
        "scope": "EXACT_PRODUCTION_COLD_LOAD_SNAPSHOTS_AND_DICTIONARY_EXPRESSION_NOT_FULL_APP_OR_WIDGETKIT",
        "storeSourceSHA256": sha((ROOT / STORE).read_bytes()),
        "appSourceSHA256": sha((ROOT / APP).read_bytes()),
        "selectedDeclarationsSHA256": {key: sha(value.encode()) for key, value in selected.items()},
        "originalPublicTypesSHA256": sha(before_actor.encode()),
        "originalActorPropertiesSHA256": sha(properties.encode()),
        "fallbackExpressionSHA256": sha(fallback.encode()),
        "completeContractInputs": contract_inputs,
        "excluded": ["CryptoKit artifact hashing", "OSLog diagnostics", "transfer engine", "WidgetKit and live host lifecycle"],
    }
    (output / "production-provenance.json").write_text(json.dumps(provenance, indent=2) + "\n")
    command = ["swift", "build", "--package-path", str(package), "--scratch-path", str(output / ".build"),
               "--product", "RegistryBoundaryProbe"]
    built = subprocess.run(command, text=True, capture_output=True, timeout=120)
    (output / "build.log").write_text(built.stdout + built.stderr)
    if built.returncode:
        raise RuntimeError((built.stdout + built.stderr)[-8000:])
    binary = output / ".build/debug/RegistryBoundaryProbe"
    cases = {}
    for scenario in ("duplicate", "mismatch", "backup-invalid", "valid-primary", "valid-backup", "unsupported"):
        case_root = output / "fixtures" / scenario
        process = subprocess.run([str(binary), scenario, str(case_root)], text=True, capture_output=True,
                                 timeout=10, preexec_fn=no_core)
        (output / (scenario + ".stdout")).write_text(process.stdout)
        (output / (scenario + ".stderr")).write_text(process.stderr)
        rows = [json.loads(line) for line in process.stdout.splitlines()]
        assert rows and all(row["registryBytesUnchanged"] for row in rows)
        cases[scenario] = {"returncode": process.returncode, "events": rows,
                           "primarySHA256": sha((case_root / "registry/catalog.json").read_bytes()),
                           "backupSHA256": sha((case_root / "registry/catalog.backup.json").read_bytes()),
                           "stderrSHA256": sha(process.stderr.encode())}
        if scenario in ("duplicate", "backup-invalid") and args.expect == "vulnerable":
            assert process.returncode < 0 and rows[0]["installedIDs"] == ["fixture-install", "fixture-install"]
            assert "Duplicate values for key" in process.stderr
        elif scenario in ("duplicate", "mismatch", "backup-invalid") and args.expect == "fixed":
            assert process.returncode == 0 and rows[-1]["error"] == "corruptRegistry"
        elif scenario == "unsupported":
            assert process.returncode == 0 and rows[-1]["error"] == "unsupportedRegistryVersion(2)"
        else:
            assert process.returncode == 0 and rows[-1]["status"] == "FALLBACK_EXPRESSION_COMPLETED"
            assert rows[-1]["identities"] == (1 if scenario == "mismatch" else 2)
    result = {"status": "PASS_EXPECTED_" + args.expect.upper(), "buildReturncode": built.returncode,
              "swiftVersion": subprocess.check_output(["swift", "--version"], text=True).strip(),
              "cases": cases, "nativeTestsExecuted": 0, "scope": provenance["scope"]}
    (output / "result.json").write_text(json.dumps(result, indent=2) + "\n")
    print(json.dumps({"status": result["status"], "cases": {name: item["returncode"] for name, item in cases.items()},
                      "output": str(output), "nativeTestsExecuted": 0}))


if __name__ == "__main__":
    main()
