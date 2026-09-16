import Foundation
import HanlinPlatformContracts

public enum HanlinMiniAppEngine: String, Codable, CaseIterable, Hashable, Sendable {
    case swift
    case nativeScript
}

public struct HanlinMiniAppCatalogItem: Identifiable, Hashable, Sendable {
    public let descriptor: HanlinAppDescriptor
    public let engine: HanlinMiniAppEngine

    public var id: HanlinAppID { descriptor.id }

    public init(descriptor: HanlinAppDescriptor, engine: HanlinMiniAppEngine) {
        self.descriptor = descriptor
        self.engine = engine
    }
}

public enum HanlinMiniAppCatalogError: Error, Equatable, Sendable {
    case unsupportedImplementation(HanlinAppID)
    case missingEntrypoint(HanlinAppID, HanlinEntryPointKind)
    case missingScriptRuntime(HanlinAppID, HanlinEntryPointKind)
    case unsupportedScriptRuntime(HanlinAppID, HanlinRuntimeProfile)
}

/// Runtime-neutral catalog backed exclusively by canonical registrations.
public struct HanlinCanonicalMiniAppCatalog: Sendable {
    private let discovery: any HanlinMiniAppDiscovery

    public init(discovery: any HanlinMiniAppDiscovery) {
        self.discovery = discovery
    }

    public func items() async throws -> [HanlinMiniAppCatalogItem] {
        var seen = Set<HanlinAppID>()
        var result: [HanlinMiniAppCatalogItem] = []
        for registration in try await discovery.registrations() {
            let descriptor = try registration.appDescriptor()
            guard seen.insert(descriptor.id).inserted,
                  let engine = Self.engine(for: descriptor) else { continue }
            result.append(.init(descriptor: descriptor, engine: engine))
        }
        return result.sorted {
            if $0.engine != $1.engine { return $0.engine.rawValue < $1.engine.rawValue }
            return $0.descriptor.id.rawValue < $1.descriptor.id.rawValue
        }
    }

    public static func engine(for descriptor: HanlinAppDescriptor) -> HanlinMiniAppEngine? {
        switch descriptor.implementation {
        case .native, .hybrid:
            return .swift
        case .nativeScript:
            return .nativeScript
        case .script:
            let profiles = descriptor.entryPoints.compactMap(\.runtimeProfile)
            if profiles.contains(where: { $0 == .hanlinNativeScript }) {
                return .nativeScript
            }
            return nil
        }
    }
}

public struct HanlinMiniAppLaunchPlan: Hashable, Sendable {
    public let appID: HanlinAppID
    public let engine: HanlinMiniAppEngine
    public let entryPoint: HanlinEntryPointDescriptor

    public init(
        descriptor: HanlinAppDescriptor,
        entryPointKind: HanlinEntryPointKind = .app
    ) throws {
        guard let engine = HanlinCanonicalMiniAppCatalog.engine(for: descriptor) else {
            throw HanlinMiniAppCatalogError.unsupportedImplementation(descriptor.id)
        }
        guard let entryPoint = descriptor.entryPoints.first(where: { $0.kind == entryPointKind }) else {
            throw HanlinMiniAppCatalogError.missingEntrypoint(descriptor.id, entryPointKind)
        }
        if engine == .nativeScript {
            guard let runtime = entryPoint.runtimeProfile else {
                throw HanlinMiniAppCatalogError.missingScriptRuntime(descriptor.id, entryPointKind)
            }
            guard runtime == .hanlinNativeScript else {
                throw HanlinMiniAppCatalogError.unsupportedScriptRuntime(descriptor.id, runtime)
            }
        }
        self.appID = descriptor.id
        self.engine = engine
        self.entryPoint = entryPoint
    }
}
