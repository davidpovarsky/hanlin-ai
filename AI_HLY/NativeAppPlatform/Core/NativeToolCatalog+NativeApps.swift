import Foundation

extension NativeToolCatalog {
    /// Registers Assistant Tool entry points exported by NativeAppModule packages.
    /// Call this once from NativeToolCatalog.ensureBuiltinsRegistered().
    @MainActor
    func registerNativeAppTools() {
        let context = NativeAppContext()
        registerNativeAppTools(context: context)
    }

    @MainActor
    func registerNativeAppTools(context: NativeAppContext) {
        let tools = NativeAppRegistry.shared.allAssistantToolsWithOwners(context: context)
        NativeToolTraceLogger.shared.log(
            "native_app_tools_registration_started",
            [
                "toolCount": tools.count,
                "toolNames": tools.map { $0.tool.name },
                "sourceAppIDs": tools.map { $0.sourceApp.id }
            ]
        )
        for registration in tools {
            register(registration.tool, sourceApp: registration.sourceApp)
        }
        NativeToolTraceLogger.shared.log(
            "native_app_tools_registration_completed",
            [
                "toolCount": tools.count,
                "toolNames": tools.map { $0.tool.name }
            ]
        )
    }
}
