import SwiftUI

struct SefariaRootView: View {
    let searchService: SefariaSearchService
    let sourceService: SefariaSourceService
    let context: NativeAppContext

    @State private var query = ""
    @State private var results: [SefariaSearchResult] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        List {
            Section {
                TextField("Search Jewish texts", text: $query)
                    .textInputAutocapitalization(.never)
                    .onSubmit { Task { await search() } }
                Button {
                    Task { await search() }
                } label: {
                    Label("Search", systemImage: "magnifyingglass")
                }
                .disabled(query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isLoading)
            }

            if isLoading {
                Section { ProgressView("Searching...") }
            }

            if let errorMessage {
                Section { Text(errorMessage).foregroundStyle(.red) }
            }

            Section("Results") {
                ForEach(results) { result in
                    NavigationLink {
                        SefariaSourceLoaderView(result: result, sourceService: sourceService)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(result.title).font(.headline)
                            if !result.snippet.isEmpty {
                                Text(result.snippet).font(.caption).foregroundStyle(.secondary).lineLimit(3)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Sefaria")
    }

    @MainActor
    private func search() async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            results = try await searchService.search(query: trimmed, limit: 10)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct SefariaSourceLoaderView: View {
    let result: SefariaSearchResult
    let sourceService: SefariaSourceService
    @State private var source: SefariaSource?
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if let source {
                SefariaSourceCard(source: source, mode: .fullApp)
                    .padding()
            } else if let errorMessage {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text("Unable to load source")
                        .font(.headline)
                    Text(errorMessage)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding()
            } else {
                ProgressView("Loading source...")
            }
        }
        .navigationTitle(result.ref)
        .task {
            do { source = try await sourceService.source(ref: result.ref) }
            catch { errorMessage = error.localizedDescription }
        }
    }
}
