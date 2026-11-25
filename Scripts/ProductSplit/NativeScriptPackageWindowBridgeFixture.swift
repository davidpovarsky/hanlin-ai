import Foundation

/// Incoming data only. Import, package execution, file reads, native edits,
/// cancellation and completion are performed by the actual application.
@main
struct NativeScriptPackageWindowBridgeFixture {
    static let windows: [(name: String, package: String, id: String)] = [
        ("alpha", "alpha", "1e23b001-6a2c-4c0f-b001-202611240011"),
        ("beta", "beta", "1e23b002-6a2c-4c0f-b002-202611240012"),
        ("gamma", "alpha", "1e23b003-6a2c-4c0f-b003-202611240013"),
        ("delta", "beta", "1e23b004-6a2c-4c0f-b004-202611240014"),
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
                let appID = "hanlin.nativescript.package-" + window.package
                let request = MiniAppInvocation(
                    id: id, appID: appID,
                    source: .init(
                        appID: "com.itorah.hanlinminiapps.package-window-fixture",
                        displayName: "NativeScript package window fixture source",
                        documentID: "ns-package-" + window.name,
                        documentTitle: "NativeScript package " + window.name,
                        revision: "fixture-" + window.name + "-v1",
                        selection: .init(location: 7, length: window.name.utf16.count, text: window.name),
                        documentText: "before " + window.name + " after"
                    ),
                    inputs: [.init(kind: .text, text: window.name)],
                    operation: .replaceSelection, opensInNewWindow: true
                )
                let url = try store.enqueue(request)
                incoming.append([
                    "name": window.name, "package_id": appID,
                    "request_id": window.id, "launch_url": url.absoluteString,
                ])
            }
            try emit([
                "status": "FOUR_DISTINCT_PACKAGE_INCOMING_REQUESTS_STAGED",
                "requests": incoming, "result_synthesized": false,
            ])
        case "verify":
            var results: [MiniAppResult] = []
            var sessions: Set<UUID> = []
            for window in windows {
                let id = UUID(uuidString: window.id)!
                let appID = "hanlin.nativescript.package-" + window.package
                guard let request = try store.request(id: id),
                      request.appID == appID, request.opensInNewWindow,
                      request.source.documentID == "ns-package-" + window.name,
                      request.inputs.count == 1, request.inputs[0].text == window.name,
                      let result = try store.result(id: id), result.requestID == id
                else { throw Failure.actualRuntimeResultMissingOrIncorrect }
                if window.name == "gamma" {
                    guard result.status == .cancelled, result.items.isEmpty else {
                        throw Failure.actualRuntimeResultMissingOrIncorrect
                    }
                } else {
                    let expectedStyle = window.package == "alpha" ? "255,59,48,255" : "0,122,255,255"
                    guard result.status == .success, result.operation == .replaceSelection,
                          result.items.count == 1, result.items[0].kind == .text,
                          result.items[0].text == window.name + "-edited",
                          result.metadata["packageID"] == appID,
                          result.metadata["staticModule"] == window.package + ":relative",
                          result.metadata["privateModule"] == window.package + ":private",
                          result.metadata["dynamicModule"] == window.package + ":dynamic",
                          result.metadata["asset"] == window.package + ":asset",
                          result.metadata["storedValue"] == window.name + "-edited",
                          result.metadata["styleColor"] == expectedStyle,
                          let returnedRequest = result.metadata["requestID"],
                          UUID(uuidString: returnedRequest) == id,
                          result.metadata["documentID"] == "ns-package-" + window.name,
                          result.metadata["counter"] == (window.name == "beta" ? "2" : "1"),
                          let rawSession = result.metadata["windowSessionID"],
                          let session = UUID(uuidString: rawSession), session != id,
                          sessions.insert(session).inserted
                    else { throw Failure.actualRuntimeResultMissingOrIncorrect }
                }
                results.append(result)
            }
            guard sessions.count == 3 else { throw Failure.actualRuntimeResultMissingOrIncorrect }
            let payload = try JSONSerialization.jsonObject(with: JSONEncoder().encode(results))
            try emit([
                "status": "ACTUAL_DISTINCT_PACKAGE_WINDOW_RESULTS_VERIFIED",
                "results": payload, "successful_request_scopes": 3, "cancelled_request_scopes": 1,
                "distinct_package_ids": ["hanlin.nativescript.package-alpha", "hanlin.nativescript.package-beta"],
                "distinct_successful_window_session_ids": sessions.map { $0.uuidString.lowercased() }.sorted(),
                "verified_from_runtime_outputs": [
                    "relative_static_import", "colliding_private_bare_import", "late_dynamic_import",
                    "package_asset_bytes", "fresh_package_data_readback", "computed_scoped_style",
                    "original_request_document", "captured_callback_counter",
                ],
                "result_synthesized": false,
            ])
        default:
            throw Failure.invalidArguments
        }
    }

    static func emit(_ value: [String: Any]) throws {
        let data = try JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    }

    enum Failure: Error {
        case invalidArguments, missingOSContainer, existingFixture, actualRuntimeResultMissingOrIncorrect
    }
}
