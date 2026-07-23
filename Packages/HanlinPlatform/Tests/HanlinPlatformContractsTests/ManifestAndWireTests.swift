import Foundation
import Testing
@testable import HanlinPlatformContracts

@Test
func manifestRoundTripsDeterministically() throws {
    let descriptor = try ContractFixtures.descriptor()
    try descriptor.validate()

    let data = try descriptor.canonicalJSONData()
    let decoded = try HanlinAppDescriptor.decodeAndValidate(data)
    #expect(decoded == descriptor)
    #expect(try decoded.canonicalJSONData() == data)
}

@Test
func manifestSchemaResourceIsValidJSONAndUnknownFieldsAreTolerated() throws {
    let schemaData = try HanlinManifestSchema.data()
    _ = try JSONSerialization.jsonObject(with: schemaData)

    let descriptor = try ContractFixtures.descriptor()
    let data = try descriptor.canonicalJSONData()
    let json = try #require(String(data: data, encoding: .utf8))
    let withUnknownField = Data(
        "{\"futureField\":{\"enabled\":true},\(json.dropFirst())".utf8
    )
    let decoded = try HanlinAppDescriptor.decodeAndValidate(withUnknownField)
    #expect(decoded == descriptor)
}

@Test
func manifestRejectsUnsafePathsAndUnsupportedVersions() throws {
    let unsafe = HanlinEntryPointDescriptor(
        kind: .app,
        handler: "../outside.tsx",
        allowedContexts: [.mainApplication]
    )
    let unsafeDescriptor = try ContractFixtures.descriptor(
        entryPoints: [unsafe]
    )
    #expect(throws: HanlinContractError.self) {
        try unsafeDescriptor.validate()
    }

    let futureDescriptor = try ContractFixtures.descriptor(
        schemaVersion: .init(major: 2, minor: 0)
    )
    #expect(throws: HanlinContractError.self) {
        try futureDescriptor.validate()
    }
}

@Test
func manifestRejectsDuplicateCanonicalIdentifiers() throws {
    let routeID = try HanlinRouteID(validating: "details")
    let route = HanlinRouteDescriptor(
        id: routeID,
        title: try ContractFixtures.localized("Details"),
        parameterSchema: .object(
            properties: [:],
            required: [],
            additionalProperties: false
        )
    )
    let descriptor = try ContractFixtures.descriptor(routes: [route, route])
    #expect(throws: HanlinContractError.self) {
        try descriptor.validate()
    }
}

@Test
func wireEnvelopeRoundTripsAndEnforcesRequestIdentity() throws {
    let envelope = HanlinScriptEnvelope(
        protocolVersion: .init(major: 1, minor: 0),
        sessionID: try HanlinSessionID(validating: "session.1"),
        sequence: 7,
        requestID: try HanlinRequestID(validating: "request.7"),
        kind: .request,
        payload: .object([
            "operation": .string("storage.get")
        ])
    )
    try envelope.validate()
    let data = try envelope.canonicalJSONData()
    #expect(try HanlinScriptEnvelope.decodeAndValidate(data) == envelope)

    let missingRequest = HanlinScriptEnvelope(
        protocolVersion: .init(major: 1, minor: 0),
        sessionID: try HanlinSessionID(validating: "session.1"),
        sequence: 8,
        kind: .response,
        payload: .null
    )
    #expect(throws: HanlinContractError.self) {
        try missingRequest.validate()
    }
}

@Test
func wireEnvelopeRejectsUnknownVersionMalformedKindAndOversizedPayload() throws {
    let future = HanlinScriptEnvelope(
        protocolVersion: .init(major: 2, minor: 0),
        sessionID: try HanlinSessionID(validating: "session.1"),
        sequence: 1,
        kind: .hello,
        payload: .null
    )
    #expect(throws: HanlinContractError.self) {
        try future.validate()
    }

    let malformed = Data(
        """
        {
          "kind": "future",
          "payload": {"type": "null"},
          "protocolVersion": "1.0",
          "sequence": 1,
          "sessionID": "session.1"
        }
        """.utf8
    )
    #expect(throws: DecodingError.self) {
        try JSONDecoder().decode(HanlinScriptEnvelope.self, from: malformed)
    }

    let oversized = HanlinScriptEnvelope(
        protocolVersion: .init(major: 1, minor: 0),
        sessionID: try HanlinSessionID(validating: "session.1"),
        sequence: 2,
        kind: .event,
        payload: .string(String(repeating: "x", count: 100))
    )
    #expect(throws: HanlinContractError.self) {
        try oversized.validate(maximumPayloadBytes: 16)
    }
}
