import Foundation
import HanlinPresentationKit
import HanlinRichUI
import Testing
import UIKit
import WebKit

/// Uses the shipping local bundle and original React/lang-core interpreters.
/// The injected tool reply is a boundary fixture, not live Host acceptance.
@MainActor
@Suite("Original OpenUI Host wire", .serialized)
struct HanlinOpenUIBridgeTests {
    @Test(arguments: ["react", "swiftui"])
    func originalBundledQueryUsesHostBridge(target: String) async throws {
        let directory = try #require(OpenUICatalogs.resourceDirectory)
        let bridge = OpenUIHostWireFixture()
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.userContentController.addScriptMessageHandler(
            bridge, contentWorld: .page, name: "hanlinOpenUI")
        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 390, height: 300),
                                configuration: configuration)
        let controller = UIViewController()
        controller.view = webView
        let window = UIWindow(frame: webView.frame)
        window.rootViewController = controller
        window.makeKeyAndVisible()
        defer {
            configuration.userContentController.removeScriptMessageHandler(forName: "hanlinOpenUI",
                                                                            contentWorld: .page)
            webView.stopLoading()
            window.isHidden = true
        }
        webView.loadFileURL(directory.appending(path: "index.html"), allowingReadAccessTo: directory)
        try await waitFor("original bridge ready") { bridge.ready }

        let program = """
        result = Query("fixture_lookup", {query: "original runtime"}, {})
        root = Stack([TextContent(result.title)])
        """
        let input: [String: Any] = [
            "program": program, "complete": true, "target": target,
            "state": [String: String](), "catalogID": "openui.original@1",
        ]
        _ = try await webView.callAsyncJavaScript("window.hanlinOpenUI.update(input)",
            arguments: ["input": input], in: nil, contentWorld: .page)
        try await waitFor("original \(target) query result") {
            if target == "swiftui" { return bridge.nativeTree.contains(OpenUIHostWireFixture.resultText) }
            let text = try await webView.callAsyncJavaScript(
                "return document.getElementById('root').textContent",
                arguments: [:], in: nil, contentWorld: .page) as? String
            return text?.contains(OpenUIHostWireFixture.resultText) == true
        }
        #expect(bridge.requests == [
            .init(name: "fixture_lookup", arguments: ["query": .string("original runtime")]),
        ])
        #expect(bridge.errors.isEmpty)
    }

    private func waitFor(_ description: String,
                         until condition: @MainActor () async throws -> Bool) async throws {
        let deadline = Date().addingTimeInterval(10)
        while Date() < deadline {
            if try await condition() { return }
            try await Task.sleep(for: .milliseconds(25))
        }
        throw OpenUIHostWireFixture.Failure.timeout(description)
    }
}

@MainActor
private final class OpenUIHostWireFixture: NSObject, WKScriptMessageHandlerWithReply {
    struct Request: Equatable {
        let name: String
        let arguments: [String: PresentationValue]
    }
    enum Failure: Error { case timeout(String), invalidRequest }

    static let resultText = "ORIGINAL_OPENUI_HOST_RESULT_שלום"
    var ready = false
    var requests: [Request] = []
    var nativeTree = ""
    var errors: [String] = []

    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage,
                               replyHandler: @escaping @MainActor @Sendable (Any?, String?) -> Void) {
        guard message.frameInfo.isMainFrame, let body = message.body as? [String: Any],
              let kind = body["kind"] as? String else {
            replyHandler(nil, "Invalid fixture bridge message")
            return
        }
        do {
            switch kind {
            case "ready":
                ready = true
            case "tool":
                guard let name = body["name"] as? String, let raw = body["args"] else {
                    throw Failure.invalidRequest
                }
                let args = try JSONDecoder().decode([String: PresentationValue].self,
                    from: JSONSerialization.data(withJSONObject: raw))
                requests.append(.init(name: name, arguments: args))
                replyHandler(["title": Self.resultText], nil)
                return
            case "tree":
                nativeTree = String(decoding: try JSONSerialization.data(
                    withJSONObject: body["tree"] ?? NSNull(), options: [.fragmentsAllowed]), as: UTF8.self)
            case "error":
                errors.append(body["message"] as? String ?? "Unspecified original renderer error")
            default:
                break
            }
            replyHandler(NSNull(), nil)
        } catch {
            errors.append(String(describing: error))
            replyHandler(nil, String(describing: error))
        }
    }
}
