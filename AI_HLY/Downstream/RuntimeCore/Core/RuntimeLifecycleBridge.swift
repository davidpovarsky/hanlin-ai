import Foundation
import SwiftUI

@MainActor
enum RuntimeLifecycleBridge {
    private static var isUnitTestHost: Bool {
        let environment = ProcessInfo.processInfo.environment
        return environment["HANLIN_UNIT_TEST_HOST"] == "1"
            || environment["XCTestConfigurationFilePath"] != nil
            || environment["HANLIN_EXPO_E2E"] != nil
            || environment["HANLIN_NATIVESCRIPT_E2E"] != nil
            || environment["HANLIN_SCRIPTUI_E2E"] != nil
    }

    private static var preparationTask: Task<Void, Never>?
    private static var prepared = false
    private static var sceneTransitionTask: Task<Void, Never>?
    private static var sceneTransitionID: UUID?
    private static var lastHandledScenePhase: ScenePhase?

    static func prepareApplication() async {
        if prepared { return }
        if let preparationTask {
            await preparationTask.value
            return
        }
        let task = Task { @MainActor in
            try? await AppRuntimeCore.shared.prepareStorage()
            guard !isUnitTestHost else { return }
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
            // Node is a process-lifetime engine. Warm it once without requiring
            // a user-facing runtime switch; other engines initialize on demand.
            _ = try? await AppRuntimeCore.shared.node.healthCheck()
        }
        preparationTask = task
        await task.value
        prepared = true
    }

    static func handleScenePhase(_ phase: ScenePhase) async {
        guard !isUnitTestHost else { return }
        let predecessor = sceneTransitionTask
        let transitionID = UUID()
        let task = Task { @MainActor in
            if let predecessor { await predecessor.value }
            guard lastHandledScenePhase != phase else { return }
            if phase == .active { await AppRuntimeCore.shared.handleForegroundIfLaunched() }
            await MCPRuntimeProvider.shared.handleScenePhase(phase)
            lastHandledScenePhase = phase
        }
        sceneTransitionTask = task
        sceneTransitionID = transitionID
        await task.value
        if sceneTransitionID == transitionID {
            sceneTransitionTask = nil
            sceneTransitionID = nil
        }
    }
}
