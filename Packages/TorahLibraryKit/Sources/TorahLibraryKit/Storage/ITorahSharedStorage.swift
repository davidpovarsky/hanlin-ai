import Foundation

public enum ITorahSharedStorageError: LocalizedError, Sendable {
    case appGroupUnavailable(String)
    case directoryNotFound(String)
    case generationMismatch(expected: String, actual: String)

    public var errorDescription: String? {
        switch self {
        case .appGroupUnavailable(let id):
            return "App Group '\(id)' container could not be located. Ensure proper entitlements."
        case .directoryNotFound(let path):
            return "Required storage directory not found: \(path)"
        case .generationMismatch(let exp, let act):
            return "Corpus generation mismatch: expected \(exp), found \(act)."
        }
    }
}

public struct ITorahCorpusManifest: Codable, Hashable, Sendable {
    public let corpusID: String
    public let generation: String
    public let version: String
    public let totalBooks: Int
    public let lastUpdated: Date

    public init(corpusID: String, generation: String, version: String, totalBooks: Int, lastUpdated: Date = Date()) {
        self.corpusID = corpusID
        self.generation = generation
        self.version = version
        self.totalBooks = totalBooks
        self.lastUpdated = lastUpdated
    }
}

public enum ITorahSharedStorage: Sendable {
    public static let appGroupIdentifier = "group.com.davidpovarsky.itorah"
    public static let otzariaNamespace = "Otzaria"
    public static let zayitNamespace = "Zayit"

    private final class StorageOverrideBox: @unchecked Sendable {
        private let lock = NSLock()
        private var _root: URL?

        var root: URL? {
            get {
                lock.lock()
                defer { lock.unlock() }
                return _root
            }
            set {
                lock.lock()
                defer { lock.unlock() }
                _root = newValue
            }
        }
    }

    private static let overrideBox = StorageOverrideBox()

    /// Custom storage root for testing or simulation.
    public static var customRootURL: URL? {
        get { overrideBox.root }
        set { overrideBox.root = newValue }
    }

    /// Resolves the canonical shared container root URL.
    public static func containerURL() throws -> URL {
        if let custom = customRootURL {
            return custom
        }
        #if os(iOS) || os(macOS) || os(watchOS) || os(tvOS) || os(visionOS)
        if let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier) {
            return url
        }
        #endif
        throw ITorahSharedStorageError.appGroupUnavailable(appGroupIdentifier)
    }

    /// Resolves the Otzaria directory inside the container.
    public static func otzariaURL() throws -> URL {
        let base = try containerURL()
        return base.appendingPathComponent(otzariaNamespace, isDirectory: true)
    }

    /// Resolves the canonical database path (`seforim.db`).
    public static func seforimDatabaseURL() throws -> URL {
        let otzaria = try otzariaURL()
        return otzaria.appendingPathComponent("seforim.db", isDirectory: false)
    }

    /// Reads the active corpus manifest if present.
    public static func readActiveManifest() throws -> ITorahCorpusManifest? {
        let manifestURL = try otzariaURL().appendingPathComponent("manifest.json", isDirectory: false)
        guard FileManager.default.fileExists(atPath: manifestURL.path) else {
            return nil
        }
        let data = try Data(contentsOf: manifestURL)
        return try JSONDecoder().decode(ITorahCorpusManifest.self, from: data)
    }
}
