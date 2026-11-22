import HanlinMiniAppCore
import HanlinPlatformContracts
import HanlinScriptStore
import SwiftData
import SwiftUI
import Observation

struct NativeAppsHubView: View {
    @Environment(\.modelContext) private var modelContext

    @State private var searchText = ""
    @State private var isEditingApps = false
    @State private var showsAddSheet = false
    @State private var showsTorahCapture = false
    @State private var scriptingPlatform = HanlinScriptingPlatform.shared
    @State private var miniAppHost = HanlinMiniAppHost.shared
    @State private var launchSession = NativeAppsLaunchSession()
    @State private var informationItem: HanlinMiniAppCatalogItem?
    @State private var scriptingPackageID: HanlinInstalledPackageID?
    @State private var pendingPackageLaunchID: HanlinInstalledPackageID?

    private let columns = [
        GridItem(.adaptive(minimum: 205, maximum: 320), spacing: 20)
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 28) {
                    engineSection(.swift, title: "Swift")
                    engineSection(.scriptingJSC, title: "ScriptUI")
                    engineSection(.nativeScript, title: "NativeScript")
                    engineSection(.expo, title: "Expo")
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 18)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle(String(localized: "Apps"))
            .searchable(text: $searchText, prompt: "hanlin.apps.search")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showsAddSheet = true } label: {
                        Label("Add App", systemImage: "plus")
                    }
                    .accessibilityIdentifier("hanlin-apps-add")
                    .accessibilityLabel("hanlin-apps-add")
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button(isEditingApps ? "Done" : "Edit") { isEditingApps.toggle() }
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button { showsTorahCapture = true } label: {
                        Label("לימוד מצילום", systemImage: "camera.viewfinder")
                    }
                    .accessibilityIdentifier("hanlin-apps-torah-capture")
                }
            }
            .sheet(isPresented: $showsTorahCapture) {
                TorahPhotoStudyCaptureView()
            }
            .overlay {
                if !searchText.isEmpty && filteredItems.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                }
            }
            .sheet(isPresented: $showsAddSheet, onDismiss: {
                refreshCatalog()
                if let packageID = pendingPackageLaunchID {
                    pendingPackageLaunchID = nil
                    if let pkg = scriptingPlatform.installedPackages.first(where: { $0.record.installedPackageID == packageID }),
                       !pkg.hasLaunchableApp {
                        scriptingPackageID = packageID
                    } else {
                        Task {
                            try? await Task.sleep(for: .milliseconds(350))
                            await scriptingPlatform.launch(packageID)
                        }
                    }
                }
            }) {
                NativeAppsAddSheet(
                    items: miniAppHost.items,
                    host: miniAppHost,
                    scriptingPlatform: scriptingPlatform,
                    onLaunchPackage: { packageID in
                        if let pkg = scriptingPlatform.installedPackages.first(where: { $0.record.installedPackageID == packageID }),
                           !pkg.hasLaunchableApp {
                            scriptingPackageID = packageID
                        } else {
                            pendingPackageLaunchID = packageID
                        }
                    }
                )
            }
            .sheet(item: $informationItem) { item in
                MiniAppDescriptorDetailView(item: item)
            }
            .sheet(isPresented: Binding(
                get: { scriptingPackageID != nil },
                set: { if !$0 { scriptingPackageID = nil } }
            )) {
                if let packageID = scriptingPackageID {
                    NavigationStack {
                        ScriptingInstalledPackageDetailView(
                            packageID: packageID,
                            platform: scriptingPlatform
                        )
                    }
                }
            }
            .modifier(NativeAppsLaunchPresentation(session: launchSession, observesLibraryLaunches: true))
            .task {
                scriptingPlatform.configure(modelContext: modelContext)
                await scriptingPlatform.restore()
                await miniAppHost.refresh(installedPackages: scriptingPlatform.installedPackages)
            }
            .onChange(of: scriptingPlatform.installedPackages) { _, packages in
                Task { await miniAppHost.refresh(installedPackages: packages) }
            }
        }
    }

    private var filteredItems: [HanlinMiniAppCatalogItem] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return miniAppHost.visibleItems.filter { item in
            guard !query.isEmpty else { return true }
            let descriptor = item.descriptor
            return [
                descriptor.id.rawValue,
                descriptor.name.preferredValue(forLocale: Locale.current.identifier),
                descriptor.summary.preferredValue(forLocale: Locale.current.identifier),
                descriptor.description.preferredValue(forLocale: Locale.current.identifier),
                descriptor.category.rawValue
            ].joined(separator: " ").localizedStandardContains(query)
        }
    }

    @ViewBuilder
    private func engineSection(_ engine: HanlinMiniAppEngine, title: String) -> some View {
        let values = filteredItems.filter { $0.engine == engine }
        if !values.isEmpty {
            Section {
                LazyVGrid(columns: columns, spacing: 20) {
                    ForEach(values) { item in miniAppCard(item) }
                }
            } header: {
                Text(title)
                    .font(HanlinTypography.title2.bold())
                    .accessibilityIdentifier("hanlin-miniapps-section-\(engine.rawValue)")
            }
        }
    }

    private func miniAppCard(_ item: HanlinMiniAppCatalogItem) -> some View {
        let appName = item.descriptor.name.preferredValue(forLocale: Locale.current.identifier)
        return ZStack(alignment: .topLeading) {
            Button { launch(item) } label: {
                MiniAppCardView(descriptor: item.descriptor, isEditing: isEditingApps)
            }
            .buttonStyle(.plain)
            .disabled(isEditingApps)
            .contextMenu { commonActions(for: item) }
            .accessibilityIdentifier("hanlin-package-card-\(appName)")
            .accessibilityLabel(appName)

            if isEditingApps {
                Button { miniAppHost.setHidden(true, appID: item.id) } label: {
                    Image(systemName: "minus.circle.fill")
                        .font(HanlinTypography.title2)
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, .red)
                }
                .padding(10)
                .accessibilityLabel("Hide \(item.descriptor.name.preferredValue(forLocale: Locale.current.identifier))")
            } else {
                Menu { commonActions(for: item) } label: {
                    Image(systemName: "ellipsis")
                        .font(HanlinTypography.headline)
                        .foregroundStyle(.white)
                        .frame(width: 38, height: 38)
                        .background(.white.opacity(0.18), in: Circle())
                }
                .padding(12)
            }
        }
    }

    @ViewBuilder
    private func commonActions(for item: HanlinMiniAppCatalogItem) -> some View {
        Button { launch(item) } label: { Label("Open", systemImage: "play.fill") }
        if let pkg = scriptingPlatform.installedPackages.first(where: { $0.appID == item.id || $0.record.packageID.rawValue == item.id.rawValue }) {
            Button { scriptingPackageID = pkg.record.installedPackageID } label: {
                Label("Package Information", systemImage: "info.circle")
            }
            .accessibilityIdentifier("hanlin-package-information-menu-item")
        }
        Button { informationItem = item } label: { Label("App Information", systemImage: "info.circle") }
        Divider()
        Button { miniAppHost.setHidden(true, appID: item.id) } label: {
            Label("Hide App", systemImage: "eye.slash")
        }
    }

    private func launch(_ item: HanlinMiniAppCatalogItem) {
        launchSession.launch(item)
    }

    private func refreshCatalog() {
        Task { await miniAppHost.refresh(installedPackages: scriptingPlatform.installedPackages) }
    }
}

/// The launching lifetime belongs to a stable host, not a conditional Morph
/// page. The library and composer reuse the same real engine dispatch path.
@MainActor
@Observable
final class NativeAppsLaunchSession {
    var swiftDestination: HanlinMiniAppHost.SwiftDestination?
    var launchError: String?
    private(set) var ownsScriptPresentation = false
    private(set) var isLaunching = false
    private(set) var isLoading = false
    private var didLoad = false
    let platform = HanlinScriptingPlatform.shared
    let host = HanlinMiniAppHost.shared

    func prepare(modelContext: ModelContext) async {
        guard !didLoad, !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        platform.configure(modelContext: modelContext)
        await platform.restore()
        await host.refresh(installedPackages: platform.installedPackages)
        didLoad = true
    }

    func refreshCatalog() async {
        await host.refresh(installedPackages: platform.installedPackages)
    }

    func launch(_ item: HanlinMiniAppCatalogItem) {
        guard !isLaunching, swiftDestination == nil else { return }
        isLaunching = true
        launchError = nil
        Task { @MainActor in
            defer { isLaunching = false }
            do {
                switch item.engine {
                case .swift:
                    swiftDestination = try host.swiftDestination(for: item)
                case .nativeScript:
                    ownsScriptPresentation = true
                    try await host.launchNativeScript(item, platform: platform)
                case .expo:
                    ownsScriptPresentation = true
                    try await host.launchExpo(item, platform: platform)
                case .scriptingJSC:
                    ownsScriptPresentation = true
                    try await host.launchScriptingJSC(item, platform: platform)
                }
            } catch {
                ownsScriptPresentation = false
                launchError = error.localizedDescription
            }
        }
    }

    var hasActiveScriptApplication: Bool {
        platform.activeApplicationModel != nil || platform.activeNativeScriptController != nil
            || platform.activeExpoController != nil
    }

    var isScriptPresented: Bool { ownsScriptPresentation && hasActiveScriptApplication }

    func dismissScript() {
        guard ownsScriptPresentation else { return }
        ownsScriptPresentation = false
        platform.dismissActiveApplication()
    }

    func clearFailure() {
        launchError = nil
        if ownsScriptPresentation { platform.clearFailure() }
    }

    var failureMessage: String? {
        launchError ?? (ownsScriptPresentation ? platform.activity.failureMessage : nil)
    }
}

/// Apply to ChatViewBottom itself (or the library screen), never to a page that
/// disappears when the user navigates inside the action bubble.
struct NativeAppsLaunchPresentation: ViewModifier {
    @Bindable var session: NativeAppsLaunchSession
    var observesLibraryLaunches = false

    private var failureMessage: String? {
        session.failureMessage ?? (observesLibraryLaunches ? session.platform.activity.failureMessage : nil)
    }

    private func clearFailure() {
        session.clearFailure()
        if observesLibraryLaunches { session.platform.clearFailure() }
    }

    func body(content: Content) -> some View {
        content
            .fullScreenCover(item: $session.swiftDestination) { destination in
                destination.view
            }
            .fullScreenCover(isPresented: Binding(
                get: { session.isScriptPresented || (observesLibraryLaunches && session.hasActiveScriptApplication) },
                set: { if !$0 {
                    if observesLibraryLaunches { session.platform.dismissActiveApplication() }
                    session.dismissScript()
                } }
            )) {
                ScriptingApplicationContainerView(platform: session.platform)
            }
            .alert("Script App Error", isPresented: Binding(
                get: { failureMessage != nil },
                set: { if !$0 { clearFailure() } }
            )) {
                Button("OK") { clearFailure() }
            } message: {
                Text(failureMessage ?? "The app could not be opened.")
            }
    }
}

/// Launch-only catalogue in the bubble's existing measured scroll view. No
/// nested sheet, navigation bar, editing, import or package-management menus.
struct NativeAppsComposerPage: View {
    let session: NativeAppsLaunchSession
    @Environment(\.modelContext) private var modelContext
    @State private var searchText = ""

    private var filteredItems: [HanlinMiniAppCatalogItem] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return session.host.visibleItems.filter { item in
            query.isEmpty || [
                item.descriptor.name.preferredValue(forLocale: Locale.current.identifier),
                item.descriptor.summary.preferredValue(forLocale: Locale.current.identifier)
            ].joined(separator: " ").localizedStandardContains(query)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: HanlinControlMetrics.sectionSpacing) {
            HanlinSearchField(text: $searchText, prompt: String(localized: "hanlin.apps.search"),
                              accessibilityIdentifier: "hanlin-composer-mini-apps-search")
            if session.isLoading && session.host.visibleItems.isEmpty {
                ProgressView().frame(maxWidth: .infinity)
            } else if filteredItems.isEmpty {
                ContentUnavailableView.search(text: searchText)
            } else {
                appSection(.swift, title: "Swift")
                appSection(.scriptingJSC, title: "ScriptUI")
                appSection(.nativeScript, title: "NativeScript")
                appSection(.expo, title: "Expo")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("hanlin-composer-mini-apps-page")
        .task { await session.prepare(modelContext: modelContext) }
        .onChange(of: session.platform.installedPackages) { _, _ in
            Task { await session.refreshCatalog() }
        }
    }

    @ViewBuilder
    private func appSection(_ engine: HanlinMiniAppEngine, title: String) -> some View {
        let items = filteredItems.filter { $0.engine == engine }
        if !items.isEmpty {
            Text(title).font(HanlinTypography.headline)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 180, maximum: 320), spacing: 12)], spacing: 12) {
                ForEach(items) { item in
                    Button { session.launch(item) } label: {
                        MiniAppCardView(descriptor: item.descriptor, isEditing: false)
                    }
                    .buttonStyle(.plain)
                    .disabled(session.isLaunching)
                    .accessibilityIdentifier("hanlin-composer-mini-app-\(item.id.rawValue)")
                    .accessibilityLabel(item.descriptor.name.preferredValue(forLocale: Locale.current.identifier))
                }
            }
        }
    }
}

private struct MiniAppDescriptorDetailView: View {
    let item: HanlinMiniAppCatalogItem
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Mini App") {
                    LabeledContent("Name", value: item.descriptor.name.preferredValue(forLocale: Locale.current.identifier))
                    LabeledContent("ID", value: item.id.rawValue)
                    LabeledContent("Engine", value: item.engine.displayName)
                    LabeledContent("Version", value: item.descriptor.version.rawValue)
                }
                Section("Canonical entrypoints") {
                    ForEach(Array(item.descriptor.entryPoints.enumerated()), id: \.offset) { _, entrypoint in
                        LabeledContent(entrypoint.kind.rawValue, value: entrypoint.runtimeProfile?.rawValue ?? "compiled-swift")
                    }
                }
                Section("Capabilities") {
                    ForEach(item.descriptor.capabilities, id: \.id) { capability in
                        Text(capability.id.rawValue)
                    }
                }
            }
            .navigationTitle("App Information")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}

private extension HanlinScriptingPlatform.Activity {
    var isFailure: Bool { if case .failed = self { true } else { false } }
    var failureMessage: String? { if case let .failed(message) = self { message } else { nil } }
}
