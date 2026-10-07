import Foundation

public protocol TorahLibraryProvider: Sendable {
    var providerID: String { get }
    var displayName: String { get }

    func search(query: String, limit: Int) async throws -> [TorahSearchHit]
    func getSection(locator: SourceLocator) async throws -> StudySource?
    func getLinks(locator: SourceLocator, type: String?) async throws -> [TorahLinkedSource]
    func getTopics(locator: SourceLocator) async throws -> [TorahLinkedTopic]
}

public final class MockTorahLibraryProvider: TorahLibraryProvider, TorahLibrarySearchEngine, @unchecked Sendable {
    public let providerID: String
    public let displayName: String
    private var sources: [String: StudySource] = [:]
    private var titles: [String: String] = [:]

    public init(providerID: String = "mock_otzaria", displayName: String = "Otzaria (Mock)") {
        self.providerID = providerID
        self.displayName = displayName
    }

    public func register(source: StudySource, title: String) {
        sources[source.locator.persistenceKey] = source
        titles[source.locator.persistenceKey] = title
    }

    public func search(query: String, limit: Int) async throws -> [TorahSearchHit] {
        searchSync(anchors: [query], limit: limit)
    }

    public func search(anchors: [String], limit: Int) async throws -> [TorahSearchHit] {
        searchSync(anchors: anchors, limit: limit)
    }

    private func searchSync(anchors: [String], limit: Int) -> [TorahSearchHit] {
        var hits: [TorahSearchHit] = []
        for (key, source) in sources {
            let normalizedSrc = HebrewTextNormalizer.stripNiqqud(from: source.primaryText)
            for anchor in anchors {
                let normalizedAnchor = HebrewTextNormalizer.stripNiqqud(from: anchor)
                if normalizedSrc.contains(normalizedAnchor) {
                    hits.append(
                        TorahSearchHit(
                            locator: source.locator,
                            workTitle: titles[key] ?? source.locator.workKey,
                            textSnippet: source.primaryText,
                            fullText: source.primaryText,
                            providerScore: 1.0
                        )
                    )
                    break
                }
            }
            if hits.count >= limit { break }
        }
        return hits
    }

    public func fetchSection(locator: SourceLocator) async throws -> String? {
        sources[locator.persistenceKey]?.primaryText
    }

    public func getSection(locator: SourceLocator) async throws -> StudySource? {
        sources[locator.persistenceKey]
    }

    public func getLinks(locator: SourceLocator, type: String?) async throws -> [TorahLinkedSource] {
        sources[locator.persistenceKey]?.links ?? []
    }

    public func getTopics(locator: SourceLocator) async throws -> [TorahLinkedTopic] {
        sources[locator.persistenceKey]?.topics ?? []
    }
}
