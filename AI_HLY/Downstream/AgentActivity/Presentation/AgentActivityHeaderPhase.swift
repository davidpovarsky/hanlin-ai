/// Run lifetime includes answer streaming. Activity lifetime ends as soon as an
/// answer is visible unless a real operation is still executing concurrently.
/// Persisted labels and stale reasoning state never revive completed activity.
enum AgentActivityHeaderPhase: Equatable, Sendable {
    case working
    case awaitingApproval
    case history

    static func resolve(isRunActive: Bool, hasPendingApproval: Bool,
                        hasAnswerText: Bool = false, hasActiveOperation: Bool = false) -> Self {
        guard isRunActive else { return .history }
        if hasPendingApproval && !hasActiveOperation { return .awaitingApproval }
        return hasAnswerText && !hasActiveOperation ? .history : .working
    }

    var showsShimmer: Bool { self == .working }

    static func showsStandaloneStatus(
        isRunActive: Bool, isCurrentMessage: Bool, hasActivityHeader: Bool,
        hasAnswerText: Bool = false
    ) -> Bool {
        isRunActive && isCurrentMessage && !hasActivityHeader && !hasAnswerText
    }
}

/// One visible owner per active path. Tool details are payload, not another
/// activity node; expanding them does not move the shimmer into raw output.
/// Concurrent tools can each own a leaf, but an ancestor never duplicates it.
enum AgentActivityShimmerOwner: Hashable, Sendable {
    case root
    case round(String)
    case activity(String)

    struct Path: Equatable, Sendable {
        let activityID: String
        let roundID: String?
        let isRoundExpanded: Bool
    }

    static func resolve(isWorking: Bool, isHierarchyExpanded: Bool,
                        activePaths: [Path]) -> Set<Self> {
        guard isWorking else { return [] }
        guard isHierarchyExpanded, !activePaths.isEmpty else { return [.root] }
        return Set(activePaths.map { path in
            if let roundID = path.roundID, !path.isRoundExpanded { return .round(roundID) }
            return .activity(path.activityID)
        })
    }
}
