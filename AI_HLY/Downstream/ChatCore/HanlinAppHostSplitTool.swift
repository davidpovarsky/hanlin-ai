import Foundation
import HanlinAgentCore
import HanlinHostContracts
import HanlinPlatformContracts

extension HanlinAppHostIntegration {
    static let splitAlias = "open_mini_app"
    static let splitSchema = Data(#"{"type":"object","properties":{"target":{"type":"string","enum":["hanlin.demo.swift-parity"]},"action":{"type":"string","enum":["share.value"]},"payload":{}},"required":["target","action","payload"],"additionalProperties":false}"#.utf8)

    static func splitTool() throws -> HanlinHostTool {
        let logical = try HanlinLogicalToolID(providerInstanceID: .init(validating: "hanlin.host"),
            localToolID: .init(validating: splitAlias))
        let revision = try HanlinDescriptorRevision(1)
        let input = try HanlinJSONSchemaDocument.decodeCanonicalJSON(splitSchema, defaultDialect: .draft2020_12)
        let descriptor = HanlinToolDescriptor(logicalID: logical, descriptorRevision: revision, owner: .system,
            title: try .init(["en": "Open Swift Parity Mini App"]),
            summary: try .init(["en": "Open the installed Swift Parity Mini App and return its existing share.value result to this original conversation. Only hanlin.demo.swift-parity/share.value is supported."]),
            inputSchema: input, risk: .write, presentation: .init())
        return .init(route: .init(alias: splitAlias, logicalToolID: logical, descriptorRevision: revision),
            descriptor: descriptor, writeGuarantee: .hostManagedMutation, originalInputSchemaJSON: splitSchema)
    }
}
