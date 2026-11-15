import Foundation
import Testing
#if canImport(HanlinChatDiagnosticsProof)
@testable import HanlinChatDiagnosticsProof
#else
@testable import AI_Hanlin
#endif

@Suite("Readable diagnostic session schema")
struct AgentDiagnosticsSessionPersistenceTests {
    private func sampleSession() -> AgentDiagnosticsSession {
        var session = AgentDiagnosticsSession(id: UUID(), runID: UUID(), groupID: UUID(),
            startedAt: Date(), lastUpdatedAt: Date(), providerID: "test", modelID: "test-model",
            endpointKind: "chatCompletions", appVersion: "1", buildNumber: "1", status: "completed",
            isComplete: true, level: .fullLocalDebug, rounds: [], totals: .unavailable, efficiency: AgentEfficiencyReport())
        session.efficiency.timeToFirstAnswerToken = 0.125
        session.rounds = [.init(id: UUID(), index: 1, startedAt: Date(), trigger: "initialUserRequest",
            request: .init(byteCount: 0, contentHash: "fixture", composition: .init()),
            response: .init(visibleContent: "REOPENED_שלום🙂", streamEventCount: 1, timeToFirstToken: 0.25),
            toolCalls: [], usage: .unavailable)]
        return session
    }

    @Test func numericLatencyMetricsSurviveRedactionAndTypedSessionReopen() throws {
        let session = sampleSession()
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        let object = try JSONSerialization.jsonObject(with: encoder.encode(session))
        let safe = AgentDiagnosticsRedactor.redactKnownCredentials(
            in: AgentDiagnosticsRedactor.sanitizeJSONObject(object), credentials: ["PRIVATE_TEST_CREDENTIAL"])
        let bytes = try JSONSerialization.data(withJSONObject: safe)
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let reopened = try decoder.decode(AgentDiagnosticsSession.self, from: bytes)
        #expect(reopened.runID == session.runID && reopened.isComplete)
        #expect(reopened.efficiency.timeToFirstAnswerToken == 0.125)
        #expect(reopened.rounds[0].response.timeToFirstToken == 0.25)
        #expect(reopened.rounds[0].response.visibleContent == "REOPENED_שלום🙂")
    }

    @Test func oldRedactedLatenciesRecoverWithoutRewritingTheSourceFile() throws {
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        var object = try #require(try JSONSerialization.jsonObject(with: encoder.encode(sampleSession())) as? [String: Any])
        var efficiency = try #require(object["efficiency"] as? [String: Any])
        efficiency["timeToFirstAnswerToken"] = "<redacted>"; object["efficiency"] = efficiency
        var rounds = try #require(object["rounds"] as? [[String: Any]])
        var response = try #require(rounds[0]["response"] as? [String: Any])
        response["timeToFirstToken"] = "<redacted>"; rounds[0]["response"] = response; object["rounds"] = rounds
        let bytes = try JSONSerialization.data(withJSONObject: object)
        let url = FileManager.default.temporaryDirectory.appending(path: "old-diagnostics-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        try bytes.write(to: url)
        let decoded = try AgentDiagnosticsSession.decodeStoredFile(Data(contentsOf: url))
        #expect(decoded.efficiency.timeToFirstAnswerToken == nil && decoded.rounds[0].response.timeToFirstToken == nil)
        #expect(decoded.rounds[0].response.visibleContent == "REOPENED_שלום🙂")
        #expect(decoded.efficiency.warnings.contains { $0.contains("Timing unavailable") })
        #expect(try Data(contentsOf: url) == bytes)
    }

    @Test func legacyRepairDoesNotAcceptOtherCorruptFieldsOrGuessedNumericStrings() throws {
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        var object = try #require(try JSONSerialization.jsonObject(with: encoder.encode(sampleSession())) as? [String: Any])
        var efficiency = try #require(object["efficiency"] as? [String: Any])
        efficiency["timeToFirstAnswerToken"] = "0.125"; object["efficiency"] = efficiency
        #expect(throws: DecodingError.self) {
            try AgentDiagnosticsSession.decodeStoredFile(JSONSerialization.data(withJSONObject: object))
        }
        efficiency["timeToFirstAnswerToken"] = "<redacted>"; efficiency["modelRoundCount"] = "invalid"; object["efficiency"] = efficiency
        #expect(throws: DecodingError.self) {
            try AgentDiagnosticsSession.decodeStoredFile(JSONSerialization.data(withJSONObject: object))
        }
    }

    @Test func latencyNamesDoNotAllowCredentialStringsOrOrdinaryTokensThrough() throws {
        let safe = AgentDiagnosticsRedactor.sanitizeJSONObject([
            "timeToFirstToken": "PRIVATE_STRING_SECRET", "time_to_first_answer_token": "PRIVATE_OTHER_SECRET",
            "authToken": 123456, "access_token": "PRIVATE_ACCESS_SECRET",
            "inputTokens": 42, "reasoningTokens": 7, "timeToFirstAnswerToken": 0.75
        ]) as? [String: Any]
        let fields = try #require(safe)
        #expect(fields["timeToFirstToken"] as? String == "<redacted>")
        #expect(fields["time_to_first_answer_token"] as? String == "<redacted>")
        #expect(fields["authToken"] as? String == "<redacted>")
        #expect(fields["access_token"] as? String == "<redacted>")
        #expect(fields["inputTokens"] as? Int == 42 && fields["reasoningTokens"] as? Int == 7)
        #expect(fields["timeToFirstAnswerToken"] as? Double == 0.75)
        // NSNumber(0/1) can bridge to Swift Bool. Preserve JSON numeric types,
        // while not treating JSON boolean storage types as measurements.
        for value in [0.0, 1.0, 0.125] {
            let original = try JSONSerialization.data(withJSONObject: ["timeToFirstToken": value])
            let object = try JSONSerialization.jsonObject(with: original)
            let safe = AgentDiagnosticsRedactor.sanitizeJSONObject(object) as? [String: Any]
            #expect(safe?["timeToFirstToken"] as? Double == value)
        }
        let boolean = AgentDiagnosticsRedactor.sanitizeJSONObject(["timeToFirstToken": true]) as? [String: Any]
        #expect(boolean?["timeToFirstToken"] as? String == "<redacted>")
    }
}
