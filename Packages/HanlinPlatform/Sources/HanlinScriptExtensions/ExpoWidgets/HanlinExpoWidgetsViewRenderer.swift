import SwiftUI

public typealias HanlinExpoActionContext = HanlinWidgetActionContext

@MainActor
public enum HanlinExpoWidgetsViewRenderer {
    /// A declared Host action opens the main app; local Expo callbacks retain
    /// their original non-opening intent and execute in the widget runtime.
    public static func hostActionIntent(target: String, context: HanlinWidgetActionContext) throws -> HanlinWidgetHostActionIntent {
        guard context.engine == .expo, context.presentation == nil,
              context.actions.contains(where: { $0.id == target && $0.kind == .hostAction }) else {
            throw HanlinWidgetActionError.undeclaredAction
        }
        return try .init(command: .init(context: context, actionID: target))
    }

    public static func actionIntent(target: String, context: HanlinWidgetActionContext) throws -> HanlinGenericWidgetActionIntent {
        guard context.engine == .expo, context.actions.contains(where: { $0.id == target && $0.kind == .expoCallback }) else {
            throw HanlinWidgetActionError.undeclaredAction
        }
        return try .init(command: .init(context: context, actionID: target))
    }
}
