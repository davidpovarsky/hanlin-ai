import Foundation

enum ToolPresentationValidation {
    static func metadataIsRemovedBeforeExecution() -> Bool {
        let extraction = ToolInvocationMetadataExtractor.extract(
            from: #"{"query":"Swift","progress_summary":"Searching","result_presentation":"card"}"#
        )
        return extraction.metadata.progressSummary == "Searching"
            && extraction.metadata.resultPresentation == .card
            && !extraction.sanitizedArgumentsJSON.contains(ToolSchemaDecorator.progressSummaryKey)
            && !extraction.sanitizedArgumentsJSON.contains(ToolSchemaDecorator.resultPresentationKey)
    }

    static func missingAndInvalidPresentationAreSafe() -> Bool {
        let missing = ToolInvocationMetadataExtractor.extract(from: #"{"query":"Swift"}"#)
        let invalid = ToolInvocationMetadataExtractor.extract(
            from: #"{"query":"Swift","result_presentation":"customRenderer"}"#
        )
        return missing.metadata.resultPresentation == .none
            && invalid.metadata.resultPresentation == .none
            && invalid.hadInvalidResultPresentation
    }

    static func cardDecisionRequiresRequestSupportAndPayload() -> Bool {
        let profile = ToolPresentationProfile.modernNative(
            toolName: "validation_tool",
            kind: .generic,
            systemImage: "sparkles",
            runningTitle: "Working…",
            completedTitle: "Done",
            visibleArgumentKeys: []
        )
        let call = AgentToolCall.parse(
            id: "validation-call",
            name: "validation_tool",
            argumentsJSON: #"{"result_presentation":"card"}"#,
            presentationProfile: profile
        )
        return ToolResultPresentationCoordinator.decide(
            call: call,
            profile: profile,
            hasPayload: true
        ).shouldPresent
            && ToolResultPresentationCoordinator.decide(
                call: call,
                profile: profile,
                hasPayload: false
            ).suppressionReason == .emptyResult
    }
}
