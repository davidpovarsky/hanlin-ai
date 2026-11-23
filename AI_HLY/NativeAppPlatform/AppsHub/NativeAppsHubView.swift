import HanlinLocalization
import HanlinMiniAppCore
import HanlinPlatformContracts
import HanlinScriptStore
import SwiftData
import SwiftUI
import Observation

struct NativeAppsHubView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var launchSession = NativeAppsLaunchSession()

    var body: some View {
        NativeAppsCatalogView(
            prepareCatalog: {
                launchSession.platform.configure(modelContext: modelContext)
                await launchSession.platform.restore()
                await launchSession.refreshCatalog()
            },
            refreshCatalog: { await launchSession.refreshCatalog() },
            onLaunch: launchSession.launch,
            onLaunchPackage: { packageID in
                Task {
                    try? await Task.sleep(for: .milliseconds(350))
                    await launchSession.platform.launch(packageID)
                }
            }
        ) {
            ToolbarItem { EmptyView() }
        }
        .modifier(NativeAppsLaunchPresentation(session: launchSession, observesLibraryLaunches: true))
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
            .alert(Text("Script App Error", bundle: HanlinLocalization.bundle), isPresented: Binding(
                get: { failureMessage != nil },
                set: { if !$0 { clearFailure() } }
            )) {
                Button(hanlin: "OK") { clearFailure() }
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
            HanlinSearchField(text: $searchText, prompt: String(localized: "hanlin.apps.search", bundle: HanlinLocalization.bundle),
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

private extension HanlinScriptingPlatform.Activity {
    var isFailure: Bool { if case .failed = self { true } else { false } }
    var failureMessage: String? { if case let .failed(message) = self { message } else { nil } }
}
