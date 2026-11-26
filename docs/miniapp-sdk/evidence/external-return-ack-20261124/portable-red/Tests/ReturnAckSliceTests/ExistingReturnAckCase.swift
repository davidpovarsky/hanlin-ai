import Foundation
import XCTest
@testable import ReturnAckSlice

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

    func testUnavailableCallbackRetainsResultForSourceRecovery() async throws {
        let (root, store) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let original = request("")
        _ = try store.enqueue(original)
        var openCalls = 0
        let session = HanlinExternalMiniAppSession(requestID: original.id, store: store, openSource: { _ in
            openCalls += 1
            XCTAssertEqual(try? store.result(id: original.id)?.text, "retained")
            return false
        })
        try session.restoreRequest()
        let completion = try await session.perform("miniapps.complete", payload: #""retained""#)
        XCTAssertEqual(completion, #"{"ok":true}"#, "Completion acknowledges the saved result, independently of opening its source.")
        let response = try await session.perform("miniapps.return", payload: "{}")
        let acknowledgement = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: Data(response.utf8)) as? [String: Any])
        XCTAssertEqual(acknowledgement["ok"] as? Bool, false,
                       "A failed actual open callback must not return an unconditional success acknowledgement.")
        XCTAssertEqual(acknowledgement["requested"] as? Bool, true)
        XCTAssertEqual(acknowledgement["opened"] as? Bool, false)
        XCTAssertEqual(acknowledgement["status"] as? String, "failed")
        XCTAssertEqual(openCalls, 1)
        XCTAssertEqual(try store.pendingResults(sourceAppID: original.source.appID).map(\.text), ["retained"])
        XCTAssertNotNil(session.error)
        XCTAssertFalse(session.returning)
    }
}
