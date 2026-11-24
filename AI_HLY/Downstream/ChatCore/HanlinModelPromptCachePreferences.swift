import Foundation
import HanlinChatCore

enum HanlinModelPromptCachePreferenceError: LocalizedError {
    case conversationScopedPolicy

    var errorDescription: String? {
        "Conversation cache resources and response comparisons cannot be saved as model defaults."
    }
}

/// Serialization for the existing model store, with no additional database/cache owner.
enum HanlinModelPromptCachePreferences {
    static func encode(_ policy: HanlinPromptCachePolicy?) throws -> String? {
        guard let policy else { return nil }
        guard policy.googleCachedContent == nil, policy.openAI?.comparisonResponseID == nil else {
            throw HanlinModelPromptCachePreferenceError.conversationScopedPolicy
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return String(decoding: try encoder.encode(policy), as: UTF8.self)
    }
}
