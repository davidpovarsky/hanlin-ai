import Foundation
import XCTest
import HanlinMiniAppsBridge
@testable import HanlinMiniApps

@MainActor
final class CrossAppInvocationTests: XCTestCase {
    private func fixture() throws -> (URL, MiniAppBridgeStore) {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        return (root, try MiniAppBridgeStore(containerURL: root))
    }
    private func request(_ text: String, operation: MiniAppOperation = .replaceSelection) -> MiniAppInvocation {
        .init(appID: "nativeapp.textstudio",
              source: .init(appID: "com.example.source", displayName: "Original",
                            documentID: UUID().uuidString, documentText: text),
              inputs: [.init(kind: .text, text: text)], operation: operation,
              callbacks: .init(success: URL(string: "original://miniapps/return"),
                               error: URL(string: "original://miniapps/error"),
                               cancel: URL(string: "original://miniapps/cancel")))
    }
    func testCompletionIsSavedBeforeSourceOpensAndSurvivesColdRestore() async throws {
        let (root, store) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let original = request("שלום 👨‍👩‍👧")
        _ = try store.enqueue(original)
        var calls = 0
        let session = HanlinExternalMiniAppSession(requestID: original.id, store: store) { url in
            calls += 1
            XCTAssertEqual(try? store.result(id: original.id)?.text, "חדש 🚀")
            XCTAssertEqual(URLComponents(url: url, resolvingAgainstBaseURL: false)?.host, "miniapps")
            return true
        }
        try session.restoreRequest()
        _ = try await session.perform("miniapps.complete", payload: #""חדש 🚀""#)
        XCTAssertEqual(calls, 1)
        let cold = HanlinExternalMiniAppSession(requestID: original.id,
            store: try MiniAppBridgeStore(containerURL: root), openSource: { _ in true })
        try cold.restoreRequest()
        XCTAssertEqual(cold.result?.text, "חדש 🚀")
        XCTAssertEqual(cold.result?.operation, .replaceSelection)
        XCTAssertNil(cold.view, "Completed invocations must not execute again.")
    }
    func testTwoWindowsKeepTheirOwnInputOutputAndCallbacks() async throws {
        let (root, store) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let first = request("ראשון"), second = request("שני", operation: .insert)
        _ = try store.enqueue(first); _ = try store.enqueue(second)
        let a = HanlinExternalMiniAppSession(requestID: first.id, store: store, openSource: { _ in true })
        let b = HanlinExternalMiniAppSession(requestID: second.id, store: store, openSource: { _ in true })
        try a.restoreRequest(); try b.restoreRequest()
        let context = try await b.perform("miniapps.context", payload: "{}")
        XCTAssertEqual(try JSONDecoder().decode(MiniAppInvocation.self, from: Data(context.utf8)), second)
        _ = try await b.perform("miniapps.complete", payload: #""B""#)
        _ = try await a.perform("miniapps.complete", payload: #""A""#)
        XCTAssertEqual(try store.result(id: first.id)?.text, "A")
        XCTAssertEqual(try store.result(id: second.id)?.text, "B")
        XCTAssertEqual(try store.result(id: second.id)?.operation, .insert)
    }
    func testCancelAndDisplayDoneReturnNoDocumentMutation() async throws {
        let (root, store) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let cancelled = request("do not insert"), viewed = request("view only")
        _ = try store.enqueue(cancelled); _ = try store.enqueue(viewed)
        let a = HanlinExternalMiniAppSession(requestID: cancelled.id, store: store, openSource: { _ in true })
        let b = HanlinExternalMiniAppSession(requestID: viewed.id, store: store, openSource: { _ in true })
        try a.restoreRequest(); try b.restoreRequest()
        await a.cancel(); await b.done()
        XCTAssertEqual(try store.result(id: cancelled.id)?.status, .cancelled)
        XCTAssertEqual(try store.result(id: viewed.id)?.operation, .display)
        XCTAssertTrue(try store.result(id: viewed.id)?.items.isEmpty == true)
    }
    func testActualProducerAttachmentOperationsPreserveBytes() async throws {
        let (root, store) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let original = request("")
        _ = try store.enqueue(original)
        let session = HanlinExternalMiniAppSession(requestID: original.id, store: store, openSource: { _ in true })
        try session.restoreRequest()
        let bytes = Data((0...255).map(UInt8.init))
        let payload = String(decoding: try JSONEncoder().encode(
            ["base64": bytes.base64EncodedString(), "name": "מקור.bin", "typeIdentifier": "public.data"]), as: UTF8.self)
        let encoded = try await session.perform("miniapps.writeAttachment", payload: payload)
        let item = try JSONDecoder().decode(MiniAppContent.self, from: Data(encoded.utf8))
        let id = try XCTUnwrap(item.attachmentID)
        let read = try await session.perform("miniapps.readAttachment", payload: "{\"id\":\"\(id.uuidString)\"}")
        let result = try JSONDecoder().decode([String: String].self, from: Data(read.utf8))
        XCTAssertEqual(Data(base64Encoded: try XCTUnwrap(result["base64"])), bytes)
        XCTAssertEqual(item.name, "מקור.bin")
    }
    func testUnavailableCallbackRetainsResultForSourceRecovery() async throws {
        let (root, store) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let original = request("")
        _ = try store.enqueue(original)
        let session = HanlinExternalMiniAppSession(requestID: original.id, store: store, openSource: { _ in false })
        try session.restoreRequest()
        _ = try await session.perform("miniapps.complete", payload: #""retained""#)
        XCTAssertEqual(try store.pendingResults(sourceAppID: original.source.appID).map(\.text), ["retained"])
        XCTAssertNotNil(session.error)
        XCTAssertFalse(session.returning)
    }
}
