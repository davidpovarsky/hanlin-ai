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
        let tools = NativeAppRegistry.shared.allAssistantTools(context: context)
        NativeToolTraceLogger.shared.log(
            "native_app_tools_registration_started",
            [
                "toolCount": tools.count,
                "toolNames": tools.map(\.name)
            ]
        )
        for tool in tools {
            register(tool)
        }
        NativeToolTraceLogger.shared.log(
            "native_app_tools_registration_completed",
            [
                "toolCount": tools.count,
                "toolNames": tools.map(\.name)
            ]
        )
    }
}
