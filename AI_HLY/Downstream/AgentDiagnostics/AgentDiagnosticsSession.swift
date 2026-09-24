import Foundation

struct AgentDiagnosticsSession: Codable, Identifiable, Sendable {
    static let currentSchemaVersion = 2

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
    var loadedSkillIDs: [String]? = nil
    var modelVisibleToolAliases: [String]? = nil
    var modelVisibleToolCount: Int? = nil
    var modelVisibleSchemaBytes: Int? = nil
    var providerID: String? = nil
    var modelID: String? = nil
    var meaningfulStreamEventCount: Int? = nil
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
    var presentationProfileIdentity: String?
    var resultPresentationRequested: String?
    var resultPresentationEffective: Bool?
    var resultRendererKind: String?
    var resultPresentationSuppressed: Bool?
    var suppressionReason: String?
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
    var canonicalLogicalToolID: String? = nil
    var modelFacingAlias: String? = nil
    var backendRoute: String? = nil
    var backendSource: String? = nil
    var runtimeKind: String? = nil
    var outcome: String? = nil
    var failureCategory: String? = nil
    var argumentKeys: [String]? = nil
    var argumentHash: String? = nil
    var capabilityDecision: String? = nil
    var availabilityDecision: String? = nil
    var runtimeStateBefore: String? = nil
    var runtimeStateAfter: String? = nil
    var exitCode: Int? = nil
    var didTimeOut: Bool? = nil
    var wasCancelled: Bool? = nil
    var outputWasTruncated: Bool? = nil
    var stdoutByteCount: Int? = nil
    var stderrByteCount: Int? = nil
    var valueType: String? = nil
    var modelResultByteCount: Int? = nil
    var userResultByteCount: Int? = nil
    var uiBlockTypes: [String]? = nil
    var callerIdentity: String? = nil
    var durationMilliseconds: Int? = nil
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
    var resultPresentationSchemaToolCount: Int?
    var resultPresentationSchemaEstimatedTokens: Int?
    var progressMessageCount = 0
    var hiddenProgressCount = 0
    var transportOnlyEventCount = 0
    var timeToFirstAnswerToken: TimeInterval?
    var totalDuration: TimeInterval?
    var failedToolCount = 0
    var succeededToolCount: Int? = nil
    var invalidArgumentToolCount: Int? = nil
    var capabilityDeniedToolCount: Int? = nil
    var availabilityDeniedToolCount: Int? = nil
    var timedOutToolCount: Int? = nil
    var cancelledToolCount: Int? = nil
    var retryCount = 0
    var warnings: [String] = []
}
