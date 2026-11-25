import Combine
import Foundation
import HanlinExpoRuntime
import SwiftData
import SwiftUI

@MainActor
final class HanlinApplicationLifecycleState {
    var preparationTask: Task<Void, Never>?
    var systemIntegrationTask: Task<Void, Never>?
    var saveObserver: AnyCancellable?
}

extension HanlinApplicationContext {
    /// Starts the existing runtimes once and prepares this context's original stores.
    /// Both an embedded view and the full Scene use this same bootstrap.
    public func prepareApplication() async {
        if let task = applicationLifecycle.preparationTask {
            await task.value
            return
        }
        let task = Task { @MainActor [self] in
            if HanlinNativeA2UIAcceptanceProvider.isEnabled {
                dataManager.preloadDataIfNeeded()
                return
            }
            HanlinExpoSession.ensureAppDefinesLoaded()
            // The mounted workspace reads this store immediately. Prepare its
            // original data before waiting for independent system integrations.
            dataManager.preloadDataIfNeeded()
            HanlinNativeScriptProductionBootstrap.prepareEmbeddedProviders()
            HanlinScriptingPlatform.shared.configure(modelContext: modelContainer.mainContext)
            applicationLifecycle.systemIntegrationTask = Task { @MainActor in
                await ChavrusaSystemIntegrationBootstrap.configure()
            }
            await HanlinScriptingPlatform.shared.publishCompactAgentConfig()
            await RuntimeLifecycleBridge.prepareApplication()
            applicationLifecycle.saveObserver = NotificationCenter.default.publisher(for: ModelContext.didSave)
                .sink { [weak self] _ in
                    Task { @MainActor [weak self] in
                        guard self != nil else { return }
                        await HanlinScriptingPlatform.shared.publishCompactAgentConfig()
                    }
                }
        }
        applicationLifecycle.preparationTask = task
        await task.value
    }

    /// For hosts managing their own lifecycle. Embedded SDK views call this automatically.
    public func handleScenePhase(_ phase: ScenePhase) async {
        guard !HanlinNativeA2UIAcceptanceProvider.isEnabled else { return }
        await prepareApplication()
        await RuntimeLifecycleBridge.handleScenePhase(phase)
        if phase == .active {
            await HanlinScriptingPlatform.shared.publishCompactAgentConfig()
        }
    }
}

#if HANLIN_NATIVESCRIPT_POC
/// Keeps the existing dedicated NativeScript acceptance entry point available.
public struct HanlinNativeScriptAcceptanceView: View {
    public init() {}
    public var body: some View { HanlinNativeScriptPOCView() }
}
#endif
