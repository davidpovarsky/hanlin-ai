import SwiftUI

@MainActor
enum RuntimeLifecycleBridge {
    static func prepareApplication() async {
        try? await AppRuntimeCore.shared.prepareStorage()
#if targetEnvironment(simulator)
        let acceptance = ProcessInfo.processInfo.environment["HANLIN_RUNTIME_ACCEPTANCE"]
        if acceptance == "shell" {
            await ShellRuntimeAcceptance.run()
            return
        }
        if acceptance == "mcp" {
            await MCPRuntimeAcceptance.run()
            return
        }
#endif
        await MCPRuntimeProvider.shared.loadIfNeeded()
    }

    static func handleScenePhase(_ phase: ScenePhase) async {
        await MCPRuntimeProvider.shared.handleScenePhase(phase)
        if phase == .active { await AppRuntimeCore.shared.handleForeground() }
    }
}
