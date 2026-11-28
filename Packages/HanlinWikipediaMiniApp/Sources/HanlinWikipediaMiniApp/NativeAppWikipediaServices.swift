import Foundation

public struct NativeAppWikipediaSearchService: Sendable {
    public let client: NativeAppWikipediaClient

    public init(client: NativeAppWikipediaClient = NativeAppWikipediaClient()) {
        self.client = client
    }

    public func search(query: String, limit: Int = 10, languageCode: String) async throws -> [NativeAppWikipediaSearchResult] {
        try await client.search(query: query, limit: limit, languageCode: languageCode)
    }
}

public struct NativeAppWikipediaSummaryService: Sendable {
    public let client: NativeAppWikipediaClient

    public init(client: NativeAppWikipediaClient = NativeAppWikipediaClient()) {
        self.client = client
    }

    public func summary(title: String, languageCode: String) async throws -> NativeAppWikipediaSummary {
        try await client.summary(title: title, languageCode: languageCode)
    }
}
