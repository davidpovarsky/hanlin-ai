import AISDKProvider
import Foundation
import SwiftAISDK
import Testing
@testable import HanlinChatCore

@Suite("Original SDK structured output schema")
struct HanlinAISDKJSONOutputTests {
    private static let schema = Data(#"{"type":"object","properties":{"count":{"type":"integer","minimum":2}},"required":["count"],"additionalProperties":false}"#.utf8)

    @Test("The SDK validates complete JSON against the declared response schema")
    func completeSchemaValidation() async throws {
        let specification = try HanlinAISDKJSONOutput.specification(schemaData: Self.schema)
        let value = try await specification.parseOutput(text: #"{"count":3}"#,
            response: .init(id: "fixture", timestamp: .distantPast, modelId: "fixture"),
            usage: .init(), finishReason: .stop)
        #expect(value == .object(["count": .number(3)]))
        for invalid in [#"{"count":1}"#, #"{"count":"three"}"#, #"{"count":3,"extra":true}"#, #"{"count":"#] {
            await #expect(throws: (any Error).self) {
                _ = try await specification.parseOutput(text: invalid,
                    response: .init(id: "fixture", timestamp: .distantPast, modelId: "fixture"),
                    usage: .init(), finishReason: .stop)
            }
        }
    }

    @Test("Malformed, non-schema and oversized schema inputs fail before provider dispatch")
    func invalidSchemaInput() {
        for invalid in [Data("null".utf8), Data("[]".utf8), Data("{".utf8), Data(repeating: 32, count: 1_048_577)] {
            #expect(throws: (any Error).self) {
                _ = try HanlinAISDKJSONOutput.specification(schemaData: invalid)
            }
        }
    }
}
