import SwiftUI

@MainActor
enum NativeAppTextStudioExports {
    static func service() -> NativeAppTextStudioService { NativeAppTextStudioService() }

    static func rootView(context: NativeAppContext) -> AnyView {
        AnyView(NativeAppTextStudioRootView(service: service(), context: context))
    }

    static func assistantTools(context: NativeAppContext) -> [NativeTool] {
        [
            NativeAppTextStudioAnalyzeTool(service: service()),
            NativeAppTextStudioTransformTool(service: service())
        ]
    }
}
