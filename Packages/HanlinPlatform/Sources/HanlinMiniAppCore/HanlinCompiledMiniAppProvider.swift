import Foundation
import HanlinPlatformContracts
#if canImport(SwiftUI)
import SwiftUI
#endif

public enum NativePresentationMode: String, Codable, Hashable, Sendable {
    case fullApp
    case chatCard
    case compact
}

public struct HanlinMiniAppHostContext: Sendable {
    public let appID: HanlinAppID
    public let storage: HanlinMiniAppStorageContext
    public let requestBroker: HanlinMiniAppRequestBroker
    public let network: @Sendable (URL) async throws -> String
    public let dismiss: @MainActor @Sendable () -> Void

    public init(
        appID: HanlinAppID,
        storage: HanlinMiniAppStorageContext,
        requestBroker: HanlinMiniAppRequestBroker,
        network: @escaping @Sendable (URL) async throws -> String,
        dismiss: @escaping @MainActor @Sendable () -> Void = {}
    ) {
        self.appID = appID
        self.storage = storage
        self.requestBroker = requestBroker
        self.network = network
        self.dismiss = dismiss
    }
}

public protocol HanlinCompiledMiniAppProvider: Sendable {
    var registration: any HanlinStaticMiniAppRegistration { get }
    var descriptor: HanlinAppDescriptor { get }
    var appID: HanlinAppID { get }
    #if canImport(SwiftUI)
    @MainActor
    func makeRootView(context: HanlinMiniAppHostContext) -> AnyView
    #endif
}

public extension HanlinCompiledMiniAppProvider {
    var descriptor: HanlinAppDescriptor {
        guard let desc = try? registration.appDescriptor() else {
            preconditionFailure("Failed to resolve descriptor")
        }
        return desc
    }
    var appID: HanlinAppID { registration.appID }
}

public final class HanlinCompiledMiniAppRegistry: @unchecked Sendable {
    public static let shared = HanlinCompiledMiniAppRegistry()
    private var providers: [HanlinAppID: any HanlinCompiledMiniAppProvider] = [:]
    private let lock = NSLock()

    public init() {}

    public func register(_ provider: any HanlinCompiledMiniAppProvider) {
        lock.lock()
        defer { lock.unlock() }
        providers[provider.appID] = provider
    }

    public func provider(for appID: HanlinAppID) -> (any HanlinCompiledMiniAppProvider)? {
        lock.lock()
        defer { lock.unlock() }
        return providers[appID]
    }

    public func allProviders() -> [any HanlinCompiledMiniAppProvider] {
        lock.lock()
        defer { lock.unlock() }
        return Array(providers.values).sorted { $0.appID.rawValue < $1.appID.rawValue }
    }
}

public struct HanlinCompiledMiniAppDiscovery: HanlinMiniAppDiscovery, Sendable {
    private let registry: HanlinCompiledMiniAppRegistry

    public init(registry: HanlinCompiledMiniAppRegistry = .shared) {
        self.registry = registry
    }

    public func registrations() async throws -> [any HanlinMiniAppRegistration] {
        registry.allProviders().map(\.registration)
    }

    public func registration(for appID: HanlinAppID) async throws -> (any HanlinMiniAppRegistration)? {
        registry.provider(for: appID)?.registration
    }

    public func catalogSnapshot(
        revision: HanlinCatalogRevision = .init(1)
    ) async throws -> HanlinCatalogSnapshot {
        let descriptors = registry.allProviders().map(\.descriptor)
        return HanlinCatalogSnapshot(
            revision: revision,
            generatedAt: .now,
            apps: descriptors
        )
    }
}
