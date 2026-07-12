import SwiftUI

struct NativeAppSefariaRootView: View {
    private enum Tab: Hashable { case home, search, saved, settings }

    let searchService: NativeAppSefariaSearchService
    let sourceService: NativeAppSefariaSourceService
    let context: NativeAppContext

    @StateObject private var store = NativeAppSefariaStore()
    @State private var selectedTab: Tab

    init(
        searchService: NativeAppSefariaSearchService,
        sourceService: NativeAppSefariaSourceService,
        context: NativeAppContext
    ) {
        self.searchService = searchService
        self.sourceService = sourceService
        self.context = context
        _selectedTab = State(initialValue: context.initialRoute?.screen == "search" ? .search : .home)
    }

    var body: some View {
        if let ref = sourceReference {
            NativeAppSefariaSourceLoaderView(ref: ref, sourceService: sourceService, store: store)
        } else {
            TabView(selection: $selectedTab) {
                NativeAppSefariaHomeView(
                    searchService: searchService,
                    sourceService: sourceService,
                    store: store
                )
                .tabItem { Label("Home", systemImage: "house") }
                .tag(Tab.home)

                NativeAppSefariaSearchView(
                    initialQuery: searchQuery,
                    searchService: searchService,
                    sourceService: sourceService,
                    store: store
                )
                .tabItem { Label("Search", systemImage: "magnifyingglass") }
                .tag(Tab.search)

                NativeAppSefariaSavedView(
                    sourceService: sourceService,
                    store: store
                )
                .tabItem { Label("Saved", systemImage: "bookmark") }
                .tag(Tab.saved)

                NativeAppSefariaSettingsView(store: store)
                    .tabItem { Label("Settings", systemImage: "gearshape") }
                    .tag(Tab.settings)
            }
            .navigationTitle("Sefaria")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var route: NativeAppRoute? {
        guard context.initialRoute?.appID == NativeAppSefariaIndex.id else { return nil }
        return context.initialRoute
    }

    private var searchQuery: String { route?.screen == "search" ? route?.payload.string("query") ?? "" : "" }
    private var sourceReference: String? { route?.screen == "source" ? route?.payload.string("ref") : nil }
}
