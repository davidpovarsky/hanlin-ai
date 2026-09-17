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

public struct NativeAppWikipediaRootView: View {
    private enum Tab: Hashable { case home, search, saved, settings }

    public let searchService: NativeAppWikipediaSearchService
    public let summaryService: NativeAppWikipediaSummaryService
    public let initialArticleTitle: String?
    public let initialArticleLanguageCode: String?
    public let initialQuery: String?

    @StateObject private var store = NativeAppWikipediaStore()
    @State private var selectedTab: Tab

    public init(
        searchService: NativeAppWikipediaSearchService = NativeAppWikipediaSearchService(),
        summaryService: NativeAppWikipediaSummaryService = NativeAppWikipediaSummaryService(),
        initialArticleTitle: String? = nil,
        initialArticleLanguageCode: String? = nil,
        initialQuery: String? = nil
    ) {
        self.searchService = searchService
        self.summaryService = summaryService
        self.initialArticleTitle = initialArticleTitle
        self.initialArticleLanguageCode = initialArticleLanguageCode
        self.initialQuery = initialQuery
        _selectedTab = State(initialValue: (initialQuery != nil) ? .search : .home)
    }

    public var body: some View {
        if let title = initialArticleTitle {
            NativeAppWikipediaArticleLoaderView(
                title: title,
                languageCode: initialArticleLanguageCode ?? store.language.rawValue,
                searchService: searchService,
                summaryService: summaryService,
                store: store
            )
        } else {
            TabView(selection: $selectedTab) {
                NativeAppWikipediaHomeView(
                    searchService: searchService,
                    summaryService: summaryService,
                    store: store
                )
                .tabItem { Label("Home", systemImage: "house") }
                .tag(Tab.home)

                NativeAppWikipediaSearchView(
                    initialQuery: initialQuery ?? "",
                    searchService: searchService,
                    summaryService: summaryService,
                    store: store
                )
                .tabItem { Label("Search", systemImage: "magnifyingglass") }
                .tag(Tab.search)

                NativeAppWikipediaSavedView(
                    searchService: searchService,
                    summaryService: summaryService,
                    store: store
                )
                .tabItem { Label("Saved", systemImage: "bookmark") }
                .tag(Tab.saved)

                NativeAppWikipediaSettingsView(store: store)
                    .tabItem { Label("Settings", systemImage: "gearshape") }
                    .tag(Tab.settings)
            }
            .navigationTitle("Wikipedia")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

// MARK: - Summary Card

public struct NativeAppWikipediaSummaryCard: View {
    public let summary: NativeAppWikipediaSummary
    public let mode: NativePresentationMode

    public init(summary: NativeAppWikipediaSummary, mode: NativePresentationMode = .fullApp) {
        self.summary = summary
        self.mode = mode
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let thumbnailURL = summary.thumbnailURL {
                AsyncImage(url: thumbnailURL) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    Rectangle().fill(.quaternary)
                }
                .frame(maxWidth: .infinity)
                .frame(height: mode == .chatCard ? 120 : 210)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }

            Label(summary.title, systemImage: "globe")
                .font(.title3.weight(.semibold))

            if let description = summary.description, !description.isEmpty {
                Text(description).font(.subheadline).foregroundStyle(.secondary)
            }

            if !summary.extract.isEmpty {
                Text(summary.extract)
                    .font(mode == .chatCard ? .callout : .body)
                    .textSelection(.enabled)
            }

            if let url = summary.url {
                Link("Open Wikipedia", destination: url)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Article Views

public struct NativeAppWikipediaArticleLoaderView: View {
    public let title: String
    public let languageCode: String
    public let searchService: NativeAppWikipediaSearchService
    public let summaryService: NativeAppWikipediaSummaryService
    @ObservedObject public var store: NativeAppWikipediaStore

    @State private var summary: NativeAppWikipediaSummary?
    @State private var errorMessage: String?

    public init(
        title: String,
        languageCode: String,
        searchService: NativeAppWikipediaSearchService,
        summaryService: NativeAppWikipediaSummaryService,
        store: NativeAppWikipediaStore
    ) {
        self.title = title
        self.languageCode = languageCode
        self.searchService = searchService
        self.summaryService = summaryService
        self.store = store
    }

    public var body: some View {
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

public struct NativeAppWikipediaArticleDetailView: View {
    public let summary: NativeAppWikipediaSummary
    public let searchService: NativeAppWikipediaSearchService
    public let summaryService: NativeAppWikipediaSummaryService
    @ObservedObject public var store: NativeAppWikipediaStore

    @State private var related: [NativeAppWikipediaSearchResult] = []
    @State private var loadsRelated = false

    public init(
        summary: NativeAppWikipediaSummary,
        searchService: NativeAppWikipediaSearchService,
        summaryService: NativeAppWikipediaSummaryService,
        store: NativeAppWikipediaStore
    ) {
        self.summary = summary
        self.searchService = searchService
        self.summaryService = summaryService
        self.store = store
    }

    public var body: some View {
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
                    #if canImport(UIKit)
                    UIPasteboard.general.string = summary.extract
                    #elseif canImport(AppKit)
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(summary.extract, forType: .string)
                    #endif
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

// MARK: - Home View

public struct NativeAppWikipediaHomeView: View {
    public let searchService: NativeAppWikipediaSearchService
    public let summaryService: NativeAppWikipediaSummaryService
    @ObservedObject public var store: NativeAppWikipediaStore

    private let topics = [
        "Computer science", "Artificial intelligence", "Jerusalem", "Science", "History", "Philosophy"
    ]

    public init(
        searchService: NativeAppWikipediaSearchService,
        summaryService: NativeAppWikipediaSummaryService,
        store: NativeAppWikipediaStore
    ) {
        self.searchService = searchService
        self.summaryService = summaryService
        self.store = store
    }

    public var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Explore the World's Knowledge", systemImage: "globe.americas.fill")
                        .font(.title3.weight(.semibold))
                    Text("The full reader and the Assistant tools use the same search and summary services.")
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 6)
            }

            Section("Explore Topics") {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(topics, id: \.self) { topic in
                            NavigationLink {
                                NativeAppWikipediaSearchView(
                                    initialQuery: topic,
                                    searchService: searchService,
                                    summaryService: summaryService,
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
                            NativeAppWikipediaSearchView(
                                initialQuery: query,
                                searchService: searchService,
                                summaryService: summaryService,
                                store: store
                            )
                        } label: {
                            Label(query, systemImage: "clock")
                        }
                    }
                }
            }
        }
        .navigationTitle("Wikipedia")
    }
}

// MARK: - Search View

public struct NativeAppWikipediaSearchView: View {
    public let searchService: NativeAppWikipediaSearchService
    public let summaryService: NativeAppWikipediaSummaryService
    @ObservedObject public var store: NativeAppWikipediaStore

    @State private var query: String
    @State private var results: [NativeAppWikipediaSearchResult] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var searchTask: Task<Void, Never>?

    public init(
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

    public var body: some View {
        List {
            Section {
                TextField("Search Wikipedia", text: $query)
                    .textInputAutocapitalization(.never)
                    .onSubmit { startSearch() }

                Button {
                    startSearch()
                } label: {
                    Label("Search", systemImage: "magnifyingglass")
                }
                .disabled(query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isLoading)
            }

            if isLoading {
                Section { ProgressView("Searching Wikipedia…") }
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
                        VStack(alignment: .leading, spacing: 4) {
                            Text(result.title).font(.headline)
                            if !result.description.isEmpty {
                                Text(result.description).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
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

// MARK: - Saved View

public struct NativeAppWikipediaSavedView: View {
    public let searchService: NativeAppWikipediaSearchService
    public let summaryService: NativeAppWikipediaSummaryService
    @ObservedObject public var store: NativeAppWikipediaStore

    public init(
        searchService: NativeAppWikipediaSearchService,
        summaryService: NativeAppWikipediaSummaryService,
        store: NativeAppWikipediaStore
    ) {
        self.searchService = searchService
        self.summaryService = summaryService
        self.store = store
    }

    public var body: some View {
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
                            if let description = article.description, !description.isEmpty {
                                Text(description).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                            }
                        }
                    }
                }
                .onDelete { offsets in
                    for index in offsets.sorted(by: >) {
                        let article = store.savedArticles[index]
                        store.toggleSaved(article)
                    }
                }
            }
        }
        .navigationTitle("Saved")
    }
}

// MARK: - Settings View

public struct NativeAppWikipediaSettingsView: View {
    @ObservedObject public var store: NativeAppWikipediaStore

    public init(store: NativeAppWikipediaStore) {
        self.store = store
    }

    public var body: some View {
        Form {
            Section("Language") {
                Picker("Language", selection: $store.language) {
                    ForEach(NativeAppWikipediaLanguage.allCases) { language in
                        Text(language.title).tag(language)
                    }
                }
            }

            Section("Data") {
                LabeledContent("Recent Searches", value: "\(store.recentQueries.count)")
                LabeledContent("Saved Articles", value: "\(store.savedArticles.count)")
                Button("Clear Recent Searches", role: .destructive) {
                    store.clearRecentQueries()
                }
                Button("Clear Saved Articles", role: .destructive) {
                    store.clearSavedArticles()
                }
            }

            Section("Architecture") {
                Text("The app UI and Assistant tools both call NativeAppWikipediaSearchService and NativeAppWikipediaSummaryService from Core.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Settings")
    }
}
#endif
