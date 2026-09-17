import Foundation
import HanlinPlatformContracts

public enum HanlinMiniAppEngine: String, Codable, CaseIterable, Hashable, Sendable {
    case swift
    case nativeScript

    public var displayName: String {
        switch self {
        case .swift: return "Swift"
        case .nativeScript: return "NativeScript"
        }
    }
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

    /// Resolves the execution engine for a specific entrypoint.
    public static func engine(
        for entryPoint: HanlinEntryPointDescriptor,
        implementation: HanlinAppImplementation
    ) -> HanlinMiniAppEngine? {
        if let runtime = entryPoint.runtimeProfile {
            switch runtime {
            case .hanlinNativeScript:
                return .nativeScript
            default:
                return nil
            }
        }
        switch implementation {
        case .native, .hybrid:
            return .swift
        case .nativeScript:
            return .nativeScript
        case .script:
            return nil
        }
    }

    /// Resolves the primary foreground engine for an app descriptor based on its `.app` entrypoint.
    public static func foregroundEngine(for descriptor: HanlinAppDescriptor) -> HanlinMiniAppEngine? {
        if let appEntryPoint = descriptor.entryPoints.first(where: { $0.kind == .app }) {
            return engine(for: appEntryPoint, implementation: descriptor.implementation)
        }
        if let firstEntryPoint = descriptor.entryPoints.first {
            return engine(for: firstEntryPoint, implementation: descriptor.implementation)
        }
        switch descriptor.implementation {
        case .native, .hybrid:
            return .swift
        case .nativeScript:
            return .nativeScript
        case .script:
            return nil
        }
    }

    /// Resolves the engine for an app descriptor (delegates to foregroundEngine).
    public static func engine(for descriptor: HanlinAppDescriptor) -> HanlinMiniAppEngine? {
        foregroundEngine(for: descriptor)
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
        guard let entryPoint = descriptor.entryPoints.first(where: { $0.kind == entryPointKind }) else {
            throw HanlinMiniAppCatalogError.missingEntrypoint(descriptor.id, entryPointKind)
        }
        guard let engine = HanlinCanonicalMiniAppCatalog.engine(for: entryPoint, implementation: descriptor.implementation) else {
            throw HanlinMiniAppCatalogError.unsupportedImplementation(descriptor.id)
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
