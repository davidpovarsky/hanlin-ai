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
