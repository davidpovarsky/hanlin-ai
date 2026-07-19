import Foundation

enum AgentDisplayActivityKind: String, Hashable, Sendable {
    case reasoning
    case narrative
    case tool
    case search
    case source
    case document
    case code
    case map
    case calendar
    case health
    case result
    case error
}

struct AgentDisplayActivity: Identifiable, Hashable {
    var id: String
    var kind: AgentDisplayActivityKind
    var systemImage: String?
    var title: String
    var subtitle: String?
    var narrativeText: String?
    var status: AgentActivityStatus
    var startedAt: Date?
    var completedAt: Date?
    var queries: [String]
    var sources: [AgentActivitySource]
    var inputPreview: String?
    var outputPreview: String?
    var errorDescription: String?
    var isExpandable: Bool
    var sourceStepIDs: [UUID]
}

struct AgentDisplayTimeline: Hashable {
    var summaryTitle: String
    var activities: [AgentDisplayActivity]
    var totalDuration: TimeInterval?
    var status: AgentActivityStatus
}
