import Foundation

/// Presentation ownership follows persisted source links. Unattributed legacy
/// activities remain siblings; visual proximity never assigns a causal parent.
struct AgentDisplayRound: Identifiable {
    let id: String
    let roundID: String?
    var activities: [AgentDisplayActivity]

    /// An explicit model-round marker is the hierarchy boundary even when the
    /// round contains only one tool or reasoning item. Legacy items keep their
    /// sibling placement because no source attributes them to a round.
    var hasHierarchyHeader: Bool { roundID != nil }
}

extension AgentActivityComposer {
    static func rounds(for run: AgentRun, timeline: AgentDisplayTimeline) -> [AgentDisplayRound] {
        var roundsByStep: [UUID: Set<String>] = [:]
        for item in run.transcriptItems {
            if let stepID = item.activityStepID, let roundID = item.roundID {
                roundsByStep[stepID, default: []].insert(roundID)
            }
        }
        var result: [AgentDisplayRound] = []
        var indexByRound: [String: Int] = [:]
        for activity in timeline.activities {
            let roundIDs = activity.sourceStepIDs.reduce(into: Set<String>()) { result, stepID in
                result.formUnion(roundsByStep[stepID] ?? [])
            }
            let roundID = roundIDs.count == 1 ? roundIDs.first : nil
            let key = roundID ?? "unattributed"
            if let index = indexByRound[key] {
                result[index].activities.append(activity)
            } else {
                indexByRound[key] = result.count
                result.append(AgentDisplayRound(id: key, roundID: roundID, activities: [activity]))
            }
        }
        return result
    }
}
