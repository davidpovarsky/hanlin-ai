import HanlinChatCore

/// The single model/generation policy used when Hanlin creates a conversation
/// without an existing per-chat selection (including compact extension chat).
enum HanlinDefaultChatPolicy {
    static func orderedModels(_ models: [AllModels]) -> [AllModels] {
        models.sorted {
            let lhsPosition = $0.position ?? Int.max
            let rhsPosition = $1.position ?? Int.max
            if lhsPosition != rhsPosition { return lhsPosition < rhsPosition }
            return ($0.name ?? "") < ($1.name ?? "")
        }
    }

    static func defaultModelIndex(in models: [AllModels]) -> Int? {
        models.enumerated()
            .filter { !$0.element.isHidden }
            .sorted {
                let lhsPosition = $0.element.position ?? Int.max
                let rhsPosition = $1.element.position ?? Int.max
                if lhsPosition != rhsPosition { return lhsPosition < rhsPosition }
                return ($0.element.name ?? "") < ($1.element.name ?? "")
            }
            .first?.offset
    }

    static func defaultModel(in models: [AllModels]) -> AllModels? {
        orderedModels(models).first { !$0.isHidden }
    }

    static let temperature = HanlinChatGenerationDefaults.temperature
    static let topP = HanlinChatGenerationDefaults.topP
    static let maxTokens = HanlinChatGenerationDefaults.maxTokens
    static let thinkingLength = HanlinChatGenerationDefaults.thinkingLength
}
