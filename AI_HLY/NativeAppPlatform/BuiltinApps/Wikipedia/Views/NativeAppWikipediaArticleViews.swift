import SwiftUI
import UIKit

struct NativeAppWikipediaArticleLoaderView: View {
    let title: String
    let languageCode: String
    let searchService: NativeAppWikipediaSearchService
    let summaryService: NativeAppWikipediaSummaryService
    @ObservedObject var store: NativeAppWikipediaStore

    @State private var summary: NativeAppWikipediaSummary?
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if let summary {
                NativeAppWikipediaArticleDetailView(
                    summary: summary,
                    searchService: searchService,
                    summaryService: summaryService,
                    store: store
                )
            } else if let errorMessage {
                ContentUnavailableView(
                    "Unable to Load Article",
                    systemImage: "exclamationmark.triangle",
                    description: Text(errorMessage)
                )
            } else {
                ProgressView("Loading \(title)…")
            }
        }
        .navigationTitle(title)
        .task {
            do { summary = try await summaryService.summary(title: title, languageCode: languageCode) }
            catch { errorMessage = error.localizedDescription }
        }
    }
}

struct NativeAppWikipediaArticleDetailView: View {
    let summary: NativeAppWikipediaSummary
    let searchService: NativeAppWikipediaSearchService
    let summaryService: NativeAppWikipediaSummaryService
    @ObservedObject var store: NativeAppWikipediaStore

    @State private var related: [NativeAppWikipediaSearchResult] = []
    @State private var loadsRelated = false

    var body: some View {
        List {
            Section {
                NativeAppWikipediaSummaryCard(summary: summary, mode: .fullApp)
            }

            Section("Actions") {
                Button {
                    store.toggleSaved(summary)
                } label: {
                    Label(
                        store.isSaved(summary) ? "Remove Bookmark" : "Bookmark",
                        systemImage: store.isSaved(summary) ? "bookmark.fill" : "bookmark"
                    )
                }

                Button {
                    UIPasteboard.general.string = summary.extract
                } label: {
                    Label("Copy Summary", systemImage: "doc.on.doc")
                }

                ShareLink(item: summary.extract) {
                    Label("Share Summary", systemImage: "square.and.arrow.up")
                }
            }

            Section("Related Articles") {
                if loadsRelated {
                    ProgressView()
                } else if related.isEmpty {
                    Button("Find Related Articles") {
                        Task { await loadRelated() }
                    }
                } else {
                    ForEach(related.filter { $0.title != summary.title }.prefix(5)) { item in
                        NavigationLink {
                            NativeAppWikipediaArticleLoaderView(
                                title: item.title,
                                languageCode: item.languageCode,
                                searchService: searchService,
                                summaryService: summaryService,
                                store: store
                            )
                        } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(item.title)
                                Text(item.description).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(summary.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    @MainActor
    private func loadRelated() async {
        loadsRelated = true
        defer { loadsRelated = false }
        related = (try? await searchService.search(
            query: summary.title,
            limit: 8,
            languageCode: summary.languageCode
        )) ?? []
    }
}
