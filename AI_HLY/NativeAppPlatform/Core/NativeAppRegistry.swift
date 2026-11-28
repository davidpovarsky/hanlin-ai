import Foundation
import HanlinPlatformContracts

@MainActor
final class NativeAppRegistry {
    static let shared = NativeAppRegistry()

    private var modulesByID: [String: NativeAppModule] = [:]
    private var didRegisterBuiltins = false

    init() {}

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

    func allCapabilityProjections(context: NativeAppContext = NativeAppContext()) -> [String: NativeCapabilityProjection] {
        ensureBuiltinsRegistered()
        var result: [String: NativeCapabilityProjection] = [:]
        for module in allModules() {
            result[module.manifest.id] = module.capabilityProjection(context: context)
        }
        return result
    }

    func aggregatedCapabilityProjection(context: NativeAppContext = NativeAppContext()) -> NativeCapabilityProjection {
        ensureBuiltinsRegistered()
        var allSupported: [NativeCapabilityRequest] = []
        var allDiagnostics: [NativeCapabilityDiagnostic] = []
        for module in allModules() {
            let projection = module.capabilityProjection(context: context)
            allSupported.append(contentsOf: projection.supportedRequests)
            allDiagnostics.append(contentsOf: projection.diagnostics)
        }
        return NativeCapabilityProjection(supportedRequests: allSupported, diagnostics: allDiagnostics)
    }

    func allCapabilities() -> [NativeCapabilityRequest] {
        let context = NativeAppContext()
        return allCapabilities(context: context)
    }

    func allCapabilities(context: NativeAppContext) -> [NativeCapabilityRequest] {
        aggregatedCapabilityProjection(context: context).supportedRequests
    }

    func allCanonicalRegistrations() -> [any HanlinStaticMiniAppRegistration] {
        ensureBuiltinsRegistered()
        return allModules().compactMap { $0.canonicalRegistration }
    }
}
