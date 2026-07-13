import Foundation

@MainActor
final class NativeAppRegistry {
    static let shared = NativeAppRegistry()

    private var modulesByID: [String: NativeAppModule] = [:]
    private var didRegisterBuiltins = false

    private init() {}

    func ensureBuiltinsRegistered() {
        guard !didRegisterBuiltins else { return }
        didRegisterBuiltins = true
        let modules = BuiltinAppsIndex.modules()
        NativeToolTraceLogger.shared.log(
            "native_app_modules_discovered",
            ["moduleCount": modules.count, "moduleIDs": modules.map(\.manifest.id)]
        )
        for module in modules {
            register(module)
        }
    }

    func register(_ module: NativeAppModule) {
        modulesByID[module.manifest.id] = module
    }

    func allModules() -> [NativeAppModule] {
        ensureBuiltinsRegistered()
        return modulesByID.values.sorted { $0.manifest.title < $1.manifest.title }
    }

    func module(id: String) -> NativeAppModule? {
        ensureBuiltinsRegistered()
        return modulesByID[id]
    }

    func allAssistantTools() -> [NativeTool] {
        let context = NativeAppContext()
        return allAssistantTools(context: context)
    }

    func allAssistantTools(context: NativeAppContext) -> [NativeTool] {
        allAssistantToolsWithOwners(context: context).map { $0.tool }
    }

    func allAssistantToolsWithOwners(context: NativeAppContext) -> [(tool: NativeTool, sourceApp: NativeAppManifest)] {
        ensureBuiltinsRegistered()
        return allModules().flatMap { module in
            module.assistantTools(context: context).map { (tool: $0, sourceApp: module.manifest) }
        }
    }

    func allCapabilities() -> [NativeCapabilityRequest] {
        let context = NativeAppContext()
        return allCapabilities(context: context)
    }

    func allCapabilities(context: NativeAppContext) -> [NativeCapabilityRequest] {
        ensureBuiltinsRegistered()
        return allModules().flatMap { $0.capabilities(context: context) }
    }
}
