import SwiftUI

@MainActor
enum WikipediaExports {
    static func client() -> WikipediaClient { WikipediaClient() }
    static func searchService() -> WikipediaSearchService { WikipediaSearchService(client: client()) }
    static func summaryService() -> WikipediaSummaryService { WikipediaSummaryService(client: client()) }

    static func rootView(context: NativeAppContext) -> AnyView {
        AnyView(WikipediaRootView(searchService: searchService(), summaryService: summaryService(), context: context))
    }

    static func assistantTools(context: NativeAppContext) -> [NativeTool] {
        [
            NativeAppWikipediaSearchTool(service: searchService()),
            NativeAppWikipediaSummaryTool(service: summaryService())
        ]
    }
}
