import Foundation

/// Controlled incoming requests only; every result must come from the real
/// installed NativeScript package or the original Host Cancel action.
@main
struct NativeScriptWindowBridgeFixture {
    static let appID = "hanlin.nativescript.window-factory"
    static let windows: [(name: String, id: String)] = [
        ("alpha", "1e23a001-6a2c-4c0f-b001-202611240001"),
        ("beta", "1e23a002-6a2c-4c0f-b002-202611240002"),
        ("gamma", "1e23a003-6a2c-4c0f-b003-202611240003"),
        ("delta", "1e23a004-6a2c-4c0f-b004-202611240004"),
    ]

    static func main() throws {
        guard CommandLine.arguments.count == 3 else { throw Failure.invalidArguments }
        let container = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
        guard try container.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true else {
            throw Failure.missingOSContainer
        }
        let store = try MiniAppBridgeStore(containerURL: container)
        switch CommandLine.arguments[1] {
        case "seed":
            var incoming: [[String: String]] = []
            for window in windows {
                let id = UUID(uuidString: window.id)!
                guard try store.request(id: id) == nil else { throw Failure.existingFixture }
                let request = MiniAppInvocation(id: id, appID: appID,
                    source: .init(appID: "com.itorah.hanlinminiapps.window-fixture",
                        displayName: "NativeScript window fixture source",
                        documentID: "ns-window-" + window.name,
                        documentTitle: "NativeScript window " + window.name,
                        revision: "fixture-" + window.name + "-v1",
                        selection: .init(location: 7, length: window.name.utf16.count, text: window.name),
                        documentText: "before " + window.name + " after"),
                    inputs: [.init(kind: .text, text: window.name)],
                    operation: .replaceSelection, opensInNewWindow: true)
                let url = try store.enqueue(request)
                incoming.append(["name": window.name, "request_id": window.id, "launch_url": url.absoluteString])
            }
            try emit(["status": "FOUR_INCOMING_REQUESTS_STAGED", "requests": incoming,
                      "result_synthesized": false])
        case "verify":
            var results: [MiniAppResult] = []
            var windowSessionIDs: Set<UUID> = []
            for window in windows {
                let id = UUID(uuidString: window.id)!
                guard let request = try store.request(id: id),
                      request.appID == appID, request.opensInNewWindow,
                      request.source.documentID == "ns-window-" + window.name,
                      request.inputs.count == 1, request.inputs[0].text == window.name,
                      let result = try store.result(id: id), result.requestID == id
                else { throw Failure.actualRuntimeResultMissingOrIncorrect }
                if window.name == "gamma" {
                    guard result.status == .cancelled, result.items.isEmpty else {
                        throw Failure.actualRuntimeResultMissingOrIncorrect
                    }
                } else {
                    guard result.status == .success, result.operation == .replaceSelection,
                          result.items.count == 1, result.items[0].kind == .text,
                          result.items[0].text == window.name + "-edited",
                          let metadataRequestID = result.metadata["requestID"],
                          UUID(uuidString: metadataRequestID) == id,
                          result.metadata["documentID"] == "ns-window-" + window.name,
                          result.metadata["counter"] == (window.name == "beta" ? "2" : "1"),
                          let rawSessionID = result.metadata["windowSessionID"],
                          let sessionID = UUID(uuidString: rawSessionID), sessionID != id,
                          windowSessionIDs.insert(sessionID).inserted
                    else { throw Failure.actualRuntimeResultMissingOrIncorrect }
                }
                results.append(result)
            }
            guard windowSessionIDs.count == 3 else { throw Failure.actualRuntimeResultMissingOrIncorrect }
            let encoder = JSONEncoder()
            let payload = try JSONSerialization.jsonObject(with: encoder.encode(results))
            try emit(["status": "ACTUAL_NATIVE_WINDOW_RESULTS_VERIFIED", "results": payload,
                      "successful_request_scopes": 3, "cancelled_request_scopes": 1,
                      "distinct_successful_window_session_ids": windowSessionIDs.map { $0.uuidString.lowercased() }.sorted(),
                      "result_synthesized": false])
        default:
            throw Failure.invalidArguments
        }
    }

    static func emit(_ value: [String: Any]) throws {
        print(String(decoding: try JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys]),
                     as: UTF8.self))
    }

    enum Failure: Error {
        case invalidArguments, missingOSContainer, existingFixture, actualRuntimeResultMissingOrIncorrect
    }
}
