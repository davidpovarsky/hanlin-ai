import Foundation

enum TokenUsageSource: String, Codable, Hashable, Sendable {
    case providerReported
    case locallyEstimated
    case mixed
    case unavailable
}

struct AgentTokenUsage: Codable, Hashable, Sendable {
    var inputTokens: Int?
    var outputTokens: Int?
    var reasoningTokens: Int?
    var cachedInputTokens: Int?
    var cacheWriteTokens: Int?
    var toolSchemaEstimatedTokens: Int?
    var toolResultEstimatedTokens: Int?
    var systemPromptEstimatedTokens: Int?
    var conversationHistoryEstimatedTokens: Int?
    var totalTokens: Int?
    var source: TokenUsageSource

    static let unavailable = AgentTokenUsage(source: .unavailable)

    init(
        inputTokens: Int? = nil,
        outputTokens: Int? = nil,
        reasoningTokens: Int? = nil,
        cachedInputTokens: Int? = nil,
        cacheWriteTokens: Int? = nil,
        toolSchemaEstimatedTokens: Int? = nil,
        toolResultEstimatedTokens: Int? = nil,
        systemPromptEstimatedTokens: Int? = nil,
        conversationHistoryEstimatedTokens: Int? = nil,
        totalTokens: Int? = nil,
        source: TokenUsageSource
    ) {
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.reasoningTokens = reasoningTokens
        self.cachedInputTokens = cachedInputTokens
        self.cacheWriteTokens = cacheWriteTokens
        self.toolSchemaEstimatedTokens = toolSchemaEstimatedTokens
        self.toolResultEstimatedTokens = toolResultEstimatedTokens
        self.systemPromptEstimatedTokens = systemPromptEstimatedTokens
        self.conversationHistoryEstimatedTokens = conversationHistoryEstimatedTokens
        self.totalTokens = totalTokens ?? [inputTokens, outputTokens].compactMap { $0 }.reduce(0, +)
        self.source = source
    }

    static func + (lhs: Self, rhs: Self) -> Self {
        func sum(_ a: Int?, _ b: Int?) -> Int? {
            let values = [a, b].compactMap { $0 }
            return values.isEmpty ? nil : values.reduce(0, +)
        }
        let source: TokenUsageSource
        if lhs.source == .unavailable { source = rhs.source }
        else if rhs.source == .unavailable || lhs.source == rhs.source { source = lhs.source }
        else { source = .mixed }
        return AgentTokenUsage(
            inputTokens: sum(lhs.inputTokens, rhs.inputTokens),
            outputTokens: sum(lhs.outputTokens, rhs.outputTokens),
            reasoningTokens: sum(lhs.reasoningTokens, rhs.reasoningTokens),
            cachedInputTokens: sum(lhs.cachedInputTokens, rhs.cachedInputTokens),
            cacheWriteTokens: sum(lhs.cacheWriteTokens, rhs.cacheWriteTokens),
            toolSchemaEstimatedTokens: sum(lhs.toolSchemaEstimatedTokens, rhs.toolSchemaEstimatedTokens),
            toolResultEstimatedTokens: sum(lhs.toolResultEstimatedTokens, rhs.toolResultEstimatedTokens),
            systemPromptEstimatedTokens: sum(lhs.systemPromptEstimatedTokens, rhs.systemPromptEstimatedTokens),
            conversationHistoryEstimatedTokens: sum(lhs.conversationHistoryEstimatedTokens, rhs.conversationHistoryEstimatedTokens),
            totalTokens: sum(lhs.totalTokens, rhs.totalTokens),
            source: source
        )
    }
}

struct AgentPromptCompositionMetrics: Codable, Hashable, Sendable {
    var systemCharacters = 0
    var toolSchemaCharacters = 0
    var historyCharacters = 0
    var currentUserCharacters = 0
    var contextCharacters = 0
    var toolResultCharacters = 0
    var estimatedTokensBySection: [String: Int] = [:]
    var resultPresentationSchemaToolCount: Int?
    var resultPresentationSchemaEstimatedTokens: Int?
}

enum AgentTokenEstimator {
    static func estimate(_ text: String) -> Int {
        guard !text.isEmpty else { return 0 }
        let ascii = text.unicodeScalars.filter(\.isASCII).count
        let nonASCII = text.unicodeScalars.count - ascii
        return max(1, Int(ceil(Double(ascii) / 4.0)) + Int(ceil(Double(nonASCII) / 1.5)))
    }
}
