#if os(iOS)
import ActivityKit
import Foundation

extension HanlinGenericLiveActivityAttributes: ActivityAttributes {}

public enum HanlinScriptLiveActivityController {
    public static func start(
        attributes: HanlinGenericLiveActivityAttributes,
        state: HanlinGenericLiveActivityAttributes.ContentState,
        staleDate: Date? = nil,
        relevanceScore: Double = 0
    ) throws -> String {
        let activity = try Activity.request(
            attributes: attributes,
            content: ActivityContent(state: state, staleDate: staleDate, relevanceScore: relevanceScore),
            pushType: nil
        )
        return activity.id
    }

    public static func update(
        systemActivityID: String,
        state: HanlinGenericLiveActivityAttributes.ContentState,
        staleDate: Date? = nil,
        relevanceScore: Double = 0
    ) async -> Bool {
        guard let activity = Activity<HanlinGenericLiveActivityAttributes>.activities.first(
            where: { $0.id == systemActivityID }
        ) else { return false }
        await activity.update(ActivityContent(
            state: state,
            staleDate: staleDate,
            relevanceScore: relevanceScore
        ))
        return true
    }

    public static func end(
        systemActivityID: String,
        finalState: HanlinGenericLiveActivityAttributes.ContentState,
        dismissTimeInterval: Double? = nil
    ) async -> Bool {
        guard let activity = Activity<HanlinGenericLiveActivityAttributes>.activities.first(
            where: { $0.id == systemActivityID }
        ) else { return false }
        let dismissalPolicy: ActivityUIDismissalPolicy = if let dismissTimeInterval {
            dismissTimeInterval <= 0
                ? .immediate
                : .after(.now.addingTimeInterval(min(dismissTimeInterval, 4 * 60 * 60)))
        } else {
            .default
        }
        await activity.end(
            ActivityContent(state: finalState, staleDate: nil),
            dismissalPolicy: dismissalPolicy
        )
        return true
    }

    public static var areActivitiesEnabled: Bool {
        ActivityAuthorizationInfo().areActivitiesEnabled
    }
}
#endif
