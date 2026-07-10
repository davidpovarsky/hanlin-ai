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
        for module in BuiltinAppsIndex.modules() {
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
        ensureBuiltinsRegistered()
        return allModules().flatMap { $0.assistantTools(context: context) }
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
