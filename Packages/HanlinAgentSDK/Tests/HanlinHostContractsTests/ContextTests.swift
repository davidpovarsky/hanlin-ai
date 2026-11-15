import Foundation
import HanlinHostContracts
import Testing

@Suite struct ContextTests {
    @Test func decodedNamespacesCannotBypassValidation() throws {
        #expect(throws: HanlinHostError.invalidContext) {
            try JSONDecoder().decode(HanlinConversationNamespace.self, from: Data(#"{"app":"","account":"a","workspace":"w","space":"s"}"#.utf8))
        }
    }
    @Test func persistedPresentationCarriesNoExecutionAuthority() throws {
        let ns = try HanlinConversationNamespace(app: "a", account: "a", workspace: "w", space: "s")
        let record = HanlinConversationRecord(namespace: ns, conversationID: UUID(), revision: 0,
            entries: [.init(runID: UUID(), step: 0, sequence: 0, payload: .presentationReference(version: 1, opaqueReference: "view-only"))])
        let decoded = try JSONDecoder().decode(HanlinConversationRecord.self, from: JSONEncoder().encode(record))
        try decoded.validate()
        #expect(decoded == record)
    }
    @Test func previousMetadataFormatRemainsReadableWithoutMutation() throws {
        let ns = try HanlinConversationNamespace(app: "a", account: "a", workspace: "w", space: "s")
        let original = HanlinConversationRecord(formatVersion: 1, namespace: ns, conversationID: UUID(), revision: 4,
            draft: "Preserve original", entries: [.init(runID: UUID(), step: 0, sequence: 0, payload: .text("History"))])
        let bytes = try JSONEncoder().encode(original)
        let restored = try JSONDecoder().decode(HanlinConversationRecord.self, from: bytes)
        try restored.validate()
        #expect(restored == original && restored.formatVersion == 1)
        #expect(HanlinConversationRecord.currentFormat == 2)
    }
}
