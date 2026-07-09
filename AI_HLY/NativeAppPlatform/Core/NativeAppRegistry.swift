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

    func allAssistantTools(context: NativeAppContext = NativeAppContext()) -> [NativeTool] {
        ensureBuiltinsRegistered()
        return allModules().flatMap { $0.assistantTools(context: context) }
    }

    func allCapabilities(context: NativeAppContext = NativeAppContext()) -> [NativeCapabilityRequest] {
        ensureBuiltinsRegistered()
        return allModules().flatMap { $0.capabilities(context: context) }
    }
}
