import Foundation

struct AgentDiagnosticsSession: Codable, Identifiable, Sendable {
    static let currentSchemaVersion = 1

    var schemaVersion = currentSchemaVersion
    var id: UUID
    var runID: UUID
    var groupID: UUID
    var startedAt: Date
    var completedAt: Date?
    var lastUpdatedAt: Date
    var providerID: String
    var modelID: String
    var endpointKind: String
    var appVersion: String?
    var buildNumber: String?
    var status: String
    var isComplete: Bool
    var level: AgentDiagnosticsLevel
    var rounds: [AgentDiagnosticsRound]
    var totals: AgentTokenUsage
    var efficiency: AgentEfficiencyReport
}

struct AgentDiagnosticsRound: Codable, Identifiable, Sendable {
    var id: UUID
    var index: Int
    var startedAt: Date
    var completedAt: Date?
    var trigger: String
    var request: AgentDiagnosticsModelRequest
    var response: AgentDiagnosticsModelResponse
    var toolCalls: [AgentDiagnosticsToolCall]
    var usage: AgentTokenUsage
}

struct AgentDiagnosticsModelRequest: Codable, Sendable {
    var sanitizedJSON: String?
    var byteCount: Int
    var contentHash: String
    var composition: AgentPromptCompositionMetrics
}

struct AgentDiagnosticsModelResponse: Codable, Sendable {
    var httpStatus: Int?
    var providerRequestID: String?
    var visibleContent: String?
    var visibleReasoningSummary: String?
    var finishReason: String?
    var error: String?
    var streamEventCount: Int
    var timeToFirstToken: TimeInterval?
    var totalLatency: TimeInterval?
}

struct AgentDiagnosticsToolCall: Codable, Identifiable, Sendable {
    var id: String { callID }
    var callID: String
    var toolName: String
    var progressSummary: String?
    var requestedAt: Date
    var executionStartedAt: Date?
    var executionCompletedAt: Date?
    var status: String
    var rawArgumentsBeforeSanitization: String?
    var argumentsAfterMetadataRemoval: String?
    var resultForModel: String?
    var resultForUser: String?
    var resultByteCount: Int
    var error: String?
    var wasDeduplicated: Bool
    var duplicateOfCallID: String?
}

struct AgentEfficiencyReport: Codable, Hashable, Sendable {
    var modelRoundCount = 0
    var toolCallCount = 0
    var uniqueToolCallCount = 0
    var duplicateToolCallCount = 0
    var repeatedIdenticalQueryCount = 0
    var totalInputTokens: Int?
    var totalOutputTokens: Int?
    var tokenAmplificationRatio: Double?
    var totalToolResultCharactersResent = 0
    var largestToolResultCharacters = 0
    var historyGrowthByRound: [Int] = []
    var toolSchemaOverheadTokens = 0
    var progressMessageCount = 0
    var hiddenProgressCount = 0
    var transportOnlyEventCount = 0
    var timeToFirstAnswerToken: TimeInterval?
    var totalDuration: TimeInterval?
    var failedToolCount = 0
    var retryCount = 0
    var warnings: [String] = []
}
