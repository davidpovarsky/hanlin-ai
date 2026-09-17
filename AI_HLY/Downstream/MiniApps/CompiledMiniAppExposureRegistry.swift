import HanlinMiniAppCore
import HanlinParityMiniApp
import HanlinPlatformContracts
import HanlinScriptExtensions
import HanlinScriptUI

/// Provides widget/intent exposure functions for compiled Swift MiniApps.
/// Widget rendering uses `HanlinScriptUINode` from the extension framework.
struct CompiledMiniAppExposureProvider {
    let descriptor: HanlinAppDescriptor
    let widget: @Sendable (String) -> HanlinScriptUINode
    let intentNames: [String]
    let performIntent: @Sendable (String, HanlinValue) throws -> HanlinValue

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
        return providers.map { provider in
            let desc = provider.descriptor
            let title = desc.name.preferredValue(forLocale: "en")
            let idString = desc.id.rawValue

            let widgetNode: @Sendable (String) -> HanlinScriptUINode = { family in
                .init(
                    kind: .vStack,
                    properties: ["spacing": .number(8)],
                    children: [
                        .init(kind: .text, properties: ["text": .string(title)]),
                        .init(kind: .text, properties: ["text": .string("Generic hosted widget · \(family)")]),
                        .init(kind: .text, properties: ["text": .string(idString)])
                    ]
                )
            }

            let intentNames = idString == "hanlin.demo.swift-parity"
                ? ["ReadSwiftParityState"]
                : ["Read\(idString.replacingOccurrences(of: ".", with: "").capitalized)State"]

            let intentFn: @Sendable (String, HanlinValue) throws -> HanlinValue = { name, parameters in
                .object([
                    "appID": .string(idString),
                    "message": .string("\(title) App Intent invoked"),
                    "parameters": parameters
                ])
            }

            return CompiledMiniAppExposureProvider(
                descriptor: desc,
                widget: widgetNode,
                intentNames: intentNames,
                performIntent: intentFn
            )
        }
    }

    static func provider(packageID: HanlinPackageID) -> CompiledMiniAppExposureProvider? {
        all.first { $0.descriptor.id.rawValue == packageID.rawValue }
    }
}
