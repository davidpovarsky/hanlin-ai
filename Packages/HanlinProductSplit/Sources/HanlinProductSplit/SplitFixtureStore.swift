import Foundation

/// Test/dry-run adapter only. The explicit marker, fixed filenames and symlink
/// checks prevent applying a fixture command to an arbitrary application store.
/// This is not an AppGroup, SwiftData, Keychain or production migration adapter.
public struct SplitFixtureStore: Sendable {
    public enum Slot: String { case source, destination, journal, receiver, migrationIntent, effect, delivery }
    public static let marker = "synthetic-fixture-only-v1\n"
    private let root: URL

    public init(root: URL) throws {
        let normalized = root.standardizedFileURL
        guard normalized.isFileURL,
              normalized.resolvingSymlinksInPath().pathComponents == normalized.pathComponents,
              try Data(contentsOf: normalized.appendingPathComponent(".hanlin-product-split-fixture")) == Data(Self.marker.utf8)
        else { throw SplitMigrationError.unsafePath }
        self.root = normalized
    }
    func url(_ slot: Slot) throws -> URL {
        guard root.resolvingSymlinksInPath().pathComponents == root.pathComponents,
              try Data(contentsOf: root.appendingPathComponent(".hanlin-product-split-fixture")) == Data(Self.marker.utf8)
        else { throw SplitMigrationError.unsafePath }
        let result = root.appendingPathComponent(slot.rawValue + ".json")
        guard result.resolvingSymlinksInPath().pathComponents == result.pathComponents else { throw SplitMigrationError.unsafePath }
        return result
    }
    public func write<T: Encodable>(_ value: T, to slot: Slot) throws {
        let data = try JSONEncoder().encode(value)
        try data.write(to: url(slot), options: .atomic)
    }
    public func read<T: Decodable>(_ type: T.Type, from slot: Slot) throws -> T {
        let attributes = try FileManager.default.attributesOfItem(atPath: url(slot).path)
        guard let size = attributes[.size] as? NSNumber, size.intValue <= 16_777_216
        else { throw SplitDurabilityError.corruptState }
        return try JSONDecoder().decode(type, from: Data(contentsOf: url(slot)))
    }

    /// Exclusive create is shared by separate fixture-store instances/processes.
    /// A crash while holding this lock leaves it busy: never steal a stale lock
    /// and accidentally overlap a writer. Production locking is not implemented.
    func locked<T>(_ operation: () throws -> T) throws -> T {
        _ = try url(.source)
        let lock = root.appendingPathComponent(".split-fixture-write-lock")
        let token = Data(UUID().uuidString.utf8)
        do { try token.write(to: lock, options: .withoutOverwriting) }
        catch {
            // The winner may release the lock between exclusive-create failure
            // and this catch. Classify the original error, not only a racy stat.
            let failure = error as NSError
            if (failure.domain == NSCocoaErrorDomain && failure.code == CocoaError.Code.fileWriteFileExists.rawValue)
                || FileManager.default.fileExists(atPath: lock.path) { throw SplitDurabilityError.busy }
            throw error
        }
        defer {
            if (try? Data(contentsOf: lock)) == token { try? FileManager.default.removeItem(at: lock) }
        }
        return try operation()
    }
}
