import Foundation
import HanlinMiniAppCore
import HanlinParityMiniApp
import HanlinPlatformContracts
import HanlinScriptExtensions
import HanlinScriptUI

/// Provides widget/intent exposure functions for compiled Swift MiniApps.
/// Widget rendering uses `HanlinScriptUINode` from the extension framework.
struct CompiledMiniAppExposureProvider {
    let descriptor: HanlinAppDescriptor
    let widget: @Sendable (String) async throws -> HanlinScriptUINode
    let intentNames: [String]
    let performIntent: @Sendable (String, HanlinValue) async throws -> HanlinValue

    var installedPackageID: HanlinInstalledPackageID {
        get throws { try .init(validating: "compiled.\(descriptor.id.rawValue)") }
    }

    var packageID: HanlinPackageID {
        get throws { try .init(validating: descriptor.id.rawValue) }
    }

    func identity(entrypoint: HanlinEntryPointDescriptor) throws -> HanlinScriptExtensionIdentity {
        try .init(
            installedPackageID: installedPackageID,
            packageID: packageID,
            generation: 0,
            entrypointID: entrypoint.handler
        )
    }
}

@MainActor
enum CompiledMiniAppExposureRegistry {
    static var all: [CompiledMiniAppExposureProvider] {
        BuiltinCanonicalRegistrations.ensureRegistered()
        let providers = HanlinCompiledMiniAppRegistry.shared.allProviders()
        return providers.compactMap { provider in
            let desc = provider.descriptor
            let idString = desc.id.rawValue

            if idString == "hanlin.demo.swift-parity" {
                let widgetNode: @Sendable (String) async throws -> HanlinScriptUINode = { family in
                    let storeRoot = try HanlinMiniAppDataStore.applicationSupportRoot()
                    let dataStore = try HanlinMiniAppDataStore(root: storeRoot)
                    let data = try await dataStore.read(appID: desc.id, area: .state, path: "parity.json")
                    return try SwiftParityMiniAppExposures.widget(family: family, persistedData: data)
                }

                let intentNames = ["ReadSwiftParityState"]

                let intentFn: @Sendable (String, HanlinValue) async throws -> HanlinValue = { name, parameters in
                    guard name == "ReadSwiftParityState" else {
                        throw HanlinHostServiceError.invalidRequest("Unsupported intent: \(name)")
                    }
                    let storeRoot = try HanlinMiniAppDataStore.applicationSupportRoot()
                    let dataStore = try HanlinMiniAppDataStore(root: storeRoot)
                    let data = try await dataStore.read(appID: desc.id, area: .state, path: "parity.json")
                    return try SwiftParityMiniAppExposures.performIntent(name: name, parameters: parameters, persistedData: data)
                }

                return CompiledMiniAppExposureProvider(
                    descriptor: desc,
                    widget: widgetNode,
                    intentNames: intentNames,
                    performIntent: intentFn
                )
            } else {
                // Providers without a registered real handler must NOT produce generic fake widgets or fake intents.
                return nil
            }
        }
    }

    static func provider(packageID: HanlinPackageID) -> CompiledMiniAppExposureProvider? {
        all.first { $0.descriptor.id.rawValue == packageID.rawValue }
    }
}
