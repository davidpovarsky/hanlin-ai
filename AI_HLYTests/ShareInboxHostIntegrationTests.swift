import Foundation
import HanlinScriptStore
import Testing
import UniformTypeIdentifiers
@testable import AI_Hanlin

@Suite("Actual App Group Share ingress reader", .serialized)
@MainActor
struct ShareInboxHostIntegrationTests {
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
