import HanlinLocalization
import HanlinMiniAppCore
import HanlinPlatformContracts
import HanlinChatUI
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
/// page. Only the app library uses this foreground launch path.
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

/// Only manifest-declared assistant capabilities are selectable in chat.
/// Preparing the catalog never opens the app's foreground entrypoint.
struct NativeAppsComposerPage: View {
    let session: NativeAppsLaunchSession
    let capabilities: [HanlinComposerCapabilityDescriptor]
    let attachments: [HanlinCapabilityAttachment]
    let onAttach: (HanlinComposerCapabilityDescriptor, String?) -> Void
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        HanlinCapabilityPicker(capabilities: capabilities, attachments: attachments, onSelect: onAttach)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("hanlin-composer-mini-apps-page")
            .task { await session.prepare(modelContext: modelContext) }
            .onChange(of: session.platform.installedPackages) { _, _ in
                Task { await session.refreshCatalog() }
            }
    }
}

private extension HanlinScriptingPlatform.Activity {
    var isFailure: Bool { if case .failed = self { true } else { false } }
    var failureMessage: String? { if case let .failed(message) = self { message } else { nil } }
}
