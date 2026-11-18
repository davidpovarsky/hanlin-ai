import CryptoKit
import Foundation
import HanlinPlatformContracts
import HanlinMiniAppCore
import HanlinScriptContracts
@testable import HanlinScriptStore
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

    @Test("Packages install and restore with legacy empty grants")
    func requiredCapabilityMetadataDoesNotBlockInstall() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let capability = try HanlinCapabilityID(validating: "network")
        let request = HanlinCapabilityRequest(capabilityID: capability, required: true, purpose: "Network fixture")
        let store = try HanlinAtomicScriptStore(root: fixture.storeRoot)
        _ = try await store.install(
            plan: fixture.plan(version: "1.0.0", sourceDigest: fixture.first.manifest.packageContentDigest,
                               requestedCapabilities: [request]),
            artifactDirectory: fixture.first.url, artifactManifest: fixture.first.manifest
        )
        let restored = try HanlinAtomicScriptStore(root: fixture.storeRoot)
        let snapshot = try #require(await restored.snapshots().first)
        #expect(snapshot.record.installedPackageID == fixture.installedID)
        #expect(snapshot.grantedCapabilities.isEmpty)
        #expect(snapshot.enabled)
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

@Suite("Production MiniApps transfer using the original package and data stores")
struct HanlinProductTransferTests {
    @Test("Real identities, all generations, grants, disabled state and private bytes survive import and rollback")
    func actualStoresRoundTrip() async throws {
        let fixture = try ProductTransferFixture()
        defer { fixture.base.remove() }
        try await fixture.seed()
        let sourceBefore = try fixture.bytes(fixture.base.storeRoot)
        let sourceDataBefore = try fixture.bytes(fixture.sourceData)
        let destinationBefore = try fixture.bytes(fixture.targetRoot)
        let destinationDataBefore = try fixture.bytes(fixture.targetData)
        // Compare the durable source, as opened by a new process. The store's
        // existing millisecond JSON encoding does not promise in-memory Date
        // bit patterns before its first persistence round trip.
        let sourceOnDisk = try HanlinAtomicScriptStore(root: fixture.base.storeRoot)
        let originalPackages = try await sourceOnDisk.restore()
        let receipt = try await fixture.export()
        #expect(receipt.packageCount == 1)
        #expect(try await fixture.export() == receipt)
        let received = try await fixture.receive(receipt)
        #expect(received == receipt)
        let reopened = try HanlinAtomicScriptStore(root: fixture.targetRoot)
        #expect(try await reopened.restore() == originalPackages)
        let visibility = try HanlinMiniAppVisibilityStore(dataRoot: fixture.targetData, legacyHiddenIDs: [])
        #expect(try visibility.hiddenIDs() == [fixture.appID, fixture.otherAppID])
        let storage = try HanlinMiniAppDataStore(root: fixture.targetData)
        #expect(try await storage.read(appID: fixture.appID, area: .state, path: "saved/value.json")
                == Data("ערך מקורי — 汉林".utf8))
        #expect(try await storage.read(appID: fixture.otherAppID, area: .documents, path: "keep.txt")
                == Data("Existing companion data".utf8))
        #expect(try fixture.bytes(fixture.base.storeRoot) == sourceBefore)
        #expect(try fixture.bytes(fixture.sourceData) == sourceDataBefore)
        try await reopened.rollbackProductTransfer(dataRoot: fixture.targetData,
                                                   transactionRoot: fixture.transactionRoot)
        #expect(try fixture.bytes(fixture.targetRoot) == destinationBefore)
        #expect(try fixture.bytes(fixture.targetData) == destinationDataBefore)
        #expect(try visibility.hiddenIDs() == [fixture.otherAppID])
        #expect(try fixture.bytes(fixture.base.storeRoot) == sourceBefore)
    }

    @Test("Live canonical KV and SQLite owners checkpoint, reopen, and follow rollback roots")
    func liveDatabaseOwners() async throws {
        let fixture = try ProductTransferFixture()
        defer { fixture.base.remove() }
        try await fixture.seed()
        let sourceKV = try HanlinMiniAppKeyValueStore(root: fixture.sourceData, appID: fixture.appID)
        let sharedKV = try HanlinMiniAppKeyValueStore(root: fixture.sourceData, appID: nil)
        let targetKV = try HanlinMiniAppKeyValueStore(root: fixture.targetData, appID: fixture.otherAppID)
        try sourceKV.set(.init(kind: .json, content: #"{"saved":"שלום — 汉林"}"#), for: "private")
        try sharedKV.set(.init(kind: .data, content: "AAH+/w=="), for: "shared")
        try targetKV.set(.init(kind: .json, content: #""companion""#), for: "existing")
        let sqlite = HanlinSQLiteService(rootURL: fixture.sourceData.appending(path: "\(fixture.appID.rawValue)/Data"))
        defer { sqlite.closeAll() }
        _ = try sqlite.open(handle: "notes", name: "notes.sqlite3")
        try sqlite.execute(handle: "notes",
            sql: "CREATE TABLE notes(value TEXT); INSERT INTO notes VALUES(?)", arguments: ["kept"])
        #expect(sqlite.openDatabaseCount == 1)
        let receipt = try await fixture.export()
        #expect(sqlite.openDatabaseCount == 0)
        #expect(try sourceKV.value(for: "private")?.content == #"{"saved":"שלום — 汉林"}"#)
        _ = try sqlite.open(handle: "notes", name: "notes.sqlite3")
        #expect(try sqlite.fetchAll(handle: "notes", sql: "SELECT value FROM notes").first?["value"] as? String == "kept")
        // Quiesce the existing destination before taking its durable baseline.
        // A later read may rewrite Apple's retained WAL index, which is not
        // user data. The actual database and every nonempty WAL remain hashed.
        HanlinSQLiteService.closeConnections(under: fixture.targetData)
        let before = try HanlinTransferTree.capture(fixture.targetData, durableSQLiteData: true)
        // Keep a real destination owner open across root replacement.
        #expect(try targetKV.contains(key: "existing"))
        _ = try await fixture.receive(receipt)
        let imported = try HanlinMiniAppKeyValueStore(root: fixture.targetData, appID: fixture.appID)
        let sharedImported = try HanlinMiniAppKeyValueStore(root: fixture.targetData, appID: nil)
        #expect(try imported.value(for: "private") == sourceKV.value(for: "private"))
        #expect(try sharedImported.value(for: "shared") == sharedKV.value(for: "shared"))
        #expect(try targetKV.value(for: "existing")?.content == #""companion""#)
        let receivedSQLite = HanlinSQLiteService(rootURL: fixture.targetData.appending(path: "\(fixture.appID.rawValue)/Data"))
        defer { receivedSQLite.closeAll() }
        _ = try receivedSQLite.open(handle: "received", name: "notes.sqlite3")
        #expect(try receivedSQLite.fetchAll(handle: "received", sql: "SELECT value FROM notes").first?["value"] as? String == "kept")
        // If a read-only reopen changes durable bytes, preserve the complete
        // failing inventory in native diagnostics before rejecting rollback.
        HanlinSQLiteService.closeConnections(under: fixture.targetData)
        let savedJournal = try HanlinProductTransferRecovery.load(fixture.transactionRoot)
        let journal = try #require(savedJournal)
        let readInstalled = try HanlinTransferTree.capture(fixture.targetRoot)
        let readData = try HanlinTransferTree.capture(fixture.targetData, durableSQLiteData: true)
        #expect(readInstalled == journal.afterInstalled)
        #expect(readData == journal.afterData)
        try await fixture.target.rollbackProductTransfer(dataRoot: fixture.targetData, transactionRoot: fixture.transactionRoot)
        #expect(receivedSQLite.openDatabaseCount == 0)
        #expect(try HanlinTransferTree.capture(fixture.targetData, durableSQLiteData: true) == before)
        #expect(try targetKV.value(for: "existing")?.content == #""companion""#)
        let retained = fixture.transactionRoot.appending(path: "rolled-forward-data")
        let retainedBefore = try fixture.bytes(retained)
        try targetKV.set(.init(kind: .json, content: #""new companion edit""#), for: "existing")
        let reopened = try HanlinMiniAppKeyValueStore(root: fixture.targetData, appID: fixture.otherAppID)
        #expect(try reopened.value(for: "existing")?.content == #""new companion edit""#)
        #expect(try fixture.bytes(retained) == retainedBefore)
        #expect(try sourceKV.value(for: "private")?.content == #"{"saved":"שלום — 汉林"}"#)
    }

    @Test("Unopened legacy ScriptUI defaults migrate before export without replacing newer canonical data")
    func unopenedLegacyStorageTransfers() async throws {
        let fixture = try ProductTransferFixture(installedPackageID: "legacy-transfer-\(UUID().uuidString.lowercased())")
        defer { fixture.base.remove() }
        try await fixture.seed()
        let packages = try await fixture.source.restore()
        let package = try #require(packages.first)
        let suite = HanlinMiniAppKeyValueStore.legacyScriptingStorageIdentity(for: fixture.base.installedID)
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(#""legacy — שלום — 汉林""#, forKey: "private")
        defaults.set(Data([0,127,255]), forKey: "__hanlin_data__:bytes")
        let database = fixture.sourceData.appending(path: "\(package.appID.rawValue)/State/KeyValue.sqlite3")
        #expect(!FileManager.default.fileExists(atPath: database.path))
        let receipt = try await fixture.export()
        _ = try await fixture.receive(receipt)
        let received = try HanlinMiniAppKeyValueStore(root: fixture.targetData, appID: package.appID)
        #expect(try received.value(for: "private")?.content == #""legacy — שלום — 汉林""#)
        #expect(try received.value(for: "bytes") == .init(kind: .data, content: Data([0,127,255]).base64EncodedString()))
        #expect(defaults.string(forKey: "private") == #""legacy — שלום — 汉林""#)
        #expect(defaults.data(forKey: "__hanlin_data__:bytes") == Data([0,127,255]))
        let original = try HanlinMiniAppKeyValueStore(root: fixture.sourceData, appID: package.appID)
        try original.set(.init(kind: .json, content: #""newer canonical edit""#), for: "private")
        _ = try await fixture.export()
        #expect(try original.value(for: "private")?.content == #""newer canonical edit""#)
        try await fixture.target.rollbackProductTransfer(dataRoot: fixture.targetData, transactionRoot: fixture.transactionRoot)
        #expect(!FileManager.default.fileExists(atPath: fixture.targetData.appending(path: package.appID.rawValue).path))
        #expect(try original.value(for: "private")?.content == #""newer canonical edit""#)
    }

    @Test("Durable snapshots retain nonempty SQLite WAL and ordinary similarly named files")
    func durableSQLiteSidecars() throws {
        let fixture = try ProductTransferFixture()
        defer { fixture.base.remove() }
        let sqlite = HanlinSQLiteService(rootURL: fixture.sourceData)
        defer { sqlite.closeAll() }
        _ = try sqlite.open(handle: "database", name: "actual.sqlite3")
        try sqlite.execute(handle: "database", sql: """
            PRAGMA wal_autocheckpoint = 0;
            CREATE TABLE records(value TEXT);
            INSERT INTO records VALUES('first');
            """)
        try Data("ordinary user file".utf8).write(to: fixture.sourceData.appending(path: "notes-shm"))
        try Data().write(to: fixture.sourceData.appending(path: "empty-wal"))
        let before = try HanlinTransferTree.capture(fixture.sourceData, durableSQLiteData: true)
        #expect((before.files["actual.sqlite3-wal"]?.bytes ?? 0) > 0)
        #expect(before.files["actual.sqlite3-shm"] == nil)
        // Installed package assets use byte-exact capture, including sidecars.
        let packageAssets = try HanlinTransferTree.capture(fixture.sourceData)
        #expect(packageAssets.files["actual.sqlite3-shm"] != nil)
        #expect(before.files["notes-shm"] != nil)
        #expect(before.files["empty-wal"] != nil)
        try sqlite.execute(handle: "database", sql: "INSERT INTO records VALUES('later user edit')")
        #expect(try HanlinTransferTree.capture(fixture.sourceData, durableSQLiteData: true) != before)
    }

    @Test("A later committed SQLite KV edit prevents rollback and survives a repeated import")
    func laterDatabaseEdits() async throws {
        let fixture = try ProductTransferFixture()
        defer { fixture.base.remove() }
        try await fixture.seed()
        let source = try HanlinMiniAppKeyValueStore(root: fixture.sourceData, appID: fixture.appID)
        try source.set(.init(kind: .json, content: "1"), for: "value")
        let receipt = try await fixture.export()
        _ = try await fixture.receive(receipt)
        let target = try HanlinMiniAppKeyValueStore(root: fixture.targetData, appID: fixture.appID)
        try target.set(.init(kind: .json, content: "2"), for: "value")
        _ = try await fixture.receive(receipt)
        await #expect(throws: HanlinProductTransferError.rollbackWouldLoseChanges) {
            try await fixture.target.rollbackProductTransfer(dataRoot: fixture.targetData, transactionRoot: fixture.transactionRoot)
        }
        #expect(try target.value(for: "value")?.content == "2")
        #expect(try source.value(for: "value")?.content == "1")
    }

    @Test("A fresh process recovers each durable two-store promotion boundary",
          arguments: [HanlinProductTransferFaultPoint.intentPersisted, .installedBackedUp,
                      .installedPromoted, .dataBackedUp, .dataPromoted, .committed])
    func recoverImport(point: HanlinProductTransferFaultPoint) async throws {
        let fixture = try ProductTransferFixture()
        defer { fixture.base.remove() }
        try await fixture.seed()
        let sourceOnDisk = try HanlinAtomicScriptStore(root: fixture.base.storeRoot)
        let original = try await sourceOnDisk.restore()
        let sourceBefore = try fixture.bytes(fixture.base.storeRoot)
        let receipt = try await fixture.export()
        await #expect(throws: InjectedFailure.self) {
            try await fixture.target.receiveProductTransfer(from: fixture.checkpoint(receipt),
                dataRoot: fixture.targetData, transactionRoot: fixture.transactionRoot,
                transferFaults: TransferFault(point: point))
        }
        try HanlinProductTransferRecovery.recover(installedRoot: fixture.targetRoot,
            dataRoot: fixture.targetData, transactionRoot: fixture.transactionRoot)
        let fresh = try HanlinAtomicScriptStore(root: fixture.targetRoot)
        #expect(try await fresh.restore() == original)
        #expect(try await fresh.receiveProductTransfer(from: fixture.checkpoint(receipt),
            dataRoot: fixture.targetData, transactionRoot: fixture.transactionRoot) == receipt)
        let storage = try HanlinMiniAppDataStore(root: fixture.targetData)
        #expect(try await storage.read(appID: fixture.appID, area: .state, path: "saved/value.json")
                == Data("ערך מקורי — 汉林".utf8))
        #expect(try fixture.bytes(fixture.base.storeRoot) == sourceBefore)
    }

    @Test("Rollback resumes after every journaled restore boundary",
          arguments: [HanlinProductTransferFaultPoint.rollbackIntentPersisted, .installedRestored, .dataRestored])
    func recoverRollback(point: HanlinProductTransferFaultPoint) async throws {
        let fixture = try ProductTransferFixture()
        defer { fixture.base.remove() }
        try await fixture.seed()
        let before = try fixture.bytes(fixture.targetRoot)
        let dataBefore = try fixture.bytes(fixture.targetData)
        let receipt = try await fixture.export()
        _ = try await fixture.receive(receipt)
        await #expect(throws: InjectedFailure.self) {
            try await fixture.target.rollbackProductTransfer(dataRoot: fixture.targetData,
                transactionRoot: fixture.transactionRoot, transferFaults: TransferFault(point: point))
        }
        try HanlinProductTransferRecovery.recover(installedRoot: fixture.targetRoot,
            dataRoot: fixture.targetData, transactionRoot: fixture.transactionRoot)
        #expect(try fixture.bytes(fixture.targetRoot) == before)
        #expect(try fixture.bytes(fixture.targetData) == dataBefore)
        let fresh = try HanlinAtomicScriptStore(root: fixture.targetRoot)
        #expect(try await fresh.restore().isEmpty)
    }

    @Test("Retry preserves later user edits, and rollback refuses to discard them")
    func laterEdits() async throws {
        let fixture = try ProductTransferFixture()
        defer { fixture.base.remove() }
        try await fixture.seed()
        let receipt = try await fixture.export()
        _ = try await fixture.receive(receipt)
        let storage = try HanlinMiniAppDataStore(root: fixture.targetData)
        try await storage.write(Data("Later user work".utf8), appID: fixture.appID,
                                area: .state, path: "saved/value.json")
        let edited = try fixture.bytes(fixture.targetData)
        _ = try await fixture.receive(receipt)
        try HanlinProductTransferRecovery.recover(installedRoot: fixture.targetRoot,
            dataRoot: fixture.targetData, transactionRoot: fixture.transactionRoot)
        #expect(try fixture.bytes(fixture.targetData) == edited)
        await #expect(throws: HanlinProductTransferError.rollbackWouldLoseChanges) {
            try await fixture.target.rollbackProductTransfer(dataRoot: fixture.targetData,
                transactionRoot: fixture.transactionRoot)
        }
        #expect(try fixture.bytes(fixture.targetData) == edited)
    }

    @Test("Conflicting package identities or data are rejected before live changes",
          arguments: ["package", "data"])
    func destinationConflict(kind: String) async throws {
        let fixture = try ProductTransferFixture()
        defer { fixture.base.remove() }
        try await fixture.seed()
        let receipt = try await fixture.export()
        if kind == "package" {
            _ = try await fixture.target.install(
                plan: fixture.base.plan(version: "9.0.0",
                    sourceDigest: fixture.base.first.manifest.packageContentDigest),
                artifactDirectory: fixture.base.first.url, artifactManifest: fixture.base.first.manifest)
        } else {
            let storage = try HanlinMiniAppDataStore(root: fixture.targetData)
            try await storage.write(Data("Different existing data".utf8), appID: fixture.appID,
                                    area: .state, path: "saved/value.json")
        }
        let before = try fixture.bytes(fixture.targetRoot)
        let dataBefore = try fixture.bytes(fixture.targetData)
        await #expect(throws: HanlinProductTransferError.destinationConflict) { try await fixture.receive(receipt) }
        #expect(try fixture.bytes(fixture.targetRoot) == before)
        #expect(try fixture.bytes(fixture.targetData) == dataBefore)
    }

    @Test("Tampered checkpoint bytes are rejected before destination writes")
    func tamperedCheckpoint() async throws {
        let fixture = try ProductTransferFixture()
        defer { fixture.base.remove() }
        try await fixture.seed()
        let receipt = try await fixture.export()
        let before = try fixture.bytes(fixture.targetRoot)
        let dataBefore = try fixture.bytes(fixture.targetData)
        let file = fixture.checkpoint(receipt).appending(path: "MiniApps/\(fixture.appID.rawValue)/State/saved/value.json")
        try Data("Tampered".utf8).write(to: file)
        await #expect(throws: HanlinProductTransferError.invalidCheckpoint) { try await fixture.receive(receipt) }
        #expect(try fixture.bytes(fixture.targetRoot) == before)
        #expect(try fixture.bytes(fixture.targetData) == dataBefore)
    }

    @Test("A symlink in private data cannot pull other files into the transfer")
    func sourceSymlink() async throws {
        let fixture = try ProductTransferFixture()
        defer { fixture.base.remove() }
        try await fixture.seed()
        let outside = fixture.base.root.appending(path: "outside.txt")
        try Data("Do not transfer".utf8).write(to: outside)
        try FileManager.default.createSymbolicLink(at: fixture.sourceData.appending(path: "linked"),
                                                   withDestinationURL: outside)
        await #expect(throws: HanlinProductTransferError.unsafePath) { try await fixture.export() }
        #expect(!FileManager.default.fileExists(atPath: fixture.outbox.appending(path: "latest.json").path))
        #expect(try Data(contentsOf: outside) == Data("Do not transfer".utf8))
    }

    @Test("A read-only destination cannot change either source store")
    func readOnlyOutbox() async throws {
        let fixture = try ProductTransferFixture()
        defer { fixture.base.remove() }
        try await fixture.seed()
        let before = try fixture.bytes(fixture.base.storeRoot)
        let dataBefore = try fixture.bytes(fixture.sourceData)
        try FileManager.default.createDirectory(at: fixture.outbox, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: fixture.outbox.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: fixture.outbox.path) }
        await #expect(throws: (any Error).self) { try await fixture.export() }
        #expect(try fixture.bytes(fixture.base.storeRoot) == before)
        #expect(try fixture.bytes(fixture.sourceData) == dataBefore)
    }
}

private struct TransferFault: HanlinProductTransferFaultInjector {
    let point: HanlinProductTransferFaultPoint
    func check(_ candidate: HanlinProductTransferFaultPoint) throws {
        if candidate == point { throw InjectedFailure() }
    }
}

private struct ProductTransferFixture {
    let base: Fixture
    let source: HanlinAtomicScriptStore
    let target: HanlinAtomicScriptStore
    let sourceData: URL
    let targetRoot: URL
    let targetData: URL
    let transactionRoot: URL
    let outbox: URL
    let appID: HanlinAppID
    let otherAppID: HanlinAppID

    init(installedPackageID: String = "fixture-install") throws {
        base = try Fixture(installedPackageID: installedPackageID)
        source = try HanlinAtomicScriptStore(root: base.storeRoot)
        sourceData = base.root.appending(path: "source-private-data")
        targetRoot = base.root.appending(path: "companion-installed")
        targetData = base.root.appending(path: "companion-private-data")
        transactionRoot = base.root.appending(path: "recovery/current")
        outbox = base.root.appending(path: "shared-outbox")
        target = try HanlinAtomicScriptStore(root: targetRoot)
        appID = try #require(HanlinAppID(rawValue: "fixture.transfer"))
        otherAppID = try #require(HanlinAppID(rawValue: "fixture.existing"))
    }

    func seed() async throws {
        _ = try HanlinMiniAppVisibilityStore(dataRoot: sourceData, legacyHiddenIDs: [appID])
        _ = try HanlinMiniAppVisibilityStore(dataRoot: targetData, legacyHiddenIDs: [otherAppID])
        _ = try await source.install(plan: base.plan(version: "1.0.0",
            sourceDigest: base.first.manifest.packageContentDigest),
            artifactDirectory: base.first.url, artifactManifest: base.first.manifest)
        _ = try await source.update(plan: base.plan(version: "2.0.0",
            sourceDigest: base.second.manifest.packageContentDigest),
            artifactDirectory: base.second.url, artifactManifest: base.second.manifest)
        try await source.setCapabilityGranted(true, capability: HanlinCapabilityID(validating: "network"),
                                              for: base.installedID)
        try await source.setEnabled(false, for: base.installedID)
        let sourceStore = try HanlinMiniAppDataStore(root: sourceData)
        try await sourceStore.write(Data("ערך מקורי — 汉林".utf8), appID: appID,
                                    area: .state, path: "saved/value.json")
        try await sourceStore.write(Data([0, 255, 1, 12]), appID: appID,
                                    area: .documents, path: "binary.dat")
        let targetStore = try HanlinMiniAppDataStore(root: targetData)
        try await targetStore.write(Data("Existing companion data".utf8), appID: otherAppID,
                                    area: .documents, path: "keep.txt")
    }

    func export() async throws -> HanlinProductTransferReceipt {
        try await source.createProductTransfer(dataRoot: sourceData, outbox: outbox)
    }

    func checkpoint(_ receipt: HanlinProductTransferReceipt) -> URL {
        outbox.appending(path: receipt.id.uuidString.lowercased())
    }

    func receive(_ receipt: HanlinProductTransferReceipt) async throws -> HanlinProductTransferReceipt {
        try await target.receiveProductTransfer(from: checkpoint(receipt), dataRoot: targetData,
                                                transactionRoot: transactionRoot)
    }

    func bytes(_ directory: URL) throws -> [String: Data] {
        let paths = try #require(FileManager.default.enumerator(at: directory,
            includingPropertiesForKeys: [.isRegularFileKey]))
        var values: [String: Data] = [:]
        for case let file as URL in paths {
            if try file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true {
                values[String(file.path.dropFirst(directory.path.count + 1))] = try Data(contentsOf: file)
            }
        }
        return values
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

    init(installedPackageID: String = "fixture-install") throws {
        root = FileManager.default.temporaryDirectory.appending(
            path: "hanlin store tests \(UUID().uuidString.lowercased())",
            directoryHint: .isDirectory
        )
        storeRoot = root.appending(path: "store", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        installedID = try HanlinInstalledPackageID(validating: installedPackageID)
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
