#if canImport(SwiftUI)
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif
#if canImport(AppKit)
import AppKit
#endif

// MARK: - Root View

public struct NativeAppTextStudioRootView: View {
    private enum Tab: Hashable { case editor, analyze, transform, history }

    public let service: NativeAppTextStudioService
    public let storage: any TextStudioStorage
    public let pasteboard: any TextStudioPasteboard
    public let initialText: String?
    public let initialTransform: NativeAppTextStudioTransform?
    public let initialScreen: String?

    @StateObject private var store: NativeAppTextStudioStore
    @State private var selectedTab: Tab = .editor
    @State private var didApplyInitialText = false

    public init(
        service: NativeAppTextStudioService = NativeAppTextStudioService(),
        storage: any TextStudioStorage = UserDefaultsTextStudioStorage(),
        pasteboard: any TextStudioPasteboard = StandardTextStudioPasteboard(),
        initialText: String? = nil,
        initialTransform: NativeAppTextStudioTransform? = nil,
        initialScreen: String? = nil
    ) {
        self.service = service
        self.storage = storage
        self.pasteboard = pasteboard
        self.initialText = initialText
        self.initialTransform = initialTransform
        self.initialScreen = initialScreen
        _store = StateObject(wrappedValue: NativeAppTextStudioStore(storage: storage))
        if let initialScreen {
            switch initialScreen {
            case "editor": _selectedTab = State(initialValue: .editor)
            case "transform": _selectedTab = State(initialValue: .transform)
            default: break
            }
        }
    }

    public var body: some View {
        TabView(selection: $selectedTab) {
            NativeAppTextStudioEditorView(store: store, pasteboard: pasteboard)
                .tabItem { Label("Editor", systemImage: "square.and.pencil") }
                .tag(Tab.editor)

            NativeAppTextStudioAnalysisView(service: service, store: store)
                .tabItem { Label("Analyze", systemImage: "chart.bar.doc.horizontal") }
                .tag(Tab.analyze)

            NativeAppTextStudioTransformView(
                service: service,
                store: store,
                pasteboard: pasteboard,
                initialTransform: initialTransform
            )
            .tabItem { Label("Transform", systemImage: "wand.and.stars") }
            .tag(Tab.transform)

            NativeAppTextStudioHistoryView(store: store)
                .tabItem { Label("History", systemImage: "clock.arrow.circlepath") }
                .tag(Tab.history)
        }
        .navigationTitle("Text Studio")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if !didApplyInitialText, let initialText, !initialText.isEmpty {
                didApplyInitialText = true
                store.draft = initialText
            }
        }
    }
}

// MARK: - Editor View

public struct NativeAppTextStudioEditorView: View {
    @ObservedObject public var store: NativeAppTextStudioStore
    public let pasteboard: any TextStudioPasteboard

    private let sample = "Hanlin Native Apps share one Core between the full app and Assistant tools. Visit https://example.com or email hello@example.com to test extraction."

    public init(
        store: NativeAppTextStudioStore,
        pasteboard: any TextStudioPasteboard = StandardTextStudioPasteboard()
    ) {
        self.store = store
        self.pasteboard = pasteboard
    }

    public var body: some View {
        VStack(spacing: 0) {
            TextEditor(text: $store.draft)
                .font(.body.monospaced())
                .padding(12)
                #if canImport(UIKit)
                .background(Color(uiColor: .secondarySystemGroupedBackground))
                #endif

            Divider()

            HStack {
                Button("Paste") {
                    store.draft = pasteboard.readString() ?? store.draft
                }
                Button("Sample") {
                    store.draft = sample
                }
                Button("Clear", role: .destructive) {
                    store.draft = ""
                }
                Spacer()
                Text("\(store.draft.count) characters")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button {
                    pasteboard.writeString(store.draft)
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .disabled(store.draft.isEmpty)
            }
            .buttonStyle(.bordered)
            .padding()
        }
        .navigationTitle("Editor")
    }
}

// MARK: - Analysis View

public struct NativeAppTextStudioAnalysisView: View {
    public let service: NativeAppTextStudioService
    @ObservedObject public var store: NativeAppTextStudioStore

    @State private var analysis: NativeAppTextStudioAnalysis?

    public init(
        service: NativeAppTextStudioService,
        store: NativeAppTextStudioStore
    ) {
        self.service = service
        self.store = store
    }

    public var body: some View {
        List {
            Section {
                Button {
                    analyze()
                } label: {
                    Label("Analyze Current Draft", systemImage: "chart.bar.doc.horizontal")
                }
                .disabled(store.draft.isEmpty)
            }

            if let analysis {
                Section("Statistics") {
                    LabeledContent("Characters", value: "\(analysis.characters)")
                    LabeledContent("Without Spaces", value: "\(analysis.charactersWithoutSpaces)")
                    LabeledContent("Words", value: "\(analysis.words)")
                    LabeledContent("Sentences", value: "\(analysis.sentences)")
                    LabeledContent("Paragraphs", value: "\(analysis.paragraphs)")
                    LabeledContent("Lines", value: "\(analysis.lines)")
                }

                Section("Top Words") {
                    if analysis.topWords.isEmpty {
                        Text("No repeated words found.").foregroundStyle(.secondary)
                    } else {
                        ForEach(analysis.topWords) { item in
                            LabeledContent(item.word, value: "\(item.count)")
                        }
                    }
                }

                Section("Detected Content") {
                    NativeAppTextStudioDetectedList(title: "Links", values: analysis.links)
                    NativeAppTextStudioDetectedList(title: "Emails", values: analysis.emails)
                    NativeAppTextStudioDetectedList(title: "Numbers", values: analysis.numbers)
                }
            } else {
                Section {
                    ContentUnavailableView(
                        "No Analysis Yet",
                        systemImage: "chart.bar.doc.horizontal",
                        description: Text("Write or paste text in the Editor, then analyze it here.")
                    )
                }
            }
        }
        .navigationTitle("Analyze")
    }

    private func analyze() {
        let value = service.analyze(store.draft)
        analysis = value
        store.addHistory(
            operation: "Analysis",
            input: store.draft,
            output: "Words: \(value.words), Sentences: \(value.sentences), Links: \(value.links.count)"
        )
    }
}

private struct NativeAppTextStudioDetectedList: View {
    let title: String
    let values: [String]

    var body: some View {
        DisclosureGroup("\(title) (\(values.count))") {
            if values.isEmpty {
                Text("None").foregroundStyle(.secondary)
            } else {
                ForEach(values, id: \.self) { value in
                    Text(value).textSelection(.enabled)
                }
            }
        }
    }
}

// MARK: - History View

public struct NativeAppTextStudioHistoryView: View {
    @ObservedObject public var store: NativeAppTextStudioStore

    public init(store: NativeAppTextStudioStore) {
        self.store = store
    }

    public var body: some View {
        List {
            if store.history.isEmpty {
                ContentUnavailableView(
                    "No History",
                    systemImage: "clock.arrow.circlepath",
                    description: Text("Analyses and transformations will appear here.")
                )
            } else {
                ForEach(store.history) { item in
                    NavigationLink {
                        NativeAppTextStudioHistoryDetailView(item: item)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.operation).font(.headline)
                            Text(item.createdAt, style: .date)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(item.output).font(.caption).lineLimit(2)
                        }
                    }
                }
                .onDelete(perform: store.removeHistory)
            }
        }
        .navigationTitle("History")
        .toolbar {
            if !store.history.isEmpty {
                Button("Clear", role: .destructive) { store.clearHistory() }
            }
        }
    }
}

private struct NativeAppTextStudioHistoryDetailView: View {
    let item: NativeAppTextStudioHistoryItem

    var body: some View {
        List {
            Section("Operation") {
                LabeledContent("Name", value: item.operation)
                LabeledContent("Date") { Text(item.createdAt, style: .date) }
            }
            Section("Input") {
                Text(item.input).textSelection(.enabled)
            }
            Section("Output") {
                Text(item.output).textSelection(.enabled)
            }
        }
        .navigationTitle(item.operation)
    }
}

// MARK: - Transform View

public struct NativeAppTextStudioTransformView: View {
    public let service: NativeAppTextStudioService
    @ObservedObject public var store: NativeAppTextStudioStore
    public let pasteboard: any TextStudioPasteboard
    public let initialTransform: NativeAppTextStudioTransform?

    @State private var transform: NativeAppTextStudioTransform
    @State private var output = ""

    public init(
        service: NativeAppTextStudioService,
        store: NativeAppTextStudioStore,
        pasteboard: any TextStudioPasteboard = StandardTextStudioPasteboard(),
        initialTransform: NativeAppTextStudioTransform? = nil
    ) {
        self.service = service
        self.store = store
        self.pasteboard = pasteboard
        self.initialTransform = initialTransform
        _transform = State(initialValue: initialTransform ?? .trimWhitespace)
    }

    public var body: some View {
        List {
            Section("Transformation") {
                Picker("Operation", selection: $transform) {
                    ForEach(NativeAppTextStudioTransform.allCases) { item in
                        Text(item.title).tag(item)
                    }
                }

                Button {
                    runTransform()
                } label: {
                    Label("Run Transformation", systemImage: "wand.and.stars")
                }
                .disabled(store.draft.isEmpty)
            }

            Section("Before") {
                Text(store.draft.isEmpty ? "No text in the editor." : store.draft)
                    .foregroundStyle(store.draft.isEmpty ? .secondary : .primary)
                    .textSelection(.enabled)
            }

            Section("After") {
                Text(output.isEmpty ? "Run a transformation to see the result." : output)
                    .foregroundStyle(output.isEmpty ? .secondary : .primary)
                    .textSelection(.enabled)

                if !output.isEmpty {
                    Button("Replace Draft with Result") {
                        store.draft = output
                    }
                    Button("Copy Result") {
                        pasteboard.writeString(output)
                    }
                }
            }
        }
        .navigationTitle("Transform")
        .task {
            if initialTransform != nil && !store.draft.isEmpty && output.isEmpty {
                runTransform()
            }
        }
    }

    private func runTransform() {
        let result = service.transform(store.draft, using: transform)
        output = result
        store.addHistory(
            operation: transform.title,
            input: store.draft,
            output: result
        )
    }
}
#endif
