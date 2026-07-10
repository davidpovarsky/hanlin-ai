import SwiftUI

struct NativeAppSefariaRootView: View {
    let searchService: NativeAppSefariaSearchService
    let sourceService: NativeAppSefariaSourceService
    let context: NativeAppContext

    @StateObject private var store = NativeAppSefariaStore()

    var body: some View {
        TabView {
            NativeAppSefariaHomeView(
                searchService: searchService,
                sourceService: sourceService,
                store: store
            )
            .tabItem { Label("Home", systemImage: "house") }

            NativeAppSefariaSearchView(
                searchService: searchService,
                sourceService: sourceService,
                store: store
            )
            .tabItem { Label("Search", systemImage: "magnifyingglass") }

            NativeAppSefariaSavedView(
                sourceService: sourceService,
                store: store
            )
            .tabItem { Label("Saved", systemImage: "bookmark") }

            NativeAppSefariaSettingsView(store: store)
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
        .navigationTitle("Sefaria")
        .navigationBarTitleDisplayMode(.inline)
    }
}
