/// Real reasoning and tool lifetimes own activity motion. Answer streaming ends
/// reasoning motion; independently running tools may still continue alongside it.
/// A run alone, persisted labels or stale approval never revive completed activity.
enum AgentActivityHeaderPhase: Equatable, Sendable {
    case working
    case awaitingApproval
    case history

    static func resolve(isRunActive: Bool, hasPendingApproval: Bool,
                        hasAnswerText: Bool = false, hasActiveOperation: Bool = false,
                        hasActiveReasoning: Bool = false, hasPendingModelRequest: Bool = false) -> Self {
        guard isRunActive else { return .history }
        let hasLiveWork = hasActiveOperation
            || ((hasActiveReasoning || hasPendingModelRequest) && !hasAnswerText && !hasPendingApproval)
        if hasPendingApproval && !hasActiveOperation { return .awaitingApproval }
        return hasLiveWork ? .working : .history
    }

    var showsShimmer: Bool { self == .working }

    static func showsModelRequestStatus(isRunActive: Bool, requestID: String?,
                                       hasAnswerText: Bool, hasPendingApproval: Bool) -> Bool {
        isRunActive && requestID?.isEmpty == false && !hasAnswerText && !hasPendingApproval
    }

    static func showsStandaloneStatus(
        isRunActive: Bool, isCurrentMessage: Bool, hasActivityHeader: Bool,
        hasAnswerText: Bool = false
    ) -> Bool {
        // Transport state is not a tool invocation. The send/stop control owns
        // request lifetime; there is no synthetic "preparing your answer" row.
        false
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
        guard isWorking, !activePaths.isEmpty else { return [] }
        guard isHierarchyExpanded else { return [.root] }
        return Set(activePaths.map { path in
            if let roundID = path.roundID, !path.isRoundExpanded { return .round(roundID) }
            return .activity(path.activityID)
        })
    }
}
