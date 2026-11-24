import AISDKProvider
import Foundation
import Testing
@testable import HanlinAgentCore

@Suite("Closed native tool schema admission")
struct HanlinAppleToolSchemaTests {
    @Test("Unsupported constraints and numeric schemas are never advertised", arguments: [
        #"{"type":"object","properties":{"n":{"type":"number"}},"additionalProperties":false}"#,
        #"{"type":"object","properties":{"n":{"type":"integer"}},"additionalProperties":false}"#,
        #"{"type":"object","properties":{"s":{"type":"string","pattern":"x+"}},"additionalProperties":false}"#,
        #"{"type":"object","properties":{"s":{"type":"string","minLength":1}},"additionalProperties":false}"#,
        #"{"type":"object","properties":{}}"#,
        #"{"type":"object","additionalProperties":true}"#,
        #"{"type":"object","properties":{},"required":["missing"],"additionalProperties":false}"#,
        #"{"type":"object","properties":{"x":{"type":"string"}},"required":["x","x"],"additionalProperties":false}"#,
        #"{"type":"object","properties":{"a":{"type":"array","items":{"type":"string"},"minItems":2,"maxItems":1}},"additionalProperties":false}"#,
        #"{"type":"object","properties":{"a":{"type":"array","items":{"type":"string"},"uniqueItems":true}},"additionalProperties":false}"#,
        #"{"type":"object","properties":{"x":{"type":["string","null"]}},"additionalProperties":false}"#,
        #"{"type":"object","properties":{},"oneOf":[{}],"additionalProperties":false}"#
    ])
    func rejectsUnrepresentedSemantics(_ json: String) throws {
        let value = try JSONDecoder().decode(JSONValue.self, from: Data(json.utf8))
        #expect(throws: HanlinAppleToolBridgeError.unsupportedSchema) { try HanlinAppleToolSchema(value) }
    }

    @Test("Required fields, closed objects, enum and array bounds survive admission")
    func validatesSupportedSubsetBeforeHandoff() throws {
        let json = #"{"type":"object","properties":{"name":{"type":"string","enum":["שלום","value"]},"items":{"type":"array","items":{"type":"boolean"},"minItems":1,"maxItems":2},"optional":{"type":"null"}},"required":["name","items"],"additionalProperties":false}"#
        let schema = try HanlinAppleToolSchema(JSONDecoder().decode(JSONValue.self, from: Data(json.utf8)))
        try schema.validate(arguments: .object(["name": .string("שלום"), "items": .array([.bool(true)])]))
        try schema.validate(arguments: .object(["name": .string("value"), "items": .array([.bool(true), .bool(false)]), "optional": .null]))
        for invalid: JSONValue in [
            .object(["name": .string("wrong"), "items": .array([.bool(true)])]),
            .object(["name": .string("value"), "items": .array([])]),
            .object(["name": .string("value"), "items": .array([.bool(true), .bool(false), .bool(true)])]),
            .object(["name": .string("value")]),
            .object(["name": .string("value"), "items": .array([.bool(true)]), "unknown": .null])
        ] {
            #expect(throws: HanlinAppleToolBridgeError.invalidArguments) { try schema.validate(arguments: invalid) }
        }
        #expect(throws: HanlinAppleToolBridgeError.numericArgumentsUnsupported) {
            try schema.validate(arguments: .object(["name": .string("value"), "items": .array([.number(1)])]))
        }
    }
}
