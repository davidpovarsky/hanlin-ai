import SwiftUI

public struct HanlinScriptWidgetElementView: View {
    public let node: HanlinScriptWidgetPreparedNode
    public let context: HanlinWidgetActionContext
    public init(node: HanlinScriptWidgetPreparedNode, context: HanlinWidgetActionContext) {
        self.node = node
        self.context = context
    }
    public var body: some View {
        ScriptWidgetElementView(element: node.nativeElement(), context: ScriptWidgetElementContext(actionContext: context))
    }
}

extension HanlinScriptWidgetPreparedNode {
    // Construct only native-string elements. No JSValue access in presentation.
    @MainActor func nativeElement() -> ScriptWidgetRuntimeElement {
        let children: [Any] = children.map {
            switch $0 {
            case let .element(node): return node.nativeElement()
            case let .value(value): return value.toAny()
            }
        }
        return .init(tagString: tag, props: Dictionary(uniqueKeysWithValues: props.map { (AnyHashable($0.key), $0.value.toAny()) }), children: children)
    }
}