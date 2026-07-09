import Foundation

struct SefariaSearchService {
    let client: SefariaClient

    func search(query: String, limit: Int = 5) async throws -> [NativeAppSefariaSearchResult] {
        try await client.search(query: query, limit: limit)
    }
}

struct NativeAppSefariaSourceService {
    let client: SefariaClient

    func source(ref: String) async throws -> NativeAppSefariaSource {
        try await client.source(ref: ref)
    }
}
