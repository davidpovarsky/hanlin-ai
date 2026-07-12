import SwiftUI

struct NativeAppWikipediaSearchView: View {
    let searchService: NativeAppWikipediaSearchService
    let summaryService: NativeAppWikipediaSummaryService
    @ObservedObject var store: NativeAppWikipediaStore
    @Environment(\.nativeAppSession) private var nativeAppSession

    @State private var query: String
    @State private var results: [NativeAppWikipediaSearchResult] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var searchTask: Task<Void, Never>?

    init(
        initialQuery: String = "",
        searchService: NativeAppWikipediaSearchService,
        summaryService: NativeAppWikipediaSummaryService,
        store: NativeAppWikipediaStore
    ) {
        self.searchService = searchService
        self.summaryService = summaryService
        self.store = store
        _query = State(initialValue: initialQuery)
    }

    var body: some View {
        List {
            Section {
                TextField("Search Wikipedia", text: $query)
                    .textInputAutocapitalization(.never)
                    .onSubmit { startSearch() }

                HStack {
                    Button {
                        startSearch()
                    } label: {
                        Label("Search", systemImage: "magnifyingglass")
                    }
                    .disabled(query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isLoading)

                    Spacer()
                    Text(store.language.title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if isLoading {
                Section { ProgressView("Searching…") }
            }

            if let errorMessage {
                Section {
                    Label(errorMessage, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                }
            }

            Section("Results") {
                if !isLoading && results.isEmpty {
                    Text(query.isEmpty ? "Enter a search above." : "No results yet.")
                        .foregroundStyle(.secondary)
                }

                ForEach(results) { result in
                    NavigationLink {
                        NativeAppWikipediaArticleLoaderView(
                            title: result.title,
                            languageCode: result.languageCode,
                            searchService: searchService,
                            summaryService: summaryService,
                            store: store
                        )
                    } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(result.title).font(.headline)
                            if !result.description.isEmpty {
                                Text(result.description).font(.subheadline).foregroundStyle(.secondary).lineLimit(3)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
        .navigationTitle("Search")
        .task {
            if !query.isEmpty && results.isEmpty {
                startSearch()
            }
        }
        .onDisappear {
            searchTask?.cancel()
        }
    }

    private func startSearch() {
        searchTask?.cancel()
        let task = Task {
            await search()
        }
        searchTask = task
        nativeAppSession?.track(task)
    }

    @MainActor
    private func search() async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        store.addRecentQuery(trimmed)
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let newResults = try await searchService.search(
                query: trimmed,
                limit: 15,
                languageCode: store.language.rawValue
            )
            guard !Task.isCancelled else { return }
            results = newResults
        } catch {
            guard !Task.isCancelled else { return }
            results = []
            errorMessage = error.localizedDescription
        }
    }
}
