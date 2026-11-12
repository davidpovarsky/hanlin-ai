import CryptoKit
import Foundation
import HanlinChatCore
import Testing
@testable import AI_Hanlin

@Suite("Automatic diagnostic journal")
struct AgentDiagnosticsJournalTests {
    @Test func splitUTF8TransportRetainsExactEncryptedBytesAndReadableSSE() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let base = directory.appending(path: "agent-session-fixture")
        let key = SymmetricKey(size: .bits256)
        let journal = AgentDiagnosticsJournal(baseURL: base, runID: UUID(), groupID: UUID(), full: true, keyProvider: { key })
        let id = UUID(), round = UUID()
        journal.setRound(round)
        var request = URLRequest(url: URL(string: "https://example.invalid/chat?sig=URL_SECRET")!)
        request.setValue("Bearer HEADER_SECRET", forHTTPHeaderField: "Authorization")
        request.httpBody = Data(#"{"messages":[{"role":"user","content":"שלום 🙂"}],"api_key":"BODY_SECRET"}"#.utf8)
        journal.transportObserver(.request(id: id, request: request))
        let wire = Data("data: {\"choices\":[{\"delta\":{\"content\":\"שָׁלוֹם🙂مرحبا中文\"}}]}\r\n\r\ndata: [DONE]\n\n".utf8)
        // Every possible scalar is split, and multiple frames share the body.
        for byte in wire { journal.transportObserver(.bytes(id: id, data: Data([byte]))) }
        journal.transportObserver(.end(id: id, error: nil))
        await journal.checkpoint(status: "completed")
        let eventsURL = URL(filePath: base.path + "-stage-events.jsonl")
        let readable = try String(contentsOf: eventsURL, encoding: .utf8)
        #expect(!readable.contains("HEADER_SECRET") && !readable.contains("BODY_SECRET") && !readable.contains("URL_SECRET"))
        let snapshots = try String(contentsOf: URL(filePath: base.path + "-stage-snapshots.json"), encoding: .utf8)
        #expect(snapshots.contains("שָׁלוֹם🙂مرحبا中文"))
        #expect(!readable.contains("�"))
        let events = try readable.split(separator: "\n").map { try #require(try JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any]) }
        #expect(events.compactMap { $0["roundID"] as? String }.allSatisfy { $0 == round.uuidString })
        let rawURL = URL(filePath: base.path + ".raw.enc")
        let raw = try Data(contentsOf: rawURL)
        #expect(!String(decoding: raw, as: UTF8.self).contains("HEADER_SECRET"))
        var restored = Data()
        for line in raw.split(separator: 0x0A) {
            let frame = try #require(try JSONSerialization.jsonObject(with: Data(line)) as? [String: Any])
            let aad = try #require(frame["aad"] as? String)
            let encoded = try #require(frame["combined"] as? String)
            let combined = try #require(Data(base64Encoded: encoded))
            let box = try AES.GCM.SealedBox(combined: combined)
            let plaintext = try AES.GCM.open(box, using: key, authenticating: Data(aad.utf8))
            if aad.hasSuffix("|response_chunk") { restored.append(plaintext) }
            #expect(throws: (any Error).self) {
                _ = try AES.GCM.open(box, using: key, authenticating: Data((aad + "tampered").utf8))
            }
        }
        #expect(restored == wire)
        let manifest = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: URL(filePath: base.path + "-manifest.json"))) as? [String: Any])
        #expect(manifest["droppedByteCount"] as? Int == 0)
        #expect(manifest["truncated"] as? Bool == false)
        #expect(manifest["rawFileSHA256"] as? String == SHA256.hash(data: raw).map { String(format: "%02x", $0) }.joined())
    }

    @Test func unavailableKeyNeverWritesRawPlaintextAndReportsTheLoss() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let base = directory.appending(path: "agent-session-key-failure")
        let journal = AgentDiagnosticsJournal(baseURL: base, runID: UUID(), groupID: UUID(), full: true,
            keyProvider: { throw CocoaError(.fileReadNoPermission) })
        let id = UUID()
        journal.transportObserver(.request(id: id, request: URLRequest(url: URL(string: "https://example.invalid")!)))
        journal.transportObserver(.bytes(id: id, data: Data("data: {\"token\":\"NEVER_PLAINTEXT\"}\n\n".utf8)))
        journal.transportObserver(.end(id: id, error: "cancelled"))
        await journal.checkpoint(status: "cancelled")
        #expect(!FileManager.default.fileExists(atPath: base.path + ".raw.enc"))
        let manifest = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: URL(filePath: base.path + "-manifest.json"))) as? [String: Any])
        #expect(manifest["truncated"] as? Bool == true)
        #expect((manifest["droppedByteCount"] as? Int ?? 0) > 0)
        #expect(!(manifest["captureError"] as? String ?? "").isEmpty)
        let readable = try String(contentsOf: URL(filePath: base.path + "-stage-events.jsonl"), encoding: .utf8)
        #expect(!readable.contains("NEVER_PLAINTEXT"))
    }

    @Test func redactionPreservesOrdinaryConversationAndMasksNestedSecrets() throws {
        let text = #"{"messages":[{"role":"user","content":"ordinary private conversation שלום"}],"nested":{"api_key":"UNSAFE_KEY","authorization":"Bearer UNSAFE_AUTH"},"url":"https://x.invalid/?X-Amz-Signature=UNSAFE_SIGNATURE&ok=1"}"#
        let safe = AgentDiagnosticsRedactor.sanitize(text)
        #expect(safe.contains("ordinary private conversation שלום"))
        #expect(!safe.contains("UNSAFE_"))
        #expect(try JSONSerialization.jsonObject(with: Data(safe.utf8)) is [String: Any])
    }

    @Test func credentialsSplitAcrossSSEEventsRemainOnlyInTheEncryptedSource() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let base = directory.appending(path: "agent-session-split-secret")
        let key = SymmetricKey(size: .bits256)
        let journal = AgentDiagnosticsJournal(baseURL: base, runID: UUID(), groupID: UUID(), full: true, keyProvider: { key })
        let secret = "sk-project_PRIVATE_CREDENTIAL_12345678"
        var request = URLRequest(url: URL(string: "https://example.invalid")!)
        request.setValue("Bearer " + secret, forHTTPHeaderField: "Authorization")
        let id = UUID()
        journal.transportObserver(.request(id: id, request: request))
        for piece in ["sk-pro", "ject_PRIVATE_", "CREDENTIAL_12345678"] {
            let data = try JSONSerialization.data(withJSONObject: ["choices": [["delta": ["content": piece]]]])
            journal.transportObserver(.bytes(id: id, data: Data("data: ".utf8) + data + Data("\n\n".utf8)))
        }
        journal.transportObserver(.end(id: id, error: nil))
        await journal.checkpoint(status: "completed")
        for url in try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) {
            let text = try String(contentsOf: url, encoding: .utf8)
            #expect(!text.contains("PRIVATE_") && !text.contains("CREDENTIAL_12345678"))
        }
    }
}
