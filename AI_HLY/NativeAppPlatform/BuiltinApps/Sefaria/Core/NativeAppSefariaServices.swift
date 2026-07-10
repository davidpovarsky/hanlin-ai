import Foundation

struct NativeAppSefariaSearchService {
    let client: NativeAppSefariaClient

    func search(query: String, limit: Int = 10) async throws -> [NativeAppSefariaSearchResult] {
        try await client.search(query: query, limit: limit)
    }
}

struct NativeAppSefariaSourceService {
    let client: NativeAppSefariaClient

    func source(ref: String) async throws -> NativeAppSefariaSource {
        try await client.source(ref: ref)
    }
}
