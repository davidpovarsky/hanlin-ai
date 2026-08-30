import Foundation
import HanlinPlatformContracts
import HanlinScriptContracts
import Testing

@Suite("Full Scripting contracts")
struct HanlinScriptContractsTests {
    @Test("Capability approval normalizes requests and retains explicit grants")
    func capabilityApprovalState() throws {
        let network = try HanlinCapabilityID(validating: "network")
        let storage = try HanlinCapabilityID(validating: "storage")
        var state = HanlinCapabilityApprovalState(requests: [
            .init(capabilityID: network, required: false, purpose: "Optional network"),
            .init(capabilityID: network, required: true, purpose: "Required network"),
            .init(capabilityID: storage, required: true, purpose: "Required storage"),
        ])
        #expect(state.requiredCapabilities == [network, storage])
        #expect(state.missingRequiredCapabilities == [network, storage])

        state.setApproved(true, capability: network)
        state.setApproved(true, capability: storage)
        #expect(state.hasApprovedEveryRequiredCapability)
        #expect(state.approvedCapabilities == [network, storage])
    }


    @Test("Legacy installed entrypoint migrates to its historical QuickJS profile")
    func legacyEntrypointRuntimeMigration() throws {
        let data = Data(#"""
        {
          "id":"app","kind":"app","sourcePath":"index.tsx",
          "supportedContexts":["mainApplication"],"requiredCapabilities":[],
          "runtimePolicyID":"foreground-app-v1","compatibility":"partial"
        }
        """#.utf8)
        let descriptor = try JSONDecoder().decode(HanlinPackageEntrypointDescriptor.self, from: data)
        #expect(descriptor.runtimeProfile == .hanlinQuickJS)
    }
    @Test("Preserves unknown script.json fields without granting behavior")
    func manifestUnknownFieldRoundTrip() throws {
        let data = Data(#"{"name":"Fixture","version":"1.2.3","runInApp":false,"future":{"enabled":true}}"#.utf8)
        let manifest = try JSONDecoder().decode(HanlinScriptingManifest.self, from: data)
        #expect(manifest.name == "Fixture")
        #expect(manifest.unknownFields["future"] == .object(["enabled": .bool(true)]))

        let encoded = try JSONEncoder().encode(manifest)
        let decoded = try JSONDecoder().decode(HanlinScriptingManifest.self, from: encoded)
        #expect(decoded == manifest)
    }

    @Test("Preview installability fails closed on archive or analyzer errors")
    func previewInstallability() throws {
        let source = HanlinImportedPackageSource(
            originalFileName: "fixture.scripting",
            format: .scripting,
            contentSHA256: String(repeating: "a", count: 64),
            byteCount: 42,
            importedAt: Date(timeIntervalSince1970: 1)
        )
        let archive = HanlinArchiveInspection(
            fileCount: 2,
            directoryCount: 1,
            compressedBytes: 42,
            uncompressedBytes: 84,
            maximumDepth: 2,
            manifestPath: "script.json"
        )
        let preview = HanlinImportPreview(
            source: source,
            archive: archive,
            manifest: .init(name: "Fixture", version: "1.0.0"),
            entrypoints: [],
            dependencyGraph: .init(modules: [], edges: []),
            requestedCapabilities: [],
            findings: [.init(
                state: .unsupported,
                severity: .error,
                message: "Required app entrypoint is unavailable."
            )],
            sourceBytes: 42,
            extractedBytes: 84
        )
        #expect(!preview.canInstall)
    }

    @Test("Installed records and artifact manifests round trip deterministically")
    func installedRecordRoundTrip() throws {
        let installedID = try HanlinInstalledPackageID(validating: "11111111-1111-1111-1111-111111111111")
        let packageID = try HanlinPackageID(validating: "fixture.package")
        let version = try HanlinPackageVersion(validating: "1.0.0")
        let record = HanlinInstalledPackageRecord(
            installedPackageID: installedID,
            packageID: packageID,
            version: version,
            sourceDigest: String(repeating: "1", count: 64),
            artifactDigest: String(repeating: "2", count: 64),
            activeGeneration: 1,
            installedAt: Date(timeIntervalSince1970: 2),
            updatedAt: Date(timeIntervalSince1970: 2)
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let first = try encoder.encode(record)
        let second = try encoder.encode(try JSONDecoder().decode(
            HanlinInstalledPackageRecord.self,
            from: first
        ))
        #expect(first == second)
    }

    @Test("Release performance budgets are versioned and deterministic")
    func performanceBudgets() throws {
        let budgets = try HanlinScriptingPerformanceBudgets.release()
        #expect(budgets.schemaVersion == 1)
        #expect(budgets.foregroundEngineHeapBytes == 16 << 20)
        #expect(budgets.coldCompileP95Milliseconds >= budgets.warmCompileP95Milliseconds)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let first = try encoder.encode(budgets)
        let second = try encoder.encode(try JSONDecoder().decode(
            HanlinScriptingPerformanceBudgets.self,
            from: first
        ))
        #expect(first == second)
    }
}
