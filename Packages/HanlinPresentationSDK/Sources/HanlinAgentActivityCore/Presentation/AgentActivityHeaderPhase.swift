/// Run lifetime owns the root Thinking indicator; actual tools own their row motion.
/// `hasAnswerText` means a confirmed final answer, never provisional commentary.
/// A gap between model/tool events must not turn a still-active run into history.
public enum AgentActivityHeaderPhase: Equatable, Sendable {
    case working
    case awaitingApproval
    case history

    public static func resolve(isRunActive: Bool, hasPendingApproval: Bool,
                        hasAnswerText: Bool = false, hasActiveOperation: Bool = false,
                        hasActiveReasoning: Bool = false, hasPendingModelRequest: Bool = false) -> Self {
        guard isRunActive else { return .history }
        if hasPendingApproval && !hasActiveOperation { return .awaitingApproval }
        if hasActiveOperation { return .working }
        return hasAnswerText ? .history : .working
    }

    public var showsShimmer: Bool { self == .working }

    public static func showsModelRequestStatus(isRunActive: Bool, requestID: String?,
                                       hasAnswerText: Bool, hasPendingApproval: Bool) -> Bool {
        isRunActive && requestID?.isEmpty == false && !hasAnswerText && !hasPendingApproval
    }

    public static func showsStandaloneStatus(
        isRunActive: Bool, isCurrentMessage: Bool, hasActivityHeader: Bool,
        hasAnswerText: Bool = false
    ) -> Bool {
        // Transport state is not a tool invocation. The send/stop control owns
        // request lifetime; there is no synthetic "preparing your answer" row.
        false
    }
}

/// The root remains the live Thinking status while real tools keep their own
/// row indicators. Expanding details never replaces or duplicates Thinking.
/// Callers pass only tool paths; provider reasoning is displayed below the root
/// as its actual text, without a second synthetic Thinking header.
public enum AgentActivityShimmerOwner: Hashable, Sendable {
    case root
    case round(String)
    case activity(String)

    public struct Path: Equatable, Sendable {
        public let activityID: String
        public let roundID: String?
        public let isRoundExpanded: Bool
    
    public init(
        activityID: String,
        roundID: String?,
        isRoundExpanded: Bool
    ) {
        self.activityID = activityID
        self.roundID = roundID
        self.isRoundExpanded = isRoundExpanded
    }
}

    public static func resolve(isWorking: Bool, isHierarchyExpanded: Bool,
                        activePaths: [Path]) -> Set<Self> {
        guard isWorking else { return [] }
        guard isHierarchyExpanded else { return [.root] }
        return Set(activePaths.map { path in
            if let roundID = path.roundID, !path.isRoundExpanded { return .round(roundID) }
            return .activity(path.activityID)
        }).union([.root])
    }
}
