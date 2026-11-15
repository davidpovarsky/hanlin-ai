import SwiftUI

/// Independent composition of the existing Host in this process. No AI data
/// model or assistant credential adapter is configured in the MiniApps target.
@main
struct HanlinMiniAppsApplication: App {
    @State private var bootstrap = HanlinMiniAppsBootstrap {
        try await AppRuntimeCore.shared.prepareStorage()
        HanlinNativeScriptProductionBootstrap.prepareEmbeddedProviders()
    }

    var body: some Scene {
        WindowGroup {
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
        }
    }
}

/// Constructed only after the real storage preparation succeeded.
private struct HanlinMiniAppsReadyRoot: View {
    @State private var provider = HanlinMiniAppsProvider()
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        MiniAppsLibrary(services: .connected(to: provider))
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
