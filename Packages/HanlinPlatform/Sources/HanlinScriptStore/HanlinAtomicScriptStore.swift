import CryptoKit
import Foundation
import HanlinPlatformContracts
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

    private let root: URL
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
        try Self.prepare(root: self.root, fileManager: fileManager)
        registry = try Self.loadRegistry(root: self.root, fileManager: fileManager)
    }

    @discardableResult
    public func restore() throws -> [HanlinStoredPackageSnapshot] {
        try recoverTransactions()
        registry = try Self.loadRegistry(root: root, fileManager: fileManager)
        try discardUnreferencedStaging()
        return try snapshots()
    }

    public func snapshots() throws -> [HanlinStoredPackageSnapshot] {
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

    public func unifiedCatalog(native: HanlinCatalogSnapshot) -> HanlinUnifiedPackageCatalogSnapshot {
        .init(
            revision: max(registry.revision, native.revision.rawValue),
            generatedAt: now(),
            nativeCatalog: native,
            scriptPackages: registry.packages.values.map {
                .init(record: $0.record, entrypoints: $0.entrypoints, enabled: $0.enabled, manifest: $0.manifest)
            }.sorted { $0.record.installedPackageID.rawValue < $1.record.installedPackageID.rawValue }
        )
    }

    @discardableResult
    public func install(
        plan: HanlinInstallPlan,
        artifactDirectory: URL,
        artifactManifest: HanlinPackageArtifactManifest
    ) throws -> HanlinInstalledPackageRecord {
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

    @discardableResult
    public func update(
        plan: HanlinInstallPlan,
        artifactDirectory: URL,
        artifactManifest: HanlinPackageArtifactManifest
    ) throws -> HanlinInstalledPackageRecord {
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

    @discardableResult
    public func rollback(_ id: HanlinInstalledPackageID, to generation: UInt64) throws -> HanlinInstalledPackageRecord {
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

    public func setEnabled(_ enabled: Bool, for id: HanlinInstalledPackageID) throws {
        guard var entry = registry.packages[id.rawValue] else {
            throw HanlinAtomicScriptStoreError.notInstalled(id)
        }
        entry.enabled = enabled
        registry.packages[id.rawValue] = entry
        registry.revision &+= 1
        try persistRegistry()
    }

    public func setCapabilityGranted(
        _ granted: Bool,
        capability: HanlinCapabilityID,
        for id: HanlinInstalledPackageID
    ) throws {
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

    public func uninstall(_ id: HanlinInstalledPackageID) throws {
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
        if fileManager.fileExists(atPath: installed.path()) {
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

    public func activeArtifactURL(for id: HanlinInstalledPackageID) throws -> URL {
        guard let entry = registry.packages[id.rawValue] else {
            throw HanlinAtomicScriptStoreError.notInstalled(id)
        }
        let url = generationURL(id, generation: entry.record.activeGeneration)
        _ = try loadAndVerifyManifest(at: url)
        return url
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
                    if fileManager.fileExists(atPath: tombstone.path()) {
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
        guard fileManager.fileExists(atPath: directory.path()) else { return [] }
        return try fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .compactMap { UInt64($0.lastPathComponent) }.sorted()
    }

    private func loadAndVerifyManifest(
        at directory: URL,
        expected: HanlinPackageArtifactManifest? = nil
    ) throws -> HanlinPackageArtifactManifest {
        let url = directory.appending(path: "artifact-manifest.json", directoryHint: .notDirectory)
        guard fileManager.fileExists(atPath: url.path()) else {
            let discovered = (try? fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil
            ).map(\.lastPathComponent).sorted().prefix(32).joined(separator: ",")) ?? "unreadable"
            Self.logger.error(
                "phase=artifact-manifest-resolution expected=artifact-manifest.json directory=\(directory.lastPathComponent, privacy: .public) discovered=\(discovered, privacy: .public)"
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
        if fileManager.fileExists(atPath: registryURL.path()) {
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
        if !fileManager.fileExists(atPath: registryURL.path()) {
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
