import CryptoKit
import Foundation
import HanlinPlatformContracts
import HanlinScriptContracts
import HanlinScriptStore
import Testing

@Suite("Atomic Scripting installation store")
struct HanlinAtomicScriptStoreTests {
    @Test("Install, update, rollback, disable, restore, and uninstall preserve stable identity")
    func lifecycle() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let clock = FixedClock()
        let store = try HanlinAtomicScriptStore(root: fixture.storeRoot, now: { clock.date })

        let installed = try await store.install(
            plan: fixture.plan(version: "1.0.0", sourceDigest: fixture.first.manifest.packageContentDigest),
            artifactDirectory: fixture.first.url,
            artifactManifest: fixture.first.manifest
        )
        #expect(installed.activeGeneration == 1)
        #expect(installed.installedPackageID == fixture.installedID)

        let updated = try await store.update(
            plan: fixture.plan(version: "2.0.0", sourceDigest: fixture.second.manifest.packageContentDigest),
            artifactDirectory: fixture.second.url,
            artifactManifest: fixture.second.manifest
        )
        #expect(updated.activeGeneration == 2)
        #expect(updated.installedPackageID == installed.installedPackageID)
        #expect(try await store.activeArtifactURL(for: fixture.installedID).lastPathComponent == "2")

        let rolledBack = try await store.rollback(fixture.installedID, to: 1)
        #expect(rolledBack.activeGeneration == 1)
        #expect(rolledBack.version.rawValue == "1.0.0")
        try await store.setEnabled(false, for: fixture.installedID)
        let restored = try await HanlinAtomicScriptStore(root: fixture.storeRoot).restore()
        #expect(restored.count == 1)
        #expect(restored[0].enabled == false)
        #expect(restored[0].availableGenerations == [1, 2])

        try await store.uninstall(fixture.installedID)
        #expect(try await store.snapshots().isEmpty)
    }

    @Test(
        "Install recovery is atomic at every persisted transition",
        arguments: [
            HanlinInstallFaultPoint.journalPersisted,
            .artifactStaged,
            .generationPromoted,
            .registryCommitted
        ]
    )
    func installRecovery(point: HanlinInstallFaultPoint) async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let store = try HanlinAtomicScriptStore(
            root: fixture.storeRoot,
            faults: ThrowingFault(point: point)
        )
        await #expect(throws: InjectedFailure.self) {
            try await store.install(
                plan: fixture.plan(version: "1.0.0", sourceDigest: fixture.first.manifest.packageContentDigest),
                artifactDirectory: fixture.first.url,
                artifactManifest: fixture.first.manifest
            )
        }
        let recovered = try HanlinAtomicScriptStore(root: fixture.storeRoot)
        let snapshots = try await recovered.restore()
        if point == .registryCommitted {
            #expect(snapshots.count == 1)
            #expect(snapshots[0].record.activeGeneration == 1)
        } else {
            #expect(snapshots.isEmpty)
        }
        #expect(try FileManager.default.contentsOfDirectory(
            at: fixture.storeRoot.appending(path: "registry/journals"),
            includingPropertiesForKeys: nil
        ).isEmpty)
    }

    @Test("Failed update promotion restores the previous active generation")
    func updateRecovery() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let initial = try HanlinAtomicScriptStore(root: fixture.storeRoot)
        _ = try await initial.install(
            plan: fixture.plan(version: "1.0.0", sourceDigest: fixture.first.manifest.packageContentDigest),
            artifactDirectory: fixture.first.url,
            artifactManifest: fixture.first.manifest
        )
        let failing = try HanlinAtomicScriptStore(
            root: fixture.storeRoot,
            faults: ThrowingFault(point: .generationPromoted)
        )
        await #expect(throws: InjectedFailure.self) {
            try await failing.update(
                plan: fixture.plan(version: "2.0.0", sourceDigest: fixture.second.manifest.packageContentDigest),
                artifactDirectory: fixture.second.url,
                artifactManifest: fixture.second.manifest
            )
        }
        let recovered = try HanlinAtomicScriptStore(root: fixture.storeRoot)
        let snapshots = try await recovered.restore()
        #expect(snapshots.map(\.record.activeGeneration) == [1])
        #expect(snapshots[0].availableGenerations == [1])
    }

    @Test(
        "Uninstall recovery restores or completes according to its commit point",
        arguments: [HanlinInstallFaultPoint.uninstallMoved, .uninstallRegistryCommitted]
    )
    func uninstallRecovery(point: HanlinInstallFaultPoint) async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let initial = try HanlinAtomicScriptStore(root: fixture.storeRoot)
        _ = try await initial.install(
            plan: fixture.plan(version: "1.0.0", sourceDigest: fixture.first.manifest.packageContentDigest),
            artifactDirectory: fixture.first.url,
            artifactManifest: fixture.first.manifest
        )
        let failing = try HanlinAtomicScriptStore(
            root: fixture.storeRoot,
            faults: ThrowingFault(point: point)
        )
        await #expect(throws: InjectedFailure.self) {
            try await failing.uninstall(fixture.installedID)
        }
        let recovered = try HanlinAtomicScriptStore(root: fixture.storeRoot)
        let snapshots = try await recovered.restore()
        #expect(snapshots.isEmpty == (point == .uninstallRegistryCommitted))
    }

    @Test("Artifact corruption fails before catalog mutation")
    func corruption() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try Data("tampered".utf8).write(to: fixture.first.url.appending(path: "main.js"), options: .atomic)
        let store = try HanlinAtomicScriptStore(root: fixture.storeRoot)
        await #expect(throws: HanlinAtomicScriptStoreError.artifactManifestMismatch("main.js")) {
            try await store.install(
                plan: fixture.plan(version: "1.0.0", sourceDigest: fixture.first.manifest.packageContentDigest),
                artifactDirectory: fixture.first.url,
                artifactManifest: fixture.first.manifest
            )
        }
        #expect(try await store.snapshots().isEmpty)
    }

    @Test("Missing artifact manifest fails deterministically before catalog mutation")
    func missingArtifactManifest() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try FileManager.default.removeItem(
            at: fixture.first.url.appending(path: "artifact-manifest.json")
        )
        let store = try HanlinAtomicScriptStore(root: fixture.storeRoot)
        await #expect(throws: HanlinAtomicScriptStoreError.artifactManifestMissing) {
            try await store.install(
                plan: fixture.plan(version: "1.0.0", sourceDigest: fixture.first.manifest.packageContentDigest),
                artifactDirectory: fixture.first.url,
                artifactManifest: fixture.first.manifest
            )
        }
        #expect(try await store.snapshots().isEmpty)
    }

    @Test("Cold restoration through a symlinked root preserves the active manifest while pruning staging")
    func activeGenerationSurvivesCanonicalRootAndStagingCleanup() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let store = try HanlinAtomicScriptStore(root: fixture.storeRoot)
        _ = try await store.install(
            plan: fixture.plan(version: "1.0.0", sourceDigest: fixture.first.manifest.packageContentDigest),
            artifactDirectory: fixture.first.url,
            artifactManifest: fixture.first.manifest
        )
        let activeManifest = fixture.storeRoot.appending(
            path: "packages/\(fixture.installedID.rawValue)/generations/1/artifact-manifest.json",
            directoryHint: .notDirectory
        )
        #expect(FileManager.default.fileExists(atPath: activeManifest.path(percentEncoded: false)))

        let abandonedStaging = fixture.storeRoot.appending(
            path: "staging/abandoned-unreferenced-artifact",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(at: abandonedStaging, withIntermediateDirectories: true)
        let rootAlias = fixture.root.appending(path: "store-alias", directoryHint: .isDirectory)
        try FileManager.default.createSymbolicLink(at: rootAlias, withDestinationURL: fixture.storeRoot)

        let coldStore = try HanlinAtomicScriptStore(root: rootAlias)
        let restored = try await coldStore.restore()
        let resolvedActive = try await coldStore.activeArtifactURL(for: fixture.installedID)
        #expect(restored.map(\.record.activeGeneration) == [1])
        #expect(restored[0].availableGenerations == [1])
        #expect(resolvedActive.resolvingSymlinksInPath() == activeManifest.deletingLastPathComponent().resolvingSymlinksInPath())
        #expect(FileManager.default.fileExists(
            atPath: resolvedActive.appending(path: "artifact-manifest.json").path(percentEncoded: false)
        ))
        #expect(!FileManager.default.fileExists(atPath: abandonedStaging.path(percentEncoded: false)))
    }

    @Test("Required capabilities are rejected until the production grant representation approves them")
    func requiredCapabilityGate() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let capability = try HanlinCapabilityID(validating: "network")
        let request = HanlinCapabilityRequest(
            capabilityID: capability,
            required: true,
            purpose: "Network fixture"
        )
        let store = try HanlinAtomicScriptStore(root: fixture.storeRoot)
        await #expect(throws: HanlinAtomicScriptStoreError.requiredCapabilitiesNotGranted([capability])) {
            try await store.install(
                plan: fixture.plan(
                    version: "1.0.0",
                    sourceDigest: fixture.first.manifest.packageContentDigest,
                    requestedCapabilities: [request]
                ),
                artifactDirectory: fixture.first.url,
                artifactManifest: fixture.first.manifest
            )
        }

        _ = try await store.install(
            plan: fixture.plan(
                version: "1.0.0",
                sourceDigest: fixture.first.manifest.packageContentDigest,
                requestedCapabilities: [request],
                grantedCapabilities: [capability]
            ),
            artifactDirectory: fixture.first.url,
            artifactManifest: fixture.first.manifest
        )
        #expect(try await store.snapshots()[0].grantedCapabilities == [capability])
    }

    @Test("Capability grants persist and revocation is package scoped")
    func capabilityGrantLifecycle() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let capability = try HanlinCapabilityID(validating: "network")
        let store = try HanlinAtomicScriptStore(root: fixture.storeRoot)
        _ = try await store.install(
            plan: fixture.plan(version: "1.0.0", sourceDigest: fixture.first.manifest.packageContentDigest),
            artifactDirectory: fixture.first.url,
            artifactManifest: fixture.first.manifest
        )

        try await store.setCapabilityGranted(true, capability: capability, for: fixture.installedID)
        let restored = try await HanlinAtomicScriptStore(root: fixture.storeRoot).restore()
        #expect(restored[0].grantedCapabilities == [capability])

        try await store.setCapabilityGranted(false, capability: capability, for: fixture.installedID)
        #expect(try await store.snapshots()[0].grantedCapabilities.isEmpty)
    }

    @Test("Unified catalog retains native and installed script authorities")
    func unifiedCatalog() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let store = try HanlinAtomicScriptStore(root: fixture.storeRoot)
        _ = try await store.install(
            plan: fixture.plan(version: "1.0.0", sourceDigest: fixture.first.manifest.packageContentDigest),
            artifactDirectory: fixture.first.url,
            artifactManifest: fixture.first.manifest
        )
        let native = HanlinCatalogSnapshot(
            revision: .init(9),
            generatedAt: Date(timeIntervalSince1970: 1),
            apps: []
        )
        let unified = await store.unifiedCatalog(native: native)
        #expect(unified.nativeCatalog.revision.rawValue == 9)
        #expect(unified.scriptPackages.map(\.record.installedPackageID) == [fixture.installedID])
        #expect(unified.revision == 9)
    }
}

private struct InjectedFailure: Error {}

private struct ThrowingFault: HanlinInstallFaultInjector {
    let point: HanlinInstallFaultPoint
    func check(_ candidate: HanlinInstallFaultPoint) throws {
        if candidate == point { throw InjectedFailure() }
    }
}

private final class FixedClock: @unchecked Sendable {
    let date = Date(timeIntervalSince1970: 1_700_000_000)
}

private struct Fixture {
    struct Artifact {
        let url: URL
        let manifest: HanlinPackageArtifactManifest
    }

    let root: URL
    let storeRoot: URL
    let first: Artifact
    let second: Artifact
    let installedID: HanlinInstalledPackageID
    let packageID: HanlinPackageID
    let entrypoint: HanlinPackageEntrypointDescriptor

    init() throws {
        root = FileManager.default.temporaryDirectory.appending(
            path: "hanlin store tests \(UUID().uuidString.lowercased())",
            directoryHint: .isDirectory
        )
        storeRoot = root.appending(path: "store", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        installedID = try HanlinInstalledPackageID(validating: "fixture-install")
        packageID = try HanlinPackageID(validating: "fixture-package")
        entrypoint = .init(
            id: "app",
            kind: .app,
            sourcePath: "index.tsx",
            supportedContexts: [.mainApplication],
            runtimePolicyID: "foreground-app-v1",
            compatibility: .supported
        )
        first = try Self.artifact(root: root, name: "first", source: "export default 1", packageDigest: String(repeating: "1", count: 64))
        second = try Self.artifact(root: root, name: "second", source: "export default 2", packageDigest: String(repeating: "2", count: 64))
    }

    func plan(
        version: String,
        sourceDigest: String,
        requestedCapabilities: [HanlinCapabilityRequest] = [],
        grantedCapabilities: [HanlinCapabilityID] = []
    ) throws -> HanlinInstallPlan {
        HanlinInstallPlan(
            installedPackageID: installedID,
            packageID: packageID,
            version: try #require(HanlinPackageVersion(rawValue: version)),
            sourceDigest: sourceDigest,
            entrypoints: [entrypoint],
            requestedCapabilities: requestedCapabilities,
            grantedCapabilities: grantedCapabilities
        )
    }

    func remove() { try? FileManager.default.removeItem(at: root) }

    private static func artifact(root: URL, name: String, source: String, packageDigest: String) throws -> Artifact {
        let url = root.appending(path: name, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        let bytes = Data(source.utf8)
        try bytes.write(to: url.appending(path: "main.js"))
        let file = HanlinArtifactFile(
            logicalPath: "main.js",
            sha256: SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined(),
            byteCount: Int64(bytes.count),
            context: .app
        )
        let manifest = HanlinPackageArtifactManifest(
            compilerVersion: "6.0.3",
            compilerIntegrity: "sha512-fixture",
            compilerOptionsHash: String(repeating: "a", count: 64),
            baselineID: "fixture",
            baselineDigest: String(repeating: "b", count: 64),
            hanlinABIVersion: "2",
            packageContentDigest: packageDigest,
            cacheFingerprint: String(repeating: name == "first" ? "c" : "d", count: 64),
            files: [file]
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(manifest).write(to: url.appending(path: "artifact-manifest.json"))
        return .init(url: url, manifest: manifest)
    }
}
