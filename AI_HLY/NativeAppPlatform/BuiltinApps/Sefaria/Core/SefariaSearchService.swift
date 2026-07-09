import Foundation

struct SefariaSearchService {
    let client: SefariaClient

    func search(query: String, limit: Int = 5) async throws -> [SefariaSearchResult] {
        try await client.search(query: query, limit: limit)
    }
}

struct SefariaSourceService {
    let client: SefariaClient

    func source(ref: String) async throws -> SefariaSource {
        try await client.source(ref: ref)
    }
}
