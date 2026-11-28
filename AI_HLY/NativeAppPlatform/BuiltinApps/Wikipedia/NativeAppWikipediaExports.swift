import HanlinWikipediaMiniApp
import SwiftUI

@MainActor
enum NativeAppWikipediaExports {
    static func client() -> NativeAppWikipediaClient { NativeAppWikipediaClient() }
    static func searchService() -> NativeAppWikipediaSearchService { NativeAppWikipediaSearchService(client: client()) }
    static func summaryService() -> NativeAppWikipediaSummaryService { NativeAppWikipediaSummaryService(client: client()) }

    static func rootView(context: NativeAppContext) -> AnyView {
        let query = context.initialRoute?.screen == "search" ? context.initialRoute?.payload.string("query") : nil
        let articleTitle = context.initialRoute?.screen == "article" ? context.initialRoute?.payload.string("title") : nil
        let articleLang = context.initialRoute?.screen == "article" ? context.initialRoute?.payload.string("languageCode") : nil
        return AnyView(
            NativeAppWikipediaRootView(
                searchService: searchService(),
                summaryService: summaryService(),
                initialArticleTitle: articleTitle,
                initialArticleLanguageCode: articleLang,
                initialQuery: query
            )
        )
    }

    static func assistantTools(context: NativeAppContext) -> [NativeTool] {
        [
            WikipediaAssistantSearchTool(service: searchService()),
            WikipediaAssistantSummaryTool(service: summaryService())
        ]
    }
}
