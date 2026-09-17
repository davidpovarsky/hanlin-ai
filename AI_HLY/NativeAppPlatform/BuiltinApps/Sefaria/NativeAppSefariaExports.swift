import HanlinSefariaMiniApp
import SwiftUI

@MainActor
enum NativeAppSefariaExports {
    static func client() -> NativeAppSefariaClient { NativeAppSefariaClient() }
    static func searchService() -> NativeAppSefariaSearchService { NativeAppSefariaSearchService(client: client()) }
    static func sourceService() -> NativeAppSefariaSourceService { NativeAppSefariaSourceService(client: client()) }

    static func rootView(context: NativeAppContext) -> AnyView {
        let query = context.initialRoute?.screen == "search" ? context.initialRoute?.payload.string("query") : nil
        let ref = context.initialRoute?.screen == "source" ? context.initialRoute?.payload.string("ref") : nil
        return AnyView(
            NativeAppSefariaRootView(
                searchService: searchService(),
                sourceService: sourceService(),
                initialQuery: query,
                initialReference: ref
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
