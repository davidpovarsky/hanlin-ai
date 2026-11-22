//
//  ToolPresentationRegistry.swift
//  AI_HLY
//

import Foundation

struct ToolPresentation {
    var title: String
    var systemImage: String
    var runningDescription: String
    var completedDescription: String
    var activityKind: AgentActivityKind
}

enum ToolPresentationRegistry {
    static func presentation(
        for toolName: String,
        profile: ToolPresentationProfile? = nil
    ) -> ToolPresentation {
        let resolved = ToolPresentationProfileRegistry.resolve(
            toolName: toolName,
            explicitProfile: profile
        )
        return ToolPresentation(
            title: resolved.activity.runningTitle,
            systemImage: resolved.activity.systemImage,
            runningDescription: resolved.activity.runningTitle,
            completedDescription: resolved.activity.completedTitle,
            activityKind: resolved.activity.kind.agentActivityKind
        )
    }
}

/// A readable view of the original, redacted request. Operational metadata is
/// not an authorization scope. Complex or long arguments remain available in
/// the original request disclosure and must be reviewed before allowing them.
struct AgentToolApprovalSummary {
    let title: String
    let systemImage: String
    let scope: String
    let requiresDetailedReview: Bool

    static func make(toolName: String, reviewText: String) -> Self {
        let presentation = ToolPresentationRegistry.presentation(for: toolName)
        let raw = reviewText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let arguments = try? JSONSerialization.jsonObject(with: Data(raw.utf8)) as? [String: Any] else {
            return .init(title: presentation.title, systemImage: presentation.systemImage,
                scope: String(localized: "Review request details"), requiresDetailedReview: true)
        }
        // These keys are removed by ToolInvocationMetadataExtractor before the
        // actual invocation. Never let the model's summary replace real scope.
        let inputs = arguments.filter { !["progress_summary", "result_presentation"].contains($0.key) }
        if toolName.lowercased() == "get_current_location",
           inputs.count == 1, inputs["query"] as? String == "local" {
            return .init(title: String(localized: "Use current location"), systemImage: "location",
                scope: String(localized: "Your current location"), requiresDetailedReview: false)
        }
        let fields = inputs.keys.sorted().compactMap { key -> String? in
            guard let value = inputs[key] else { return nil }
            // NSNumber would reformat the original lexical value (and can
            // round large numbers). Numeric/boolean/nested arguments therefore
            // require the untouched original request disclosure.
            guard let text = value as? String else { return nil }
            guard !text.contains("\n"), text.count <= 140 else { return nil }
            let label = key.replacingOccurrences(of: "_", with: " ")
            return "\(label): \(text)"
        }
        let scope = fields.joined(separator: " · ")
        let complete = !inputs.isEmpty && inputs.count <= 3 && fields.count == inputs.count && scope.count <= 220
        return .init(title: presentation.title, systemImage: presentation.systemImage,
            scope: complete ? scope : String(localized: "Review request details"),
            requiresDetailedReview: !complete)
    }
}
