import SwiftUI

struct WikipediaRootView: View {
    let searchService: WikipediaSearchService
    let summaryService: NativeAppWikipediaSummaryService
    let context: NativeAppContext

    @State private var query = ""
    @State private var results: [NativeAppWikipediaSearchResult] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        List {
            Section {
                TextField("Search Wikipedia", text: $query)
                    .textInputAutocapitalization(.never)
                    .onSubmit { Task { await search() } }
                Button { Task { await search() } } label: {
                    Label("Search", systemImage: "magnifyingglass")
                }
                .disabled(query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isLoading)
            }

            if isLoading { Section { ProgressView("Searching...") } }
            if let errorMessage { Section { Text(errorMessage).foregroundStyle(.red) } }

            Section("Results") {
                ForEach(results) { result in
                    NavigationLink {
                        NativeAppWikipediaSummaryLoaderView(title: result.title, summaryService: summaryService)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(result.title).font(.headline)
                            if !result.description.isEmpty {
                                Text(result.description).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Wikipedia")
    }

    @MainActor
    private func search() async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do { results = try await searchService.search(query: trimmed, limit: 10) }
        catch { errorMessage = error.localizedDescription }
    }
}

private struct NativeAppWikipediaSummaryLoaderView: View {
    let title: String
    let summaryService: NativeAppWikipediaSummaryService
    @State private var summary: NativeAppWikipediaSummary?
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if let summary {
                NativeAppWikipediaSummaryCard(summary: summary, mode: .fullApp).padding()
            } else if let errorMessage {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text("Unable to load article")
                        .font(.headline)
                    Text(errorMessage)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding()
            } else {
                ProgressView("Loading summary...")
            }
        }
        .navigationTitle(title)
        .task {
            do { summary = try await summaryService.summary(title: title) }
            catch { errorMessage = error.localizedDescription }
        }
    }
}
