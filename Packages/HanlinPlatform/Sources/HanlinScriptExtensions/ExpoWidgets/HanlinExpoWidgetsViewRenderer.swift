import SwiftUI

public typealias HanlinExpoActionContext = HanlinWidgetActionContext

@MainActor
public enum HanlinExpoWidgetsViewRenderer {
    public static func actionIntent(target: String, context: HanlinWidgetActionContext) throws -> HanlinGenericWidgetActionIntent {
        guard context.engine == .expo, context.actions.contains(where: { $0.id == target && $0.kind == .expoCallback }) else {
            throw HanlinWidgetActionError.undeclaredAction
        }
        return try .init(command: .init(context: context, actionID: target))
    }
}
