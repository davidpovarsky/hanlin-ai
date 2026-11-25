import AppIntents
import ExpoWidgets
import HanlinTranslationUI
import HanlinScriptExtensions
import HanlinWidgetUI
import SwiftUI
import HanlinProductSplit
import HanlinMiniAppsBridge

/// Independent composition of the existing Host in this process. No AI data
/// model or assistant credential adapter is configured in the MiniApps target.
@main
struct HanlinMiniAppsApplication: App {
    @UIApplicationDelegateAdaptor(HanlinNotificationApplicationDelegate.self) private var notificationDelegate
    var body: some Scene {
        WindowGroup(id: "miniapps-root", for: HanlinMiniAppsRootScene.self) { $scene in
            HanlinMiniAppsWindow(requestID: Binding(
                get: { scene.requestID },
                set: { scene = $0.map(HanlinMiniAppsRootScene.request) ?? .catalog }
            ))
        } defaultValue: {
            .catalog
        }
        WindowGroup("MiniApp", id: "miniapp-invocation", for: UUID.self) { $requestID in
            HanlinMiniAppsWindow(requestID: $requestID)
        }
    }
}

/// A catalog has its own value so returning to Apps can focus an existing
/// catalog without replacing another root window's in-flight request.
private enum HanlinMiniAppsRootScene: Codable, Hashable {
    case catalog
    case request(UUID)

    var requestID: UUID? {
        if case let .request(id) = self { return id }
        return nil
    }
}

struct HanlinMiniAppsWindow: View {
    @Environment(\.openURL) private var openURL
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow
    @Environment(\.supportsMultipleWindows) private var supportsMultipleWindows
    @Binding private var sceneRequestID: UUID?
    @SceneStorage("hanlin.miniapps.inlineRequestID") private var inlineRequestID = ""
    private let hasSceneIdentity: Bool

    // WindowGroup uses this binding for both focus matching and restoration.
    // Reusing a value window must update its identity along with its content.
    var externalRequestID: UUID? {
        get { hasSceneIdentity ? sceneRequestID : UUID(uuidString: inlineRequestID) }
        nonmutating set {
            if hasSceneIdentity { sceneRequestID = newValue }
            else { inlineRequestID = newValue?.uuidString ?? "" }
        }
    }

    init(requestID: Binding<UUID?>? = nil) {
        _sceneRequestID = requestID ?? .constant(nil)
        hasSceneIdentity = requestID != nil
    }
    @State private var foreground = MiniAppsForegroundBridge()
    @State private var incomingURLs: [URL] = []
    private var incomingURL: URL? { incomingURLs.first }
    @State private var showsImport = false
    @State private var bootstrap = HanlinMiniAppsBootstrap(preparation: Self.prepareStorage)

    private func openReturnURL(_ url: URL) async -> Bool {
        await withCheckedContinuation { continuation in
            openURL(url) { continuation.resume(returning: $0) }
        }
    }

    private func closeRequest(_ requestID: UUID) {
        guard externalRequestID == requestID else { return }
        if hasSceneIdentity, supportsMultipleWindows {
            // Replacing a value window's content with nil leaves its scene
            // alive. A process exit can restore its previous request before
            // SwiftUI flushes the updated presentation value. Close this actual
            // scene, and focus a catalog without touching other requests.
            openWindow(id: "miniapps-root", value: HanlinMiniAppsRootScene.catalog)
            dismissWindow()
        } else {
            externalRequestID = nil
        }
    }

    private var preferredExternalEvents: Set<String> {
        guard let externalRequestID else { return [] }
        // SwiftUI matches URL absolute strings case-insensitively. Prefer the
        // request already owned by this scene, including an inline root request,
        // so a repeated URL focuses it instead of rebinding another window.
        return ["request=" + externalRequestID.uuidString]
    }

    private var alertMessage: String {
        let base = foreground.error ?? ""
        #if DEBUG || HANLIN_TESTING
        if let code = foreground.lastFailureCode, !code.isEmpty {
            return "\(base)\n[diagnostic:\(code)]"
        }
        #endif
        return base
    }

    @MainActor
    private static func prepareStorage() async throws {
        try HanlinScriptingPlatform.prepareProductTransferRecovery()
        try await AppRuntimeCore.shared.prepareStorage()
        HanlinNativeScriptProductionBootstrap.prepareEmbeddedProviders()
    }

    var body: some View {
        Group {
            Group {
                switch bootstrap.phase {
                case .idle, .preparing:
                    ProgressView("Preparing app storage…")
                case .failed(let error):
                    ContentUnavailableView {
                        Label("App storage unavailable", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text("App storage could not be prepared. Error \(error.domain) (\(error.code)).")
                    } actions: {
                        Button("Retry") { Task { await bootstrap.prepare() } }
                    }
                    .accessibilityIdentifier("hanlin-miniapps-bootstrap-failure")
                case .ready:
                    if let externalRequestID {
                        HanlinExternalMiniAppView(requestID: externalRequestID,
                            onClose: { closeRequest(externalRequestID) })
                            .id(externalRequestID)
                    } else {
                        HanlinMiniAppsReadyRoot()
                    }
                }
            }
            .task {
                if bootstrap.phase == .idle { await bootstrap.prepare() }
            }
            .handlesExternalEvents(preferring: preferredExternalEvents, allowing: ["*"])
            .onOpenURL { url in
                if !incomingURLs.contains(url) { incomingURLs.append(url) }
            }
            .task(id: bootstrap.phase == .ready ? incomingURL : nil) {
                guard bootstrap.phase == .ready, let url = incomingURL else { return }
                if let transferID = MiniAppAuthoringTransfer.reference(in: url, purpose: .install) {
                    do {
                        try await MiniAppAuthoringDelivery.receiveImport(transferID, platform: .shared)
                    } catch {
                        HanlinScriptingPlatform.shared.reportImportFailure(error)
                        if let store = try? MiniAppAuthoringDelivery.store() {
                            try? store.record(.init(transferID: transferID, status: .failed,
                                message: error.localizedDescription))
                        }
                    }
                    if !HanlinScriptingPlatform.shared.hasImportPresentation {
                        showsImport = true
                    }
                } else if url.scheme?.lowercased() == "hanlinminiapps",
                          url.host?.lowercased() == "x-callback-url",
                          url.path == "/run",
                          let requestID = MiniAppBridgeStore.requestID(from: url) {
                    do {
                        let mailbox = try MiniAppBridgeStore()
                        guard let request = try mailbox.request(id: requestID) else {
                            throw NSError(domain: "HanlinMiniApps.CrossApp", code: 1,
                                          userInfo: [NSLocalizedDescriptionKey: "Shared request not found."])
                        }
                        if externalRequestID != requestID, request.opensInNewWindow, supportsMultipleWindows {
                            openWindow(id: "miniapp-invocation", value: requestID)
                        } else {
                            externalRequestID = requestID
                        }
                    } catch {
                        foreground.error = error.localizedDescription
                    }
                } else if SplitCompanionCatalogRoute.matches(url) {
                    // The existing root is already the catalog. Never execute an
                    // action or discard an in-flight operation on a catalog wake.
                } else if url.isFileURL {
                    await HanlinScriptingPlatform.shared.importPackage(from: url)
                    showsImport = true
                } else {
                    await foreground.open(url)
                }
                if incomingURLs.first == url { incomingURLs.removeFirst() }
            }
            .sheet(isPresented: $showsImport) {
                NavigationStack { ScriptingPackageImportView(platform: .shared) }
            }
            .fullScreenCover(item: $foreground.presentation) { destination in
                NavigationStack {
                    destination.view.toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") { Task { await foreground.cancelAndClose(openURL: openReturnURL) } }
                                .disabled(foreground.returning)
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Return to Hanlin") { Task { await foreground.returnToOrigin(openURL: openReturnURL) } }
                                .disabled(foreground.returning)
                                .accessibilityIdentifier("miniapps.return-to-origin")
                                #if DEBUG || HANLIN_TESTING
                                .accessibilityValue(foreground.lastFailureCode ?? "")
                                #endif
                        }
                    }
                    #if DEBUG || HANLIN_TESTING
                    .safeAreaInset(edge: .bottom) {
                        if let code = foreground.lastFailureCode, !code.isEmpty {
                            Text(code)
                                .font(.caption2.monospaced())
                                .foregroundStyle(.secondary)
                                .accessibilityIdentifier("miniapps.last-failure-code")
                        }
                    }
                    #endif
                }
                .interactiveDismissDisabled()
                .alert("Hanlin request unavailable", isPresented: Binding(
                    get: { foreground.presentation != nil && foreground.error != nil },
                    set: { if !$0 { foreground.error = nil } }
                )) { Button("OK") { foreground.error = nil } }
                message: { Text(alertMessage) }
            }
            .alert("Hanlin request unavailable", isPresented: Binding(
                get: { foreground.presentation == nil && foreground.error != nil },
                set: { if !$0 { foreground.error = nil } }
            )) { Button("OK") { foreground.error = nil } }
            message: { Text(alertMessage) }
        }
    }
}

/// Constructed only after the real storage preparation succeeded.
private struct HanlinMiniAppsReadyRoot: View {
    @State private var provider = HanlinMiniAppsProvider(platform: .shared)
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        MiniAppsLibrary(provider: provider)
                .task {
                    await AppRuntimeCore.shared.handleForegroundIfLaunched()
                    await provider.platform.resumePendingInvocations(recoverDeliveredNotifications: true)
                }
                .fullScreenCover(isPresented: Binding(
                    get: { provider.platform.presentsForegroundAction },
                    set: { if !$0 { provider.platform.dismissActiveApplication() } }
                )) {
                    ScriptingApplicationContainerView(platform: provider.platform)
                }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active {
                        Task {
                            await AppRuntimeCore.shared.handleForegroundIfLaunched()
                            await provider.platform.resumePendingInvocations(recoverDeliveredNotifications: true)
                        }
                    }
                }
    }
}

/// Index the original shared actions in the foreground app that executes them.
struct HanlinMiniAppsIntents: AppIntentsPackage {
    static var includedPackages: [any AppIntentsPackage.Type] {
        [HanlinWidgetIntentsPackage.self, HanlinNativePresentationIntentsPackage.self, HanlinExpoWidgetsIntentsPackage.self]
    }
}
