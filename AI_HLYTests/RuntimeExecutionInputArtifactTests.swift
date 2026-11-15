import CryptoKit
import Foundation
import Testing
@testable import AI_Hanlin

@Suite("Owned Runtime execution input transport")
struct RuntimeExecutionInputArtifactTests {
    @Test func smallControlInputStaysInlineWithoutCreatingAnInbox() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "inline-input-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let bytes = Data(#"{"source":"console.log('שלום')"}"#.utf8)
        let input = try RuntimeExecutionInputArtifact(body: bytes, executionID: UUID(), layout: RuntimeFileLayout(root: root))
        #expect(input.file == nil && input.controlBody == bytes)
        input.discardBeforeSubmission()
        #expect(!FileManager.default.fileExists(atPath: root.path))
    }

    @Test func largeInputKeepsExactBytesAndDigestAndRejectsAnotherOwnerBeforeSubmission() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "file-input-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let id = UUID()
        let bytes = try JSONSerialization.data(withJSONObject: ["executionID": id.uuidString.lowercased(),
            "source": "/*" + String(repeating: "שלום 👨‍👩‍👧‍👦 ", count: 1_000_000) + "*/ export default 42;"])
        #expect(bytes.count > 32 * 1_024 * 1_024)
        let layout = RuntimeFileLayout(root: root)
        let input = try RuntimeExecutionInputArtifact(body: bytes, executionID: id, layout: layout)
        let file = try #require(input.file)
        #expect(try Data(contentsOf: file) == bytes)
        #expect(input.controlBody.count < 1_024)
        let envelope = try #require(try JSONSerialization.jsonObject(with: input.controlBody) as? [String: Any])
        let artifact = try #require(envelope["inputArtifact"] as? [String: Any])
        #expect(artifact["bytes"] as? Int == bytes.count)
        #expect(artifact["sha256"] as? String == SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined())
        #expect(throws: (any Error).self) {
            _ = try RuntimeExecutionInputArtifact(body: bytes, executionID: id, layout: layout)
        }
        #expect(try Data(contentsOf: file) == bytes)
        input.discardBeforeSubmission()
        #expect(!FileManager.default.fileExists(atPath: file.path))
    }
}
