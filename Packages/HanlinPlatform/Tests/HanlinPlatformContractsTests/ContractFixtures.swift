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
        let providerInstanceID = try HanlinProviderInstanceID(
            validating: "native.app.com.example.transit"
        )
        let packageVersion = try HanlinPackageVersion(validating: "1.2.3")
        let defaultEntryPoints = [
            HanlinEntryPointDescriptor(
                kind: .app,
                handler: "src/index.tsx",
                allowedContexts: [.mainApplication]
            )
        ]
        let inputSchema = try jsonSchema(
            .object([
                "additionalProperties": .bool(false),
                "properties": .object([
                    "stop": .object([
                        "maxLength": .integer(80),
                        "minLength": .integer(1),
                        "type": .string("string")
                    ])
                ]),
                "required": .array([.string("stop")]),
                "type": .string("object")
            ])
        )
        return HanlinAppDescriptor(
            schemaVersion: schemaVersion,
            descriptorRevision: try HanlinDescriptorRevision(1),
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
                    logicalID: HanlinLogicalToolID(
                        providerInstanceID: providerInstanceID,
                        localToolID: toolID
                    ),
                    descriptorRevision: try HanlinDescriptorRevision(1),
                    owner: .app(appID),
                    title: try localized("Refresh"),
                    summary: try localized("Refresh arrivals"),
                    inputSchema: inputSchema,
                    outputSchema: try jsonSchema(
                        .object([
                            "items": .object(["type": .string("string")]),
                            "maxItems": .integer(100),
                            "minItems": .integer(0),
                            "type": .string("array")
                        ])
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

    static func jsonSchema(
        _ root: HanlinJSONValue
    ) throws -> HanlinJSONSchemaDocument {
        try HanlinJSONSchemaDocument(
            dialect: .draft2020_12,
            root: root
        )
    }
}
