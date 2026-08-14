import Foundation
import Testing
@testable import HanlinPlatformContracts

@Test
func jsonPrimitivesUseCanonicalLexicalForms() throws {
    let fixtures: [(HanlinJSONValue, String)] = [
        (.null, "null"),
        (.bool(false), "false"),
        (.bool(true), "true"),
        (.string(""), "\"\""),
        (.string("hello\n/world"), "\"hello\\n/world\""),
        (.integer(0), "0"),
        (.integer(1), "1"),
        (.integer(-1), "-1"),
        (.integer(.min), String(Int64.min)),
        (.integer(.max), String(Int64.max)),
        (.number(0.0), "0.0"),
        (.number(-0.0), "-0.0"),
        (.number(1.0), "1.0"),
        (.number(-1.0), "-1.0"),
        (.number(1.5), "1.5")
    ]

    for (value, expected) in fixtures {
        let data = try value.canonicalJSONData()
        #expect(String(decoding: data, as: UTF8.self) == expected)
        let decoded = try HanlinJSONValue.decodeCanonicalJSON(data)
        switch (value, decoded) {
        case let (.number(original), .number(roundTripped)):
            #expect(original.bitPattern == roundTripped.bitPattern)
        default:
            #expect(value == decoded)
        }
    }
}

@Test
func binary64ExtremesRoundTripBitIdentically() throws {
    let values: [Double] = [
        .leastNonzeroMagnitude,
        .leastNormalMagnitude,
        .greatestFiniteMagnitude,
        1e-200,
        1e200,
        9_007_199_254_740_992.0,
        -9_007_199_254_740_992.0
    ]

    for value in values {
        let data = try HanlinJSONValue.number(value).canonicalJSONData()
        let decoded = try HanlinJSONValue.decodeCanonicalJSON(data)
        guard case let .number(roundTripped) = decoded else {
            Issue.record("binary64 token decoded as a different numeric case")
            continue
        }
        #expect(roundTripped.bitPattern == value.bitPattern)
    }
}

@Test
func richValuesUseExactTaggedIntegerNumberAndDataRepresentations() throws {
    let values: [HanlinValue] = [
        .integer(.min),
        .integer(.max),
        .number(-0.0),
        .number(.leastNonzeroMagnitude),
        .number(.greatestFiniteMagnitude),
        .data(Data([0x00, 0xFF, 0x10])),
        .array([.null, .bool(true), .string("שלום")]),
        .object(["z": .integer(1), "a": .number(1.0)])
    ]

    for value in values {
        let data = try value.canonicalJSONData()
        let decoded = try HanlinValue.decodeCanonicalJSON(data)
        switch (value, decoded) {
        case let (.number(original), .number(roundTripped)):
            #expect(original.bitPattern == roundTripped.bitPattern)
        default:
            #expect(decoded == value)
        }
    }

    let signedZero = String(decoding: try HanlinValue.number(-0.0).canonicalJSONData(), as: UTF8.self)
    #expect(signedZero.contains("8000000000000000"))
}

@Test
func jsonObjectsSortByUnmodifiedUTF8KeyBytes() throws {
    let decomposed = "e\u{301}"
    let value = HanlinJSONValue.object([
        "é": .integer(3),
        "z": .integer(2),
        decomposed: .integer(1)
    ])
    let text = String(decoding: try value.canonicalJSONData(), as: UTF8.self)
    #expect(text == "{\"\(decomposed)\":1,\"z\":2,\"é\":3}")
    #expect(text.contains("\(decomposed)"))
    #expect(text.contains("é"))
}

@Test
func jsonDecoderRejectsDuplicateKeysAndOutOfRangeIntegers() {
    #expect(throws: HanlinContractError.self) {
        try HanlinJSONValue.decodeCanonicalJSON(Data(#"{"a":1,"a":2}"#.utf8))
    }
    #expect(throws: HanlinContractError.self) {
        try HanlinJSONValue.decodeCanonicalJSON(Data(#"9223372036854775808"#.utf8))
    }
    #expect(throws: HanlinContractError.self) {
        try HanlinJSONValue.decodeCanonicalJSON(Data(#"-9223372036854775809"#.utf8))
    }
}

@Test
func conversionsRejectLossAndNonFiniteNumbers() throws {
    #expect(throws: HanlinContractError.self) {
        try HanlinValue.finiteNumber(.nan)
    }
    #expect(throws: HanlinContractError.self) {
        try HanlinJSONValue.number(.infinity).canonicalJSONData()
    }
    #expect(throws: HanlinContractError.self) {
        try HanlinJSONValue.number(-.infinity).canonicalJSONData()
    }
    #expect(throws: HanlinContractError.self) {
        try HanlinValue.integer(9_007_199_254_740_992).jsonValue(
            destination: .javaScriptBinary64
        )
    }
    #expect(throws: HanlinContractError.self) {
        try HanlinValue.data(Data([1])).jsonValue()
    }

    let safeEdges: [Int64] = [
        -9_007_199_254_740_991,
        -9_007_199_254_740_990,
        9_007_199_254_740_990,
        9_007_199_254_740_991
    ]
    for edge in safeEdges {
        _ = try HanlinValue.integer(edge).jsonValue(destination: .javaScriptBinary64)
    }
}

@Test
func canonicalLimitsRejectExcessiveDepthAndSize() throws {
    let depthLimited = HanlinValueLimits(maximumDepth: 1)
    #expect(throws: HanlinContractError.self) {
        try HanlinJSONValue.array([.array([.null])]).canonicalJSONData(
            limits: depthLimited
        )
    }

    let memberLimited = HanlinValueLimits(maximumObjectMembers: 1)
    #expect(throws: HanlinContractError.self) {
        try HanlinJSONValue.decodeCanonicalJSON(
            Data(#"{"a":1,"b":2}"#.utf8),
            limits: memberLimited
        )
    }

    let payloadLimited = HanlinValueLimits(maximumPayloadBytes: 4)
    #expect(throws: HanlinContractError.self) {
        try HanlinJSONValue.string("1234").canonicalJSONData(limits: payloadLimited)
    }
}

@Test
func valueSchemasValidateAndRoundTrip() throws {
    let schema = HanlinValueSchema.object(
        properties: [
            "name": .string(minLength: 1, maxLength: 100, pattern: nil),
            "payload": .data(maxBytes: 1_024)
        ],
        required: ["name"],
        additionalProperties: false
    )
    try schema.validateDefinition()
    let data = try JSONEncoder().encode(schema)
    #expect(try JSONDecoder().decode(HanlinValueSchema.self, from: data) == schema)

    #expect(throws: HanlinContractError.self) {
        try HanlinValueSchema.object(
            properties: [:],
            required: ["missing"],
            additionalProperties: false
        ).validateDefinition()
    }
    #expect(throws: HanlinContractError.self) {
        try HanlinValueSchema.oneOf([]).validateDefinition()
    }
}

@Test
func jsonSchemaDocumentsPreserveUnknownAndNarrowingKeywords() throws {
    let source = Data(
        #"{"$schema":"https://json-schema.org/draft/2020-12/schema","additionalProperties":false,"futureSecurityKeyword":{"mode":"strict"},"type":"object","unevaluatedProperties":false}"#.utf8
    )
    let document = try HanlinJSONSchemaDocument.decodeCanonicalJSON(source)
    guard case let .object(root) = document.root else {
        Issue.record("schema root was not retained as an object")
        return
    }
    #expect(root["futureSecurityKeyword"] == .object(["mode": .string("strict")]))
    #expect(root["additionalProperties"] == .bool(false))
    #expect(root["unevaluatedProperties"] == .bool(false))

    let encoded = try document.canonicalJSONData()
    let decoded = try HanlinJSONSchemaDocument.decodeCanonicalJSON(encoded)
    #expect(decoded.root == document.root)
    #expect(try decoded.canonicalJSONData() == encoded)
}
