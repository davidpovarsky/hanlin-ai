import Foundation
import SwiftUI

@MainActor
enum RuntimeLifecycleBridge {
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
        preparationTask = task
        await task.value
        prepared = true
    }

    static func handleScenePhase(_ phase: ScenePhase) async {
        let predecessor = sceneTransitionTask
        let transitionID = UUID()
        let task = Task { @MainActor in
            if let predecessor { await predecessor.value }
            guard lastHandledScenePhase != phase else { return }
            await MCPRuntimeProvider.shared.handleScenePhase(phase)
            if phase == .active { await AppRuntimeCore.shared.handleForegroundIfLaunched() }
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
