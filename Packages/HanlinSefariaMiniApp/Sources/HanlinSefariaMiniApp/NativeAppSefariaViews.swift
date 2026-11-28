#if canImport(SwiftUI)
import SwiftUI
import HanlinMiniAppCore
#if canImport(UIKit)
import UIKit
#endif
#if canImport(AppKit)
import AppKit
#endif

// MARK: - Root View

public struct NativeAppSefariaRootView: View {
    private enum Tab: Hashable { case home, search, saved, settings }

    public let searchService: NativeAppSefariaSearchService
    public let sourceService: NativeAppSefariaSourceService
    public let initialQuery: String?
    public let initialReference: String?

    @StateObject private var store = NativeAppSefariaStore()
    @State private var selectedTab: Tab

    public init(
        searchService: NativeAppSefariaSearchService = NativeAppSefariaSearchService(),
        sourceService: NativeAppSefariaSourceService = NativeAppSefariaSourceService(),
        initialQuery: String? = nil,
        initialReference: String? = nil
    ) {
        self.searchService = searchService
        self.sourceService = sourceService
        self.initialQuery = initialQuery
        self.initialReference = initialReference
        _selectedTab = State(initialValue: (initialQuery != nil) ? .search : .home)
    }

    public var body: some View {
        if let ref = initialReference {
            NativeAppSefariaSourceLoaderView(ref: ref, sourceService: sourceService, store: store)
        } else {
            TabView(selection: $selectedTab) {
                NativeAppSefariaHomeView(
                    searchService: searchService,
                    sourceService: sourceService,
                    store: store
                )
                .tabItem { Label("Home", systemImage: "house") }
                .tag(Tab.home)

                NativeAppSefariaSearchView(
                    initialQuery: initialQuery ?? "",
                    searchService: searchService,
                    sourceService: sourceService,
                    store: store
                )
                .tabItem { Label("Search", systemImage: "magnifyingglass") }
                .tag(Tab.search)

                NativeAppSefariaSavedView(
                    sourceService: sourceService,
                    store: store
                )
                .tabItem { Label("Saved", systemImage: "bookmark") }
                .tag(Tab.saved)

                NativeAppSefariaSettingsView(store: store)
                    .tabItem { Label("Settings", systemImage: "gearshape") }
                    .tag(Tab.settings)
            }
            .navigationTitle("Sefaria")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

// MARK: - Home View

public struct NativeAppSefariaHomeView: View {
    public let searchService: NativeAppSefariaSearchService
    public let sourceService: NativeAppSefariaSourceService
    @ObservedObject public var store: NativeAppSefariaStore

    private let topics = [
        "Charity", "Prayer", "Shabbat", "Returning lost objects", "Kindness", "Jerusalem"
    ]

    public init(
        searchService: NativeAppSefariaSearchService,
        sourceService: NativeAppSefariaSourceService,
        store: NativeAppSefariaStore
    ) {
        self.searchService = searchService
        self.sourceService = sourceService
        self.store = store
    }

    public var body: some View {
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
                            Label(query, systemImage: "clock")
                        }
                    }
                }
            }
        }
        .navigationTitle("Sefaria")
    }
}

// MARK: - Search View

public struct NativeAppSefariaSearchView: View {
    public let searchService: NativeAppSefariaSearchService
    public let sourceService: NativeAppSefariaSourceService
    @ObservedObject public var store: NativeAppSefariaStore

    @State private var query: String
    @State private var results: [NativeAppSefariaSearchResult] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var searchTask: Task<Void, Never>?

    public init(
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

    public var body: some View {
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
        searchTask = Task {
            await search()
        }
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

// MARK: - Saved View

public struct NativeAppSefariaSavedView: View {
    public let sourceService: NativeAppSefariaSourceService
    @ObservedObject public var store: NativeAppSefariaStore

    public init(sourceService: NativeAppSefariaSourceService, store: NativeAppSefariaStore) {
        self.sourceService = sourceService
        self.store = store
    }

    public var body: some View {
        List {
            if store.savedSources.isEmpty {
                ContentUnavailableView(
                    "No Saved Sources",
                    systemImage: "bookmark",
                    description: Text("Open a source and tap Bookmark.")
                )
            } else {
                ForEach(store.savedSources) { source in
                    NavigationLink {
                        NativeAppSefariaSourceDetailView(source: source, store: store)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(source.ref).font(.headline)
                            Text(source.combinedText)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(3)
                        }
                    }
                }
                .onDelete { offsets in
                    for index in offsets.sorted(by: >) {
                        let source = store.savedSources[index]
                        store.toggleSaved(source)
                    }
                }
            }
        }
        .navigationTitle("Saved")
    }
}

// MARK: - Settings View

public struct NativeAppSefariaSettingsView: View {
    @ObservedObject public var store: NativeAppSefariaStore

    public init(store: NativeAppSefariaStore) {
        self.store = store
    }

    public var body: some View {
        Form {
            Section("Reading") {
                Picker("Text Language", selection: $store.preferredLanguage) {
                    ForEach(NativeAppSefariaLanguage.allCases) { language in
                        Text(language.title).tag(language)
                    }
                }
            }

            Section("Data") {
                LabeledContent("Recent Searches", value: "\(store.recentQueries.count)")
                LabeledContent("Saved Sources", value: "\(store.savedSources.count)")
                Button("Clear Recent Searches", role: .destructive) {
                    store.clearRecentQueries()
                }
                Button("Clear Saved Sources", role: .destructive) {
                    store.clearSavedSources()
                }
            }

            Section("Architecture") {
                Text("Views, Assistant tools and chat cards all consume NativeAppSefariaSearchService and NativeAppSefariaSourceService from Core.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Settings")
    }
}

// MARK: - Source Views & Cards

public struct NativeAppSefariaSourceCard: View {
    public let source: NativeAppSefariaSource
    public let language: NativeAppSefariaLanguage
    public let mode: NativePresentationMode

    public init(
        source: NativeAppSefariaSource,
        language: NativeAppSefariaLanguage = .bilingual,
        mode: NativePresentationMode = .fullApp
    ) {
        self.source = source
        self.language = language
        self.mode = mode
    }

    public var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                Label(source.ref, systemImage: "book.closed")
                    .font(.headline)

                if language != .english,
                   let hebrew = source.heText,
                   !hebrew.isEmpty {
                    Text(hebrew)
                        .font(mode == .chatCard ? .callout : .body)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .environment(\.layoutDirection, .rightToLeft)
                        .textSelection(.enabled)
                }

                if language != .hebrew, !source.text.isEmpty {
                    Text(source.text)
                        .font(mode == .chatCard ? .callout : .body)
                        .textSelection(.enabled)
                }
            }
        }
    }
}

public struct NativeAppSefariaSourceLoaderView: View {
    public let ref: String
    public let sourceService: NativeAppSefariaSourceService
    @ObservedObject public var store: NativeAppSefariaStore

    @State private var source: NativeAppSefariaSource?
    @State private var errorMessage: String?

    public init(
        ref: String,
        sourceService: NativeAppSefariaSourceService,
        store: NativeAppSefariaStore
    ) {
        self.ref = ref
        self.sourceService = sourceService
        self.store = store
    }

    public var body: some View {
        Group {
            if let source {
                NativeAppSefariaSourceDetailView(source: source, store: store)
            } else if let errorMessage {
                ContentUnavailableView(
                    "Unable to Load Source",
                    systemImage: "exclamationmark.triangle",
                    description: Text(errorMessage)
                )
            } else {
                ProgressView("Loading \(ref)…")
            }
        }
        .navigationTitle(ref)
        .task {
            do { source = try await sourceService.source(ref: ref) }
            catch { errorMessage = error.localizedDescription }
        }
    }
}

public struct NativeAppSefariaSourceDetailView: View {
    public let source: NativeAppSefariaSource
    @ObservedObject public var store: NativeAppSefariaStore

    public init(source: NativeAppSefariaSource, store: NativeAppSefariaStore) {
        self.source = source
        self.store = store
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                NativeAppSefariaSourceCard(
                    source: source,
                    language: store.preferredLanguage,
                    mode: .fullApp
                )

                HStack {
                    Button {
                        store.toggleSaved(source)
                    } label: {
                        Label(
                            store.isSaved(source) ? "Remove Bookmark" : "Bookmark",
                            systemImage: store.isSaved(source) ? "bookmark.fill" : "bookmark"
                        )
                    }

                    Button {
                        #if canImport(UIKit)
                        UIPasteboard.general.string = source.combinedText
                        #elseif canImport(AppKit)
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(source.combinedText, forType: .string)
                        #endif
                    } label: {
                        Label("Copy", systemImage: "doc.on.doc")
                    }

                    if let url = source.url {
                        Link(destination: url) {
                            Label("Open in Sefaria", systemImage: "arrow.up.right.square")
                        }
                    }
                }
                .buttonStyle(.bordered)
            }
            .padding()
        }
        .navigationTitle(source.ref)
        .navigationBarTitleDisplayMode(.inline)
    }
}
#endif
