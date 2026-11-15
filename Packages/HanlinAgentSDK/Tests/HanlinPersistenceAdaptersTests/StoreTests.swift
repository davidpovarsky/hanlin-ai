import Foundation
import HanlinHostContracts
import HanlinPersistenceAdapters
import Testing

@Suite struct StoreTests {
    @Test func sameConversationIDIsIsolatedBySpace() async throws {
        let store = HanlinInMemoryConversationStore()
        let one = try HanlinConversationNamespace(app: "a", account: "a", workspace: "w", space: "one")
        let two = try HanlinConversationNamespace(app: "a", account: "a", workspace: "w", space: "two")
        let id = UUID()
        try await store.save(.init(namespace: one, conversationID: id, revision: 0, draft: "private"), replacing: nil)
        #expect(await store.load(id, namespace: two) == nil)
    }
}
