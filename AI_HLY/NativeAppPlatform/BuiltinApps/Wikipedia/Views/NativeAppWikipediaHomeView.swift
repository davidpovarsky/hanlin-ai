import SwiftUI

struct NativeAppWikipediaHomeView: View {
    let searchService: NativeAppWikipediaSearchService
    let summaryService: NativeAppWikipediaSummaryService
    @ObservedObject var store: NativeAppWikipediaStore

    private let featured = [
        "Jerusalem", "Maimonides", "Swift programming language", "Artificial intelligence"
    ]

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Explore knowledge", systemImage: "globe.americas")
                        .font(.title3.weight(.semibold))
                    Text("Search, open, save and revisit articles in \(store.language.title).")
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 6)
            }

            Section("Featured") {
                ForEach(featured, id: \.self) { title in
                    NavigationLink {
                        NativeAppWikipediaArticleLoaderView(
                            title: title,
                            languageCode: store.language.rawValue,
                            searchService: searchService,
                            summaryService: summaryService,
                            store: store
                        )
                    } label: {
                        Label(title, systemImage: "sparkles")
                    }
                }
            }

            Section("Recent Searches") {
                if store.recentQueries.isEmpty {
                    Text("Your recent searches will appear here.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(store.recentQueries, id: \.self) { query in
                        NavigationLink {
                            NativeAppWikipediaSearchView(
                                initialQuery: query,
                                searchService: searchService,
                                summaryService: summaryService,
                                store: store
                            )
                        } label: {
                            Label(query, systemImage: "clock.arrow.circlepath")
                        }
                    }
                }
            }

            Section("Saved Articles") {
                if store.savedArticles.isEmpty {
                    Text("Bookmark an article to keep it here.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(store.savedArticles.prefix(3)) { article in
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
                                Text(article.extract).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Wikipedia")
    }
}
