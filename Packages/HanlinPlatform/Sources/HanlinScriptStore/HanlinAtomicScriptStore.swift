import CryptoKit
import Foundation
import HanlinPlatformContracts
import HanlinMiniAppCore
import HanlinScriptContracts
import OSLog

public enum HanlinInstallFaultPoint: String, Codable, CaseIterable, Sendable {
    case journalPersisted
    case artifactStaged
    case generationPromoted
    case registryCommitted
    case uninstallMoved
    case uninstallRegistryCommitted
}

public protocol HanlinInstallFaultInjector: Sendable {
    func check(_ point: HanlinInstallFaultPoint) throws
}

public struct HanlinNoInstallFaults: HanlinInstallFaultInjector {
    public init() {}
    public func check(_: HanlinInstallFaultPoint) throws {}
}

public enum HanlinAtomicScriptStoreError: Error, Equatable, Sendable {
    case alreadyInstalled(HanlinInstalledPackageID)
    case notInstalled(HanlinInstalledPackageID)
    case sourceAndArtifactDigestMatchRequired
    case artifactManifestMissing
    case artifactManifestMismatch(String)
    case requiredCapabilitiesNotGranted([HanlinCapabilityID])
    case unsupportedRegistryVersion(UInt32)
    case corruptRegistry
    case invalidGeneration(UInt64)
}

public struct HanlinScriptCatalogEntry: Codable, Hashable, Sendable {
    public let record: HanlinInstalledPackageRecord
    public let entrypoints: [HanlinPackageEntrypointDescriptor]
    public let enabled: Bool
    public let manifest: HanlinScriptingManifest?

    public init(
        record: HanlinInstalledPackageRecord,
        entrypoints: [HanlinPackageEntrypointDescriptor],
        enabled: Bool,
        manifest: HanlinScriptingManifest? = nil
    ) {
        self.record = record
        self.entrypoints = entrypoints
        self.enabled = enabled
        self.manifest = manifest
    }
}

public struct HanlinUnifiedPackageCatalogSnapshot: Codable, Hashable, Sendable {
    public let revision: UInt64
    public let generatedAt: Date
    public let nativeCatalog: HanlinCatalogSnapshot
    public let scriptPackages: [HanlinScriptCatalogEntry]

    public init(
        revision: UInt64,
        generatedAt: Date,
        nativeCatalog: HanlinCatalogSnapshot,
        scriptPackages: [HanlinScriptCatalogEntry]
    ) {
        self.revision = revision
        self.generatedAt = generatedAt
        self.nativeCatalog = nativeCatalog
        self.scriptPackages = scriptPackages
    }
}

public struct HanlinStoredPackageSnapshot: Codable, Hashable, Sendable {
    public let record: HanlinInstalledPackageRecord
    public let entrypoints: [HanlinPackageEntrypointDescriptor]
    public let enabled: Bool
    public let availableGenerations: [UInt64]
    public let grantedCapabilities: [HanlinCapabilityID]
    public let manifest: HanlinScriptingManifest?

    public init(
        record: HanlinInstalledPackageRecord,
        entrypoints: [HanlinPackageEntrypointDescriptor],
        enabled: Bool,
        availableGenerations: [UInt64],
        grantedCapabilities: [HanlinCapabilityID] = [],
        manifest: HanlinScriptingManifest? = nil
    ) {
        self.record = record
        self.entrypoints = entrypoints
        self.enabled = enabled
        self.availableGenerations = availableGenerations
        self.grantedCapabilities = grantedCapabilities.sorted { $0.rawValue < $1.rawValue }
        self.manifest = manifest
    }

    public var hasLaunchableApp: Bool {
        entrypoints.contains { $0.kind == .app }
    }

    public var hasWidgetEntrypoint: Bool {
        entrypoints.contains { $0.kind == .widget }
    }

    public var isWidgetOnly: Bool {
        !hasLaunchableApp && hasWidgetEntrypoint
    }
}

public actor HanlinAtomicScriptStore {
    private static let logger = Logger(subsystem: "com.hanlin.ai", category: "ScriptArtifactStore")
    private struct Registry: Codable, Sendable {
        let schemaVersion: UInt32
        var revision: UInt64
        var packages: [String: RegistryEntry]

        init(schemaVersion: UInt32 = 1, revision: UInt64 = 0, packages: [String: RegistryEntry] = [:]) {
            self.schemaVersion = schemaVersion
            self.revision = revision
            self.packages = packages
        }
    }

    private struct RegistryEntry: Codable, Sendable {
        var record: HanlinInstalledPackageRecord
        var entrypoints: [HanlinPackageEntrypointDescriptor]
        var enabled: Bool
        var grantedCapabilities: [HanlinCapabilityID]?
        var manifest: HanlinScriptingManifest?
    }

    private struct GenerationMetadata: Codable, Sendable {
        let packageID: HanlinPackageID
        let version: HanlinPackageVersion
        let sourceDigest: String
        let artifactDigest: String
    }

    private enum TransactionKind: String, Codable, Sendable { case install, update, uninstall }
    private enum TransactionPhase: String, Codable, Sendable {
        case preparing
        case generationPromoted
        case registryCommitted
        case uninstallMoved
        case uninstallRegistryCommitted
    }

    private struct Journal: Codable, Sendable {
        let schemaVersion: UInt32
        let transactionID: UUID
        let kind: TransactionKind
        let installedPackageID: String
        let generation: UInt64?
        var phase: TransactionPhase
    }

    public nonisolated let root: URL
    private let fileManager: FileManager
    private let faults: any HanlinInstallFaultInjector
    private let now: @Sendable () -> Date
    private var registry: Registry

    public init(
        root: URL,
        fileManager: FileManager = .default,
        faults: any HanlinInstallFaultInjector = HanlinNoInstallFaults(),
        now: @escaping @Sendable () -> Date = { Date() }
    ) throws {
        self.root = root.standardizedFileURL
        self.fileManager = fileManager
        self.faults = faults
        self.now = now
        registry = .init()
        registry = try HanlinStoreFileAccess.withExclusiveAccess {
            try Self.prepare(root: root.standardizedFileURL, fileManager: fileManager)
            return try Self.loadRegistry(root: root.standardizedFileURL, fileManager: fileManager)
        }
    }

    @discardableResult
    public func restore() throws -> [HanlinStoredPackageSnapshot] {
        return try HanlinStoreFileAccess.withExclusiveAccess {
            try recoverTransactions()
            registry = try Self.loadRegistry(root: root, fileManager: fileManager)
            try discardUnreferencedStaging()
            return try snapshots()
        }
    }

    public func snapshots() throws -> [HanlinStoredPackageSnapshot] {
        return try HanlinStoreFileAccess.withExclusiveAccess {
            try registry.packages.values.map { entry in
                .init(
                    record: entry.record,
                    entrypoints: entry.entrypoints,
                    enabled: entry.enabled,
                    availableGenerations: try generations(for: entry.record.installedPackageID),
                    grantedCapabilities: entry.grantedCapabilities ?? [],
                    manifest: entry.manifest
                )
            }.sorted { $0.record.installedPackageID.rawValue < $1.record.installedPackageID.rawValue }
        }
    }

    /// Returns the current persisted capability grants for one installed package.
    ///
    /// Host Services calls this at authorization time so a grant change is
    /// visible to an already-running package on its next privileged request.
    public func grantedCapabilities(
        for id: HanlinInstalledPackageID
    ) throws -> Set<HanlinCapabilityID> {
        return try HanlinStoreFileAccess.withExclusiveAccess {
            guard let entry = registry.packages[id.rawValue] else {
                throw HanlinAtomicScriptStoreError.notInstalled(id)
            }
            return Set(entry.grantedCapabilities ?? [])
        }
    }

    public func unifiedCatalog(native: HanlinCatalogSnapshot) -> HanlinUnifiedPackageCatalogSnapshot {
        return HanlinStoreFileAccess.withExclusiveAccess {
            .init(
                revision: max(registry.revision, native.revision.rawValue),
                generatedAt: now(),
                nativeCatalog: native,
                scriptPackages: registry.packages.values.map {
                    .init(record: $0.record, entrypoints: $0.entrypoints, enabled: $0.enabled, manifest: $0.manifest)
                }.sorted { $0.record.installedPackageID.rawValue < $1.record.installedPackageID.rawValue }
            )
        }
    }

    @discardableResult
    public func install(
        plan: HanlinInstallPlan,
        artifactDirectory: URL,
        artifactManifest: HanlinPackageArtifactManifest
    ) throws -> HanlinInstalledPackageRecord {
        return try HanlinStoreFileAccess.withExclusiveAccess {
            guard registry.packages[plan.installedPackageID.rawValue] == nil else {
                throw HanlinAtomicScriptStoreError.alreadyInstalled(plan.installedPackageID)
            }
            return try promote(
                kind: .install,
                plan: plan,
                artifactDirectory: artifactDirectory,
                artifactManifest: artifactManifest,
                installedAt: now()
            )
        }
    }

    @discardableResult
    public func update(
        plan: HanlinInstallPlan,
        artifactDirectory: URL,
        artifactManifest: HanlinPackageArtifactManifest
    ) throws -> HanlinInstalledPackageRecord {
        return try HanlinStoreFileAccess.withExclusiveAccess {
            guard let current = registry.packages[plan.installedPackageID.rawValue] else {
                throw HanlinAtomicScriptStoreError.notInstalled(plan.installedPackageID)
            }
            return try promote(
                kind: .update,
                plan: plan,
                artifactDirectory: artifactDirectory,
                artifactManifest: artifactManifest,
                installedAt: current.record.installedAt
            )
        }
    }

    @discardableResult
    public func rollback(_ id: HanlinInstalledPackageID, to generation: UInt64) throws -> HanlinInstalledPackageRecord {
        return try HanlinStoreFileAccess.withExclusiveAccess {
            guard var entry = registry.packages[id.rawValue] else {
                throw HanlinAtomicScriptStoreError.notInstalled(id)
            }
            _ = try loadAndVerifyManifest(at: generationURL(id, generation: generation))
            let metadata = try decoder.decode(
                GenerationMetadata.self,
                from: Data(contentsOf: generationURL(id, generation: generation).appending(path: "generation.json"))
            )
            let timestamp = now()
            entry.record = .init(
                installedPackageID: entry.record.installedPackageID,
                packageID: metadata.packageID,
                version: metadata.version,
                sourceDigest: metadata.sourceDigest,
                artifactDigest: metadata.artifactDigest,
                activeGeneration: generation,
                installedAt: entry.record.installedAt,
                updatedAt: timestamp
            )
            registry.packages[id.rawValue] = entry
            registry.revision &+= 1
            try persistRegistry()
            return entry.record
        }
    }

    public func setEnabled(_ enabled: Bool, for id: HanlinInstalledPackageID) throws {
        return try HanlinStoreFileAccess.withExclusiveAccess {
            guard var entry = registry.packages[id.rawValue] else {
                throw HanlinAtomicScriptStoreError.notInstalled(id)
            }
            entry.enabled = enabled
            registry.packages[id.rawValue] = entry
            registry.revision &+= 1
            try persistRegistry()
        }
    }

    public func setCapabilityGranted(
        _ granted: Bool,
        capability: HanlinCapabilityID,
        for id: HanlinInstalledPackageID
    ) throws {
        return try HanlinStoreFileAccess.withExclusiveAccess {
            guard var entry = registry.packages[id.rawValue] else {
                throw HanlinAtomicScriptStoreError.notInstalled(id)
            }
            var grants = Set(entry.grantedCapabilities ?? [])
            if granted { grants.insert(capability) } else { grants.remove(capability) }
            entry.grantedCapabilities = grants.sorted { $0.rawValue < $1.rawValue }
            registry.packages[id.rawValue] = entry
            registry.revision &+= 1
            try persistRegistry()
        }
    }

    public func uninstall(_ id: HanlinInstalledPackageID) throws {
        return try HanlinStoreFileAccess.withExclusiveAccess {
            guard registry.packages[id.rawValue] != nil else {
                throw HanlinAtomicScriptStoreError.notInstalled(id)
            }
            let transactionID = UUID()
            var journal = Journal(
                schemaVersion: 1,
                transactionID: transactionID,
                kind: .uninstall,
                installedPackageID: id.rawValue,
                generation: nil,
                phase: .preparing
            )
            try persist(journal)
            try faults.check(.journalPersisted)
            let installed = packageURL(id)
            let tombstone = tombstoneURL(transactionID)
            if fileManager.fileExists(atPath: installed.path(percentEncoded: false)) {
                try fileManager.moveItem(at: installed, to: tombstone)
            }
            journal.phase = .uninstallMoved
            try persist(journal)
            try faults.check(.uninstallMoved)
            registry.packages.removeValue(forKey: id.rawValue)
            registry.revision &+= 1
            try persistRegistry()
            journal.phase = .uninstallRegistryCommitted
            try persist(journal)
            try faults.check(.uninstallRegistryCommitted)
            try? fileManager.removeItem(at: tombstone)
            try? fileManager.removeItem(at: journalURL(transactionID))
        }
    }

    public func activeArtifactURL(for id: HanlinInstalledPackageID) throws -> URL {
        return try HanlinStoreFileAccess.withExclusiveAccess {
            guard let entry = registry.packages[id.rawValue] else {
                throw HanlinAtomicScriptStoreError.notInstalled(id)
            }
            let url = generationURL(id, generation: entry.record.activeGeneration)
            _ = try loadAndVerifyManifest(at: url)
            return url
        }
    }

    /// Call only after the application host has stopped admission of new engine
    /// work and verified that no native session or invocation is active.
    /// The source remains usable after this immutable copy is published.
    public func createProductTransfer(dataRoot: URL, outbox: URL) throws -> HanlinProductTransferReceipt {
        try HanlinStoreFileAccess.withExclusiveAccess {
            let packages = try restore()
            for package in packages {
                try HanlinMiniAppKeyValueStore.migrateUnopenedScriptingStorage(
                    root: dataRoot, appID: package.appID, installedPackageID: package.record.installedPackageID)
            }
            HanlinSQLiteService.closeConnections(under: dataRoot)
            try verifyTransferRegistry(registry, at: root)
            return try HanlinTransferCheckpoint.publish(installedRoot: root, dataRoot: dataRoot,
                outbox: outbox, packageCount: registry.packages.count).receipt
        }
    }

    /// Imports exact package identities, all retained generations, grants and
    /// private MiniApp files. Existing nonidentical entries are never replaced.
    /// The application must run recovery before initializing either store.
    public func receiveProductTransfer(from checkpointRoot: URL, dataRoot: URL, transactionRoot: URL,
        transferFaults: any HanlinProductTransferFaultInjector = HanlinNoProductTransferFaults()
    ) throws -> HanlinProductTransferReceipt {
        try HanlinStoreFileAccess.withExclusiveAccess {
            try HanlinProductTransferRecovery.distinct([root, dataRoot, transactionRoot, checkpointRoot])
            let checkpoint = try HanlinTransferCheckpoint.read(checkpointRoot)
            if let journal = try HanlinProductTransferRecovery.load(transactionRoot) {
                guard journal.checkpoint == checkpoint else {
                    throw HanlinProductTransferError.anotherTransferPending
                }
                guard journal.state != .rolledBack else {
                    throw HanlinProductTransferError.anotherTransferPending
                }
                try HanlinProductTransferRecovery.recover(installedRoot: root, dataRoot: dataRoot,
                    transactionRoot: transactionRoot, faults: transferFaults)
                registry = try Self.loadRegistry(root: root, fileManager: fileManager)
                return checkpoint.receipt
            }
            _ = try restore()
            let sourceRoot = checkpointRoot.appending(path: "Installed")
            let source = try decoder.decode(Registry.self,
                from: Data(contentsOf: sourceRoot.appending(path: "registry/catalog.json")))
            try verifyTransferRegistry(source, at: sourceRoot)
            try verifyTransferRegistry(registry, at: root)
            guard source.packages.count == checkpoint.receipt.packageCount else {
                throw HanlinProductTransferError.invalidCheckpoint
            }
            var merged = registry
            for (key, entry) in source.packages {
                if let existing = merged.packages[key] {
                    guard try encoder.encode(existing) == encoder.encode(entry) else {
                        throw HanlinProductTransferError.destinationConflict
                    }
                } else {
                    merged.packages[key] = entry
                }
            }
            let revision = max(source.revision, registry.revision)
            guard revision < UInt64.max else { throw HanlinProductTransferError.invalidCheckpoint }
            merged.revision = revision + 1
            HanlinSQLiteService.closeConnections(under: dataRoot)
            let beforeInstalled = try HanlinTransferTree.capture(root)
            let beforeData = try HanlinTransferTree.capture(dataRoot, durableSQLiteData: true)
            let catalogs: Set<String> = ["registry/catalog.json", "registry/catalog.backup.json"]
            try HanlinTransferTree.validateMerge(beforeInstalled, checkpoint.installed, excluding: catalogs)
            try HanlinTransferTree.validateMerge(beforeData, checkpoint.data)

            // An incomplete preparation is not the active journal. It cannot
            // change live data or prevent a later retry with another staging ID.
            let preparing = transactionRoot.deletingLastPathComponent()
                .appending(path: ".preparing-" + UUID().uuidString.lowercased())
            let stagedInstalled = preparing.appending(path: "new-installed")
            let stagedData = preparing.appending(path: "new-data")
            try beforeInstalled.copy(from: root, to: stagedInstalled, excluding: catalogs)
            try checkpoint.installed.copy(from: sourceRoot, to: stagedInstalled, excluding: catalogs)
            let catalogData = try encoder.encode(merged)
            for path in catalogs {
                try catalogData.write(to: HanlinTransferTree.child(stagedInstalled, path), options: .atomic)
            }
            try beforeData.copy(from: dataRoot, to: stagedData)
            try checkpoint.data.copy(from: checkpointRoot.appending(path: "MiniApps"), to: stagedData)
            try verifyTransferRegistry(merged, at: stagedInstalled)
            guard try HanlinTransferTree.capture(root) == beforeInstalled,
                  try HanlinTransferTree.capture(dataRoot, durableSQLiteData: true) == beforeData,
                  try HanlinTransferCheckpoint.read(checkpointRoot) == checkpoint else {
                throw HanlinProductTransferError.destinationConflict
            }
            let journal = HanlinProductTransferRecovery.Journal(version: 1, checkpoint: checkpoint,
                beforeInstalled: beforeInstalled, afterInstalled: try HanlinTransferTree.capture(stagedInstalled),
                beforeData: beforeData, afterData: try HanlinTransferTree.capture(stagedData, durableSQLiteData: true),
                state: .committing)
            try HanlinProductTransferRecovery.persist(journal, at: preparing)
            try fileManager.moveItem(at: preparing, to: transactionRoot)
            try transferFaults.check(.intentPersisted)
            try HanlinProductTransferRecovery.recover(installedRoot: root, dataRoot: dataRoot,
                transactionRoot: transactionRoot, faults: transferFaults)
            registry = try Self.loadRegistry(root: root, fileManager: fileManager)
            return checkpoint.receipt
        }
    }

    public func rollbackProductTransfer(dataRoot: URL, transactionRoot: URL,
        transferFaults: any HanlinProductTransferFaultInjector = HanlinNoProductTransferFaults()) throws {
        try HanlinStoreFileAccess.withExclusiveAccess {
            try HanlinProductTransferRecovery.rollback(installedRoot: root, dataRoot: dataRoot,
                transactionRoot: transactionRoot, faults: transferFaults)
            registry = try Self.loadRegistry(root: root, fileManager: fileManager)
        }
    }

    private func verifyTransferRegistry(_ value: Registry, at directory: URL) throws {
        guard value.schemaVersion == 1 else { throw HanlinAtomicScriptStoreError.unsupportedRegistryVersion(value.schemaVersion) }
        // A complete inventory rejects symlinks, including unreferenced files,
        // before any path in a decoded registry or manifest is read.
        let tree = try HanlinTransferTree.capture(directory)
        guard tree.exists else { throw HanlinProductTransferError.invalidCheckpoint }
        for (key, entry) in value.packages {
            let id = try HanlinInstalledPackageID(validating: key)
            _ = try HanlinPackageID(validating: entry.record.packageID.rawValue)
            guard entry.record.installedPackageID == id, entry.record.activeGeneration > 0 else {
                throw HanlinProductTransferError.invalidCheckpoint
            }
            let generationsRoot = directory.appending(path: "packages/\(key)/generations")
            let directories = try fileManager.contentsOfDirectory(at: generationsRoot, includingPropertiesForKeys: nil)
            var activeFound = false
            for generation in directories {
                guard let number = UInt64(generation.lastPathComponent), number > 0,
                      String(number) == generation.lastPathComponent else {
                    throw HanlinProductTransferError.invalidCheckpoint
                }
                let artifact = try loadAndVerifyManifest(at: generation)
                let metadata = try decoder.decode(GenerationMetadata.self,
                    from: Data(contentsOf: generation.appending(path: "generation.json")))
                guard metadata.packageID == entry.record.packageID,
                      metadata.sourceDigest == artifact.packageContentDigest,
                      metadata.artifactDigest == artifact.cacheFingerprint else {
                    throw HanlinProductTransferError.invalidCheckpoint
                }
                if number == entry.record.activeGeneration {
                    guard metadata.version == entry.record.version,
                          metadata.sourceDigest == entry.record.sourceDigest,
                          metadata.artifactDigest == entry.record.artifactDigest else {
                        throw HanlinProductTransferError.invalidCheckpoint
                    }
                    activeFound = true
                }
            }
            guard activeFound else { throw HanlinProductTransferError.invalidCheckpoint }
        }
    }

    private func promote(
        kind: TransactionKind,
        plan: HanlinInstallPlan,
        artifactDirectory: URL,
        artifactManifest: HanlinPackageArtifactManifest,
        installedAt: Date
    ) throws -> HanlinInstalledPackageRecord {
        let approvalState = HanlinCapabilityApprovalState(
            requests: plan.requestedCapabilities + plan.entrypoints.flatMap(\.requiredCapabilities),
            approvedCapabilities: Set(plan.grantedCapabilities)
        )
        guard approvalState.hasApprovedEveryRequiredCapability else {
            throw HanlinAtomicScriptStoreError.requiredCapabilitiesNotGranted(
                approvalState.missingRequiredCapabilities
            )
        }
        guard plan.sourceDigest == artifactManifest.packageContentDigest else {
            throw HanlinAtomicScriptStoreError.sourceAndArtifactDigestMatchRequired
        }
        let nextGeneration = (try generations(for: plan.installedPackageID).max() ?? 0) + 1
        let transactionID = UUID()
        let staged = stagingURL(transactionID)
        var journal = Journal(
            schemaVersion: 1,
            transactionID: transactionID,
            kind: kind,
            installedPackageID: plan.installedPackageID.rawValue,
            generation: nextGeneration,
            phase: .preparing
        )
        try persist(journal)
        try faults.check(.journalPersisted)
        try fileManager.copyItem(at: artifactDirectory, to: staged)
        _ = try loadAndVerifyManifest(at: staged, expected: artifactManifest)
        try encoder.encode(GenerationMetadata(
            packageID: plan.packageID,
            version: plan.version,
            sourceDigest: plan.sourceDigest,
            artifactDigest: artifactManifest.cacheFingerprint
        )).write(to: staged.appending(path: "generation.json"), options: .atomic)
        try faults.check(.artifactStaged)
        let destination = generationURL(plan.installedPackageID, generation: nextGeneration)
        try fileManager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fileManager.moveItem(at: staged, to: destination)
        journal.phase = .generationPromoted
        try persist(journal)
        try faults.check(.generationPromoted)

        let timestamp = now()
        let record = HanlinInstalledPackageRecord(
            installedPackageID: plan.installedPackageID,
            packageID: plan.packageID,
            version: plan.version,
            sourceDigest: plan.sourceDigest,
            artifactDigest: artifactManifest.cacheFingerprint,
            activeGeneration: nextGeneration,
            installedAt: installedAt,
            updatedAt: timestamp
        )
        registry.packages[plan.installedPackageID.rawValue] = .init(
            record: record,
            entrypoints: plan.entrypoints,
            enabled: true,
            grantedCapabilities: plan.grantedCapabilities,
            manifest: plan.manifest
        )
        registry.revision &+= 1
        try persistRegistry()
        journal.phase = .registryCommitted
        try persist(journal)
        try faults.check(.registryCommitted)
        try? fileManager.removeItem(at: journalURL(transactionID))
        return record
    }

    private func recoverTransactions() throws {
        let urls = try fileManager.contentsOfDirectory(
            at: journalsRoot,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ).filter { $0.pathExtension == "json" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
        for url in urls {
            let journal = try decoder.decode(Journal.self, from: Data(contentsOf: url))
            guard journal.schemaVersion == 1,
                  let id = try? HanlinInstalledPackageID(validating: journal.installedPackageID)
            else { throw HanlinAtomicScriptStoreError.corruptRegistry }
            switch journal.kind {
            case .install, .update:
                try? fileManager.removeItem(at: stagingURL(journal.transactionID))
                if journal.phase == .generationPromoted,
                   let generation = journal.generation,
                   registry.packages[id.rawValue]?.record.activeGeneration != generation
                {
                    try? fileManager.removeItem(at: generationURL(id, generation: generation))
                }
            case .uninstall:
                let tombstone = tombstoneURL(journal.transactionID)
                if journal.phase == .uninstallMoved, registry.packages[id.rawValue] != nil {
                    if fileManager.fileExists(atPath: tombstone.path(percentEncoded: false)) {
                        try fileManager.moveItem(at: tombstone, to: packageURL(id))
                    }
                } else {
                    try? fileManager.removeItem(at: tombstone)
                }
            }
            try? fileManager.removeItem(at: url)
        }
    }

    private func discardUnreferencedStaging() throws {
        for url in try fileManager.contentsOfDirectory(at: stagingRoot, includingPropertiesForKeys: nil) {
            try? fileManager.removeItem(at: url)
        }
    }

    private func generations(for id: HanlinInstalledPackageID) throws -> [UInt64] {
        let directory = packageURL(id).appending(path: "generations", directoryHint: .isDirectory)
        guard fileManager.fileExists(atPath: directory.path(percentEncoded: false)) else { return [] }
        return try fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .compactMap { UInt64($0.lastPathComponent) }.sorted()
    }

    private func loadAndVerifyManifest(
        at directory: URL,
        expected: HanlinPackageArtifactManifest? = nil
    ) throws -> HanlinPackageArtifactManifest {
        let url = directory.appending(path: "artifact-manifest.json", directoryHint: .notDirectory)
        guard fileManager.fileExists(atPath: url.path(percentEncoded: false)) else {
            let discovered = (try? fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil
            ).map(\.lastPathComponent).sorted().prefix(32).joined(separator: ",")) ?? "unreadable"
            let expectedPath = url.path(percentEncoded: false)
            let parentExists = fileManager.fileExists(atPath: directory.path(percentEncoded: false))
            let standardizedPath = url.standardizedFileURL.path(percentEncoded: false)
            let symlinkResolvedPath = url.resolvingSymlinksInPath().path(percentEncoded: false)
            Self.logger.error(
                "phase=artifact-manifest-resolution expected=\(expectedPath, privacy: .public) parentExists=\(parentExists, privacy: .public) standardized=\(standardizedPath, privacy: .public) symlinkResolved=\(symlinkResolvedPath, privacy: .public) discovered=\(discovered, privacy: .public)"
            )
            throw HanlinAtomicScriptStoreError.artifactManifestMissing
        }
        let manifest = try decoder.decode(HanlinPackageArtifactManifest.self, from: Data(contentsOf: url))
        if let expected, expected != manifest {
            throw HanlinAtomicScriptStoreError.artifactManifestMismatch("manifest")
        }
        for file in manifest.files {
            let candidate = try containedURL(file.logicalPath, root: directory)
            let bytes = try Data(contentsOf: candidate)
            guard Int64(bytes.count) == file.byteCount,
                  Self.sha256(bytes) == file.sha256
            else { throw HanlinAtomicScriptStoreError.artifactManifestMismatch(file.logicalPath) }
        }
        return manifest
    }

    private func persistRegistry() throws {
        let data = try encoder.encode(registry)
        if fileManager.fileExists(atPath: registryURL.path(percentEncoded: false)) {
            try? fileManager.removeItem(at: backupRegistryURL)
            try fileManager.copyItem(at: registryURL, to: backupRegistryURL)
        }
        try data.write(to: registryURL, options: .atomic)
    }

    private func persist(_ journal: Journal) throws {
        try encoder.encode(journal).write(to: journalURL(journal.transactionID), options: .atomic)
    }

    private var registryURL: URL { root.appending(path: "registry/catalog.json") }
    private var backupRegistryURL: URL { root.appending(path: "registry/catalog.backup.json") }
    private var journalsRoot: URL { root.appending(path: "registry/journals", directoryHint: .isDirectory) }
    private var stagingRoot: URL { root.appending(path: "staging", directoryHint: .isDirectory) }
    private var tombstonesRoot: URL { root.appending(path: "tombstones", directoryHint: .isDirectory) }
    private func packageURL(_ id: HanlinInstalledPackageID) -> URL {
        root.appending(path: "packages/\(id.rawValue)", directoryHint: .isDirectory)
    }
    private func generationURL(_ id: HanlinInstalledPackageID, generation: UInt64) -> URL {
        packageURL(id).appending(path: "generations/\(generation)", directoryHint: .isDirectory)
    }
    private func stagingURL(_ id: UUID) -> URL { stagingRoot.appending(path: id.uuidString.lowercased()) }
    private func tombstoneURL(_ id: UUID) -> URL { tombstonesRoot.appending(path: id.uuidString.lowercased()) }
    private func journalURL(_ id: UUID) -> URL { journalsRoot.appending(path: "\(id.uuidString.lowercased()).json") }

    private var encoder: JSONEncoder {
        let value = JSONEncoder()
        value.outputFormatting = [.sortedKeys]
        value.dateEncodingStrategy = .millisecondsSince1970
        return value
    }

    private var decoder: JSONDecoder {
        let value = JSONDecoder()
        value.dateDecodingStrategy = .millisecondsSince1970
        return value
    }

    private func containedURL(_ path: String, root: URL) throws -> URL {
        let components = path.split(separator: "/", omittingEmptySubsequences: false)
        guard !path.isEmpty, !path.hasPrefix("/"), !path.contains("\\"),
              !components.contains(".."), !components.contains("")
        else { throw HanlinAtomicScriptStoreError.artifactManifestMismatch(path) }
        return components.reduce(root) { $0.appending(path: String($1), directoryHint: .notDirectory) }
    }

    private static func prepare(root: URL, fileManager: FileManager) throws {
        for path in ["registry/journals", "packages", "staging", "tombstones"] {
            try fileManager.createDirectory(
                at: root.appending(path: path, directoryHint: .isDirectory),
                withIntermediateDirectories: true
            )
        }
        let registryURL = root.appending(path: "registry/catalog.json")
        if !fileManager.fileExists(atPath: registryURL.path(percentEncoded: false)) {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            encoder.dateEncodingStrategy = .millisecondsSince1970
            try encoder.encode(Registry()).write(to: registryURL, options: .atomic)
        }
    }

    private static func loadRegistry(root: URL, fileManager: FileManager) throws -> Registry {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        let primary = root.appending(path: "registry/catalog.json")
        let backup = root.appending(path: "registry/catalog.backup.json")
        let loaded = [primary, backup].lazy.compactMap { url -> Registry? in
            guard let data = try? Data(contentsOf: url) else { return nil }
            return try? decoder.decode(Registry.self, from: data)
        }.first
        guard let loaded else { throw HanlinAtomicScriptStoreError.corruptRegistry }
        guard loaded.schemaVersion == 1 else {
            throw HanlinAtomicScriptStoreError.unsupportedRegistryVersion(loaded.schemaVersion)
        }
        return loaded
    }

    private static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
