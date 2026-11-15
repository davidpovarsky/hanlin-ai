import Foundation
import HanlinPlatformContracts

public enum SplitMigrationError: Error, Equatable {
    case unsupportedVersion, unsafePath, duplicateDestination, overlappingStores
    case sourceChanged, destinationConflict, snapshotMismatch, rollbackConflict, interrupted
}

/// Synthetic/copy inventory only. Original application stores are never opened here.
/// Snapshots hold exact bytes, so grant/identity records are copied without reinterpretation.
public struct SplitStoreSnapshot: Codable, Equatable, Sendable {
    public let storeID: String
    public let revision: UInt64
    public let files: [String: Data]
    public init(storeID: String, revision: UInt64, files: [String: Data]) throws {
        guard !storeID.isEmpty else { throw SplitMigrationError.snapshotMismatch }
        for path in files.keys { try SplitMigrationPlan.validate(path) }
        self.storeID = storeID; self.revision = revision; self.files = files
    }
}

public struct SplitMigrationPlan: Codable, Equatable, Sendable {
    public let version: Int
    public let id: HanlinMigrationID
    public let source: SplitStoreSnapshot
    public let destination: SplitStoreSnapshot
    public let copies: [String: String]

    public init(id: HanlinMigrationID, source: SplitStoreSnapshot,
                destination: SplitStoreSnapshot, copies: [String: String]) throws {
        _ = try SplitStoreSnapshot(storeID: source.storeID, revision: source.revision, files: source.files)
        _ = try SplitStoreSnapshot(storeID: destination.storeID, revision: destination.revision, files: destination.files)
        guard source.storeID != destination.storeID else { throw SplitMigrationError.overlappingStores }
        guard Set(copies.values).count == copies.count else { throw SplitMigrationError.duplicateDestination }
        for (from, to) in copies {
            try Self.validate(from); try Self.validate(to)
            guard let bytes = source.files[from] else { throw SplitMigrationError.sourceChanged }
            if let existing = destination.files[to], existing != bytes { throw SplitMigrationError.destinationConflict }
        }
        version = 1; self.id = id; self.source = source; self.destination = destination; self.copies = copies
    }
    public static func validate(_ path: String) throws {
        guard !path.isEmpty, path.utf8.count <= 1024, !path.contains("\\"), !path.contains(":"),
              !path.contains("%"), !path.unicodeScalars.contains(where: { $0.value < 32 }),
              !path.split(separator: "/", omittingEmptySubsequences: false).contains(where: {
                  $0.isEmpty || $0 == "." || $0 == ".." || $0.hasSuffix(".") || $0.hasSuffix(" ")
              }) else { throw SplitMigrationError.unsafePath }
    }
    /// Pure dry-run: verifies exact preconditions and returns the expected copy, preserving the source.
    public func dryRun(source currentSource: SplitStoreSnapshot,
                       destination currentDestination: SplitStoreSnapshot) throws -> SplitStoreSnapshot {
        guard version == 1 else { throw SplitMigrationError.unsupportedVersion }
        // Revalidate decoded plans too: Codable is serialization, not trust.
        _ = try Self(id: id, source: source, destination: destination, copies: copies)
        guard currentSource == source else { throw SplitMigrationError.sourceChanged }
        guard currentDestination == destination else { throw SplitMigrationError.destinationConflict }
        var files = destination.files
        for (from, to) in copies { files[to] = source.files[from] }
        guard destination.revision < UInt64.max else { throw SplitMigrationError.snapshotMismatch }
        return try SplitStoreSnapshot(storeID: destination.storeID, revision: destination.revision + 1, files: files)
    }
}

/// Bounded copy executor for fixture snapshots, not a production filesystem/data migrator.
/// Keep the original plan (backup) and journal together to resume or roll back partial output.
public struct SplitMigrationJournal: Codable, Equatable, Sendable {
    public let plan: SplitMigrationPlan
    public private(set) var output: SplitStoreSnapshot
    public private(set) var copied: Set<String> = []
    public private(set) var complete = false
    public init(plan: SplitMigrationPlan) throws {
        _ = try plan.dryRun(source: plan.source, destination: plan.destination)
        self.plan = plan; output = plan.destination
    }
    public mutating func apply(source: SplitStoreSnapshot, current: SplitStoreSnapshot,
                               interruptAfter: Int? = nil) throws -> SplitStoreSnapshot {
        try validateState()
        guard current == output else { throw SplitMigrationError.destinationConflict }
        let expected = try plan.dryRun(source: source, destination: plan.destination)
        guard !complete else { return output }
        var performed = 0
        for from in plan.copies.keys.sorted() {
            guard let to = plan.copies[from], !copied.contains(to) else { continue }
            if let limit = interruptAfter, performed >= limit { throw SplitMigrationError.interrupted }
            var files = output.files; files[to] = source.files[from]
            output = try SplitStoreSnapshot(storeID: output.storeID, revision: output.revision, files: files)
            copied.insert(to); performed += 1
        }
        output = expected; complete = true
        return output
    }
    public mutating func rollback(current: SplitStoreSnapshot) throws -> SplitStoreSnapshot {
        try validateState()
        guard current == output else { throw SplitMigrationError.rollbackConflict }
        output = plan.destination; copied = []; complete = false
        return output
    }

    private func validateState() throws {
        _ = try plan.dryRun(source: plan.source, destination: plan.destination)
        guard copied.isSubset(of: Set(plan.copies.values)),
              !complete || copied == Set(plan.copies.values) else { throw SplitMigrationError.snapshotMismatch }
        var files = plan.destination.files
        for (from, to) in plan.copies where copied.contains(to) { files[to] = plan.source.files[from] }
        let expected = try SplitStoreSnapshot(storeID: plan.destination.storeID,
            revision: plan.destination.revision + (complete ? 1 : 0), files: files)
        guard expected == output else { throw SplitMigrationError.snapshotMismatch }
    }
}
