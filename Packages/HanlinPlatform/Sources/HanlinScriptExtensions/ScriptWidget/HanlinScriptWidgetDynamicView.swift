import SwiftUI

public struct HanlinScriptWidgetDynamicView: View {
    public let node: HanlinScriptWidgetPreparedNode
    public let context: HanlinWidgetActionContext
    public init(node: HanlinScriptWidgetPreparedNode, context: HanlinWidgetActionContext) {
        self.node = node
        self.context = context
    }
    public var body: some View {
        HanlinScriptWidgetElementView(node: node, context: context)
    }
}