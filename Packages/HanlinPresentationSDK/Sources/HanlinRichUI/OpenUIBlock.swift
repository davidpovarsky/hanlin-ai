#if canImport(SwiftUI) && canImport(UIKit) && canImport(WebKit)
import SwiftUI
import WebKit
import Observation
import HanlinPresentationKit

/// The React renderer and the native controls share the original local OpenUI
/// interpreter. Only the React target displays web content. SwiftUI receives the
/// evaluated tree and uses native controls, with no independent parser or AI.
public struct OpenUIBlock: View {
    public let part: MessageRichPart
    public let state: MessageOpenUIStateStore
    public let configuration: OpenUIRendererConfiguration
    public let perform: @MainActor (PresentationAction) async throws -> PresentationValue
    @State private var runtime = OpenUIBridgeModel()

    public init(part: MessageRichPart, state: MessageOpenUIStateStore,
                configuration: OpenUIRendererConfiguration = .bundled,
                perform: @escaping @MainActor (PresentationAction) async throws -> PresentationValue) {
        self.part = part; self.state = state; self.configuration = configuration; self.perform = perform
    }
    public var body: some View {
        if case .openUI(let program, let target) = part.payload,
           part.identity == state.identity, state.profile.renderTargets.contains(target),
           Set(part.catalogVersions).isSubset(of: Set(state.profile.catalogs.map(\.reference))) {
            VStack(alignment: .leading, spacing: 8) {
                if target == .swiftui, let tree = runtime.tree {
                    NativeOpenUINode(value: tree, runtime: runtime, configuration: configuration)
                }
                OpenUIWebRuntime(part: part, program: program, target: target,
                    state: state, revision: state.revision, runtime: runtime, configuration: configuration, perform: perform)
                    .frame(height: target == .react ? max(1, runtime.height) : 1)
                    .opacity(target == .react ? 1 : 0)
                    .accessibilityHidden(target == .swiftui)
                    .allowsHitTesting(target == .react)
                if let error = runtime.error {
                    Text(error).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("hanlin-openui-\(target.rawValue)-\(part.streamOrder)")
        }
    }
}

@MainActor @Observable
final class OpenUIBridgeModel {
    var tree: PresentationValue?
    var height: CGFloat = 1
    var error: String?
    @ObservationIgnored weak var webView: WKWebView?

    func field(_ id: String, value: PresentationValue) {
        invoke("window.hanlinOpenUI.field(id, value)", arguments: ["id": id, "value": value.bridgeObject])
    }
    func action(_ id: String) { invoke("return window.hanlinOpenUI.action(id)", arguments: ["id": id]) }
    private func invoke(_ script: String, arguments: [String: Any]) {
        Task { @MainActor [weak self] in
            guard let self, let webView else { return }
            do { _ = try await webView.callAsyncJavaScript(script, arguments: arguments, in: nil, contentWorld: .page) }
            catch { self.error = error.localizedDescription }
        }
    }
}

private struct OpenUIWebRuntime: UIViewRepresentable {
    let part: MessageRichPart
    let program: String
    let target: OpenUIRenderTarget
    let state: MessageOpenUIStateStore
    let revision: UInt64
    let runtime: OpenUIBridgeModel
    let configuration: OpenUIRendererConfiguration
    let perform: @MainActor (PresentationAction) async throws -> PresentationValue

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }
    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.userContentController.addScriptMessageHandler(context.coordinator, contentWorld: .page, name: "hanlinOpenUI")
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.isOpaque = false; view.backgroundColor = .clear
        view.scrollView.backgroundColor = .clear; view.scrollView.isScrollEnabled = false
        view.navigationDelegate = context.coordinator
        runtime.webView = view
        if let directory = self.configuration.resourceDirectory {
            view.loadFileURL(directory.appending(path: "index.html"), allowingReadAccessTo: directory)
        } else { runtime.error = "OpenUI assets are unavailable." }
        return view
    }
    func updateUIView(_ view: WKWebView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.update(view)
    }
    static func dismantleUIView(_ view: WKWebView, coordinator: Coordinator) {
        coordinator.invalidate()
        view.configuration.userContentController.removeScriptMessageHandler(forName: "hanlinOpenUI", contentWorld: .page)
        view.stopLoading(); view.navigationDelegate = nil
    }

    @MainActor final class Coordinator: NSObject, WKScriptMessageHandlerWithReply, WKNavigationDelegate {
        var parent: OpenUIWebRuntime
        var ready = false
        var lastInput: Data?
        var pending: [UUID: Task<Void, Never>] = [:]
        init(parent: OpenUIWebRuntime) { self.parent = parent }
        func invalidate() { for task in pending.values { task.cancel() }; pending.removeAll(); ready = false }

        func update(_ view: WKWebView) {
            guard ready else { return }
            let input: [String: PresentationValue] = [
                "program": .string(parent.program), "complete": .bool(parent.part.isComplete),
                "target": .string(parent.target.rawValue), "state": .object(parent.state.values),
                "catalogID": .string(parent.part.catalogVersions.last?.key ?? "openui.original@1"),
            ]
            let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
            guard let data = try? encoder.encode(input), data != lastInput else { return }
            lastInput = data
            Task { @MainActor [weak self] in
                guard let self, ready else { return }
                do { _ = try await view.callAsyncJavaScript("window.hanlinOpenUI.update(input)",
                    arguments: ["input": PresentationValue.object(input).bridgeObject], in: nil, contentWorld: .page) }
                catch { if ready { parent.runtime.error = error.localizedDescription } }
            }
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage,
                                   replyHandler: @escaping @MainActor @Sendable (Any?, String?) -> Void) {
            guard message.frameInfo.isMainFrame, let body = message.body as? [String: Any],
                  let kind = body["kind"] as? String else { replyHandler(nil, "Invalid bridge message"); return }
            do {
                switch kind {
                case "ready": ready = true; if let view = parent.runtime.webView { update(view) }
                case "height":
                    if let height = body["height"] as? Double, height.isFinite, height > 0,
                       abs(parent.runtime.height - height) > 0.5 { parent.runtime.height = height }
                case "tree": parent.runtime.tree = try PresentationValue.bridgeValue(body["tree"] ?? NSNull())
                case "state":
                    let next = try PresentationValue.bridgeValue(body["state"] ?? [:]).object ?? [:]
                    let previous = try PresentationValue.bridgeValue(body["previous"] ?? [:]).object ?? [:]
                    parent.state.mergeRendererState(next, previous: previous)
                case "error": parent.runtime.error = body["message"] as? String
                case "tool", "action":
                    let parameters = try PresentationValue.bridgeValue(body).object ?? [:]
                    let action = PresentationAction(identity: parent.part.identity, partID: parent.part.id,
                        name: kind, parameters: parameters)
                    let id = UUID()
                    pending[id] = Task { @MainActor [weak self] in
                        guard let self else { replyHandler(nil, "Presentation closed"); return }
                        defer { pending.removeValue(forKey: id) }
                        do {
                            let result = try await parent.perform(action)
                            try Task.checkCancellation()
                            replyHandler(result.bridgeObject, nil)
                        } catch { replyHandler(nil, error.localizedDescription) }
                    }
                    return
                default: replyHandler(nil, "Unknown bridge message"); return
                }
                replyHandler(NSNull(), nil)
            } catch { replyHandler(nil, error.localizedDescription) }
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void) {
            if navigationAction.navigationType == .linkActivated, let url = navigationAction.request.url {
                let action = PresentationAction(identity: parent.part.identity, partID: parent.part.id,
                    name: "action", parameters: ["event": .object(["type": .string("open_url"), "params": .object(["url": .string(url.absoluteString)])])])
                Task { @MainActor in
                    do { _ = try await parent.perform(action) } catch { parent.runtime.error = error.localizedDescription }
                }
                decisionHandler(.cancel)
            } else { decisionHandler(navigationAction.request.url?.isFileURL == true ? .allow : .cancel) }
        }
    }
}

extension PresentationValue {
    var bridgeObject: Any {
        switch self {
        case .null: NSNull()
        case .bool(let value): value
        case .number(let value): value
        case .string(let value): value
        case .array(let values): values.map(\.bridgeObject)
        case .object(let values): values.mapValues(\.bridgeObject)
        }
    }
    static func bridgeValue(_ object: Any) throws -> PresentationValue {
        try JSONDecoder().decode(Self.self, from: JSONSerialization.data(withJSONObject: object, options: [.fragmentsAllowed]))
    }
}
#endif
