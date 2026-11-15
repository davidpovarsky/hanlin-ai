import Foundation
import AISDKProvider
import HanlinPlatformContracts

/// Provider bridge for the one canonical shared content contract.
public extension HanlinChatStructuredPart {
    /// Adapter entry point for the existing SwiftAISDK custom-content channel.
    /// Base64 preserves the versioned Codable bytes, including exact UInt64 sequence values.
    func providerContent() throws -> LanguageModelV3CustomContent {
        try validate()
        return .init(kind: Self.channel, providerMetadata: ["hanlin": ["part": .string(try JSONEncoder().encode(self).base64EncodedString())]])
    }

    static func decodeProviderContent(kind: String, metadata: SharedV3ProviderMetadata?) throws -> Self? {
        guard kind == channel else { return nil }
        guard case .string(let encoded)? = metadata?["hanlin"]?["part"], encoded.utf8.count <= 2_097_152,
              let bytes = Data(base64Encoded: encoded), bytes.count <= 1_500_000 else {
            throw HanlinChatStructuredPartError.invalidEnvelope
        }
        return try JSONDecoder().decode(Self.self, from: bytes)
    }

}
