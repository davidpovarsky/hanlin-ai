import SwiftUI

@MainActor
enum NativeAppWikipediaExports {
    static func client() -> NativeAppWikipediaClient { NativeAppWikipediaClient() }
    static func searchService() -> NativeAppWikipediaSearchService { NativeAppWikipediaSearchService(client: client()) }
    static func summaryService() -> NativeAppWikipediaSummaryService { NativeAppWikipediaSummaryService(client: client()) }

    static func rootView(context: NativeAppContext) -> AnyView {
        AnyView(
            NativeAppWikipediaRootView(
                searchService: searchService(),
                summaryService: summaryService(),
                context: context
            )
        )
    }

    static func assistantTools(context: NativeAppContext) -> [NativeTool] {
        [
            NativeAppWikipediaSearchTool(service: searchService()),
            NativeAppWikipediaSummaryTool(service: summaryService())
        ]
    }
}
