import SwiftUI

struct NativeAppSefariaSearchView: View {
    let searchService: NativeAppSefariaSearchService
    let sourceService: NativeAppSefariaSourceService
    @ObservedObject var store: NativeAppSefariaStore
    @Environment(\.nativeAppSession) private var nativeAppSession

    @State private var query: String
    @State private var results: [NativeAppSefariaSearchResult] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var searchTask: Task<Void, Never>?

    init(
        initialQuery: String = "",
        searchService: NativeAppSefariaSearchService,
        sourceService: NativeAppSefariaSourceService,
        store: NativeAppSefariaStore
    ) {
        self.searchService = searchService
        self.sourceService = sourceService
        self.store = store
        _query = State(initialValue: initialQuery)
    }

    var body: some View {
        List {
            Section {
                TextField("Reference, topic or phrase", text: $query)
                    .textInputAutocapitalization(.never)
                    .onSubmit { startSearch() }

                Button {
                    startSearch()
                } label: {
                    Label("Search Sefaria", systemImage: "magnifyingglass")
                }
                .disabled(query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isLoading)
            }

            if isLoading {
                Section { ProgressView("Searching sources…") }
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
                        NativeAppSefariaSourceLoaderView(
                            ref: result.ref,
                            sourceService: sourceService,
                            store: store
                        )
                    } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(result.title).font(.headline)
                            Text(result.ref).font(.caption).foregroundStyle(.secondary)
                            if !result.snippet.isEmpty {
                                Text(result.snippet).font(.subheadline).lineLimit(3)
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
            let newResults = try await searchService.search(query: trimmed, limit: 15)
            guard !Task.isCancelled else { return }
            results = newResults
        } catch {
            guard !Task.isCancelled else { return }
            results = []
            errorMessage = error.localizedDescription
        }
    }
}
