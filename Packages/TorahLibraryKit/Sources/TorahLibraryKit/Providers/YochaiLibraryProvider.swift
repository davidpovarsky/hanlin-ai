import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct YochaiConfig: Sendable {
    public let endpointURL: URL
    public let apiKey: String?

    public init(
        endpointURL: URL = URL(string: "https://yochai-kg-gateway-production.up.railway.app/mcp")!,
        apiKey: String? = nil
    ) {
        self.endpointURL = endpointURL
        self.apiKey = apiKey
    }
}

public final class YochaiLibraryProvider: TorahLibraryProvider, @unchecked Sendable {
    public let providerID = "yochai"
    public let displayName = "Yochai Knowledge Graph"
    public let config: YochaiConfig

    public init(config: YochaiConfig = YochaiConfig()) {
        self.config = config
    }

    public var isConfigured: Bool {
        config.apiKey != nil && !(config.apiKey?.isEmpty ?? true)
    }

    public func search(query: String, limit: Int = 5) async throws -> [TorahSearchHit] {
        guard isConfigured else {
            throw ITorahSharedStorageError.directoryNotFound("Yochai API key is not configured. Enrichment via Yochai is unavailable.")
        }
        return []
    }

    public func getSection(locator: SourceLocator) async throws -> StudySource? {
        guard isConfigured else { return nil }
        return nil
    }

    public func getLinks(locator: SourceLocator, type: String? = nil) async throws -> [TorahLinkedSource] {
        guard isConfigured else { return [] }
        return []
    }

    public func getTopics(locator: SourceLocator) async throws -> [TorahLinkedTopic] {
        guard isConfigured else { return [] }
        return []
    }
}
