import Foundation
@testable import HanlinPlatformContracts

enum ContractFixtures {
    static func localized(_ value: String) throws -> LocalizedValue {
        try LocalizedValue(
            [
                "en": value,
                "he": "ערך"
            ]
        )
    }

    static func descriptor(
        schemaVersion: HanlinManifestVersion = .init(major: 1, minor: 0),
        apiVersion: HanlinAPIVersion = .init(major: 1, minor: 0),
        entryPoints: [HanlinEntryPointDescriptor]? = nil,
        routes: [HanlinRouteDescriptor] = []
    ) throws -> HanlinAppDescriptor {
        let appID = try HanlinAppID(validating: "com.example.transit")
        let packageID = try HanlinPackageID(validating: "com.example.transit")
        let capabilityID = try HanlinCapabilityID(validating: "network.fetch")
        let toolID = try HanlinToolID(validating: "com.example.transit.refresh")
        let packageVersion = try HanlinPackageVersion(validating: "1.2.3")
        let defaultEntryPoints = [
            HanlinEntryPointDescriptor(
                kind: .app,
                handler: "src/index.tsx",
                allowedContexts: [.mainApplication]
            )
        ]
        let inputSchema = HanlinJSONSchema.object(
            properties: [
                "stop": .string(minLength: 1, maxLength: 80, pattern: nil)
            ],
            required: ["stop"],
            additionalProperties: false
        )
        return HanlinAppDescriptor(
            schemaVersion: schemaVersion,
            id: appID,
            name: try localized("Transit"),
            summary: try localized("Nearby arrivals"),
            description: try localized("Shows nearby transit arrivals."),
            version: packageVersion,
            minimumHostVersion: try HanlinPackageVersion(validating: "1.0.0"),
            apiVersion: apiVersion,
            icon: .systemSymbol(name: "bus"),
            appearance: .init(
                accentHex: "#3366ff",
                preferredColorScheme: .system
            ),
            category: .utilities,
            implementation: .script(packageID: packageID),
            entryPoints: entryPoints ?? defaultEntryPoints,
            routes: routes,
            tools: [
                HanlinToolDescriptor(
                    id: toolID,
                    owner: .app(appID),
                    title: try localized("Refresh"),
                    summary: try localized("Refresh arrivals"),
                    inputSchema: inputSchema,
                    outputSchema: .array(
                        items: .string(
                            minLength: nil,
                            maxLength: nil,
                            pattern: nil
                        ),
                        minItems: 0,
                        maxItems: 100
                    ),
                    capabilities: [capabilityID],
                    risk: .read,
                    presentation: .init(compactStyle: .entity)
                )
            ],
            capabilities: [
                HanlinCapabilityDeclaration(
                    id: capabilityID,
                    reason: try localized("Load arrivals"),
                    constraints: .object([
                        "domains": .array([.string("api.example.com")])
                    ])
                )
            ],
            authors: [
                HanlinAuthor(
                    name: "Example",
                    identifier: try HanlinPublisherID(
                        validating: "com.example"
                    )
                )
            ],
            distribution: .init(
                sourceVisible: true,
                sourceEditable: true,
                remoteUpdates: false,
                allowedModes: [.personalDevelopment, .testFlight]
            ),
            integrity: .init(
                algorithm: .sha256,
                digest: String(repeating: "a", count: 64),
                signer: try HanlinPublisherID(validating: "com.example")
            )
        )
    }
}
