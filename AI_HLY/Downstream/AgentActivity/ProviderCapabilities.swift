//
//  ProviderCapabilities.swift
//  AI_HLY
//

import Foundation

struct ProviderCapabilities: Sendable {
    var supportsStreaming: Bool
    var supportsNativeToolCalling: Bool
    var supportsStreamingToolArguments: Bool
    var supportsParallelToolCalls: Bool
    var supportsStructuredOutput: Bool
    var supportsReasoningSummary: Bool
    var supportsVisibleThinking: Bool
    var supportsToolCallIDs: Bool
    var supportsProgressSummaryField: Bool
    var supportsReportProgressTool: Bool

    init(model: AllModels) {
        let provider = (model.company ?? "").uppercased()
        let isLocal = provider == "LOCAL"
        let hasTools = model.supportsToolUse && !isLocal

        supportsStreaming = true
        supportsNativeToolCalling = hasTools
        supportsStreamingToolArguments = hasTools
        supportsParallelToolCalls = hasTools
        supportsStructuredOutput = hasTools
        supportsReasoningSummary = model.supportsReasoning
        supportsVisibleThinking = model.supportsReasoning
        supportsToolCallIDs = hasTools
        supportsProgressSummaryField = hasTools
        supportsReportProgressTool = hasTools
    }
}

extension AllModels {
    var agentCapabilities: ProviderCapabilities {
        ProviderCapabilities(model: self)
    }
}
