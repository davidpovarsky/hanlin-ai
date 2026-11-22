import Foundation
import HanlinAgentCore
import HanlinPlatformContracts
import Testing

@Suite struct HostInputIntegrityRegressionTests {
    private func bytes(_ text: String) -> Data { Data(text.utf8) }

    @Test func routeWithoutMetadataKeepsOriginalBytesIncludingNestedHighPrecisionCoordinates() throws {
        let original = bytes(#"{ "origin": {"latitude":31.81660000000000001,"longitude":35.2021234567890123}, "destination":[{"latitude":32.0853,"longitude":34.7818}], "transit":true }"#)
        let extraction = try HanlinHostSchemaValidation.extractStringMetadata(argumentsJSON: original, keys: ["__summary", "__presentation"])
        #expect(extraction.argumentsJSON == original)
        #expect(extraction.presentKeys.isEmpty)
        let projected = try HanlinJSONValue.decodeCanonicalJSON(original)
        try HanlinHostSchemaValidation.requirePortableProjection(originalJSON: original, projected: projected)
        // An intentionally lossy DTO is never admissible as the actual executor input.
        #expect(throws: HanlinHostSchemaValidation.Failure.lossyProjection) {
            try HanlinHostSchemaValidation.requireSameValue(originalJSON: original, projectedJSON: projected.canonicalJSONData())
        }
    }

    @Test func strippingTopLevelMetadataPreservesAllNestedValuesAndScalarKeys() throws {
        let original = bytes(#"{"origin":{"lat":31.81660000000000001,"lon":35.2021234567890123,"__summary":"nested"},"waypoints":[{"id":9007199254740993,"K":1,"\u212A":2}],"__summary":"מסלול","__presentation":"card"}"#)
        let expected = bytes(#"{"origin":{"lat":31.81660000000000001,"lon":35.2021234567890123,"__summary":"nested"},"waypoints":[{"id":9007199254740993,"K":1,"\u212A":2}]}"#)
        let extracted = try HanlinHostSchemaValidation.extractStringMetadata(argumentsJSON: original, keys: ["__summary", "__presentation"])
        #expect(extracted.strings["__summary"] == "מסלול")
        #expect(extracted.strings["__presentation"] == "card")
        try HanlinHostSchemaValidation.requireSameValue(originalJSON: expected, projectedJSON: extracted.argumentsJSON)
        try HanlinHostSchemaValidation.requireSameValue(originalJSON: original, projectedJSON: extracted.argumentsJSON,
            removingMetadataKeys: ["__summary", "__presentation"])
    }

    @Test func forgedPortableDTOAndChangedActualDispatchBothFail() throws {
        let original = bytes(#"{"origin":{"lat":31.81660000000000001,"lon":35.2},"mode":"walking"}"#)
        let forged = try HanlinJSONValue.decodeCanonicalJSON(bytes(#"{"origin":{"lat":31.8167,"lon":35.2},"mode":"walking"}"#))
        #expect(throws: HanlinHostSchemaValidation.Failure.lossyProjection) {
            try HanlinHostSchemaValidation.requirePortableProjection(originalJSON: original, projected: forged)
        }
        for altered in [
            #"{"origin":{"lat":31.8166,"lon":35.2},"mode":"walking"}"#,
            #"{"origin":{"lat":31.81660000000000001,"lon":35.2},"mode":"driving"}"#,
            #"{"origin":{"lat":31.81660000000000001,"lon":35.2},"mode":"walking","extra":true}"#
        ] {
            #expect(throws: HanlinHostSchemaValidation.Failure.lossyProjection) {
                try HanlinHostSchemaValidation.requireSameValue(originalJSON: original, projectedJSON: bytes(altered))
            }
        }
    }

    @Test func schemaStillChecksExactNumbersBeforeDispatch() throws {
        let plan = try HanlinHostSchemaValidation(schemaJSON: bytes(#"{"type":"object","properties":{"origin":{"type":"object","properties":{"lat":{"type":"number","maximum":90},"lon":{"type":"number","maximum":180}},"required":["lat","lon"],"additionalProperties":false}},"required":["origin"],"additionalProperties":false}"#))
        try plan.validate(argumentsJSON: bytes(#"{"origin":{"lat":31.81660000000000001,"lon":35.2}}"#))
        #expect(throws: HanlinHostSchemaValidation.Failure.invalidArguments) {
            try plan.validate(argumentsJSON: bytes(#"{"origin":{"lat":90.00000000000000001,"lon":35.2}}"#))
        }
    }

    @Test func metadataTypesAndNestedFieldsCannotEraseBusinessArguments() throws {
        let original = bytes(#"{"input":{"__summary":"business"},"__summary":false,"__presentation":123}"#)
        let extracted = try HanlinHostSchemaValidation.extractStringMetadata(argumentsJSON: original, keys: ["__summary", "__presentation"])
        #expect(extracted.strings.isEmpty)
        #expect(extracted.presentKeys == ["__summary", "__presentation"])
        try HanlinHostSchemaValidation.requireSameValue(originalJSON: bytes(#"{"input":{"__summary":"business"}}"#), projectedJSON: extracted.argumentsJSON)
        #expect(throws: (any Error).self) {
            try HanlinHostSchemaValidation.extractStringMetadata(argumentsJSON: bytes(#"{"a":1,"a":2}"#), keys: [])
        }
    }

    @Test func scopeFieldsAreExactStringsAndDoNotIncludeOtherPayload() throws {
        let fields = try HanlinHostSchemaValidation.topLevelStringFields(
            argumentsJSON: bytes(#"{"action":"call_tool","server":"server-a","tool_name":"save","source":"private payload"}"#),
            keys: ["action", "server", "tool_name"])
        #expect(fields == ["action":"call_tool", "server":"server-a", "tool_name":"save"])
        #expect(throws: HanlinHostSchemaValidation.Failure.invalidArguments) {
            try HanlinHostSchemaValidation.topLevelStringFields(argumentsJSON: bytes(#"{"server":123}"#), keys: ["server"])
        }
    }
}
