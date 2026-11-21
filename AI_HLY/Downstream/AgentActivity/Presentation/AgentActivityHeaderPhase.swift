/// Presentation lifetime is independent of persisted historical labels.
/// A completed/reopened message can retain reasoning and operational text, but
/// neither is evidence that the original run is still working.
enum AgentActivityHeaderPhase: Equatable, Sendable {
    case working
    case awaitingApproval
    case history

    static func resolve(isRunActive: Bool, hasPendingApproval: Bool) -> Self {
        guard isRunActive else { return .history }
        return hasPendingApproval ? .awaitingApproval : .working
    }

    var showsShimmer: Bool { self == .working }

    static func showsStandaloneStatus(
        isRunActive: Bool, isCurrentMessage: Bool, hasActivityHeader: Bool
    ) -> Bool {
        isRunActive && isCurrentMessage && !hasActivityHeader
    }
}
