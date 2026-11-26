import CryptoKit
import Foundation

/// Controls Hanlin's explicit cache requests. A provider may still use its own
/// implicit prompt cache when no explicit controls are sent.
public struct HanlinPromptCachePolicy: Codable, Hashable, Sendable {
    public enum Mode: String, Codable, Hashable, Sendable {
        /// Send no Hanlin cache controls; keep the provider's own defaults.
        case providerDefault
        /// Enable supported native provider caching without creating paid resources.
        case automatic
        /// Omit Hanlin cache controls and breakpoints. This is not a remote-cache purge.
        case noExplicitCaching
    }

    public enum AnthropicTTL: String, Codable, Hashable, Sendable {
        case fiveMinutes = "5m"
        case oneHour = "1h"
    }

    public struct OpenAI: Codable, Hashable, Sendable {
        public enum Mode: String, Codable, Hashable, Sendable {
            case implicit
            case explicit
        }
        public enum TTL: String, Codable, Hashable, Sendable {
            case thirtyMinutes = "30m"
            case twelveHours = "12h"
        }
        public enum Retention: String, Codable, Hashable, Sendable {
            case inMemory = "in_memory"
            case twentyFourHours = "24h"
        }

        public let mode: Mode?
        public let ttl: TTL?
        /// Legacy-model retention; modern minimum TTL and retention are separate controls.
        public let retention: Retention?
        /// Explicit diagnostic request, supported by the Responses API.
        public let comparisonResponseID: String?

        public init(
            mode: Mode? = nil,
            ttl: TTL? = nil,
            retention: Retention? = nil,
            comparisonResponseID: String? = nil
        ) {
            self.mode = mode
            self.ttl = ttl
            self.retention = retention
            self.comparisonResponseID = comparisonResponseID
        }

        var hasModernOptions: Bool {
            mode != nil || ttl != nil || comparisonResponseID != nil
        }
    }

    public let mode: Mode
    public let openAI: OpenAI?
    public let anthropicTTL: AnthropicTTL
    /// Optional, explicitly managed content-only resource. Never created automatically.
    /// Generation must not also supply system instructions or tools.
    public let googleCachedContent: HanlinGoogleCachedContentReference?

    public init(
        mode: Mode = .automatic,
        openAI: OpenAI? = nil,
        anthropicTTL: AnthropicTTL = .fiveMinutes,
        googleCachedContent: HanlinGoogleCachedContentReference? = nil
    ) {
        self.mode = mode
        self.openAI = openAI
        self.anthropicTTL = anthropicTTL
        self.googleCachedContent = googleCachedContent
    }

    public static let automatic = Self()
    public static let providerDefault = Self(mode: .providerDefault)
    public static let noExplicitCaching = Self(mode: .noExplicitCaching)

    var requestsExplicitControls: Bool { mode == .automatic }
}

/// Opaque cache-accounting scope. Use stable, nonsecret app/account/workspace IDs,
/// never credentials or prompt text. Scope is a routing/accounting hint, not authorization.
public struct HanlinPromptCacheScope: Codable, Hashable, Sendable {
    public let namespace: [String]
    public let conversationID: String
    public let promptVersion: String

    public init(namespace: [String], conversationID: String, promptVersion: String) {
        self.namespace = namespace
        self.conversationID = conversationID
        self.promptVersion = promptVersion
    }

    public func key(configuration: HanlinChatModelConfiguration) -> String {
        var endpoint = URLComponents(url: configuration.endpoint, resolvingAgainstBaseURL: false)
        endpoint?.user = nil
        endpoint?.password = nil
        endpoint?.query = nil
        endpoint?.fragment = nil
        if let host = endpoint?.host { endpoint?.host = host.lowercased() }
        let fields = ["hanlin-prompt-cache-v1", String(namespace.count)] + namespace + [
            conversationID, promptVersion,
            configuration.company?.lowercased() ?? "",
            configuration.apiType?.lowercased() ?? "",
            endpoint?.string ?? "",
            configuration.baseModelID
        ]
        var bytes = Data()
        for field in fields {
            let data = Data(field.utf8)
            bytes.append(contentsOf: String(data.count).utf8)
            bytes.append(0x3A)
            bytes.append(data)
        }
        return SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
    }
}
