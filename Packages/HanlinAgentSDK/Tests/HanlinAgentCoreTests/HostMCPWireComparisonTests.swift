import Foundation
@testable import HanlinAgentCore
import JSON
import Testing

@Suite(.serialized) struct HostMCPWireComparisonTests {
    @Test(.timeLimit(.minutes(2)))
    func largeOriginalUTF8SurvivesOrderAndEscapeProjection() throws {
        let (original, projection) = try largeWireDocuments()
        #expect(original.count > 8 * 1_024 * 1_024)
        #expect(original != projection)
        try HanlinHostSchemaValidation.requireSameMCPWireValue(
            originalJSON: original, projectedJSON: projection
        )
    }

    @Test(.timeLimit(.minutes(2)))
    func largeOriginalUTF8RejectsAMutationAtTheTextTail() throws {
        let (original, _) = try largeWireDocuments()
        var changed = original
        // The last decoded payload byte, after the entire >8 MiB prefix, is ASCII Z.
        let tail = try #require(changed.lastIndex(of: 0x5a))
        changed[tail] = 0x58
        #expect(throws: HanlinHostSchemaValidation.Failure.lossyProjection) {
            try HanlinHostSchemaValidation.requireSameMCPWireValue(
                originalJSON: original, projectedJSON: changed
            )
        }
    }

    @Test func metadataIsPartOfTheExactWireValue() throws {
        let original = bytes(#"{"_meta":{"trace":"one"},"__summary":"keep","value":1}"#)
        for projected in [
            #"{"_meta":{"trace":"two"},"__summary":"keep","value":1}"#,
            #"{"__summary":"keep","value":1}"#,
            #"{"_meta":{"trace":"one"},"value":1}"#,
        ] {
            #expect(throws: HanlinHostSchemaValidation.Failure.lossyProjection) {
                try HanlinHostSchemaValidation.requireSameMCPWireValue(
                    originalJSON: original, projectedJSON: bytes(projected)
                )
            }
        }
    }

    @Test func exactDecimalsAndJSONKindsSurviveWithoutBinary64Rounding() throws {
        try same(#"{"n":9007199254740993,"decimal":1.2300,"zero":-0}"#,
                 #"{"zero":0.0,"decimal":123e-2,"n":9007199254740993}"#)
        for (original, projection) in [
            ("9007199254740993", "9007199254740992"),
            ("1.234567890123456789", "1.2345678901234567"),
            ("true", "1"), ("null", "false"), ("[]", "{}"),
        ] {
            #expect(throws: HanlinHostSchemaValidation.Failure.lossyProjection) {
                try same(original, projection)
            }
        }
    }

    @Test func scalarKeysAndStringsDoNotUseSwiftCanonicalEquivalence() throws {
        try same(#"{"K":1,"\u212A":2,"é":3,"e\u0301":4}"#,
                 #"{"e\u0301":4,"é":3,"\u212A":2,"K":1}"#)
        for (original, projection) in [
            (#""K""#, #""\u212A""#),
            (#""é""#, #""e\u0301""#),
            (#"{"K":1,"\u212A":2}"#, #"{"K":2}"#),
            (#"{"é":3,"e\u0301":4}"#, #"{"é":4}"#),
        ] {
            #expect(throws: HanlinHostSchemaValidation.Failure.lossyProjection) {
                try same(original, projection)
            }
        }
    }

    @Test func strictSyntaxAndDuplicateDecodedKeysStillFail() throws {
        for malformed in [#"{"a":1,"\u0061":2}"#, #""\uD800""#, "{} true"] {
            #expect(throws: JSONFailure.self) { try same(malformed, malformed) }
        }
        let malformedUTF8 = Data([0x22, 0xc0, 0xaf, 0x22])
        #expect(throws: JSONFailure.self) {
            try HanlinHostSchemaValidation.requireSameMCPWireValue(
                originalJSON: malformedUTF8, projectedJSON: malformedUTF8
            )
        }
    }

    @Test func depthKeyAndNumericLimitsRemainTheOriginalPolicy() throws {
        try expectResource(.maxDepth,
            String(repeating: "[", count: 65) + "0" + String(repeating: "]", count: 65))
        try expectResource(.keyBytes, "{\"" + String(repeating: "k", count: 16_385) + "\":0}")
        try expectResource(.numberDigits, String(repeating: "1", count: 1_025))
        try expectResource(.absoluteExponent, "1e100001")
    }

    @Test func cancellationProducesNoComparisonVerdict() async throws {
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            try HanlinHostSchemaValidation.requireSameMCPWireValue(
                originalJSON: Data("{}".utf8), projectedJSON: Data("{}".utf8)
            )
        }
        do { try await task.value; Issue.record("Cancelled wire comparison returned a verdict") }
        catch { #expect(error is CancellationError) }
    }

    @Test func existingSchemaConsentAndProjectionAdmissionRemainBounded() throws {
        let oversized = bytes("\"" + String(repeating: "x", count: 1_048_577) + "\"")
        #expect(throws: HanlinHostSchemaValidation.Failure.inputTooLarge) {
            try HanlinHostSchemaValidation.requireSameValue(originalJSON: oversized, projectedJSON: oversized)
        }
        #expect(throws: HanlinHostSchemaValidation.Failure.inputTooLarge) {
            _ = try HanlinHostSchemaValidation(schemaJSON: oversized)
        }
        #expect(throws: HanlinHostSchemaValidation.Failure.inputTooLarge) {
            _ = try HanlinHostSchemaValidation.topLevelStringFields(argumentsJSON: oversized, keys: ["id"])
        }
    }

    @Test func finitePoliciesChangeOnlyTheirDeclaredByteAndWorkMetrics() throws {
        let originalCount = 12_000_039, projectedCount = 12_000_043
        let parsing = try HanlinHostSchemaValidation.mcpWireParseLimits(inputByteCount: originalCount)
        let comparison = try HanlinHostSchemaValidation.mcpWireComparisonLimits(
            originalByteCount: originalCount, projectedByteCount: projectedCount
        )
        var original = JSONLimits.conservative
        original[.inputBytes] = 1_048_576
        original[.schemaBytes] = 1_048_576
        #expect(JSONResourceMetric.allCases.count == 49)
        let parseChanges = ["inputBytes", "stringBytes", "aggregateTextBytes", "retainedBytes", "workUnits"]
        let comparisonChanges = ["stringBytes", "aggregateTextBytes", "workUnits"]
        for metric in JSONResourceMetric.allCases {
            if !parseChanges.contains(metric.rawValue) { #expect(parsing[metric] == original[metric]) }
            if !comparisonChanges.contains(metric.rawValue) { #expect(comparison[metric] == original[metric]) }
        }
        #expect(parsing[.inputBytes] == UInt64(originalCount))
        #expect(parsing[.stringBytes] == UInt64(originalCount))
        #expect(parsing[.aggregateTextBytes] == UInt64(originalCount))
        #expect(parsing[.retainedBytes] == original[.retainedBytes] + 3 * UInt64(originalCount))
        #expect(parsing[.workUnits] == original[.workUnits] + 6 * UInt64(originalCount))
        #expect(comparison[.stringBytes] == UInt64(projectedCount))
        #expect(comparison[.aggregateTextBytes] == UInt64(originalCount + projectedCount))
        #expect(comparison[.workUnits] == original[.workUnits] + 2 * UInt64(originalCount + projectedCount))
        try parsing.validate()
        try comparison.validate()
    }

    @Test func checkedPolicyArithmeticRejectsUnrepresentableBudgetsWithoutAllocation() throws {
        #expect(throws: HanlinHostSchemaValidation.Failure.inputTooLarge) {
            _ = try HanlinHostSchemaValidation.mcpWireParseLimits(inputByteCount: -1)
        }
        #expect(throws: HanlinHostSchemaValidation.Failure.inputTooLarge) {
            _ = try HanlinHostSchemaValidation.mcpWireComparisonLimits(originalByteCount: 0, projectedByteCount: -1)
        }
        #expect(throws: (any Error).self) {
            _ = try HanlinHostSchemaValidation.mcpWireParseLimits(inputByteCount: Int.max)
        }
        #expect(throws: (any Error).self) {
            _ = try HanlinHostSchemaValidation.mcpWireComparisonLimits(
                originalByteCount: Int.max - 1, projectedByteCount: Int.max - 1
            )
        }
        // The largest input permitted by the three-byte retention allowance is finite.
        let lastRetainableCount = (Int.max - 1 - Int(JSONLimits.conservative[.retainedBytes])) / 3
        let admitted = try HanlinHostSchemaValidation.mcpWireParseLimits(inputByteCount: lastRetainableCount)
        #expect(admitted[.retainedBytes] < UInt64(Int.max))
        #expect(throws: JSONFailure.self) {
            _ = try HanlinHostSchemaValidation.mcpWireParseLimits(inputByteCount: lastRetainableCount + 1)
        }
        let zero = try HanlinHostSchemaValidation.mcpWireParseLimits(inputByteCount: 0)
        #expect(zero[.inputBytes] == 0)
        #expect(throws: JSONFailure.self) { try same("", "") }
    }

    private func bytes(_ text: String) -> Data { Data(text.utf8) }

    private func same(_ original: String, _ projection: String) throws {
        try HanlinHostSchemaValidation.requireSameMCPWireValue(
            originalJSON: bytes(original), projectedJSON: bytes(projection)
        )
    }

    private func expectResource(_ metric: JSONResourceMetric, _ document: String) throws {
        do { try same(document, document); Issue.record("Expected a finite JSON resource rejection") }
        catch let error as JSONFailure {
            #expect(error.category == .resource)
            #expect(error.resource?.metric == metric)
        }
    }

    private func largeWireDocuments() throws -> (Data, Data) {
        // Same Hebrew/emoji/newline repetition as the original real MCP transport acceptance.
        let payload = String(repeating: "שלום 😀\n", count: 800_000) + "Z"
        let encoded = try JSONSerialization.data(withJSONObject: payload, options: [.fragmentsAllowed])
        var original = bytes(#"{"payload":"#)
        original.append(encoded)
        original.append(bytes(#","tail":"end"}"#))
        var projection = bytes(#"{"tail":"e\u006ed","payload":"#)
        projection.append(encoded)
        projection.append(bytes("}"))
        return (original, projection)
    }
}
