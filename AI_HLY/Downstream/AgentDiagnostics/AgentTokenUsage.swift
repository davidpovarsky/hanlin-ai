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
        if let totalTokens {
            self.totalTokens = totalTokens
        } else if let inputTokens, let outputTokens {
            self.totalTokens = inputTokens + outputTokens
        } else {
            // A missing provider measurement is not a measured zero or a
            // partial input/output count presented as a complete total.
            self.totalTokens = nil
        }
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

/// Provider cache accounting is a subset of input tokens, not an additional
/// amount to add to token totals. Missing measurements remain unavailable.
struct AgentPromptCacheSummary: Sendable, Equatable {
    let roundCount: Int
    let readReportedRoundCount: Int
    let writeReportedRoundCount: Int
    let cachedInputTokens: Int?
    let cacheWriteTokens: Int?
    let cacheReadFraction: Double?

    init(usages: [AgentTokenUsage]) {
        roundCount = usages.count
        let providerUsages = usages.filter { $0.source == .providerReported }
        let reads = providerUsages.compactMap(\.cachedInputTokens).filter { $0 >= 0 }
        let writes = providerUsages.compactMap(\.cacheWriteTokens).filter { $0 >= 0 }
        readReportedRoundCount = reads.count
        writeReportedRoundCount = writes.count
        cachedInputTokens = reads.isEmpty ? nil : reads.reduce(0, +)
        cacheWriteTokens = writes.isEmpty ? nil : writes.reduce(0, +)

        // Do not report an apparently precise aggregate percentage if even one
        // round lacks provider measurements or contains inconsistent counts.
        let hasCompleteValidReads = !usages.isEmpty && providerUsages.count == usages.count
            && providerUsages.allSatisfy { usage in
                guard let input = usage.inputTokens, let read = usage.cachedInputTokens else { return false }
                return input >= 0 && read >= 0 && read <= input
            }
        if hasCompleteValidReads {
            let input = providerUsages.compactMap(\.inputTokens).reduce(0, +)
            cacheReadFraction = input > 0 ? Double(reads.reduce(0, +)) / Double(input) : nil
        } else {
            cacheReadFraction = nil
        }
    }

    var readableLines: [String] {
        [
            "Reported cache read input tokens: \(cachedInputTokens.map(String.init) ?? "unavailable")",
            "Reported cache write input tokens: \(cacheWriteTokens.map(String.init) ?? "unavailable")",
            "Cache read measurement coverage: \(readReportedRoundCount)/\(roundCount) rounds",
            "Cache write measurement coverage: \(writeReportedRoundCount)/\(roundCount) rounds",
            "Cache read fraction of input: \(cacheReadFraction.map { String(format: "%.1f%%", $0 * 100) } ?? "unavailable")"
        ]
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
