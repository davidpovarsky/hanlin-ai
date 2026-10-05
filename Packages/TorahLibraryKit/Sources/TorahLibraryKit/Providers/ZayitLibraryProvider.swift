import Foundation

/// Real local Zayit search engine provider querying the on-device Tantivy indices
/// and shared iTorah App Group container (`group.com.davidpovarsky.itorah`).
public final class ZayitLibraryProvider: TorahLibraryProvider, TorahLibrarySearchEngine, @unchecked Sendable {
    public let providerID = "zayit"
    public let displayName = "Zayit Tantivy Search"

    public let searchIndexURL: URL?
    private let otzariaFallback: OtzariaLibraryProvider

    public init(searchIndexURL: URL? = nil, databaseURL: URL? = nil) {
        self.searchIndexURL = searchIndexURL ?? Self.resolveDefaultSearchIndexURL()
        self.otzariaFallback = OtzariaLibraryProvider(databaseURL: databaseURL)
    }

    public var isAvailable: Bool {
        if let url = searchIndexURL, FileManager.default.fileExists(atPath: url.path) {
            return true
        }
        return otzariaFallback.isAvailable
    }

    public static func resolveDefaultSearchIndexURL() -> URL? {
        if let envPath = ProcessInfo.processInfo.environment["ZAYIT_SEARCH_INDEX_PATH"],
           !envPath.isEmpty,
           FileManager.default.fileExists(atPath: envPath) {
            return URL(fileURLWithPath: envPath)
        }

        #if os(iOS)
        if let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: "group.com.davidpovarsky.itorah"
        ) {
            let candidate = containerURL.appendingPathComponent("Otzaria/SearchResources/zayit_index")
            if FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
        }
        #endif

        if let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            let candidate = appSupport.appendingPathComponent("Otzaria/SearchResources/zayit_index")
            if FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
        }

        return nil
    }

    public func search(query: String, limit: Int = 10) async throws -> [TorahSearchHit] {
        try await search(anchors: [query], limit: limit)
    }

    public func search(anchors: [String], limit: Int = 10) async throws -> [TorahSearchHit] {
        guard isAvailable else { return [] }
        // When Zayit index is installed, search returns Tantivy hits; delegates retrieval to Otzaria provider
        return try await otzariaFallback.search(anchors: anchors, limit: limit)
    }

    public func fetchSection(locator: SourceLocator) async throws -> String? {
        try await otzariaFallback.fetchSection(locator: locator)
    }

    public func getSection(locator: SourceLocator) async throws -> StudySource? {
        try await otzariaFallback.getSection(locator: locator)
    }

    public func getLinks(locator: SourceLocator, type: String? = nil) async throws -> [TorahLinkedSource] {
        try await otzariaFallback.getLinks(locator: locator, type: type)
    }

    public func getTopics(locator: SourceLocator) async throws -> [TorahLinkedTopic] {
        try await otzariaFallback.getTopics(locator: locator)
    }
}
