import SwiftUI

@MainActor
enum RuntimeLifecycleBridge {
    static func prepareApplication() async {
        try? await AppRuntimeCore.shared.prepareStorage()
        await MCPRuntimeProvider.shared.loadIfNeeded()
    }

    static func handleScenePhase(_ phase: ScenePhase) async {
        await MCPRuntimeProvider.shared.handleScenePhase(phase)
        if phase == .active { await AppRuntimeCore.shared.handleForeground() }
    }
}
