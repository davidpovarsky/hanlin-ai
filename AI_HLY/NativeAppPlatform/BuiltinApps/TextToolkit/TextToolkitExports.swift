import SwiftUI

@MainActor
enum TextToolkitExports {
    static func service() -> TextToolkitService { TextToolkitService() }

    static func rootView(context: NativeAppContext) -> AnyView {
        AnyView(TextToolkitRootView(service: service(), context: context))
    }

    static func assistantTools(context: NativeAppContext) -> [NativeTool] {
        [
            NativeAppTextAnalyzeTool(service: service()),
            NativeAppTextTransformTool(service: service())
        ]
    }
}
