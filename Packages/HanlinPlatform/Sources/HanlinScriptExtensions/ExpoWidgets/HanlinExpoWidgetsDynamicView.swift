import SwiftUI
import HanlinPlatformContracts

/// Presentation receives already prepared values and a native renderer from the
/// widget target. The shared script module has no ExpoUI binary dependency.
public struct HanlinExpoWidgetsDynamicView<Content: View>: View {
    private let content: Content
    public init(node: HanlinValue, context: HanlinWidgetActionContext,
                @ViewBuilder renderer: (HanlinValue, HanlinWidgetActionContext) -> Content) {
        content = renderer(node, context)
    }
    public var body: some View { content }
}