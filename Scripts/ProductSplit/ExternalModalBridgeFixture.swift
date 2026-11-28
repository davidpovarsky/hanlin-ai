import Foundation

/// A controlled incoming request only. The installed MiniApp writes the result.
/// Compile this file with the existing Foundation-only bridge sources.
@main
struct ExternalModalBridgeFixture {
    static let requestID = UUID(uuidString: "4f2ecda0-9c21-46a2-b2e1-8cd4f017c623")!
    static let input = "Shared modal input 20261123"
    static let documentID = "external-modal-document"

    static func main() throws {
        guard CommandLine.arguments.count == 3 else { throw Failure.invalidArguments }
        let mode = CommandLine.arguments[1]
        let container = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
        let values = try container.resourceValues(forKeys: [.isDirectoryKey])
        guard values.isDirectory == true else { throw Failure.missingOSContainer }
        let store = try MiniAppBridgeStore(containerURL: container)
        if mode == "seed" {
            guard try store.request(id: requestID) == nil else { throw Failure.existingFixture }
            let request = MiniAppInvocation(id: requestID, appID: "hanlin.fixture.external-modal",
                source: .init(appID: "com.itorah.hanlinminiapps.modal-fixture", displayName: "Modal fixture source",
                    documentID: documentID, documentTitle: "External modal regression", revision: "fixture-v1"),
                inputs: [.init(kind: .text, text: input)], operation: .display,
                opensInNewWindow: false)
            let url = try store.enqueue(request)
            try emit(["status": "INCOMING_REQUEST_STAGED", "request_id": requestID.uuidString.lowercased(),
                      "launch_url": url.absoluteString, "app_group_container": container.path,
                      "result_synthesized": false])
        } else if mode == "verify" {
            guard let request = try store.request(id: requestID), request.appID == "hanlin.fixture.external-modal",
                  let result = try store.result(id: requestID), result.status == .success,
                  result.operation == .display, result.message == "Modal invocation survived",
                  result.items.count == 1, result.items[0].kind == .text,
                  result.items[0].text == "modal-survived:\(requestID.uuidString.lowercased()):counter=2:input=\(input)",
                  result.metadata["beforeRequestID"] == requestID.uuidString.lowercased(),
                  result.metadata["afterRequestID"] == requestID.uuidString.lowercased(),
                  result.metadata["counter"] == "2", result.metadata["documentID"] == documentID
            else { throw Failure.actualRuntimeResultMissingOrIncorrect }
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            print(String(decoding: try encoder.encode(result), as: UTF8.self))
        } else { throw Failure.invalidArguments }
    }

    static func emit(_ value: [String: Any]) throws {
        print(String(decoding: try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]), as: UTF8.self))
    }

    enum Failure: Error {
        case invalidArguments, missingOSContainer, existingFixture, actualRuntimeResultMissingOrIncorrect
    }
}
