import Foundation

public struct NativeAppSefariaSearchService: Sendable {
    public let client: NativeAppSefariaClient

    public init(client: NativeAppSefariaClient = NativeAppSefariaClient()) {
        self.client = client
    }

    public func search(query: String, limit: Int = 10) async throws -> [NativeAppSefariaSearchResult] {
        try await client.search(query: query, limit: limit)
    }
}

public struct NativeAppSefariaSourceService: Sendable {
    public let client: NativeAppSefariaClient

    public init(client: NativeAppSefariaClient = NativeAppSefariaClient()) {
        self.client = client
    }

    public func source(ref: String) async throws -> NativeAppSefariaSource {
        try await client.source(ref: ref)
    }
}
