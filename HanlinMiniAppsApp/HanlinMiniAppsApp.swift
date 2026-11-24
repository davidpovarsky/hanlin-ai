import AppIntents
import HanlinScriptExtensions
import SwiftUI
import HanlinProductSplit

/// Independent composition of the existing Host in this process. No AI data
/// model or assistant credential adapter is configured in the MiniApps target.
@main
struct HanlinMiniAppsApplication: App {
    var body: some Scene { WindowGroup { HanlinMiniAppsWindow() } }
}

private struct HanlinMiniAppsWindow: View {
    @Environment(\.openURL) private var openURL
    @State private var foreground = MiniAppsForegroundBridge()
    @State private var incomingURL: URL?
    @State private var showsImport = false
    @State private var bootstrap = HanlinMiniAppsBootstrap(preparation: Self.prepareStorage)

    private func openReturnURL(_ url: URL) async -> Bool {
        await withCheckedContinuation { continuation in
            openURL(url) { continuation.resume(returning: $0) }
        }
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
                    HanlinMiniAppsReadyRoot()
                }
            }
            .task {
                if bootstrap.phase == .idle { await bootstrap.prepare() }
            }
            .onOpenURL { incomingURL = $0 }
            .task(id: bootstrap.phase == .ready ? incomingURL : nil) {
                guard bootstrap.phase == .ready, let url = incomingURL else { return }
                if SplitCompanionCatalogRoute.matches(url) {
                    // The existing root is already the catalog. Never execute an
                    // action or discard an in-flight operation on a catalog wake.
                } else if url.isFileURL {
                    await HanlinScriptingPlatform.shared.importPackage(from: url)
                    showsImport = true
                } else {
                    await foreground.open(url)
                }
                if incomingURL == url { incomingURL = nil }
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
    @State private var provider = HanlinMiniAppsProvider()
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        MiniAppsLibrary(provider: provider)
                .task {
                    await AppRuntimeCore.shared.handleForegroundIfLaunched()
                }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active {
                        Task { await AppRuntimeCore.shared.handleForegroundIfLaunched() }
                    }
                }
    }
}

/// Index the original shared actions in the foreground app that executes them.
struct HanlinMiniAppsIntents: AppIntentsPackage {
    static var includedPackages: [any AppIntentsPackage.Type] {
        [HanlinScriptExtensionIntentsPackage.self]
    }
}
