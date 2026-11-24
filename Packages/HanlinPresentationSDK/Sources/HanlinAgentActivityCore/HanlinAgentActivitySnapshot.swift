import Foundation

/// An immutable value snapshot for the original activity hierarchy. It excludes
/// assistant answer deltas, matching Hanlin's existing invalidation boundary.
/// Persisted approval receipts are presentation only; they do not grant consent.
public struct HanlinAgentActivitySnapshot: Equatable {
    public let run: AgentRun?
    public let reasoning: String
    public let reasoningTime: String?
    public let legacyToolContent: String
    public let isActive: Bool
    public let hasAnswerText: Bool

    public init(run: AgentRun? = nil, reasoning: String = "", reasoningTime: String? = nil,
                legacyToolContent: String = "", isActive: Bool = false, hasAnswerText: Bool = false) {
        self.run = Self.presentationRun(run)
        self.reasoning = reasoning
        self.reasoningTime = reasoningTime
        self.legacyToolContent = legacyToolContent
        self.isActive = isActive
        self.hasAnswerText = hasAnswerText
    }

    public static func presentationRun(_ original: AgentRun?) -> AgentRun? {
        var run = original
        run?.transcriptItems.removeAll { $0.kind == .assistantText }
        run?.finalAnswer = nil
        return run
    }
}
