import Foundation

struct WikipediaSearchService {
    let client: WikipediaClient

    func search(query: String, limit: Int = 5) async throws -> [WikipediaSearchResult] {
        try await client.search(query: query, limit: limit)
    }
}

struct WikipediaSummaryService {
    let client: WikipediaClient

    func summary(title: String) async throws -> WikipediaSummary {
        try await client.summary(title: title)
    }
}
