import SwiftUI

/// Independent composition of the existing Host in this process. No AI data
/// model or assistant credential adapter is configured in the MiniApps target.
@main
struct HanlinMiniAppsApplication: App {
    @State private var provider = HanlinMiniAppsProvider()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            MiniAppsLibrary(services: .connected(to: provider))
                .task {
                    HanlinNativeScriptProductionBootstrap.prepareEmbeddedProviders()
                    try? await AppRuntimeCore.shared.prepareStorage()
                    await AppRuntimeCore.shared.handleForegroundIfLaunched()
                }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active {
                        Task { await AppRuntimeCore.shared.handleForegroundIfLaunched() }
                    }
                }
        }
    }
}
