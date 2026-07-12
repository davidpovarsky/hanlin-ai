import SwiftUI

struct NativeAppWikipediaRootView: View {
    private enum Tab: Hashable { case home, search, saved, settings }

    let searchService: NativeAppWikipediaSearchService
    let summaryService: NativeAppWikipediaSummaryService
    let context: NativeAppContext

    @StateObject private var store = NativeAppWikipediaStore()
    @State private var selectedTab: Tab

    init(
        searchService: NativeAppWikipediaSearchService,
        summaryService: NativeAppWikipediaSummaryService,
        context: NativeAppContext
    ) {
        self.searchService = searchService
        self.summaryService = summaryService
        self.context = context
        _selectedTab = State(initialValue: context.initialRoute?.screen == "search" ? .search : .home)
    }

    var body: some View {
        if let article = articleRoute {
            NativeAppWikipediaArticleLoaderView(
                title: article.title,
                languageCode: article.languageCode,
                searchService: searchService,
                summaryService: summaryService,
                store: store
            )
        } else {
            TabView(selection: $selectedTab) {
                NativeAppWikipediaHomeView(
                    searchService: searchService,
                    summaryService: summaryService,
                    store: store
                )
                .tabItem { Label("Home", systemImage: "house") }
                .tag(Tab.home)

                NativeAppWikipediaSearchView(
                    initialQuery: searchQuery,
                    searchService: searchService,
                    summaryService: summaryService,
                    store: store
                )
                .tabItem { Label("Search", systemImage: "magnifyingglass") }
                .tag(Tab.search)

                NativeAppWikipediaSavedView(
                    searchService: searchService,
                    summaryService: summaryService,
                    store: store
                )
                .tabItem { Label("Saved", systemImage: "bookmark") }
                .tag(Tab.saved)

                NativeAppWikipediaSettingsView(store: store)
                    .tabItem { Label("Settings", systemImage: "gearshape") }
                    .tag(Tab.settings)
            }
            .navigationTitle("Wikipedia")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var route: NativeAppRoute? {
        guard context.initialRoute?.appID == NativeAppWikipediaIndex.id else { return nil }
        return context.initialRoute
    }

    private var searchQuery: String { route?.screen == "search" ? route?.payload.string("query") ?? "" : "" }
    private var articleRoute: (title: String, languageCode: String)? {
        guard route?.screen == "article",
              let title = route?.payload.string("title"),
              let languageCode = route?.payload.string("languageCode") else { return nil }
        return (title, languageCode)
    }
}
