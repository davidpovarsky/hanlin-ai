import SwiftUI
import Foundation
import HanlinPlatformContracts

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
            case let .value(value): return value.scriptWidgetNativeValue
            }
        }
        return .init(tagString: tag, props: Dictionary(uniqueKeysWithValues: props.map { (AnyHashable($0.key), $0.value.scriptWidgetNativeValue) }), children: children)
    }
}

private extension HanlinValue {
    // Original JSExport receives NSNumber from JavaScriptCore. Preserve that
    // numeric bridge after freezing: Swift Int64 does not cast to Double.
    var scriptWidgetNativeValue: Any {
        switch self {
        case let .integer(value): NSNumber(value: value)
        case let .number(value): NSNumber(value: value)
        case let .array(values): values.map(\.scriptWidgetNativeValue)
        case let .object(values): Dictionary(uniqueKeysWithValues: values.map { ($0.key, $0.value.scriptWidgetNativeValue) })
        default: toAny()
        }
    }
}
