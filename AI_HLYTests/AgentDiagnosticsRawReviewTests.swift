import CryptoKit
import Foundation
import HanlinChatCore
import Testing
#if canImport(HanlinChatDiagnosticsProof)
@testable import HanlinChatDiagnosticsProof
#else
@testable import AI_Hanlin
#endif

@Suite("Deliberate encrypted capture review")
struct AgentDiagnosticsRawReviewTests {
    @Test func actualJournalBytesReplayLocallyAndMaskCredentialsAfterCoalescing() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let base = directory.appending(path: "agent-session-review"), runID = UUID(), requestID = UUID()
        let key = SymmetricKey(size: .bits256)
        let journal = AgentDiagnosticsJournal(baseURL: base, runID: runID, groupID: UUID(), full: true, keyProvider: { key })
        var request = URLRequest(url: URL(string: "https://example.invalid/chat?sig=URL_REVIEW_SECRET")!)
        request.setValue("Bearer HEADER_REVIEW_SECRET", forHTTPHeaderField: "Authorization")
        request.httpBody = Data(#"{"messages":[{"role":"user","content":"ordinary private שלום"}],"nested":{"api_key":"BODY_REVIEW_SECRET"}}"#.utf8)
        journal.transportObserver(.request(id: requestID, request: request))
        for text in ["שלום🙂 ", "HEADER_REVIEW_", "SECRET ", "BODY_REVIEW_SECRET"] {
            let payload = try JSONSerialization.data(withJSONObject: ["choices": [["delta": ["content": text]]]])
            let wire = Data("data: ".utf8) + payload + Data("\n\n".utf8)
            // Actual capture preserves even per-byte delivery boundaries.
            for byte in wire { journal.transportObserver(.bytes(id: requestID, data: Data([byte]))) }
        }
        journal.transportObserver(.bytes(id: requestID, data: Data("data: {\"choices\":[{\"delta\":{},\"finish_reason\":\"stop\"}]}\n\ndata: [DONE]\n\n".utf8)))
        journal.transportObserver(.end(id: requestID, error: nil))
        await journal.checkpoint(status: "completed")
        let raw = try Data(contentsOf: URL(filePath: base.path + ".raw.enc"))
        let capture = try AgentDiagnosticsRawReviewer.decode(raw, runID: runID, key: key)
        #expect(capture.attempts.count == 1 && capture.recordCount > 50 && !capture.incompleteTail)
        let report = try await AgentDiagnosticsRawReviewer.report(capture, apiType: "OpenAI", modelID: "fixture")
        #expect(report.text.contains("שלום🙂") && report.text.contains("ordinary private שלום"))
        #expect(report.text.contains("First parser-vs-SDK content mismatch byte: none"))
        #expect(!report.text.contains("HEADER_REVIEW_") && !report.text.contains("BODY_REVIEW_SECRET") && !report.text.contains("URL_REVIEW_SECRET"))
        #expect(!report.text.contains("bodyBase64") && !report.text.contains("combined"))
    }

    @Test func wrongKeyRunOrTamperedEnvelopeNeverProducesAReview() throws {
        let run = UUID(), attempt = UUID(), key = SymmetricKey(size: .bits256)
        let raw = try frame(run: run, attempt: attempt, sequence: 0, key: key)
        #expect(throws: (any Error).self) { _ = try AgentDiagnosticsRawReviewer.decode(raw, runID: UUID(), key: key) }
        #expect(throws: (any Error).self) { _ = try AgentDiagnosticsRawReviewer.decode(raw, runID: run, key: SymmetricKey(size: .bits256)) }
        var object = try #require(try JSONSerialization.jsonObject(with: raw) as? [String: Any])
        object["byteCount"] = 999
        let altered = try JSONSerialization.data(withJSONObject: object) + Data([0x0A])
        #expect(throws: (any Error).self) { _ = try AgentDiagnosticsRawReviewer.decode(altered, runID: run, key: key) }
        object["aad"] = "\(run)|\(attempt)|1|response_chunk"
        let badAAD = try JSONSerialization.data(withJSONObject: object) + Data([0x0A])
        #expect(throws: (any Error).self) { _ = try AgentDiagnosticsRawReviewer.decode(badAAD, runID: run, key: key) }
    }

    @Test func duplicatedAndReorderedAuthenticatedRecordsAreRejected() throws {
        let run = UUID(), attempt = UUID(), key = SymmetricKey(size: .bits256)
        let first = try frame(run: run, attempt: attempt, sequence: 0, key: key)
        let second = try frame(run: run, attempt: attempt, sequence: 2, key: key)
        #expect(throws: (any Error).self) { _ = try AgentDiagnosticsRawReviewer.decode(first + first, runID: run, key: key) }
        #expect(throws: (any Error).self) { _ = try AgentDiagnosticsRawReviewer.decode(second + first, runID: run, key: key) }
        #expect(try AgentDiagnosticsRawReviewer.decode(first + second, runID: run, key: key).recordCount == 2)
    }

    @Test func incompleteCrashTailIsExplicitAndCompleteMalformedRecordsFailClosed() throws {
        let run = UUID(), attempt = UUID(), key = SymmetricKey(size: .bits256)
        let first = try frame(run: run, attempt: attempt, sequence: 0, key: key)
        let recovered = try AgentDiagnosticsRawReviewer.decode(first + Data("{\"combined\":".utf8), runID: run, key: key)
        #expect(recovered.incompleteTail && recovered.recordCount == 1)
        #expect(throws: (any Error).self) { _ = try AgentDiagnosticsRawReviewer.decode(first + Data("broken\n".utf8), runID: run, key: key) }
        #expect(throws: (any Error).self) { _ = try AgentDiagnosticsRawReviewer.decode(Data(), runID: run, key: key) }
    }

    @Test func unknownReplayFormatFailsInsteadOfGuessingAProvider() async throws {
        let capture = AgentDiagnosticsRawReviewer.Capture(attempts: [], recordCount: 0, stageRecordCount: 0,
            incompleteTail: false, sourceSHA256: "fixture")
        await #expect(throws: (any Error).self) {
            _ = try await AgentDiagnosticsRawReviewer.report(capture, apiType: "unrecognized", modelID: "fixture")
        }
        let secrets = AgentDiagnosticsRedactor.credentials(in: ["nested": #"{"authToken":"NESTED_REVIEW_SECRET"}"#,
            "url": "https://x.invalid/?X-Amz-Signature=SIGNED_REVIEW_SECRET"])
        #expect(secrets.contains("NESTED_REVIEW_SECRET") && secrets.contains("SIGNED_REVIEW_SECRET"))
    }

    @Test func encodedURLKeysAndEchoedCookieValuesAreRedactedWithoutChangingOrdinaryUnicode() {
        let source = #"{"nested":{"api%5Fkey":"ENCODED_REVIEW_SECRET"},"url":"https://x.invalid/?%73ig=%53%49%47%4e%45%44%5f%53%45%4e%54%49%4e%45%4c&ok=1","content":"ordinary private שלום🙂"}"#
        let safe = AgentDiagnosticsRedactor.sanitize(source)
        #expect(!safe.contains("ENCODED_REVIEW_SECRET") && !safe.contains("%53%49%47"))
        #expect(safe.contains("ordinary private שלום🙂") && safe.contains("ok=1"))
        let credentials = AgentDiagnosticsRedactor.credentials(in: ["Cookie": "session=COOKIE_REVIEW_SECRET; locale=en"])
        let echoed = AgentDiagnosticsRedactor.redactKnownCredentials(in: "Content COOKIE_REVIEW_SECRET en", credentials: credentials) as? String
        #expect(echoed?.hasPrefix("Content ") == true && echoed?.contains("COOKIE_REVIEW_SECRET") == false)
        let embedded = AgentDiagnosticsRedactor.sanitize("failure at https://x.invalid/?%73ig=%53%49%47%4e%45%44%5f%53%45%4e%54%49%4e%45%4c&ok=1")
        #expect(!embedded.contains("%53%49%47") && embedded.contains("ok=1"))
    }

    private func frame(run: UUID, attempt: UUID, sequence: Int, key: SymmetricKey) throws -> Data {
        let data = Data("data: [DONE]\n\n".utf8), aad = "\(run.uuidString)|\(attempt.uuidString)|\(sequence)|response_chunk"
        let sealed = try AES.GCM.seal(data, using: key, authenticating: Data(aad.utf8))
        return try JSONSerialization.data(withJSONObject: ["schemaVersion": 1, "aad": aad,
            "combined": try #require(sealed.combined).base64EncodedString(), "byteCount": data.count,
            "sha256": SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()]) + Data([0x0A])
    }
}
