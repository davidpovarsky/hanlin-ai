import SwiftUI

@MainActor
enum NativeAppSefariaExports {
    static func client() -> NativeAppSefariaClient { NativeAppSefariaClient() }
    static func searchService() -> NativeAppSefariaSearchService { NativeAppSefariaSearchService(client: client()) }
    static func sourceService() -> NativeAppSefariaSourceService { NativeAppSefariaSourceService(client: client()) }

    static func rootView(context: NativeAppContext) -> AnyView {
        AnyView(
            NativeAppSefariaRootView(
                searchService: searchService(),
                sourceService: sourceService(),
                context: context
            )
        )
    }

    static func assistantTools(context: NativeAppContext) -> [NativeTool] {
        [
            SefariaAssistantSearchTool(service: searchService()),
            SefariaAssistantSourceTool(service: sourceService())
        ]
    }
}
