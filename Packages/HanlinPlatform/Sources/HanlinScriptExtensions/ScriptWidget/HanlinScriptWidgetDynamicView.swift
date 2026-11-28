import SwiftUI

public struct HanlinScriptWidgetDynamicView: View {
    public let node: HanlinScriptWidgetPreparedNode
    public let context: HanlinWidgetActionContext
    public let usesWidgetContainerBackground: Bool
    public init(node: HanlinScriptWidgetPreparedNode, context: HanlinWidgetActionContext, usesWidgetContainerBackground: Bool = false) {
        self.node = node
        self.context = context
        self.usesWidgetContainerBackground = usesWidgetContainerBackground
    }
    public var body: some View {
        HanlinScriptWidgetElementView(node: node, context: context, usesWidgetContainerBackground: usesWidgetContainerBackground)
    }
}