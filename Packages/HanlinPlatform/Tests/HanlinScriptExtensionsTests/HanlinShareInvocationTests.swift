import Foundation
import HanlinPlatformContracts
import HanlinScriptExtensions
import HanlinScriptStore
import Testing

@Suite("Owned Share delivery on the canonical queue")
struct HanlinShareInvocationTests {
    @Test func largeInputsUseOneStableQueueIdentityAndReturnTheActualResultAfterReopen() async throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let inbox = try HanlinShareInboxStore(container: root)
        let queue = HanlinScriptExtensionStore(root: root.appending(path: "ScriptingExtensions"))
        let id = try inbox.begin(), source = root.appending(path: "source.bin")
        let text = String(repeating: "שלום🙂", count: 60_000)
        let bytes = Data([0, 1, 2, 255])
        try bytes.write(to: source)
        let file = try inbox.copyFile(source, batchID: id, ordinal: 1, typeIdentifier: "public.data")
        let batch = try inbox.commit(id, items: [.text(text, ordinal: 0, typeIdentifier: "public.plain-text"), file])
        try FileManager.default.removeItem(at: source)
        let command = try make(batch)
        try queue.enqueue(command)
        // Re-selecting exactly the same batch/installed target cannot create a
        // second invocation or overwrite its delivery/receipt.
        try queue.enqueue(command)
        let encoded = try JSONEncoder().encode(command)
        #expect(encoded.count < 4096 && !String(decoding: encoded, as: UTF8.self).contains(text))
        let executor = HanlinInvocationExecutor(store: queue)
        let actual = try await executor.execute(id) { received in
            let payload = try HanlinShareInvocation.payload(for: received, inbox: inbox)
            guard case let .object(value) = payload, case let .array(items) = value["items"],
                  items.count == 2, case let .object(first) = items[0], case let .object(second) = items[1],
                  case let .string(urlString) = second["fileURL"], let url = URL(string: urlString) else {
                Issue.record("Share payload lost its ordered original input"); return .null
            }
            #expect(first["text"] == .string(text))
            #expect(try Data(contentsOf: url) == bytes)
            return .object(["receivedText": first["text"] ?? .null, "fileBytes": second["bytes"] ?? .null])
        }
        #expect(actual?.status == .succeeded)
        let reopened = HanlinScriptExtensionStore(root: queue.root)
        let receipt = try #require(try reopened.receipt(for: id))
        #expect(receipt.value == .object(["receivedText": .string(text), "fileBytes": .integer(4)]))
        try reopened.enqueue(command)
        let duplicate = try await HanlinInvocationExecutor(store: reopened).execute(id) { _ in Issue.record("Accepted Share replayed"); return .null }
        #expect(duplicate == receipt)
        let other = try make(batch, app: "share.other")
        #expect(throws: HanlinInvocationQueueError.duplicateIdentity) { try reopened.enqueue(other) }
    }

    @Test func wrongBatchReferencesAndChangedOwnedBytesFailBeforeDispatch() throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let inbox = try HanlinShareInboxStore(container: root), id = try inbox.begin()
        let source = root.appending(path: "source.bin")
        try Data("original".utf8).write(to: source)
        let file = try inbox.copyFile(source, batchID: id, ordinal: 0, typeIdentifier: "public.data")
        let batch = try inbox.commit(id, items: [file]), command = try make(batch)
        let forged = HanlinScriptResumeCommand(id: UUID(), createdAt: command.createdAt, invocation: command.invocation)
        #expect(throws: HanlinInvocationQueueError.invalidEnvelope) { _ = try HanlinShareInvocation.payload(for: forged, inbox: inbox) }
        let owned = try inbox.ownedFile(batchID: id, itemID: file.id)
        try Data("changed!".utf8).write(to: owned)
        #expect(throws: HanlinShareInboxError.integrityMismatch) { _ = try HanlinShareInvocation.payload(for: command, inbox: inbox) }
    }

    @Test func expiredOrCancelledIngressCannotInvokeTheHandler() async throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let inbox = try HanlinShareInboxStore(container: root)
        let queue = HanlinScriptExtensionStore(root: root.appending(path: "ScriptingExtensions"))
        let expiredID = try inbox.begin(), cancelledID = try inbox.begin()
        let old = try inbox.commit(expiredID, items: [.text("expired", ordinal: 0, typeIdentifier: "public.plain-text")], createdAt: .now.addingTimeInterval(-100_000))
        let fresh = try inbox.commit(cancelledID, items: [.text("cancelled", ordinal: 0, typeIdentifier: "public.plain-text")])
        try queue.enqueue(make(old)); try queue.enqueue(make(fresh))
        _ = try queue.requestCancellation(cancelledID)
        let executor = HanlinInvocationExecutor(store: queue)
        for id in [expiredID, cancelledID] {
            let result = try await executor.execute(id) { _ in Issue.record("Expired/cancelled Share executed"); return .null }
            #expect(result?.status == (id == expiredID ? .expired : .cancelled))
            #expect(result?.attempt == 0)
        }
    }

    private func make(_ batch: HanlinShareBatch, app: String = "share.demo") throws -> HanlinScriptResumeCommand {
        HanlinShareInvocation.command(batch: batch, identity: .init(installedPackageID: try .init(validating: "installed.\(app)"),
            packageID: try .init(validating: app), generation: 3, entrypointID: "share.main"),
            appID: try .init(validating: app), actionID: try .init(validating: "receive-shared"))
    }

    private func fixture() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appending(path: "share-delivery-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        return root
    }
}
