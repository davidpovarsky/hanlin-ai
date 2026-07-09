import Foundation

struct WikipediaSearchService {
    let client: WikipediaClient

    func search(query: String, limit: Int = 5) async throws -> [NativeAppWikipediaSearchResult] {
        try await client.search(query: query, limit: limit)
    }
}

struct NativeAppWikipediaSummaryService {
    let client: WikipediaClient

    func summary(title: String) async throws -> NativeAppWikipediaSummary {
        try await client.summary(title: title)
    }
}
