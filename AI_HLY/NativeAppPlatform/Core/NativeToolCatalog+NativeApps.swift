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
        for tool in NativeAppRegistry.shared.allAssistantTools(context: context) {
            register(tool)
        }
    }
}
