import SwiftUI

struct NativeAppWikipediaRootView: View {
    let searchService: NativeAppWikipediaSearchService
    let summaryService: NativeAppWikipediaSummaryService
    let context: NativeAppContext

    @StateObject private var store = NativeAppWikipediaStore()

    var body: some View {
        TabView {
            NativeAppWikipediaHomeView(
                searchService: searchService,
                summaryService: summaryService,
                store: store
            )
            .tabItem { Label("Home", systemImage: "house") }

            NativeAppWikipediaSearchView(
                searchService: searchService,
                summaryService: summaryService,
                store: store
            )
            .tabItem { Label("Search", systemImage: "magnifyingglass") }

            NativeAppWikipediaSavedView(
                searchService: searchService,
                summaryService: summaryService,
                store: store
            )
            .tabItem { Label("Saved", systemImage: "bookmark") }

            NativeAppWikipediaSettingsView(store: store)
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
        .navigationTitle("Wikipedia")
        .navigationBarTitleDisplayMode(.inline)
    }
}
