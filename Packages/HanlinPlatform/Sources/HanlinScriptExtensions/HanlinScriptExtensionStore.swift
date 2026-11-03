import CryptoKit
import Foundation
import HanlinPlatformContracts
import OSLog
#if canImport(Darwin)
import Darwin
#endif

public enum HanlinScriptExtensionStoreError: Error, Equatable, Sendable {
    case appGroupUnavailable
    case snapshotTooLarge
    case invalidEnvelope
    case integrityMismatch
    case unsupportedSchema(UInt32)
    case invalidArtifactReference
    case artifactMissing
    case artifactTooLarge
    case storageBusy
    case invalidCommit
}

private final class HanlinWidgetDiagnosticBuffer: @unchecked Sendable {
    static let shared = HanlinWidgetDiagnosticBuffer()
    private let lock = NSLock()
    private var latest: HanlinWidgetStorageDiagnostic?
    private var history: [HanlinWidgetStorageDiagnostic] = []

    func record(_ diagnostic: HanlinWidgetStorageDiagnostic) {
        lock.lock()
        defer { lock.unlock() }
        latest = diagnostic
        history.append(diagnostic)
        if history.count > 64 {
            history.removeFirst(history.count - 64)
        }
    }

    func lastDiagnostic() -> HanlinWidgetStorageDiagnostic? {
        lock.lock()
        defer { lock.unlock() }
        return latest
    }

    func recentDiagnostics() -> [HanlinWidgetStorageDiagnostic] {
        lock.lock()
        defer { lock.unlock() }
        return history
    }
}

public struct HanlinScriptExtensionStore: Sendable {
    public static let appGroupIdentifier = "group.com.itorah.chavrusachat"
    public static let maximumSnapshotBytes = 4 * 1_024 * 1_024
    public static let maximumArtifactBytes = 3 * 1_024 * 1_024
    private static let logger = Logger(subsystem: "com.hanlin.ai", category: "WidgetStorage")

    public enum Recovery: String, Sendable {
        case interruptedPublication
        case completedPublicationCleanup
        case legacyWriterDetected
    }

    public struct LoadResult: Sendable {
        public let snapshot: HanlinScriptExtensionSnapshot?
        public let recovery: Recovery?
    }

    private struct Commit: Codable, Equatable {
        let version: UInt32
        let snapshotHash: String
        let shadowHash: String
    }

    private struct Pending: Codable {
        let candidate: Commit
        let previousShadowHash: String?
    }

    private struct Envelope: Codable {
        let schemaVersion: UInt32
        let sha256: String
        let snapshot: HanlinScriptExtensionSnapshot
    }

    public let root: URL

    public init(root: URL) {
        self.root = Self.canonicalManagedRoot(for: root)
    }

    public init(appGroupIdentifier: String = Self.appGroupIdentifier) throws {
        guard let container = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupIdentifier
        ) else {
            let diag = HanlinWidgetStorageDiagnostic(
                phase: .storeLoad,
                decisionPoint: .appGroupResolution,
                relativePath: ".",
                errorDomain: "HanlinScriptExtensionStoreError",
                errorCode: 1,
                summary: "Shared App Group container is unavailable."
            )
            Self.recordDiagnostic(diag)
            throw HanlinScriptExtensionStoreError.appGroupUnavailable
        }
        let canonicalContainer = container.resolvingSymlinksInPath().standardizedFileURL
        self.root = Self.canonicalManagedRoot(
            for: canonicalContainer.appending(path: "ScriptingExtensions", directoryHint: .isDirectory)
        )
    }

    public var lastDiagnostic: HanlinWidgetStorageDiagnostic? {
        HanlinWidgetDiagnosticBuffer.shared.lastDiagnostic()
    }

    public static var latestDiagnostic: HanlinWidgetStorageDiagnostic? {
        HanlinWidgetDiagnosticBuffer.shared.lastDiagnostic()
    }

    public static var recentDiagnostics: [HanlinWidgetStorageDiagnostic] {
        HanlinWidgetDiagnosticBuffer.shared.recentDiagnostics()
    }

    public static func recordDiagnostic(_ diagnostic: HanlinWidgetStorageDiagnostic) {
        HanlinWidgetDiagnosticBuffer.shared.record(diagnostic)
        logger.error("widget_storage_diagnostic \(diagnostic.redactedReportString, privacy: .public)")
    }

    private var queryDiagnosticURL: URL {
        root.appending(path: "diagnostics", directoryHint: .isDirectory)
            .appending(path: "latest-query-diagnostic.json")
    }

    public func recordDurableQueryDiagnostic(_ diagnostic: HanlinWidgetStorageDiagnostic) {
        Self.recordDiagnostic(diagnostic)
        do {
            let dir = root.appending(path: "diagnostics", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(diagnostic)
            try data.write(to: queryDiagnosticURL, options: .atomic)
        } catch {
            Self.logger.error("Failed to write durable query diagnostic: \(error.localizedDescription)")
        }
    }

    public var latestDurableQueryDiagnostic: HanlinWidgetStorageDiagnostic? {
        guard let data = try? Data(contentsOf: queryDiagnosticURL),
              let diag = try? JSONDecoder().decode(HanlinWidgetStorageDiagnostic.self, from: data) else {
            return nil
        }
        return diag
    }

    public static func recordQueryDiagnostic(
        error: Error,
        phase: HanlinWidgetStorageDiagnostic.Phase = .widgetExtensionEntityQuery
    ) {
        let store = try? HanlinScriptExtensionStore()
        let diag: HanlinWidgetStorageDiagnostic
        if let existing = store?.lastDiagnostic ?? latestDiagnostic {
            diag = HanlinWidgetStorageDiagnostic(
                correlationID: existing.correlationID,
                phase: phase,
                decisionPoint: existing.decisionPoint,
                relativePath: existing.relativePath,
                failingComponentIndex: existing.failingComponentIndex,
                failingComponentName: existing.failingComponentName,
                errorDomain: existing.errorDomain,
                errorCode: existing.errorCode,
                posixErrno: existing.posixErrno,
                summary: existing.summary
            )
        } else {
            let nsError = error as NSError
            diag = HanlinWidgetStorageDiagnostic(
                phase: phase,
                decisionPoint: .instancePublication,
                relativePath: "ScriptingExtensions",
                errorDomain: nsError.domain,
                errorCode: nsError.code,
                summary: "Widget extension query failed: \(error.localizedDescription)"
            )
        }
        if let store {
            store.recordDurableQueryDiagnostic(diag)
        } else {
            recordDiagnostic(diag)
        }
    }

    public func load() throws -> HanlinScriptExtensionSnapshot? {
        try loadWithRecovery().snapshot
    }

    public func loadWithRecovery() throws -> LoadResult {
        try withLock { try loadUnlocked() }
    }

    /// One cross-process read/modify/commit boundary, shared by host and intents.
    /// The closure must be synchronous and must not re-enter this store.
    @discardableResult
    public func update(
        _ mutation: (HanlinScriptExtensionSnapshot?) throws -> HanlinScriptExtensionSnapshot
    ) throws -> HanlinScriptExtensionSnapshot {
        try withLock {
            let previous = try loadUnlocked().snapshot
            let snapshot = try mutation(previous)
            if snapshot != previous { try saveUnlocked(snapshot) }
            return snapshot
        }
    }

    private func loadUnlocked() throws -> LoadResult {
        var recovery: Recovery?
        let commit = try optionalDecode(Commit.self, at: commitURL)
        if let pending = try optionalDecode(Pending.self, at: pendingURL) {
            if commit == pending.candidate {
                recovery = .completedPublicationCleanup
            } else {
                // The v1 shadow was written but its v2 commit never became visible.
                // Restore exactly the preceding shadow, not a synthesized fallback.
                if let hash = pending.previousShadowHash {
                    try checkedRevision(hash).write(to: snapshotV1URL, options: Self.writeOptions)
                } else if FileManager.default.fileExists(atPath: snapshotV1URL.path) {
                    try FileManager.default.removeItem(at: snapshotV1URL)
                }
                recovery = .interruptedPublication
            }
            try FileManager.default.removeItem(at: pendingURL)
        }
        if let commit {
            guard commit.version == 1 else { throw HanlinScriptExtensionStoreError.invalidCommit }
            let data = try checkedRevision(commit.snapshotHash)
            guard let shadow = try optionalData(at: snapshotV1URL) else {
                throw HanlinScriptExtensionStoreError.invalidCommit
            }
            if Self.digest(shadow) != commit.shadowHash {
                // A previous binary can only write snapshot-v1.json. Treat its
                // verified bytes as an explicit downgrade, never prefer stale v2.
                let snapshot = try decodeEnvelope(shadow)
                guard snapshot.schemaVersion == 1 else { throw HanlinScriptExtensionStoreError.invalidCommit }
                let committed = try decodeEnvelope(data)
                // Preserve v2-only durable configuration/state while honoring
                // the old binary's newly written legacy collections. The old
                // executable cannot interpret native engines or their variants.
                let restored = HanlinScriptExtensionSnapshot(schemaVersion: 1, generatedAt: snapshot.generatedAt,
                    widgets: snapshot.widgets, intentEntities: snapshot.intentEntities, liveActivities: snapshot.liveActivities,
                    translationApps: snapshot.translationApps, widgetInstances: committed.widgetInstances,
                    widgetStates: committed.widgetStates, widgetEntityMigrations: committed.widgetEntityMigrations,
                    inactiveWidgetInstallations: committed.inactiveWidgetInstallations)
                return .init(snapshot: restored, recovery: .legacyWriterDetected)
            }
            return .init(snapshot: try decodeEnvelope(data), recovery: recovery)
        }
        // Migrate the preceding store format without hiding corrupt v2 data.
        if FileManager.default.fileExists(atPath: snapshotV2URL.path) {
            return .init(snapshot: try loadFile(at: snapshotV2URL), recovery: recovery)
        }
        return .init(snapshot: try loadFile(at: snapshotV1URL), recovery: recovery)
    }

    private func loadFile(at url: URL) throws -> HanlinScriptExtensionSnapshot? {
        try rejectSymlinks(to: url, phase: .storeLoad)
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else { return nil }
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        guard data.count <= Self.maximumSnapshotBytes else {
            throw HanlinScriptExtensionStoreError.snapshotTooLarge
        }
        return try decodeEnvelope(data)
    }

    private func decodeEnvelope(_ data: Data) throws -> HanlinScriptExtensionSnapshot {
        guard data.count <= Self.maximumSnapshotBytes,
              let raw = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rawSnapshot = raw["snapshot"],
              let expectedHash = raw["sha256"] as? String else {
            throw HanlinScriptExtensionStoreError.invalidEnvelope
        }
        // Hash the original wire fields. Re-encoding a decoded v1 model adds v2
        // defaults and would incorrectly reject a genuine historical SHA envelope.
        let wireData = try JSONSerialization.data(withJSONObject: rawSnapshot, options: [.sortedKeys, .withoutEscapingSlashes])
        guard Self.digest(wireData) == expectedHash else {
            throw HanlinScriptExtensionStoreError.integrityMismatch
        }
        let envelope = try Self.decoded(Envelope.self, from: data)
        guard envelope.schemaVersion == 1 || envelope.schemaVersion == 2 else {
            throw HanlinScriptExtensionStoreError.unsupportedSchema(envelope.schemaVersion)
        }
        guard envelope.schemaVersion == envelope.snapshot.schemaVersion else { throw HanlinScriptExtensionStoreError.invalidEnvelope }
        return envelope.snapshot
    }

    public func save(_ snapshot: HanlinScriptExtensionSnapshot) throws {
        try withLock {
            _ = try loadUnlocked()
            try saveUnlocked(snapshot)
        }
    }

    private func saveUnlocked(_ snapshot: HanlinScriptExtensionSnapshot) throws {
        guard snapshot.schemaVersion == 1 || snapshot.schemaVersion == 2 else {
            throw HanlinScriptExtensionStoreError.unsupportedSchema(snapshot.schemaVersion)
        }
        try rejectSymlinks(to: root, phase: .storeSave)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try rejectSymlinks(to: root, phase: .storeSave)

        let shadow: HanlinScriptExtensionSnapshot
        if snapshot.schemaVersion == 2 {
            let v1Widgets = snapshot.widgets.map { w in
                HanlinScriptWidgetSnapshot(
                    identity: w.identity,
                    displayName: w.displayName,
                    family: w.family,
                    actionIdentity: w.actionIdentity,
                    validUntil: w.validUntil,
                    relevance: w.relevance,
                    engine: .legacy,
                    payload: .legacy(w.root),
                    root: w.root,
                    deepLink: w.deepLink
                )
            }
            shadow = HanlinScriptExtensionSnapshot(
                schemaVersion: 1,
                generatedAt: snapshot.generatedAt,
                widgets: v1Widgets,
                intentEntities: snapshot.intentEntities,
                liveActivities: snapshot.liveActivities,
                translationApps: snapshot.translationApps
            )
        } else {
            shadow = snapshot
        }
        let data = try envelopeData(snapshot)
        let shadowData = try legacyEnvelopeData(shadow)
        let candidate = Commit(version: 1, snapshotHash: Self.digest(data), shadowHash: Self.digest(shadowData))
        try writeRevision(data)
        try writeRevision(shadowData)
        let previousShadow = try optionalData(at: snapshotV1URL)
        if let previousShadow { try writeRevision(previousShadow) }
        let pending = Pending(candidate: candidate, previousShadowHash: previousShadow.map(Self.digest))
        try rejectSymlinks(to: pendingURL, phase: .storeSave)
        try Self.encoded(pending).write(to: pendingURL, options: Self.writeOptions)
        // Older readers see one complete v1 shadow. New readers switch only at
        // the atomic commit marker after both immutable revisions are durable.
        try rejectSymlinks(to: snapshotV1URL, phase: .storeSave)
        try shadowData.write(to: snapshotV1URL, options: Self.writeOptions)
        try rejectSymlinks(to: commitURL, phase: .storeSave)
        try Self.encoded(candidate).write(to: commitURL, options: Self.writeOptions)
        try FileManager.default.removeItem(at: pendingURL)
    }

    private func envelopeData(_ snapshot: HanlinScriptExtensionSnapshot) throws -> Data {
        let snapshotData = try Self.encoded(snapshot)
        let object = try JSONSerialization.jsonObject(with: snapshotData)
        let canonical = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes])
        let envelope = Envelope(
            schemaVersion: snapshot.schemaVersion,
            sha256: Self.digest(canonical),
            snapshot: snapshot
        )
        let data = try Self.encoded(envelope)
        guard data.count <= Self.maximumSnapshotBytes else {
            throw HanlinScriptExtensionStoreError.snapshotTooLarge
        }
        return data
    }

    private func legacyEnvelopeData(_ snapshot: HanlinScriptExtensionSnapshot) throws -> Data {
        guard var raw = try JSONSerialization.jsonObject(with: Self.encoded(snapshot)) as? [String: Any] else { throw HanlinScriptExtensionStoreError.invalidEnvelope }
        for key in ["widgetInstances", "widgetStates", "widgetEntityMigrations", "inactiveWidgetInstallations"] { raw.removeValue(forKey: key) }
        func oldIdentity(_ value: Any?) -> Any? {
            guard var object = value as? [String: Any] else { return value }
            object.removeValue(forKey: "variantID")
            return object
        }
        for key in ["widgets", "intentEntities", "liveActivities", "translationApps"] {
            let records = raw[key] as? [[String: Any]] ?? []
            raw[key] = records.compactMap { record -> [String: Any]? in
                var record = record
                if key == "widgets", let identity = record["identity"] as? [String: Any],
                   let variant = identity["variantID"] as? String, variant != "default" { return nil }
                record["identity"] = oldIdentity(record["identity"])
                record["actionIdentity"] = oldIdentity(record["actionIdentity"])
                record.removeValue(forKey: "engine")
                record.removeValue(forKey: "payload")
                return record
            }
        }
        raw["schemaVersion"] = 1
        let wire = try JSONSerialization.data(withJSONObject: raw, options: [.sortedKeys, .withoutEscapingSlashes])
        let data = try JSONSerialization.data(withJSONObject: ["schemaVersion": 1, "sha256": Self.digest(wire), "snapshot": raw], options: [.sortedKeys, .withoutEscapingSlashes])
        guard data.count <= Self.maximumSnapshotBytes else { throw HanlinScriptExtensionStoreError.snapshotTooLarge }
        return data
    }

    public func storeArtifact(
        data: Data,
        installedPackageID: HanlinInstalledPackageID,
        generation: UInt64
    ) throws -> (ref: String, sha256: String) {
        guard data.count <= Self.maximumArtifactBytes else { throw HanlinScriptExtensionStoreError.artifactTooLarge }
        guard generation > 0 else {
            Self.recordDiagnostic(.init(
                phase: .storeArtifact,
                decisionPoint: .invalidIdentifier,
                relativePath: "Packages/\(installedPackageID.rawValue)/generations/\(generation)",
                errorDomain: "HanlinScriptExtensionStoreError",
                errorCode: 2,
                summary: "Artifact generation must be greater than zero."
            ))
            throw HanlinScriptExtensionStoreError.invalidArtifactReference
        }
        let hash = Self.digest(data)
        let relativePath = "Packages/\(installedPackageID.rawValue)/generations/\(generation)/artifacts/\(hash)"
        let fileURL = root.appending(path: relativePath, directoryHint: .notDirectory)
        try rejectSymlinks(to: fileURL, phase: .storeArtifact)
        let dir = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try rejectSymlinks(to: fileURL, phase: .storeArtifact)
        if FileManager.default.fileExists(atPath: fileURL.path(percentEncoded: false)) {
            guard Self.digest(try Data(contentsOf: fileURL)) == hash else {
                Self.recordDiagnostic(.init(
                    phase: .storeArtifact,
                    decisionPoint: .digestMismatch,
                    relativePath: relativePath,
                    errorDomain: "HanlinScriptExtensionStoreError",
                    errorCode: 3,
                    summary: "Existing artifact file digest did not match expected SHA-256."
                ))
                throw HanlinScriptExtensionStoreError.integrityMismatch
            }
        } else {
            try data.write(to: fileURL, options: Self.writeOptions)
        }
        return (ref: relativePath, sha256: hash)
    }

    public func loadArtifact(ref: String) throws -> Data? {
        let parts = ref.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 6, parts[0] == "Packages", parts[2] == "generations", parts[4] == "artifacts",
              let generation = UInt64(parts[3]), generation > 0 else {
            Self.recordDiagnostic(.init(
                phase: .storeArtifact,
                decisionPoint: .lexicalBoundary,
                relativePath: ref,
                errorDomain: "HanlinScriptExtensionStoreError",
                errorCode: 4,
                summary: "Artifact reference format did not match canonical 6-segment layout."
            ))
            throw HanlinScriptExtensionStoreError.invalidArtifactReference
        }
        return try loadVerifiedArtifact(ref: ref, sha256: String(parts[5]), installedPackageID: HanlinInstalledPackageID(validating: String(parts[1])), generation: generation)
    }

    public func loadVerifiedArtifact(
        ref: String, sha256: String, installedPackageID: HanlinInstalledPackageID, generation: UInt64
    ) throws -> Data {
        guard generation > 0, Self.isDigest(sha256),
              ref == "Packages/\(installedPackageID.rawValue)/generations/\(generation)/artifacts/\(sha256)" else {
            Self.recordDiagnostic(.init(
                phase: .storeArtifact,
                decisionPoint: .invalidIdentifier,
                relativePath: ref,
                errorDomain: "HanlinScriptExtensionStoreError",
                errorCode: 5,
                summary: "Artifact reference did not match package/generation/digest authority."
            ))
            throw HanlinScriptExtensionStoreError.invalidArtifactReference
        }
        let url = root.appending(path: ref, directoryHint: .notDirectory)
        try rejectSymlinks(to: url, phase: .storeArtifact)
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else {
            throw HanlinScriptExtensionStoreError.artifactMissing
        }
        let values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
        guard values.isRegularFile == true else {
            Self.recordDiagnostic(.init(
                phase: .storeArtifact,
                decisionPoint: .nonDirectoryAncestor,
                relativePath: ref,
                failingComponentName: url.lastPathComponent,
                errorDomain: "HanlinScriptExtensionStoreError",
                errorCode: 6,
                summary: "Artifact leaf is not a regular file."
            ))
            throw HanlinScriptExtensionStoreError.invalidArtifactReference
        }
        guard (values.fileSize ?? Int.max) <= Self.maximumArtifactBytes else { throw HanlinScriptExtensionStoreError.artifactTooLarge }
        let data = try readArtifactWithoutSymlinks(ref: ref)
        guard data.count <= Self.maximumArtifactBytes else { throw HanlinScriptExtensionStoreError.artifactTooLarge }
        guard Self.digest(data) == sha256 else {
            Self.recordDiagnostic(.init(
                phase: .storeArtifact,
                decisionPoint: .digestMismatch,
                relativePath: ref,
                errorDomain: "HanlinScriptExtensionStoreError",
                errorCode: 7,
                summary: "Loaded artifact bytes failed SHA-256 verification."
            ))
            throw HanlinScriptExtensionStoreError.integrityMismatch
        }
        return data
    }

    private func readArtifactWithoutSymlinks(ref: String) throws -> Data {
#if canImport(Darwin)
        var descriptors: [Int32] = []
        defer { descriptors.reversed().forEach { _ = Darwin.close($0) } }
        let rootPath = Self.lexicalNormalizedPath(root)
        var descriptor = Darwin.open(rootPath, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
        guard descriptor >= 0 else {
            let err = errno
            if err == ENOENT {
                throw HanlinScriptExtensionStoreError.artifactMissing
            }
            Self.recordDiagnostic(.init(
                phase: .storeArtifact,
                decisionPoint: err == ELOOP ? .symlinkDetected : .openNoFollowFailed,
                relativePath: ref,
                failingComponentIndex: 0,
                failingComponentName: root.lastPathComponent,
                errorDomain: NSPOSIXErrorDomain,
                errorCode: Int(err),
                posixErrno: err,
                summary: "Failed to open root directory with O_NOFOLLOW."
            ))
            throw HanlinScriptExtensionStoreError.invalidArtifactReference
        }
        descriptors.append(descriptor)
        let parts = ref.split(separator: "/")
        for (index, part) in parts.enumerated() {
            let componentName = String(part)
            descriptor = openat(descriptor, componentName, O_RDONLY | O_NOFOLLOW | (index == parts.count - 1 ? 0 : O_DIRECTORY))
            guard descriptor >= 0 else {
                let err = errno
                Self.recordDiagnostic(.init(
                    phase: .storeArtifact,
                    decisionPoint: err == ELOOP ? .symlinkDetected : .openNoFollowFailed,
                    relativePath: ref,
                    failingComponentIndex: index + 1,
                    failingComponentName: componentName,
                    errorDomain: NSPOSIXErrorDomain,
                    errorCode: Int(err),
                    posixErrno: err,
                    summary: "Failed to open artifact path component with O_NOFOLLOW."
                ))
                throw HanlinScriptExtensionStoreError.invalidArtifactReference
            }
            descriptors.append(descriptor)
        }
        var info = stat()
        guard fstat(descriptor, &info) == 0, info.st_mode & S_IFMT == S_IFREG,
              info.st_size >= 0, info.st_size <= Self.maximumArtifactBytes else { throw HanlinScriptExtensionStoreError.artifactTooLarge }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: false)
        return try handle.read(upToCount: Self.maximumArtifactBytes + 1) ?? Data()
#else
        throw HanlinScriptExtensionStoreError.appGroupUnavailable
#endif
    }

    public func loadArtifact(
        installedPackageID: HanlinInstalledPackageID,
        generation: UInt64,
        hash: String
    ) throws -> Data? {
        let relativePath = "Packages/\(installedPackageID.rawValue)/generations/\(generation)/artifacts/\(hash)"
        return try loadArtifact(ref: relativePath)
    }

    public func materializeResources(_ files: [String: Data], identity: HanlinScriptExtensionIdentity) throws -> [String: URL] {
        guard files.count <= 128 else { throw HanlinScriptExtensionStoreError.artifactTooLarge }
        var result: [String: URL] = [:]
        for (name, data) in files {
            let parts = name.split(separator: "/", omittingEmptySubsequences: false)
            guard !name.contains("\\"), !name.contains(":"), !name.contains("\0"),
                  parts.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else {
                Self.recordDiagnostic(.init(
                    phase: .storeArtifact,
                    decisionPoint: .lexicalBoundary,
                    relativePath: name,
                    errorDomain: "HanlinScriptExtensionStoreError",
                    errorCode: 8,
                    summary: "Resource name failed relative path validation."
                ))
                throw HanlinScriptExtensionStoreError.invalidArtifactReference
            }
            let artifact = try storeArtifact(data: data, installedPackageID: identity.installedPackageID, generation: identity.generation)
            _ = try loadVerifiedArtifact(ref: artifact.ref, sha256: artifact.sha256,
                installedPackageID: identity.installedPackageID, generation: identity.generation)
            result[name] = root.appending(path: artifact.ref)
        }
        return result
    }

    public func enqueue(_ command: HanlinScriptResumeCommand) throws {
        try rejectSymlinks(to: commandRoot, phase: .actionPerform)
        try FileManager.default.createDirectory(at: commandRoot, withIntermediateDirectories: true)
        try rejectSymlinks(to: commandRoot, phase: .actionPerform)
        let existing = try FileManager.default.contentsOfDirectory(
            at: commandRoot,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ).filter { $0.pathExtension == "json" }
        guard existing.count < 128 else {
            throw HanlinScriptExtensionStoreError.snapshotTooLarge
        }
        let data = try Self.encoded(command)
        guard data.count <= 256 * 1_024 else {
            throw HanlinScriptExtensionStoreError.snapshotTooLarge
        }
        let targetURL = commandRoot.appending(path: "\(command.id.uuidString.lowercased()).json")
        try rejectSymlinks(to: targetURL, phase: .actionPerform)
        try data.write(
            to: targetURL,
            options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]
        )
    }

    public func pendingCommands(limit: Int = 64) throws -> [HanlinScriptResumeCommand] {
        try rejectSymlinks(to: commandRoot, phase: .actionPerform)
        guard FileManager.default.fileExists(atPath: commandRoot.path(percentEncoded: false)) else { return [] }
        let urls = try FileManager.default.contentsOfDirectory(
            at: commandRoot,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ).filter { $0.pathExtension == "json" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
        return try urls.prefix(max(0, limit)).map {
            try rejectSymlinks(to: $0, phase: .actionPerform)
            return try Self.decoded(HanlinScriptResumeCommand.self, from: Data(contentsOf: $0))
        }.sorted { $0.createdAt < $1.createdAt }
    }

    public func acknowledge(_ commandID: UUID) throws {
        let url = commandRoot.appending(path: "\(commandID.uuidString.lowercased()).json")
        try rejectSymlinks(to: url, phase: .actionPerform)
        if FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) {
            try FileManager.default.removeItem(at: url)
        }
    }

    private var snapshotV1URL: URL {
        root.appending(path: "snapshot-v1.json", directoryHint: .notDirectory)
    }

    private var snapshotV2URL: URL {
        root.appending(path: "snapshot-v2.json", directoryHint: .notDirectory)
    }

    private var commandRoot: URL {
        root.appending(path: "ResumeQueue", directoryHint: .isDirectory)
    }

    private var commitURL: URL { root.appending(path: "commit.json") }
    private var pendingURL: URL { root.appending(path: "pending.json") }
    private static var writeOptions: Data.WritingOptions { [.atomic, .completeFileProtectionUntilFirstUserAuthentication] }

    private static func isDigest(_ value: String) -> Bool {
        value.utf8.count == 64 && value.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    }

    private func revisionURL(_ hash: String) throws -> URL {
        guard Self.isDigest(hash) else { throw HanlinScriptExtensionStoreError.invalidCommit }
        return root.appending(path: "Revisions/\(hash).json")
    }

    private func writeRevision(_ data: Data) throws {
        let url = try revisionURL(Self.digest(data))
        try rejectSymlinks(to: url, phase: .storeSave)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try rejectSymlinks(to: url, phase: .storeSave)
        if !FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) { try data.write(to: url, options: Self.writeOptions) }
    }

    private func checkedRevision(_ hash: String) throws -> Data {
        let url = try revisionURL(hash)
        try rejectSymlinks(to: url, phase: .storeLoad)
        let data = try Data(contentsOf: url)
        guard data.count <= Self.maximumSnapshotBytes, Self.digest(data) == hash else { throw HanlinScriptExtensionStoreError.integrityMismatch }
        return data
    }

    private func optionalData(at url: URL) throws -> Data? {
        try rejectSymlinks(to: url, phase: .storeLoad)
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else { return nil }
        let data = try Data(contentsOf: url)
        guard data.count <= Self.maximumSnapshotBytes else { throw HanlinScriptExtensionStoreError.snapshotTooLarge }
        return data
    }

    private func optionalDecode<T: Decodable>(_ type: T.Type, at url: URL) throws -> T? {
        try optionalData(at: url).map { try Self.decoded(type, from: $0) }
    }

    /// Canonicalizes the trusted parent container above the managed `ScriptingExtensions` root
    /// without resolving a symlink on the `ScriptingExtensions` leaf itself.
    private static func canonicalManagedRoot(for candidateRoot: URL) -> URL {
        let leafName = candidateRoot.lastPathComponent
        guard !leafName.isEmpty, leafName != "/" else {
            return URL(filePath: lexicalNormalizedPath(candidateRoot), directoryHint: .isDirectory)
        }
        let parentURL = candidateRoot.deletingLastPathComponent()
        let parentRawPath = parentURL.path(percentEncoded: false)
        let resolvedParentPath: String
        if FileManager.default.fileExists(atPath: parentRawPath) {
            resolvedParentPath = lexicalNormalizedPath(parentURL.resolvingSymlinksInPath())
        } else {
            resolvedParentPath = lexicalNormalizedPath(parentURL)
        }
        return URL(filePath: resolvedParentPath, directoryHint: .isDirectory)
            .appending(path: leafName, directoryHint: .isDirectory)
    }

    /// Normalizes a filesystem path lexically and canonicalizes Darwin's `/var` and `/tmp`
    /// system symlink prefixes consistently regardless of whether the target leaf currently exists on disk.
    private static func lexicalNormalizedPath(_ url: URL) -> String {
        var raw = url.path(percentEncoded: false)
        while raw.count > 1 && raw.hasSuffix("/") {
            raw.removeLast()
        }
#if canImport(Darwin)
        if raw == "/var" || raw.hasPrefix("/var/") {
            raw = "/private" + raw
        } else if raw == "/tmp" || raw.hasPrefix("/tmp/") {
            raw = "/private" + raw
        } else if raw == "/etc" || raw.hasPrefix("/etc/") {
            raw = "/private" + raw
        }
#endif
        return raw
    }

    private func rejectSymlinks(
        to url: URL,
        phase: HanlinWidgetStorageDiagnostic.Phase = .storeLoad
    ) throws {
        let rawTarget = url.path(percentEncoded: false)
        let rawSegments = rawTarget.split(separator: "/", omittingEmptySubsequences: true)
        if rawTarget.contains("\0") || rawTarget.contains("\\") || rawSegments.contains(".") || rawSegments.contains("..") {
            Self.recordDiagnostic(.init(
                phase: phase,
                decisionPoint: .lexicalBoundary,
                relativePath: HanlinWidgetStorageDiagnostic.sanitizeRelativePath(rawTarget),
                errorDomain: "HanlinScriptExtensionStoreError",
                errorCode: 10,
                summary: "Target path contained prohibited traversal or control segments."
            ))
            throw HanlinScriptExtensionStoreError.invalidArtifactReference
        }

        let basePath = Self.lexicalNormalizedPath(root)
        let targetPath = Self.lexicalNormalizedPath(url)
        let isRootSelf = (targetPath == basePath)
        guard isRootSelf || targetPath.hasPrefix(basePath + "/") else {
            Self.recordDiagnostic(.init(
                phase: phase,
                decisionPoint: .lexicalBoundary,
                relativePath: HanlinWidgetStorageDiagnostic.sanitizeRelativePath(targetPath),
                errorDomain: "HanlinScriptExtensionStoreError",
                errorCode: 11,
                summary: "Target path is outside the canonical ScriptingExtensions store root."
            ))
            throw HanlinScriptExtensionStoreError.invalidArtifactReference
        }

        let relativePath: String
        let components: [String]
        if isRootSelf {
            relativePath = "."
            components = []
        } else {
            relativePath = String(targetPath.dropFirst(basePath.count + 1))
            components = relativePath.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
            guard !components.isEmpty,
                  components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." && !$0.contains("\0") && !$0.contains("\\") }) else {
                Self.recordDiagnostic(.init(
                    phase: phase,
                    decisionPoint: .lexicalBoundary,
                    relativePath: relativePath,
                    errorDomain: "HanlinScriptExtensionStoreError",
                    errorCode: 12,
                    summary: "Relative path under ScriptingExtensions contained invalid component."
                ))
                throw HanlinScriptExtensionStoreError.invalidArtifactReference
            }
        }

#if canImport(Darwin)
        var currentPath = basePath
        for index in 0...components.count {
            let componentName: String
            if index == 0 {
                componentName = root.lastPathComponent
            } else {
                componentName = components[index - 1]
                currentPath += "/" + componentName
            }
            var info = stat()
            if Darwin.lstat(currentPath, &info) == 0 {
                let mode = info.st_mode & S_IFMT
                if mode == S_IFLNK {
                    Self.recordDiagnostic(.init(
                        phase: phase,
                        decisionPoint: .symlinkDetected,
                        relativePath: relativePath,
                        failingComponentIndex: index,
                        failingComponentName: componentName,
                        errorDomain: "HanlinScriptExtensionStoreError",
                        errorCode: 13,
                        summary: "Symbolic link rejected inside managed ScriptingExtensions tree."
                    ))
                    throw HanlinScriptExtensionStoreError.invalidArtifactReference
                }
                if index < components.count && mode != S_IFDIR {
                    Self.recordDiagnostic(.init(
                        phase: phase,
                        decisionPoint: .nonDirectoryAncestor,
                        relativePath: relativePath,
                        failingComponentIndex: index,
                        failingComponentName: componentName,
                        errorDomain: "HanlinScriptExtensionStoreError",
                        errorCode: 14,
                        summary: "Ancestor component inside ScriptingExtensions is not a directory."
                    ))
                    throw HanlinScriptExtensionStoreError.invalidArtifactReference
                }
            } else {
                let err = errno
                if err == ENOENT {
                    // A not-yet-created file or directory is allowed; lstat only returns
                    // ENOENT when the component itself does not exist (dangling symlinks
                    // return 0 with S_IFLNK and are rejected above).
                    continue
                }
                if err == ENOTDIR || err == ELOOP {
                    Self.recordDiagnostic(.init(
                        phase: phase,
                        decisionPoint: err == ELOOP ? .symlinkDetected : .nonDirectoryAncestor,
                        relativePath: relativePath,
                        failingComponentIndex: index,
                        failingComponentName: componentName,
                        errorDomain: NSPOSIXErrorDomain,
                        errorCode: Int(err),
                        posixErrno: err,
                        summary: "Path traversal failed due to non-directory or symlink ancestor."
                    ))
                    throw HanlinScriptExtensionStoreError.invalidArtifactReference
                }
                Self.recordDiagnostic(.init(
                    phase: phase,
                    decisionPoint: .filesystemError,
                    relativePath: relativePath,
                    failingComponentIndex: index,
                    failingComponentName: componentName,
                    errorDomain: NSPOSIXErrorDomain,
                    errorCode: Int(err),
                    posixErrno: err,
                    summary: "Filesystem lstat error while validating ScriptingExtensions path."
                ))
                throw NSError(domain: NSPOSIXErrorDomain, code: Int(err))
            }
        }
#endif
    }

    private func withLock<T>(_ operation: () throws -> T) throws -> T {
        try rejectSymlinks(to: root, phase: .storeLoad)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try rejectSymlinks(to: root, phase: .storeLoad)
#if canImport(Darwin)
        let lockURL = root.appending(path: ".transaction.lock", directoryHint: .notDirectory)
        try rejectSymlinks(to: lockURL, phase: .storeLoad)
        let lockPath = Self.lexicalNormalizedPath(lockURL)
        let descriptor = Darwin.open(lockPath, O_CREAT | O_RDWR | O_NOFOLLOW, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else {
            let err = errno
            if err == ELOOP {
                Self.recordDiagnostic(.init(
                    phase: .storeLoad,
                    decisionPoint: .symlinkDetected,
                    relativePath: ".transaction.lock",
                    failingComponentIndex: 1,
                    failingComponentName: ".transaction.lock",
                    errorDomain: NSPOSIXErrorDomain,
                    errorCode: Int(err),
                    posixErrno: err,
                    summary: "Transaction lock file is a symbolic link."
                ))
                throw HanlinScriptExtensionStoreError.invalidArtifactReference
            }
            Self.recordDiagnostic(.init(
                phase: .storeLoad,
                decisionPoint: .openNoFollowFailed,
                relativePath: ".transaction.lock",
                failingComponentIndex: 1,
                failingComponentName: ".transaction.lock",
                errorDomain: NSPOSIXErrorDomain,
                errorCode: Int(err),
                posixErrno: err,
                summary: "Failed to open transaction lock file."
            ))
            throw HanlinScriptExtensionStoreError.storageBusy
        }
        defer { Darwin.close(descriptor) }
        let deadline = ContinuousClock.now.advanced(by: .seconds(10))
        while flock(descriptor, LOCK_EX | LOCK_NB) != 0 {
            guard errno == EWOULDBLOCK, ContinuousClock.now < deadline else { throw HanlinScriptExtensionStoreError.storageBusy }
            usleep(10_000)
        }
        defer { flock(descriptor, LOCK_UN) }
        return try operation()
#else
        throw HanlinScriptExtensionStoreError.appGroupUnavailable
#endif
    }

    private static func encoded<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(value)
    }

    private static func decoded<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return try decoder.decode(type, from: data)
    }

    private static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
