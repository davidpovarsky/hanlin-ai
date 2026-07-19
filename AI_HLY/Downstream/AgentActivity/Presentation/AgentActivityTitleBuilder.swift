import Foundation

enum AgentActivityTitleBuilder {
    static func title(
        for steps: [AgentActivityStep],
        kind: AgentDisplayActivityKind,
        queries: [String],
        status: AgentActivityStatus
    ) -> String {
        if let summary = steps.compactMap(\.userFacingSummary)
            .compactMap({ ProgressSummarySanitizer.sanitize($0) })
            .first(where: { !isGeneric($0) }) {
            return summary
        }

        if kind == .search, let query = queries.first {
            if let profile = steps.compactMap(\.presentationProfile).first,
               profile.activity.kind == .search {
                let title = status == .running
                    ? profile.activity.runningTitle
                    : profile.activity.completedTitle
                return "\(title) · \(query)"
            }
            let format = status == .running
                ? String(localized: "Searching the web for %@")
                : String(localized: "Searched the web for %@")
            return String(format: format, query)
        }

        let toolName = steps.compactMap(\.subtitle).first ?? ""
        let profile = steps.compactMap(\.presentationProfile).first
        let presentation = ToolPresentationRegistry.presentation(for: toolName, profile: profile)
        return status == .running ? presentation.runningDescription : presentation.completedDescriptionForTimeline
    }

    private static func isGeneric(_ value: String) -> Bool {
        let normalized = AgentActivityDeduplicator.normalized(value) ?? ""
        return ["done", "using a tool", "progress update", "עדכון התקדמות"].contains(normalized)
    }
}

private extension ToolPresentation {
    var completedDescriptionForTimeline: String {
        completedDescription == String(localized: "Done") ? title : completedDescription
    }
}
