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

enum CompiledMiniAppExposureRegistry {
    /// Widget node builder for the Swift Parity demo app.
    private static func parityWidget(family: String) -> HanlinScriptUINode {
        .init(
            kind: .vStack,
            properties: ["spacing": .number(8)],
            children: [
                .init(kind: .text, properties: ["text": .string("Swift Parity")]),
                .init(kind: .text, properties: ["text": .string("Generic hosted widget · \(family)")]),
                .init(kind: .text, properties: ["text": .string("hanlin.demo.swift-parity")])
            ]
        )
    }

    /// App Intent handler for the Swift Parity demo app.
    private static func parityIntent(name: String, parameters: HanlinValue) throws -> HanlinValue {
        let intentName = "ReadSwiftParityState"
        guard name == intentName else { throw HanlinMiniAppRequestError.routeNotFound }
        return .object([
            "message": .string("Swift parity App Intent invoked"),
            "parameters": parameters
        ])
    }

    static let all: [CompiledMiniAppExposureProvider] = {
        let registration = SwiftParityMiniAppRegistration()
        return [.init(
            descriptor: registration.descriptor,
            widget: parityWidget,
            intentNames: ["ReadSwiftParityState"],
            performIntent: parityIntent
        )]
    }()

    static func provider(packageID: HanlinPackageID) -> CompiledMiniAppExposureProvider? {
        all.first { $0.descriptor.id.rawValue == packageID.rawValue }
    }
}
