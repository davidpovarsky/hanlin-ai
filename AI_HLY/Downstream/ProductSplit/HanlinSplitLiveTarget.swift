import Foundation
import HanlinMiniAppCore
import HanlinPlatformContracts
import HanlinProductSplit
import HanlinScriptStore

/// Reads the original host/installed registry; no package or grant database is copied.
@MainActor
enum HanlinSplitLiveTarget {
    static func registration(for item: HanlinMiniAppCatalogItem,
                             platform: HanlinScriptingPlatform) throws -> SplitTargetRegistration {
        if item.engine == .swift {
            // Same compiled package identity/generation used by existing exposures.
            return try .init(descriptor: item.descriptor,
                installedPackage: .init(validating: "compiled.\(item.id.rawValue)"), generation: 0)
        }
        guard let package = platform.installedPackages.first(where: { $0.enabled && $0.appID == item.id }) else {
            throw SplitBridgeFailure.unsupportedRoute
        }
        return try .init(descriptor: item.descriptor, installedPackage: package.record.installedPackageID,
                         generation: package.record.activeGeneration)
    }

    static func current(_ request: SplitBridgeRequest) async throws -> (HanlinMiniAppCatalogItem, SplitReceiverContext) {
        let platform = HanlinScriptingPlatform.shared, host = HanlinMiniAppHost.shared
        await platform.restore()
        guard platform.bootstrapError == nil else { throw SplitBridgeFailure.transportUnavailable }
        await host.refresh(installedPackages: platform.installedPackages)
        guard host.lastError == nil, let item = host.items.first(where: { $0.id == request.target }) else {
            throw SplitBridgeFailure.unsupportedRoute
        }
        // Logical host identity is explicit; native Bundle IDs are not MiniApp callers.
        guard request.caller.rawValue == "hanlin.host" else { throw SplitBridgeFailure.denied }
        let registration = try registration(for: item, platform: platform)
        _ = try request.launchPlan(descriptor: registration.descriptor, installedPackageID: registration.installedPackage,
                                   currentGeneration: registration.generation)
        let allowed = await host.authorize(request.canonicalRequest())
        let context = SplitReceiverContext(caller: request.caller, target: item.id, package: registration.installedPackage,
            session: request.session, chat: request.chat, generation: registration.generation,
            authorized: allowed, routeAvailable: true, online: true)
        try context.validate(request)
        return (item, context)
    }

    static func exportCatalog() throws {
        let platform = HanlinScriptingPlatform.shared
        let items = try HanlinMiniAppHost.shared.items.filter { $0.descriptor.entryPoints.contains { $0.kind == .app } }
            .map { try registration(for: $0, platform: platform) }
        try HanlinSplitMailbox().publishCatalog(items)
    }
}
