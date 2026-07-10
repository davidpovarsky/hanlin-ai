import Foundation

struct NativeAppWikipediaSearchService {
    let client: NativeAppWikipediaClient

    func search(query: String, limit: Int = 10, languageCode: String) async throws -> [NativeAppWikipediaSearchResult] {
        try await client.search(query: query, limit: limit, languageCode: languageCode)
    }
}

struct NativeAppWikipediaSummaryService {
    let client: NativeAppWikipediaClient

    func summary(title: String, languageCode: String) async throws -> NativeAppWikipediaSummary {
        try await client.summary(title: title, languageCode: languageCode)
    }
}
