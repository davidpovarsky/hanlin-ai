import Foundation

/// Test/dry-run adapter only. The explicit marker, fixed filenames and symlink
/// checks prevent applying a fixture command to an arbitrary application store.
/// This is not an AppGroup, SwiftData, Keychain or production migration adapter.
public struct SplitFixtureStore {
    public enum Slot: String { case source, destination, journal }
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
    private func url(_ slot: Slot) throws -> URL {
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
        try JSONDecoder().decode(type, from: Data(contentsOf: url(slot)))
    }
}
