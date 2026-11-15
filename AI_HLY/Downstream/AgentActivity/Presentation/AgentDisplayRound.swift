import Foundation

/// Presentation ownership follows persisted source links. Unattributed legacy
/// activities remain siblings; visual proximity never assigns a causal parent.
struct AgentDisplayRound: Identifiable {
    let id: String
    let roundID: String?
    var activities: [AgentDisplayActivity]
}

extension AgentActivityComposer {
    static func rounds(for run: AgentRun, timeline: AgentDisplayTimeline) -> [AgentDisplayRound] {
        var result: [AgentDisplayRound] = []
        for activity in timeline.activities {
            let steps = Set(activity.sourceStepIDs)
            let roundIDs = Set(run.transcriptItems.filter {
                $0.activityStepID.map(steps.contains) == true
            }.compactMap(\.roundID))
            let roundID = roundIDs.count == 1 ? roundIDs.first : nil
            let key = roundID ?? "unattributed"
            if let index = result.firstIndex(where: { $0.id == key }) {
                result[index].activities.append(activity)
            } else {
                result.append(AgentDisplayRound(id: key, roundID: roundID, activities: [activity]))
            }
        }
        return result
    }
}
