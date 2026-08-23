#if os(iOS)
import ActivityKit
import Foundation

extension HanlinGenericLiveActivityAttributes: ActivityAttributes {}

public enum HanlinScriptLiveActivityController {
    public static func start(
        attributes: HanlinGenericLiveActivityAttributes,
        state: HanlinGenericLiveActivityAttributes.ContentState,
        staleDate: Date? = nil
    ) throws -> String {
        let activity = try Activity.request(
            attributes: attributes,
            content: ActivityContent(state: state, staleDate: staleDate),
            pushType: nil
        )
        return activity.id
    }

    public static func update(
        systemActivityID: String,
        state: HanlinGenericLiveActivityAttributes.ContentState,
        staleDate: Date? = nil
    ) async {
        guard let activity = Activity<HanlinGenericLiveActivityAttributes>.activities.first(
            where: { $0.id == systemActivityID }
        ) else { return }
        await activity.update(ActivityContent(state: state, staleDate: staleDate))
    }

    public static func end(
        systemActivityID: String,
        finalState: HanlinGenericLiveActivityAttributes.ContentState
    ) async {
        guard let activity = Activity<HanlinGenericLiveActivityAttributes>.activities.first(
            where: { $0.id == systemActivityID }
        ) else { return }
        await activity.end(
            ActivityContent(state: finalState, staleDate: nil),
            dismissalPolicy: .default
        )
    }
}
#endif
