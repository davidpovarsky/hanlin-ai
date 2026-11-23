#if canImport(SwiftUI)
import SwiftUI
import HanlinMiniAppsBridge

/// The same native chooser is embedded by every source app. It only writes the
/// transport request and opens MiniApps; no runtime enters the source process.
@MainActor
public struct MiniAppPicker: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @Environment(\.scenePhase) private var scenePhase
    @State private var catalog: [MiniAppCatalogItem] = []
    @State private var preferences = MiniAppPreferences()
    @State private var errorMessage: String?
    @State private var isLoading = true
    @State private var isLaunching = false

    private let storage: MiniAppPickerStorage
    private let source: MiniAppSourceContext
    private let inputs: [MiniAppContent]
    private let operation: MiniAppOperation
    private let callbacks: MiniAppCallbacks
    private let onOpen: (URL) -> Void
    private let onError: (Error) -> Void

    public init(store: MiniAppBridgeStore, source: MiniAppSourceContext, inputs: [MiniAppContent],
                operation: MiniAppOperation = .display, callbacks: MiniAppCallbacks = .init(),
                onOpen: @escaping (URL) -> Void, onError: @escaping (Error) -> Void = { _ in }) {
        storage = MiniAppPickerStorage(store: store)
        self.source = source; self.inputs = inputs; self.operation = operation
        self.callbacks = callbacks; self.onOpen = onOpen; self.onError = onError
    }

    public var body: some View {
        NavigationStack {
            List {
                if let title = source.documentTitle {
                    Section {
                        Label(title, systemImage: "doc.text")
                        if let selection = source.selection, !selection.text.isEmpty {
                            Text(selection.text).lineLimit(3).foregroundStyle(.secondary)
                        }
                    }
                }
                Section {
                    if isLoading {
                        ProgressView().accessibilityLabel(MiniAppPickerText.string("Loading MiniApps"))
                    } else if catalog.isEmpty {
                        ContentUnavailableView(MiniAppPickerText.string("No MiniApps yet"),
                            systemImage: "square.grid.2x2",
                            description: Text(MiniAppPickerText.string("Open MiniApps to refresh your apps.")))
                        Button(MiniAppPickerText.string("Open MiniApps"), systemImage: "arrow.up.forward.app") {
                            if let url = URL(string: "hanlinminiapps://") { onOpen(url) }
                        }
                    } else {
                        ScrollView(.horizontal) {
                            HStack(alignment: .top, spacing: 20) {
                                ForEach(quickItems) { item in
                                    Button { launch(item) } label: {
                                        VStack(spacing: 8) {
                                            Image(systemName: item.systemImage)
                                                .font(.title2).frame(width: 52, height: 52)
                                                .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
                                            Text(item.title(locale: locale)).font(.caption).lineLimit(2)
                                                .multilineTextAlignment(.center).frame(maxWidth: 76)
                                        }
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityIdentifier("miniapps-launch-\(item.id)")
                                    .disabled(isLaunching)
                                }
                            }.padding(.vertical, 8)
                        }
                        NavigationLink {
                            MiniAppPickerEditor(catalog: catalog, preferences: $preferences,
                                onLaunch: launch, onChange: change)
                        } label: {
                            Label(MiniAppPickerText.string("More"), systemImage: "ellipsis.circle")
                        }
                        .accessibilityIdentifier("miniapps-more")
                    }
                } header: { Text(MiniAppPickerText.string("MiniApps")) }
            }
            .navigationTitle(MiniAppPickerText.string("MiniApps"))
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(MiniAppPickerText.string("Done")) { dismiss() }
                }
            }
            .alert(MiniAppPickerText.string("MiniApps"), isPresented: Binding(
                get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } }
            )) {
                Button(MiniAppPickerText.string("OK"), role: .cancel) { errorMessage = nil }
            } message: { Text(errorMessage ?? "") }
        }
        .task { await refresh() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await refresh() } }
        }
    }

    private var quickItems: [MiniAppCatalogItem] {
        let visible = preferences.orderedItems(catalog).filter { $0.accepts(inputs) }
        let favorites = visible.filter { preferences.favorites.contains($0.id) }
        return favorites.isEmpty ? Array(visible.prefix(6)) : favorites
    }

    private func refresh() async {
        do {
            let snapshot = try await storage.snapshot()
            catalog = snapshot.items; preferences = snapshot.preferences; isLoading = false
        } catch { isLoading = false; report(error) }
    }

    private func launch(_ item: MiniAppCatalogItem) {
        guard !isLaunching else { return }
        isLaunching = true
        Task {
            do {
                let current = try await storage.currentPreferences()
                let request = MiniAppInvocation(appID: item.id, actionID: item.actionID,
                    source: source, inputs: inputs, operation: operation, callbacks: callbacks,
                    opensInNewWindow: current.opensInNewWindow)
                let url = try await storage.enqueue(request)
                isLaunching = false
                dismiss()
                onOpen(url)
            } catch { isLaunching = false; report(error) }
        }
    }

    private func change(_ change: MiniAppPickerChange) async throws -> MiniAppPreferences {
        let updated = try await storage.change(change)
        preferences = updated
        return updated
    }

    private func report(_ error: Error) {
        errorMessage = error.localizedDescription
        onError(error)
    }
}


/// Embeds in the caller's NavigationStack. Shares the same catalog editor and
/// preferences with every source app, including the new-window option.
@MainActor
public struct MiniAppPreferencesView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var catalog: [MiniAppCatalogItem] = []
    @State private var preferences = MiniAppPreferences()
    @State private var loading = true
    @State private var errorMessage: String?
    private let storage: MiniAppPickerStorage

    public init(store: MiniAppBridgeStore) { storage = MiniAppPickerStorage(store: store) }

    public var body: some View {
        Group {
            if loading { ProgressView() }
            else {
                MiniAppPickerEditor(catalog: catalog, preferences: $preferences,
                    onLaunch: nil, onChange: change)
            }
        }
        .navigationTitle(MiniAppPickerText.string("MiniApps"))
        .task { await refresh() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await refresh() } }
        }
        .alert(MiniAppPickerText.string("MiniApps"), isPresented: Binding(
            get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } }
        )) {
            Button(MiniAppPickerText.string("OK"), role: .cancel) { errorMessage = nil }
        } message: { Text(errorMessage ?? "") }
    }

    private func refresh() async {
        do {
            let snapshot = try await storage.snapshot()
            catalog = snapshot.items; preferences = snapshot.preferences; loading = false
        } catch { loading = false; errorMessage = error.localizedDescription }
    }

    private func change(_ change: MiniAppPickerChange) async throws -> MiniAppPreferences {
        let updated = try await storage.change(change)
        preferences = updated
        return updated
    }
}

@MainActor
private struct MiniAppPickerEditor: View {
    @Environment(\.locale) private var locale
    #if os(iOS)
    @State private var nativeEditMode: EditMode = .inactive
    #else
    @State private var editing = false
    #endif
    @Binding var preferences: MiniAppPreferences
    @State private var errorMessage: String?
    let catalog: [MiniAppCatalogItem]
    let onLaunch: ((MiniAppCatalogItem) -> Void)?
    let onChange: (MiniAppPickerChange) async throws -> MiniAppPreferences

    init(catalog: [MiniAppCatalogItem], preferences: Binding<MiniAppPreferences>,
         onLaunch: ((MiniAppCatalogItem) -> Void)?,
         onChange: @escaping (MiniAppPickerChange) async throws -> MiniAppPreferences) {
        self.catalog = catalog; _preferences = preferences
        self.onLaunch = onLaunch; self.onChange = onChange
    }

    var body: some View {
        #if os(iOS)
        editorList.environment(\.editMode, $nativeEditMode)
        #else
        editorList
        #endif
    }

    private var editorList: some View {
        List {
            Section(MiniAppPickerText.string("Favorites")) {
                ForEach(favorites) { item in
                    if let onLaunch {
                        Button { onLaunch(item) } label: { row(item) }.buttonStyle(.plain)
                    } else { row(item) }
                }
                .onDelete { offsets in
                    let ids = offsets.map { favorites[$0].id }
                    update(.removeFavorites(ids))
                }
                .onMove { offsets, destination in
                    var draft = preferences
                    // Move the visible favorites while preserving absent installed-app IDs.
                    draft.favorites = favorites.map(\.id)
                    draft.moveFavorites(fromOffsets: offsets, toOffset: destination)
                    update(.order(draft.favorites))
                }
            }
            Section(MiniAppPickerText.string("Suggestions")) {
                ForEach(others) { item in
                    HStack {
                        if isEditing {
                            Button {
                                update(.favorite(item.id, true))
                            } label: {
                                Image(systemName: "plus.circle.fill").foregroundStyle(.green)
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel(MiniAppPickerText.string("Add to Favorites") + ": " + item.title(locale: locale))
                        }
                        if let onLaunch {
                            Button { onLaunch(item) } label: { row(item) }.buttonStyle(.plain)
                        } else { row(item) }
                        if isEditing {
                            Toggle(MiniAppPickerText.string("Show") + " " + item.title(locale: locale),
                                isOn: Binding(get: { !preferences.hidden.contains(item.id) },
                                              set: { update(.visible(item.id, $0)) }))
                                .labelsHidden()
                                .accessibilityIdentifier("miniapps-visible-\(item.id)")
                        }
                    }
                }
            }
            Section {
                Toggle(MiniAppPickerText.string("Open shared MiniApps in a new window"),
                    isOn: Binding(get: { preferences.opensInNewWindow },
                                  set: { update(.newWindow($0)) }))
                    .accessibilityIdentifier("miniapps-new-window")
            } footer: {
                Text(MiniAppPickerText.string("On devices with multiple windows. Other devices use the current window."))
            }
        }
        .navigationTitle(MiniAppPickerText.string("Apps"))
        .toolbar {
            #if os(iOS)
            EditButton()
            #else
            Button(MiniAppPickerText.string(editing ? "Done" : "Edit")) { editing.toggle() }
            #endif
        }
        .alert(MiniAppPickerText.string("MiniApps"), isPresented: Binding(
            get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } }
        )) {
            Button(MiniAppPickerText.string("OK"), role: .cancel) { errorMessage = nil }
        } message: { Text(errorMessage ?? "") }
    }

    private var isEditing: Bool {
        #if os(iOS)
        nativeEditMode.isEditing
        #else
        editing
        #endif
    }
    private var favorites: [MiniAppCatalogItem] {
        preferences.orderedItems(catalog).filter { preferences.favorites.contains($0.id) }
    }
    private var others: [MiniAppCatalogItem] {
        catalog.filter { !preferences.favorites.contains($0.id) && (isEditing || !preferences.hidden.contains($0.id)) }
    }
    private func row(_ item: MiniAppCatalogItem) -> some View {
        Label {
            VStack(alignment: .leading) {
                Text(item.title(locale: locale))
                if let subtitle = item.subtitle { Text(subtitle).font(.caption).foregroundStyle(.secondary) }
            }
        } icon: { Image(systemName: item.systemImage) }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    private func update(_ change: MiniAppPickerChange) {
        Task {
            do { preferences = try await onChange(change) }
            catch { errorMessage = error.localizedDescription }
        }
    }
}

private enum MiniAppPickerChange: Sendable {
    case favorite(String, Bool), visible(String, Bool), removeFavorites([String]), order([String]), newWindow(Bool)
    func apply(to preferences: inout MiniAppPreferences) {
        switch self {
        case let .favorite(id, value): preferences.setFavorite(id, value)
        case let .visible(id, value): preferences.setVisible(id, value)
        case let .removeFavorites(ids): preferences.favorites.removeAll { ids.contains($0) }
        case let .order(ids):
            preferences.favorites = ids + preferences.favorites.filter { !ids.contains($0) }
        case let .newWindow(value): preferences.opensInNewWindow = value
        }
    }
}

private actor MiniAppPickerStorage {
    struct Snapshot: Sendable { let items: [MiniAppCatalogItem]; let preferences: MiniAppPreferences }
    let store: MiniAppBridgeStore
    init(store: MiniAppBridgeStore) { self.store = store }
    func snapshot() throws -> Snapshot { .init(items: try store.loadCatalog(), preferences: try store.preferences()) }
    func currentPreferences() throws -> MiniAppPreferences { try store.preferences() }
    func enqueue(_ request: MiniAppInvocation) throws -> URL { try store.enqueue(request) }
    func change(_ change: MiniAppPickerChange) throws -> MiniAppPreferences {
        try store.updatePreferences { change.apply(to: &$0) }
        return try store.preferences()
    }
}

private enum MiniAppPickerText {
    static func string(_ key: String) -> String {
        NSLocalizedString(key, bundle: .module, comment: "")
    }
}
#endif
