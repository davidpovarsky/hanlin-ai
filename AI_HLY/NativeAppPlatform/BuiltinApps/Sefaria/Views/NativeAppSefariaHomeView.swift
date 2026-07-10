import SwiftUI

struct NativeAppSefariaHomeView: View {
    let searchService: NativeAppSefariaSearchService
    let sourceService: NativeAppSefariaSourceService
    @ObservedObject var store: NativeAppSefariaStore

    private let topics = [
        "Charity", "Prayer", "Shabbat", "Returning lost objects", "Kindness", "Jerusalem"
    ]

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Jewish texts, one shared Core", systemImage: "books.vertical")
                        .font(.title3.weight(.semibold))
                    Text("The full reader and the Assistant tools use the same search and source services.")
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 6)
            }

            Section("Explore Topics") {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(topics, id: \.self) { topic in
                            NavigationLink {
                                NativeAppSefariaSearchView(
                                    initialQuery: topic,
                                    searchService: searchService,
                                    sourceService: sourceService,
                                    store: store
                                )
                            } label: {
                                Label(topic, systemImage: "sparkles")
                                    .padding(.horizontal, 13)
                                    .padding(.vertical, 9)
                                    .background(.thinMaterial, in: Capsule())
                            }
                            .buttonStyle(.plain)
                        }
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
                            NativeAppSefariaSearchView(
                                initialQuery: query,
                                searchService: searchService,
                                sourceService: sourceService,
                                store: store
                            )
                        } label: {
                            Label(query, systemImage: "clock.arrow.circlepath")
                        }
                    }
                }
            }

            Section("Saved Sources") {
                if store.savedSources.isEmpty {
                    Text("Bookmark a source to keep it here.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(store.savedSources.prefix(3)) { source in
                        NavigationLink {
                            NativeAppSefariaSourceDetailView(source: source, store: store)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(source.ref).font(.headline)
                                Text(source.combinedText)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Sefaria")
    }
}
