import Foundation
import Testing
@testable import HanlinPlatformContracts

@Test
func valuesRoundTripWithDeterministicEncoding() throws {
    let first = HanlinValue.object([
        "z": .integer(3),
        "a": .array([
            .string("hello"),
            .bool(true),
            .null
        ])
    ])
    let second = HanlinValue.object([
        "a": .array([
            .string("hello"),
            .bool(true),
            .null
        ]),
        "z": .integer(3)
    ])

    let firstData = try first.canonicalJSONData()
    let secondData = try second.canonicalJSONData()
    #expect(firstData == secondData)
    #expect(try HanlinValue.decodeCanonicalJSON(firstData) == first)
}

@Test
func valuesRejectNonFiniteAndUnknownRepresentations() {
    #expect(throws: HanlinContractError.self) {
        try HanlinValue.finiteNumber(.infinity)
    }
    #expect(throws: HanlinContractError.self) {
        try HanlinValue.number(.nan).canonicalJSONData()
    }
    #expect(throws: DecodingError.self) {
        try HanlinValue.decodeCanonicalJSON(
            Data(#"{"type":"future","value":1}"#.utf8)
        )
    }
}

@Test
func schemasValidateAndRoundTrip() throws {
    let schema = HanlinJSONSchema.object(
        properties: [
            "name": .string(minLength: 1, maxLength: 100, pattern: nil),
            "tags": .array(
                items: .string(
                    minLength: 1,
                    maxLength: 30,
                    pattern: nil
                ),
                minItems: 0,
                maxItems: 10
            )
        ],
        required: ["name"],
        additionalProperties: false
    )
    try schema.validateDefinition()

    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let data = try encoder.encode(schema)
    let decoded = try JSONDecoder().decode(HanlinJSONSchema.self, from: data)
    #expect(decoded == schema)
    #expect(try encoder.encode(decoded) == data)
}

@Test
func schemasRejectMalformedDefinitions() {
    #expect(throws: HanlinContractError.self) {
        try HanlinJSONSchema.object(
            properties: [:],
            required: ["missing"],
            additionalProperties: false
        ).validateDefinition()
    }
    #expect(throws: HanlinContractError.self) {
        try HanlinJSONSchema.array(
            items: .any,
            minItems: 3,
            maxItems: 2
        ).validateDefinition()
    }
    #expect(throws: HanlinContractError.self) {
        try HanlinJSONSchema.oneOf([]).validateDefinition()
    }
}
