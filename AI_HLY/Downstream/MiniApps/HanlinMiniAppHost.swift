import Foundation
import HanlinMiniAppCore
import HanlinParityMiniApp
import HanlinPlatformContracts
import HanlinScriptStore
import Observation
import SwiftUI

actor HanlinMiniAppAuthorizationPolicy {
    private var descriptors: [HanlinAppID: HanlinAppDescriptor] = [:]

    func replace(with items: [HanlinMiniAppCatalogItem]) {
        descriptors = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0.descriptor) })
    }

    func authorize(_ request: HanlinMiniAppRequest) -> Bool {
        guard request.caller != request.target,
              let caller = descriptors[request.caller],
              let target = descriptors[request.target] else { return false }
        let callerCapabilities = Set(caller.capabilities.map(\.id))
        let targetCapabilities = Set(target.capabilities.map(\.id))
        return callerCapabilities.contains(request.capability)
            && targetCapabilities.contains(request.capability)
    }
}

@MainActor
@Observable
final class HanlinMiniAppHost {
    struct SwiftDestination: Identifiable {
        let id = UUID()
        let appID: HanlinAppID
        let view: AnyView
    }

    static let shared = HanlinMiniAppHost()

    private(set) var items: [HanlinMiniAppCatalogItem] = []
    private(set) var lastError: String?
    private(set) var hiddenAppIDs: Set<HanlinAppID> = []

    let dataStore: HanlinMiniAppDataStore
    let requestBroker: HanlinMiniAppRequestBroker
    private let authorization: HanlinMiniAppAuthorizationPolicy
    private let defaults: UserDefaults
    private let hiddenKey = "hanlin.canonical-mini-apps.hidden.v1"

    private init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        authorization = HanlinMiniAppAuthorizationPolicy()
        let policy = authorization
        requestBroker = HanlinMiniAppRequestBroker { request in
            await policy.authorize(request)
        }
        do {
            dataStore = try HanlinMiniAppDataStore(root: HanlinMiniAppDataStore.applicationSupportRoot())
        } catch {
            preconditionFailure("Canonical Mini App storage is unavailable: \(error)")
        }
        if let data = defaults.data(forKey: hiddenKey),
           let rawIDs = try? JSONDecoder().decode([String].self, from: data) {
            hiddenAppIDs = Set(rawIDs.compactMap(HanlinAppID.init(rawValue:)))
        }
    }

    var visibleItems: [HanlinMiniAppCatalogItem] {
        items.filter { !hiddenAppIDs.contains($0.id) }
    }

    func refresh(installedPackages: [HanlinStoredPackageSnapshot]) async {
        do {
            let nativeScriptPackages = installedPackages.filter { package in
                guard package.enabled else { return false }
                if package.entrypoints.contains(where: { $0.runtimeProfile == .hanlinNativeScript }) {
                    return true
                }
                if let rt = package.manifest?.unknownFields["hanlinRuntime"],
                   case let .string(rtStr) = rt,
                   rtStr == HanlinRuntimeProfile.hanlinNativeScript.rawValue {
                    return true
                }
                if package.manifest?.entry?.contains("nativescript") == true {
                    return true
                }
                return false
            }
            BuiltinCanonicalRegistrations.ensureRegistered()
            let discovery = HanlinCompositeMiniAppDiscovery(providers: [
                HanlinCompiledMiniAppDiscovery(),
                HanlinScriptPackageDiscovery(snapshots: nativeScriptPackages)
            ])
            let refreshed = try await HanlinCanonicalMiniAppCatalog(discovery: discovery).items()
            items = refreshed
            await authorization.replace(with: refreshed)
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    func setHidden(_ hidden: Bool, appID: HanlinAppID) {
        if hidden { hiddenAppIDs.insert(appID) } else { hiddenAppIDs.remove(appID) }
        let values = hiddenAppIDs.map(\.rawValue).sorted()
        defaults.set(try? JSONEncoder().encode(values), forKey: hiddenKey)
    }

    func isHidden(_ appID: HanlinAppID) -> Bool { hiddenAppIDs.contains(appID) }

    func swiftDestination(for item: HanlinMiniAppCatalogItem) throws -> SwiftDestination {
        let plan = try HanlinMiniAppLaunchPlan(descriptor: item.descriptor)
        guard plan.engine == .swift else {
            throw HanlinMiniAppCatalogError.unsupportedImplementation(item.id)
        }
        BuiltinCanonicalRegistrations.ensureRegistered()
        guard let provider = HanlinCompiledMiniAppRegistry.shared.provider(for: item.id) else {
            throw HanlinMiniAppCatalogError.unsupportedImplementation(item.id)
        }
        let store = dataStore
        let broker = requestBroker
        let context = HanlinMiniAppHostContext(
            appID: item.id,
            storage: HanlinMiniAppStorageContext(appID: item.id, store: store),
            requestBroker: broker,
            network: Self.fetchStatus
        )
        return SwiftDestination(
            appID: item.id,
            view: provider.makeRootView(context: context)
        )
    }

    func launchNativeScript(
        _ item: HanlinMiniAppCatalogItem,
        platform: HanlinScriptingPlatform
    ) async throws {
        let plan = try HanlinMiniAppLaunchPlan(descriptor: item.descriptor)
        guard plan.engine == .nativeScript else {
            throw HanlinMiniAppCatalogError.unsupportedImplementation(item.id)
        }
        guard case let .nativeScript(packageID) = item.descriptor.implementation,
              let package = platform.installedPackages.first(where: { $0.record.packageID == packageID }) else {
            throw HanlinMiniAppCatalogError.unsupportedImplementation(item.id)
        }
        await platform.launch(package.record.installedPackageID)
    }

    private static func fetchStatus(_ url: URL) async throws -> String {
        guard url.scheme?.lowercased() == "https" else { throw URLError(.unsupportedURL) }
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse,
              data.count <= 1_048_576 else { throw URLError(.badServerResponse) }
        return "HTTPS \(http.statusCode), \(data.count) bytes"
    }
}
