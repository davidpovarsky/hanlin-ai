import CryptoKit
import Foundation
import HanlinChatCore

struct AgentDiagnosticsRawReview: Identifiable, Sendable {
    let id = UUID()
    let text: String
}

/// Deliberate, response-only local inspection. Decrypted bytes stay in memory;
/// only coalesced, re-redacted parser output enters the review/share model.
enum AgentDiagnosticsRawReviewer {
    struct Attempt: Sendable {
        let id: UUID
        var request: Data?
        var chunks: [Data] = []
    }
    struct Capture: Sendable {
        let attempts: [Attempt]
        let recordCount: Int
        let stageRecordCount: Int
        let incompleteTail: Bool
        let sourceSHA256: String
    }
    private struct Frame: Decodable {
        let schemaVersion: Int
        let aad: String
        let combined: String
        let byteCount: Int
        let sha256: String
    }

    static func reviewLocally(sessionJSON: URL, runID: UUID, modelID: String, apiType: String) async throws -> AgentDiagnosticsRawReview {
        let work = Task.detached(priority: .utility) {
            let base = try AgentDiagnosticsExporter.ownedSessionBase(sessionJSON)
            let raw = try AgentDiagnosticsExporter.readOwnedAsset(URL(filePath: base.path + ".raw.enc"))
            let capture = try decode(raw, runID: runID, key: AgentDiagnosticsJournal.existingDeviceKey())
            return try await report(capture, apiType: apiType, modelID: modelID)
        }
        return try await withTaskCancellationHandler { try await work.value } onCancel: { work.cancel() }
    }

    static func decode(_ bytes: Data, runID: UUID, key: SymmetricKey) throws -> Capture {
        guard !bytes.isEmpty, bytes.count <= 64 * 1024 * 1024 else { throw CocoaError(.fileReadTooLarge) }
        let lines = bytes.split(separator: 0x0A, omittingEmptySubsequences: false)
        var order: [UUID] = [], attempts: [UUID: Attempt] = [:]
        var previousSequence = -1, count = 0, stages = 0, plaintextBytes = 0
        var incompleteTail = false
        for (index, line) in lines.enumerated() {
            try Task.checkCancellation()
            if line.isEmpty, index == lines.count - 1 { continue }
            guard count < 100_000 else { throw CocoaError(.fileReadTooLarge) }
            // A crash can leave an incomplete final envelope. Never repair or
            // silently skip a malformed complete line or an authentication error.
            guard let frame = try? JSONDecoder().decode(Frame.self, from: Data(line)) else {
                if index == lines.count - 1, bytes.last != 0x0A { incompleteTail = true; break }
                throw CocoaError(.fileReadCorruptFile)
            }
            let header = frame.aad.split(separator: "|", omittingEmptySubsequences: false)
            guard frame.schemaVersion == 1, header.count == 4,
                  UUID(uuidString: String(header[0])) == runID,
                  let attemptID = UUID(uuidString: String(header[1])),
                  let sequence = Int(header[2]), sequence > previousSequence,
                  frame.byteCount >= 0, frame.byteCount <= 32 * 1024 * 1024,
                  frame.sha256.count == 64,
                  let combined = Data(base64Encoded: frame.combined) else { throw CocoaError(.fileReadCorruptFile) }
            let kind = String(header[3])
            guard kind == "request" || kind == "response_chunk" ||
                    (kind.hasPrefix("stage_") && kind.utf8.count <= 256 && kind.range(of: "^[A-Za-z0-9._-]+$", options: .regularExpression) != nil)
            else { throw CocoaError(.fileReadCorruptFile) }
            let plaintext = try AES.GCM.open(AES.GCM.SealedBox(combined: combined), using: key, authenticating: Data(frame.aad.utf8))
            guard plaintext.count == frame.byteCount, digest(plaintext) == frame.sha256 else { throw CocoaError(.fileReadCorruptFile) }
            plaintextBytes += plaintext.count
            guard plaintextBytes <= 32 * 1024 * 1024 else { throw CocoaError(.fileReadTooLarge) }
            previousSequence = sequence
            count += 1
            if kind.hasPrefix("stage_") { stages += 1; continue }
            if attempts[attemptID] == nil { order.append(attemptID); attempts[attemptID] = Attempt(id: attemptID) }
            if kind == "request" {
                guard attempts[attemptID]?.request == nil else { throw CocoaError(.fileReadCorruptFile) }
                attempts[attemptID]?.request = plaintext
            } else { attempts[attemptID]?.chunks.append(plaintext) }
        }
        return Capture(attempts: order.compactMap { attempts[$0] }, recordCount: count,
            stageRecordCount: stages, incompleteTail: incompleteTail, sourceSHA256: digest(bytes))
    }

    static func report(_ capture: Capture, apiType: String, modelID: String) async throws -> AgentDiagnosticsRawReview {
        guard ["OpenAI", "Anthropic", "Gemini"].contains(apiType) else { throw CocoaError(.fileReadCorruptFile) }
        var requests: [UUID: String] = [:], credentials: Set<String> = []
        for attempt in capture.attempts {
            guard let request = attempt.request else { continue }
            guard var object = try JSONSerialization.jsonObject(with: request) as? [String: Any],
                  let body64 = object.removeValue(forKey: "bodyBase64") as? String,
                  let body = Data(base64Encoded: body64) else { throw CocoaError(.fileReadCorruptFile) }
            if let decoded = try? JSONSerialization.jsonObject(with: body, options: .fragmentsAllowed) { object["body"] = decoded }
            else if let text = String(data: body, encoding: .utf8) { object["body"] = text }
            else { object["body"] = "<non-UTF8 body omitted; exact encrypted source retained locally>" }
            credentials.formUnion(AgentDiagnosticsRedactor.credentials(in: object))
            requests[attempt.id] = AgentDiagnosticsRedactor.sanitizedJSONString(from: object, pretty: true)
        }
        var sections = ["""
        Local encrypted capture review — response-only offline replay
        Authenticated records: \(capture.recordCount); stage records: \(capture.stageRecordCount).
        Incomplete final envelope omitted: \(capture.incompleteTail).
        Encrypted source SHA-256: \(capture.sourceSHA256).
        API format explicitly selected for replay: \(apiType).
        Only stored records are authenticated; completeness is not established.
        Original timing, HTTP status/headers, request context and tool executors are not replayed.
        Stage-record bodies are not displayed here. Use the ordinary coalesced stage snapshots for comparison.
        No network or tool side effects. This is not APIManager, accumulator or rendered-bubble parity.
        This report is redacted and is not an exact raw export. The device key and encrypted source are excluded.
        """]
        if capture.attempts.isEmpty { sections.append("NOT_CAPTURED: no transport request or response records are available.") }
        for attempt in capture.attempts {
            try Task.checkCancellation()
            sections.append("Attempt \(attempt.id.uuidString)\nRequest:\n\(requests[attempt.id] ?? "NOT_CAPTURED")")
            let configuration = HanlinChatModelConfiguration(modelID: modelID, company: apiType, apiType: apiType,
                endpoint: "https://offline-replay.invalid/v1/chat/completions", credential: "offline-placeholder")
            let result = try await HanlinCapturedStreamReplay.replay(
                chunks: attempt.chunks.map { HanlinCapturedStreamChunk(bytes: $0) }, configuration: configuration)
            var responseHash = SHA256()
            for chunk in attempt.chunks { responseHash.update(data: chunk) }
            let responseDigest = responseHash.finalize().map { String(format: "%02x", $0) }.joined()
            sections.append("""
            Recorded response: \(attempt.chunks.count) chunks / \(attempt.chunks.reduce(0) { $0 + $1.count }) bytes.
            Exact recorded response SHA-256: \(responseDigest).
            Direct content SHA-256: \(digest(Data(result.directContent.utf8))). SDK content SHA-256: \(digest(Data(result.sdkContent.utf8))).
            Direct parser finish: \(result.directFinishReason ?? "NOT_OBSERVED"). SDK finish: \(result.sdkFinishReason ?? "NOT_OBSERVED").
            First parser-vs-SDK content mismatch byte: \(result.firstContentMismatchByteOffset.map(String.init) ?? "none").
            First U+FFFD byte in direct content: \(replacementOffset(result.directContent)); SDK content: \(replacementOffset(result.sdkContent)).
            Direct content:\n\(result.directContent)
            SDK content:\n\(result.sdkContent)
            Direct reasoning:\n\(result.directReasoning)
            SDK reasoning:\n\(result.sdkReasoning)
            SDK error: \(result.sdkError ?? "none")
            Coverage warnings: \(result.warnings.joined(separator: "; "))
            """)
        }
        let text = sections.joined(separator: "\n\n")
        guard text.utf8.count <= 16 * 1024 * 1024 else { throw CocoaError(.fileReadTooLarge) }
        let safe = AgentDiagnosticsRedactor.redactKnownCredentials(in: AgentDiagnosticsRedactor.sanitize(text), credentials: credentials)
        guard let safeText = safe as? String else { throw CocoaError(.fileReadCorruptFile) }
        return AgentDiagnosticsRawReview(text: safeText)
    }

    private static func digest(_ bytes: Data) -> String { SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined() }
    private static func replacementOffset(_ text: String) -> String {
        guard let match = text.range(of: "\u{FFFD}") else { return "none" }
        return String(text[..<match.lowerBound].utf8.count)
    }
}
