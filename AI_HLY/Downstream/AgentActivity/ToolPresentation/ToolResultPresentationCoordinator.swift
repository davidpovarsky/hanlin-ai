import Foundation

enum ToolResultSuppressionReason: String, Codable, Hashable, Sendable {
    case notRequested
    case toolDoesNotSupportResultUI
    case emptyResult
    case duplicate
    case invalidRequest
}

struct ToolResultPresentationDecision: Codable, Hashable, Sendable {
    var shouldPresent: Bool
    var rendererKind: ToolResultRendererKind?
    var suppressionReason: ToolResultSuppressionReason?
}

enum ToolResultPresentationCoordinator {
    static func decide(
        call: AgentToolCall,
        profile: ToolPresentationProfile,
        hasPayload: Bool,
        isDuplicate: Bool = false
    ) -> ToolResultPresentationDecision {
        let decision: ToolResultPresentationDecision
        if isDuplicate {
            decision = suppressed(.duplicate)
        } else if call.hadInvalidResultPresentation {
            decision = suppressed(.invalidRequest)
        } else if profile.resultDisplayPolicy == .never || profile.result == nil || profile.result?.supportsCard != true {
            decision = suppressed(.toolDoesNotSupportResultUI)
        } else if profile.resultDisplayPolicy == .modelControlled && call.resultPresentationRequest != .card {
            decision = suppressed(.notRequested)
        } else if !hasPayload {
            decision = suppressed(.emptyResult)
        } else {
            decision = ToolResultPresentationDecision(
                shouldPresent: true,
                rendererKind: profile.result?.rendererKind,
                suppressionReason: nil
            )
        }
        trace(decision, call: call, profile: profile)
        return decision
    }

    private static func suppressed(_ reason: ToolResultSuppressionReason) -> ToolResultPresentationDecision {
        ToolResultPresentationDecision(shouldPresent: false, rendererKind: nil, suppressionReason: reason)
    }

    private static func trace(
        _ decision: ToolResultPresentationDecision,
        call: AgentToolCall,
        profile: ToolPresentationProfile
    ) {
        guard AgentDiagnosticsConfiguration.level != .off else { return }
        NativeToolTraceLogger.shared.log(
            decision.shouldPresent ? "resultPresentationEffective" : "resultPresentationSuppressed",
            [
                "callID": call.id,
                "toolName": call.name,
                "toolPresentationProfileResolved": profile.identity,
                "resultPresentationRequested": call.resultPresentationRequest.rawValue,
                "resultPresentationEffective": decision.shouldPresent,
                "resultRendererKind": decision.rendererKind?.rawValue ?? "none",
                "suppressionReason": decision.suppressionReason?.rawValue ?? ""
            ]
        )
    }
}
