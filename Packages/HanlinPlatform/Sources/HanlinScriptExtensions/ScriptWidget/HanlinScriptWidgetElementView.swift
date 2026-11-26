import SwiftUI
import Foundation
import HanlinPlatformContracts

public struct HanlinScriptWidgetElementView: View {
    public let node: HanlinScriptWidgetPreparedNode
    public let context: HanlinWidgetActionContext
    private let usesWidgetContainerBackground: Bool
    private let nativeActionBuilder: ((HanlinWidgetActionCommand, AnyView) -> AnyView)?
    public init(node: HanlinScriptWidgetPreparedNode, context: HanlinWidgetActionContext,
                usesWidgetContainerBackground: Bool = false,
                nativeActionBuilder: ((HanlinWidgetActionCommand, AnyView) -> AnyView)? = nil) {
        self.node = node
        self.context = context
        self.usesWidgetContainerBackground = usesWidgetContainerBackground
        self.nativeActionBuilder = nativeActionBuilder
    }
    @ViewBuilder public var body: some View {
        let element = node.nativeElement()
        let elementContext = ScriptWidgetElementContext(actionContext: context,
            containerRootID: usesWidgetContainerBackground ? element.id : nil,
            nativeActionBuilder: nativeActionBuilder)
        if usesWidgetContainerBackground {
            ScriptWidgetElementView(element: element, context: elementContext)
                .modifier(ScriptWidgetContainerBackgroundModifier(element))
        } else {
            ScriptWidgetElementView(element: element, context: elementContext)
        }
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
        case let .object(values): Dictionary(values.map { ($0.key, $0.value.scriptWidgetNativeValue) }, uniquingKeysWith: { _, latest in latest })
        default: toAny()
        }
    }
}
