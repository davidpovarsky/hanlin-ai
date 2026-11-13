import CryptoKit
import Foundation
import HanlinScriptStore
import Testing
import UniformTypeIdentifiers

@Suite("Owned Share ingress transactions")
struct HanlinShareInboxStoreTests {
    @Test func copiedFilesSurviveProviderDeletionAndPublishOnlyWithTheirWholeBatch() throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try HanlinShareInboxStore(container: root)
        let id = try store.begin()
        let source = root.appending(path: "provider.pdf")
        let bytes = Data(String(repeating: "שלום🙂\n", count: 200_000).utf8)
        try bytes.write(to: source)
        let file = try store.copyFile(source, batchID: id, ordinal: 2, typeIdentifier: UTType.pdf.identifier, suggestedName: "document.pdf")
        try FileManager.default.removeItem(at: source)
        #expect(try store.scan().batches.isEmpty)
        let items: [HanlinShareItem] = [.text("exact שלום🙂", ordinal: 0, typeIdentifier: UTType.plainText.identifier),
            .text("https://example.org/a?q=1", ordinal: 1, typeIdentifier: UTType.url.identifier, isURL: true), file,
            .rejected(ordinal: 3, typeIdentifier: "unknown", failure: .providerFailed)]
        let batch = try store.commit(id, items: items)
        let reopened = try HanlinShareInboxStore(container: root)
        #expect(try reopened.scan().batches == [batch])
        let owned = try reopened.ownedFile(batchID: id, itemID: file.id)
        #expect(try Data(contentsOf: owned) == bytes)
        #expect(file.bytes == Int64(bytes.count) && file.name == "document.pdf")
        #expect(file.sha256 == SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined())
        let metadata = try String(contentsOf: owned.deletingLastPathComponent().deletingLastPathComponent().appending(path: "batch.json"), encoding: .utf8)
        #expect(!metadata.contains(source.path))
        #expect(throws: (any Error).self) { _ = try store.commit(id, items: items) }
        #expect(try reopened.scan().batches == [batch])
    }

    @Test func independentConcurrentBatchesNeverOverwriteEachOtherOrHistoricalInbox() async throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let historical = root.appending(path: "share-inbox.json")
        let historicalBytes = Data("preserve original, including malformed old records".utf8)
        try historicalBytes.write(to: historical)
        let ids = try await withThrowingTaskGroup(of: UUID.self) { group in
            for n in 0..<24 {
                group.addTask {
                    let store = try HanlinShareInboxStore(container: root)
                    let id = try store.begin()
                    _ = try store.commit(id, items: [.text("item \(n)", ordinal: 0, typeIdentifier: UTType.plainText.identifier)])
                    return id
                }
            }
            var result: [UUID] = []
            for try await id in group { result.append(id) }
            return result
        }
        let scan = try HanlinShareInboxStore(container: root).scan()
        #expect(scan.batches.count == 24 && scan.rejected.isEmpty)
        #expect(Set(scan.batches.map(\.id)) == Set(ids))
        #expect(try Data(contentsOf: historical) == historicalBytes)
    }

    @Test func cancelledStagingAndCorruptBatchesCannotRemoveOrStarveHealthyItems() throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try HanlinShareInboxStore(container: root)
        let abandoned = try store.begin(), healthy = try store.begin()
        _ = try store.commit(healthy, items: [.text("kept", ordinal: 0, typeIdentifier: UTType.plainText.identifier)])
        try store.abort(abandoned)
        let batches = store.directory.appending(path: "Batches")
        let corruptID = UUID(), corrupt = batches.appending(path: corruptID.uuidString.lowercased())
        try FileManager.default.createDirectory(at: corrupt, withIntermediateDirectories: false)
        let malformed = Data("not a manifest".utf8)
        try malformed.write(to: corrupt.appending(path: "batch.json"))
        let external = root.appending(path: "external")
        try FileManager.default.createDirectory(at: external, withIntermediateDirectories: false)
        let linkID = UUID()
        try FileManager.default.createSymbolicLink(at: batches.appending(path: linkID.uuidString.lowercased()), withDestinationURL: external)
        let scan = try store.scan()
        #expect(scan.batches.map(\.id) == [healthy])
        #expect(Set(scan.rejected.compactMap { $0 }) == Set([corruptID, linkID]))
        #expect(try Data(contentsOf: corrupt.appending(path: "batch.json")) == malformed)
        #expect(throws: (any Error).self) { _ = try store.commit(try store.begin(), items: [.text("wrong order", ordinal: 1, typeIdentifier: UTType.plainText.identifier)]) }
    }

    @Test func tamperedPathsLinksAndBytesCannotBecomeVerifiedOwnedFiles() throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try HanlinShareInboxStore(container: root)
        let source = root.appending(path: "source.bin")
        try Data([0, 1, 2, 255]).write(to: source)
        let sourceLink = root.appending(path: "source-link")
        try FileManager.default.createSymbolicLink(at: sourceLink, withDestinationURL: source)
        let id = try store.begin()
        #expect(throws: (any Error).self) { _ = try store.copyFile(sourceLink, batchID: id, ordinal: 0, typeIdentifier: UTType.data.identifier) }
        let item = try store.copyFile(source, batchID: id, ordinal: 0, typeIdentifier: UTType.data.identifier)
        _ = try store.commit(id, items: [item])
        let file = try store.ownedFile(batchID: id, itemID: item.id)
        try Data([9, 8, 7, 6]).write(to: file)
        #expect(throws: HanlinShareInboxError.integrityMismatch) { _ = try store.ownedFile(batchID: id, itemID: item.id) }
        try FileManager.default.removeItem(at: file)
        try FileManager.default.createSymbolicLink(at: file, withDestinationURL: source)
        #expect(throws: (any Error).self) { _ = try store.ownedFile(batchID: id, itemID: item.id) }
        let metadata = file.deletingLastPathComponent().deletingLastPathComponent().appending(path: "batch.json")
        var json = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: metadata)) as? [String: Any])
        var entries = try #require(json["items"] as? [[String: Any]])
        entries[0]["file"] = "../../source.bin"
        json["items"] = entries
        try JSONSerialization.data(withJSONObject: json).write(to: metadata)
        #expect(try store.scan().batches.isEmpty)
        #expect(throws: (any Error).self) { _ = try store.ownedFile(batchID: id, itemID: item.id) }
    }

    @Test @MainActor func realItemProvidersCopyFilesAndPreserveTextURLAndPerItemErrors() async throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try HanlinShareInboxStore(container: root), id = try store.begin()
        let source = root.appending(path: "provider-file.pdf")
        let bytes = Data("%PDF owned שלום🙂".utf8)
        try bytes.write(to: source)
        let fileProvider = NSItemProvider()
        fileProvider.suggestedName = "original.pdf"
        fileProvider.registerFileRepresentation(forTypeIdentifier: UTType.pdf.identifier, visibility: .all) { done in
            done(source, false, nil); return nil
        }
        let textProvider = NSItemProvider(object: "provider שלום🙂" as NSString)
        let url = try #require(URL(string: "https://example.org/share?q=1"))
        let urlProvider = NSItemProvider(object: url as NSURL)
        let failedProvider = NSItemProvider()
        failedProvider.registerFileRepresentation(forTypeIdentifier: UTType.pdf.identifier, visibility: .all) { done in
            done(nil, false, CocoaError(.fileReadUnknown)); return nil
        }
        var items: [HanlinShareItem] = []
        for (ordinal, provider) in [fileProvider, textProvider, urlProvider, failedProvider].enumerated() {
            let item: HanlinShareItem = await withCheckedContinuation { continuation in
                HanlinShareItemLoader.load(provider, store: store, batchID: id, ordinal: ordinal) { continuation.resume(returning: $0) }
            }
            items.append(item)
        }
        try FileManager.default.removeItem(at: source)
        _ = try store.commit(id, items: items)
        #expect(items[0].content == .file && items[0].name == "original.pdf")
        #expect(try Data(contentsOf: store.ownedFile(batchID: id, itemID: items[0].id)) == bytes)
        #expect(items[1].content == .text && items[1].text == "provider שלום🙂")
        #expect(items[2].content == .url && items[2].text == url.absoluteString)
        #expect(items[3].content == .rejected && items[3].failure == .providerFailed)
    }

    private func fixture() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appending(path: "owned-share-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }
}
