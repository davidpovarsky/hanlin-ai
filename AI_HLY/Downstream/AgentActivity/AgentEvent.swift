//
//  AgentEvent.swift
//  AI_HLY
//

import Foundation

struct AgentRunMetadata: Sendable {
    var id: UUID
    var groupID: UUID
    var providerID: String?
    var modelID: String?
    var startedAt: Date
}

struct AgentItemMetadata: Sendable {
    var id: String
    var title: String
    var startedAt: Date
}

struct AgentProgressMessage: Sendable {
    var id: String
    var message: String
    var source: ProgressSummarySource
    var timestamp: Date
}

struct AgentSafeError: Error, Codable, Hashable, Sendable {
    var message: String

    init(_ error: Error) {
        message = Self.redacted(error.localizedDescription)
    }

    init(message: String) {
        self.message = Self.redacted(message)
    }

    private static func redacted(_ value: String) -> String {
        var result = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let patterns = [
            "(?i)(api[_-]?key|authorization|bearer|token|password|secret)\\s*[:=]\\s*[^\\s,;]+",
            "(?i)sk-[a-z0-9_-]{12,}"
        ]
        for pattern in patterns {
            result = result.replacingOccurrences(of: pattern, with: "[redacted]", options: .regularExpression)
        }
        return String(result.prefix(500))
    }
}

struct AgentToolCall: Sendable {
    var id: String
    var name: String
    var rawArgumentsJSON: String
    var sanitizedArgumentsJSON: String
    var progressSummary: String?
    var progressSummarySource: ProgressSummarySource?
    var resultPresentationRequest: ToolResultPresentationRequest
    var hadInvalidResultPresentation: Bool
    var presentationProfile: ToolPresentationProfile

    static func parse(
        id: String,
        name: String,
        argumentsJSON: String,
        presentationProfile: ToolPresentationProfile? = nil
    ) -> AgentToolCall {
        let extraction = ToolInvocationMetadataExtractor.extract(from: argumentsJSON)
        return AgentToolCall(
            id: id,
            name: name,
            rawArgumentsJSON: argumentsJSON,
            sanitizedArgumentsJSON: extraction.sanitizedArgumentsJSON,
            progressSummary: extraction.metadata.progressSummary,
            progressSummarySource: extraction.metadata.progressSummary == nil ? nil : .model,
            resultPresentationRequest: extraction.metadata.resultPresentation,
            hadInvalidResultPresentation: extraction.hadInvalidResultPresentation,
            presentationProfile: ToolPresentationProfileRegistry.resolve(
                toolName: name,
                explicitProfile: presentationProfile
            )
        )
    }
}

struct AgentToolExecution: Sendable {
    var id: String
    var callID: String
    var name: String
    var startedAt: Date
}

struct AgentToolResult: @unchecked Sendable {
    var modelText: String
    var userText: String?
    var richResultBlocks: [NativeUIBlock]
    var evidenceItems: [AgentEvidenceItem]
    var hasLegacyPresentationPayload: Bool
    var isError: Bool
    var duration: TimeInterval
}

enum AgentAnswerDisposition: String, Codable, Hashable, Sendable {
    case provisional
    case interim
    case final
}

enum AgentEvent: @unchecked Sendable {
    case runStarted(AgentRunMetadata)
    case reasoningStarted(AgentItemMetadata)
    case reasoningDelta(id: String, text: String)
    case reasoningCompleted(id: String)
    case progressMessage(AgentProgressMessage)
    case toolCallStarted(AgentToolCall)
    case toolCallArgumentsDelta(id: String, delta: String)
    case toolCallCompleted(AgentToolCall)
    case toolExecutionStarted(AgentToolExecution)
    case toolExecutionProgress(id: String, message: String)
    case toolExecutionCompleted(id: String, result: AgentToolResult)
    case toolExecutionFailed(id: String, error: AgentSafeError)
    case answerSegmentStarted(AgentItemMetadata)
    case answerSegmentDelta(id: String, text: String)
    case answerSegmentEnded(id: String, disposition: AgentAnswerDisposition)
    case searchStarted(id: String, title: String, queries: [String], providerName: String?)
    case searchCompleted(id: String, sources: [AgentActivitySource], output: String?)
    case runCompleted
    case runFailed(AgentSafeError)
    case runCancelled
}
