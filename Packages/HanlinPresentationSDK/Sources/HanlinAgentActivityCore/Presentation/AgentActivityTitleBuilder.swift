import HanlinLocalization
import Foundation

public enum AgentActivityTitleBuilder {
    public static func title(
        for steps: [AgentActivityStep],
        kind: AgentDisplayActivityKind,
        queries: [String],
        status: AgentActivityStatus
    ) -> String {
        if status == .failed || status == .cancelled {
            // A terminal update may retain its earlier running title. Name the
            // actual operation; the row separately presents the real outcome.
            let name = steps.compactMap(\.subtitle).first ?? ""
            let profile = steps.compactMap(\.presentationProfile).first
            return ToolPresentationRegistry.presentation(for: name, profile: profile).title
        }

        // Historical completion uses the completed presentation below, never
        // a retained in-progress summary from an earlier lifecycle event.
        if status == .running, let summary = steps.compactMap(\.userFacingSummary)
            .compactMap({ ProgressSummarySanitizer.sanitize($0) })
            .first(where: { !isGeneric($0) }) {
            return summary
        }

        if kind == .search, status != .pending, let query = queries.first {
            if let profile = steps.compactMap(\.presentationProfile).first,
               profile.activity.kind == .search {
                let title = status == .running
                    ? profile.activity.runningTitle
                    : profile.activity.completedTitle
                return "\(title) · \(query)"
            }
            let format = status == .running
                ? String(localized: "Searching the web for %@", bundle: HanlinLocalization.bundle)
                : String(localized: "Searched the web for %@", bundle: HanlinLocalization.bundle)
            return String(format: format, query)
        }

        let toolName = steps.compactMap(\.subtitle).first ?? ""
        let profile = steps.compactMap(\.presentationProfile).first
        let presentation = ToolPresentationRegistry.presentation(for: toolName, profile: profile)
        if status == .pending { return presentation.title }
        return status == .running ? presentation.runningDescription : presentation.completedDescriptionForTimeline
    }

    private static func isGeneric(_ value: String) -> Bool {
        let normalized = AgentActivityDeduplicator.normalized(value) ?? ""
        // A permission receipt describes consent, never the result or the name
        // of the subsequent operation. Keep it in the approval state only.
        let permissionLabels = ["Allowed once", "Allowed and remembered", "Awaiting approval", "Not approved",
            String(localized: "Allowed and remembered", bundle: HanlinLocalization.bundle),
            String(localized: "Allowed once", bundle: HanlinLocalization.bundle), String(localized: "Awaiting approval", bundle: HanlinLocalization.bundle),
            String(localized: "Not approved", bundle: HanlinLocalization.bundle)]
        return ["done", "using a tool", "using tools", "loading skill", "loading skill...",
            "working through your request", "preparing your answer", "progress update", "עדכון התקדמות"].contains(normalized)
            || permissionLabels.contains { AgentActivityDeduplicator.normalized($0) == normalized }
    }
}

private extension ToolPresentation {
    var completedDescriptionForTimeline: String {
        completedDescription == String(localized: "Done", bundle: HanlinLocalization.bundle) ? title : completedDescription
    }
}
