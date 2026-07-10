import SwiftUI

struct NativeAppWikipediaSavedView: View {
    let searchService: NativeAppWikipediaSearchService
    let summaryService: NativeAppWikipediaSummaryService
    @ObservedObject var store: NativeAppWikipediaStore

    var body: some View {
        List {
            if store.savedArticles.isEmpty {
                ContentUnavailableView(
                    "No Saved Articles",
                    systemImage: "bookmark",
                    description: Text("Open an article and tap Bookmark.")
                )
            } else {
                ForEach(store.savedArticles) { article in
                    NavigationLink {
                        NativeAppWikipediaArticleDetailView(
                            summary: article,
                            searchService: searchService,
                            summaryService: summaryService,
                            store: store
                        )
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(article.title).font(.headline)
                            Text(article.extract).font(.caption).foregroundStyle(.secondary).lineLimit(3)
                        }
                    }
                }
                .onDelete { offsets in
                    for index in offsets.sorted(by: >) {
                        store.toggleSaved(store.savedArticles[index])
                    }
                }
            }
        }
        .navigationTitle("Saved")
    }
}
