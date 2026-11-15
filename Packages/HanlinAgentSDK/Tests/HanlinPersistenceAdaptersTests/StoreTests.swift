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

    @Test func versionOneCheckpointCanBeRestoredWithoutDestructiveMigration() async throws {
        // macOS's temporary root may be a system symlink (/var -> /private/var).
        // The private store intentionally rejects symlink ancestors; supply a canonical fixture root.
        let directory = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
            .appending(path: "HanlinStoreTest-" + UUID().uuidString)
        #if os(macOS)
        print("CHECKPOINT_FILE_STANDARDIZATION_CHANGED_ROOT=\(directory.standardizedFileURL.path != directory.standardized.path)")
        #endif
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try HanlinPrivateConversationStore(directory: directory)
        let ns = try HanlinConversationNamespace(app: "a", account: "a", workspace: "w", space: "one")
        let original = HanlinConversationRecord(formatVersion: 1, namespace: ns, conversationID: UUID(), revision: 0,
            draft: "Original draft", entries: [.init(runID: UUID(), step: 0, sequence: 0, payload: .text("Original history"))])
        try await store.save(original, replacing: nil)
        let checkpoint = try await store.checkpoint(original.conversationID, namespace: ns)
        #expect(try JSONDecoder().decode(HanlinConversationRecord.self, from: checkpoint) == original)
        let next = HanlinConversationRecord(namespace: ns, conversationID: original.conversationID, revision: 1, draft: "New draft", entries: original.entries)
        try await store.save(next, replacing: 0)
        try await store.restoreCheckpoint(checkpoint, namespace: ns, replacing: 1)
        let restored = try #require(await store.load(original.conversationID, namespace: ns))
        #expect(restored.formatVersion == 2 && restored.revision == 2)
        #expect(restored.entries == original.entries && restored.draft == original.draft)
        #expect(try JSONDecoder().decode(HanlinConversationRecord.self, from: checkpoint).formatVersion == 1)
        do {
            try await store.save(.init(formatVersion: 3, namespace: ns, conversationID: original.conversationID, revision: 3), replacing: 2)
            Issue.record("Unknown future format replaced the original record")
        } catch { #expect(error as? HanlinHostError == .unsupportedVersion) }
        #expect(try await store.load(original.conversationID, namespace: ns) == restored)
        let target = directory.appending(path: "link-target")
        let link = directory.appending(path: "linked-root")
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        let linked = try HanlinPrivateConversationStore(directory: link)
        do { _ = try await linked.load(original.conversationID, namespace: ns); Issue.record("A symbolic-link store root bypassed rejection") }
        catch { #expect(error as? HanlinHostError == .invalidRecord) }
    }
}
