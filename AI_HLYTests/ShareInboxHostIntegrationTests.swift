import Foundation
import HanlinScriptStore
import Testing
import UniformTypeIdentifiers
@testable import AI_Hanlin

@Suite("Actual App Group Share ingress reader", .serialized)
@MainActor
struct ShareInboxHostIntegrationTests {
    @Test func mixedBatchBecomesNamedVerifiedChatAttachmentsWithoutConsumingTheInbox() async throws {
        let (store, id, source, item) = try makeDraftFile()
        defer { removeOwnedBatch(store, id: id, source: source) }
        let text = "shared שלום🙂", link = "https://example.org/original?q=1"
        let batch = try store.commit(id, items: [
            .text(text, ordinal: 0, typeIdentifier: UTType.plainText.identifier),
            .text(link, ordinal: 1, typeIdentifier: UTType.url.identifier, isURL: true), item
        ])
        let prepared = try await ChavrusaShareInbox.shared.prepareDraft(batchID: id, availableFileSlots: 1)
        #expect(prepared.text == text + "\n\n" + link)
        #expect(prepared.files.count == 1 && prepared.files[0].lastPathComponent == "original.txt")
        #expect(try Data(contentsOf: prepared.files[0]) == Data(contentsOf: source))
        #expect(prepared.files[0].path.contains("/Library/Application Support/SharedChatAttachments/"))
        #expect(try store.batch(id) == batch)
        await ChavrusaShareInbox.shared.discardPreparedDraft(prepared)
        #expect(!FileManager.default.fileExists(atPath: prepared.files[0].path))
        #expect(try Data(contentsOf: store.ownedFile(batchID: id, itemID: item.id)) == Data(contentsOf: source))
    }

    @Test func invalidCapacityRejectedItemsAndTamperedBytesCannotChangeTheSourceBatch() async throws {
        let (store, id, source, item) = try makeDraftFile(ordinal: 0)
        defer { removeOwnedBatch(store, id: id, source: source) }
        let batch = try store.commit(id, items: [item])
        do {
            _ = try await ChavrusaShareInbox.shared.prepareDraft(batchID: id, availableFileSlots: 0)
            Issue.record("A full Composer must reject the entire addition")
        } catch ChavrusaShareDraftError.fileLimit { }
        let owned = try store.ownedFile(batchID: id, itemID: item.id)
        try Data("tampered".utf8).write(to: owned)
        do {
            _ = try await ChavrusaShareInbox.shared.prepareDraft(batchID: id, availableFileSlots: 5)
            Issue.record("Corrupt source bytes must never become a chat attachment")
        } catch HanlinShareInboxError.integrityMismatch { }
        #expect(try store.batch(id) == batch)
        #expect(try Data(contentsOf: owned) == Data("tampered".utf8))
        let rejected = try store.begin()
        defer { removeOwnedBatch(store, id: rejected, source: nil) }
        _ = try store.commit(rejected, items: [.rejected(ordinal: 0, typeIdentifier: "public.data", failure: .providerFailed)])
        do {
            _ = try await ChavrusaShareInbox.shared.prepareDraft(batchID: rejected, availableFileSlots: 5)
            Issue.record("An incomplete batch must not silently omit an item")
        } catch ChavrusaShareDraftError.incompleteBatch { }
        #expect(try store.batch(rejected).items.count == 1)
    }

    @Test func cancelledDraftPreparationKeepsTheOriginalFile() async throws {
        let (store, id, source, item) = try makeDraftFile(ordinal: 0)
        defer { removeOwnedBatch(store, id: id, source: source) }
        let batch = try store.commit(id, items: [item])
        let operation = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await ChavrusaShareInbox.shared.prepareDraft(batchID: id, availableFileSlots: 5)
        }
        do { _ = try await operation.value; Issue.record("Cancelled preparation returned content") }
        catch is CancellationError { }
        #expect(try store.batch(id) == batch)
        #expect(try Data(contentsOf: store.ownedFile(batchID: id, itemID: item.id)) == Data(contentsOf: source))
    }

    private func makeDraftFile(ordinal: Int = 2) throws -> (HanlinShareInboxStore, UUID, URL, HanlinShareItem) {
        let group = try #require(FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.itorah.chavrusachat"))
        let store = try HanlinShareInboxStore(container: group), id = try store.begin()
        let source = FileManager.default.temporaryDirectory.appending(path: "share-draft-test-" + id.uuidString + ".txt")
        try Data("original bytes שלום🙂".utf8).write(to: source)
        let item = try store.copyFile(source, batchID: id, ordinal: ordinal,
            typeIdentifier: UTType.plainText.identifier, suggestedName: "../original.txt")
        return (store, id, source, item)
    }

    private func removeOwnedBatch(_ store: HanlinShareInboxStore, id: UUID, source: URL?) {
        if let source { try? FileManager.default.removeItem(at: source) }
        try? FileManager.default.removeItem(at: store.directory.appending(path: "Batches").appending(path: id.uuidString.lowercased()))
        try? store.abort(id)
    }

    @Test func providerBatchSurvivesSourceDeletionAndIsReadByTheRealHostInbox() async throws {
        let group = try #require(FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.itorah.chavrusachat"))
        let store = try HanlinShareInboxStore(container: group), id = try store.begin()
        let directory = FileManager.default.temporaryDirectory.appending(path: "host-share-\(id.uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        let source = directory.appending(path: "original.pdf")
        let bytes = Data("%PDF actual App Group provider שלום🙂".utf8)
        try bytes.write(to: source)
        let batchRoot = store.directory.appending(path: "Batches").appending(path: id.uuidString.lowercased())
        defer {
            try? FileManager.default.removeItem(at: directory)
            try? FileManager.default.removeItem(at: batchRoot)
            try? store.abort(id)
        }
        let provider = NSItemProvider()
        provider.registerFileRepresentation(forTypeIdentifier: UTType.pdf.identifier, visibility: .all) { done in
            done(source, false, nil); return nil
        }
        let item: HanlinShareItem = await withCheckedContinuation { continuation in
            HanlinShareItemLoader.load(provider, store: store, batchID: id, ordinal: 0) { continuation.resume(returning: $0) }
        }
        try FileManager.default.removeItem(at: source)
        #expect(item.content == .file)
        let batch = try store.commit(id, items: [item])
        let pending = try await ChavrusaShareInbox.shared.pendingBatches()
        #expect(pending.batches.first(where: { $0.id == id }) == batch)
        let owned = try await ChavrusaShareInbox.shared.ownedFile(batchID: id, itemID: item.id)
        #expect(try Data(contentsOf: owned) == bytes)
        #expect(owned.path.hasPrefix(batchRoot.path + "/Files/"))
    }
}
