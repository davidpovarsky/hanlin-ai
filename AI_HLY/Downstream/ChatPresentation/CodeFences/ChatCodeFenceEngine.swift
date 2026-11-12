import Foundation
import UIKit
import WebKit

/// One private rendering document. Visible previews receive static HTML with
/// JavaScript disabled; no Markdown source becomes executable JavaScript.
@MainActor
final class ChatCodeFenceEngine: NSObject, WKNavigationDelegate {
    static let shared = ChatCodeFenceEngine()

    enum Failure: Error { case unavailable, invalidOutput, timeout, busy }
    private final class Cached: NSObject {
        let payload: ChatCodeFencePayload
        init(_ payload: ChatCodeFencePayload) { self.payload = payload }
    }
    private final class Invocation {
        var continuation: CheckedContinuation<ChatCodeFencePayload, Error>?
        var deadline: Task<Void, Never>?
        func finish(_ result: Result<ChatCodeFencePayload, Error>) {
            guard let continuation else { return }
            self.continuation = nil
            deadline?.cancel()
            deadline = nil
            continuation.resume(with: result)
        }
    }

    private let cache = NSCache<NSString, Cached>()
    private var cacheCosts: [NSString: Int] = [:]
    private var cacheOrder: [NSString] = []
    private var retainedBytes = 0
    private var webView: WKWebView?
    private var startup: Task<ChatCodeFenceDocument.Assets, Error>?
    private var navigation: WKNavigation?
    private var navigationContinuation: CheckedContinuation<Void, Error>?
    private var navigationDeadline: Task<Void, Never>?
    private var tail: Task<ChatCodeFencePayload, Error>?
    private var tailID = UUID()
    private var pending = 0
    private var disabledAfterTimeout = false
    var requiresRestart: Bool { disabledAfterTimeout }

    override init() {
        super.init()
        cache.totalCostLimit = 8 * 1024 * 1024
    }

    func render(kind: String, source: String, dark: Bool, fontSize: Double, split: Bool) async throws -> ChatCodeFencePayload {
        guard pending < 8 else { throw Failure.busy }
        guard ["mermaid", "diff"].contains(kind), source.utf8.count <= 1_048_576, fontSize.isFinite else { throw Failure.unavailable }
        pending += 1
        defer { pending -= 1 }
        let previous = tail, id = UUID()
        let work = Task {
            if let previous { _ = await previous.result }
            try Task.checkCancellation()
            return try await renderSerially(kind: kind, source: source, dark: dark, fontSize: min(28, max(12, fontSize)), split: split)
        }
        tail = work
        tailID = id
        defer { if tailID == id { tail = nil } }
        return try await withTaskCancellationHandler {
            try await work.value
        } onCancel: { work.cancel() }
    }

    private func renderSerially(kind: String, source: String, dark: Bool, fontSize: Double, split: Bool) async throws -> ChatCodeFencePayload {
        guard !disabledAfterTimeout else { throw Failure.unavailable }
        let assets = try await prepare()
        try Task.checkCancellation()
        let identity = await Task.detached(priority: .utility) {
            ChatCodeFenceDocument.digest(Data(("\(assets.identity)|\(kind)|\(dark)|\(fontSize)|\(split)|" + source).utf8))
        }.value as NSString
        if let hit = cache.object(forKey: identity) { return hit.payload }
        guard let webView else { throw Failure.unavailable }
        var result: ChatCodeFencePayload = try await withCheckedThrowingContinuation { continuation in
            let invocation = Invocation()
            invocation.continuation = continuation
            invocation.deadline = Task { [weak self] in
                do { try await Task.sleep(for: .seconds(8)) } catch { return }
                self?.disabledAfterTimeout = true
                self?.webView?.stopLoading()
                self?.webView = nil
                invocation.finish(.failure(Failure.timeout))
            }
            webView.callAsyncJavaScript("return await window.hanlinRenderCodeFence(options);", arguments: ["options": [
                "kind": kind, "source": source, "dark": dark, "fontSize": fontSize, "split": split
            ]], in: nil, in: .page) { result in
                let decoded = result.flatMap { raw in Result {
                    try Self.decode(raw, css: assets.css, dark: dark, fontSize: fontSize)
                } }
                Task { @MainActor in invocation.finish(decoded) }
            }
        }
        // Cancellation keeps serial ownership until the actual JS call drains;
        // it never starts a second Mermaid operation against shared globals.
        try Task.checkCancellation()
        let snapshot = result
        result.displayHTML = await Task.detached(priority: .utility) { ChatCodeFenceDocument.readonlyHTML(snapshot) }.value
        try Task.checkCancellation()
        let cost = result.html.utf8.count + result.css.utf8.count + (result.displayHTML?.utf8.count ?? 0)
        removeCached(identity)
        if cost <= 8 * 1024 * 1024 {
            while retainedBytes + cost > 8 * 1024 * 1024 || cacheCosts.count >= 32 {
                guard let oldest = cacheOrder.first else { break }
                removeCached(oldest)
            }
            retainedBytes += cost
            cacheCosts[identity] = cost
            cacheOrder.append(identity)
            cache.setObject(Cached(result), forKey: identity, cost: cost)
        }
        return result
    }

    private func removeCached(_ key: NSString) {
        retainedBytes -= cacheCosts.removeValue(forKey: key) ?? 0
        cacheOrder.removeAll { $0 == key }
        cache.removeObject(forKey: key)
    }

    nonisolated private static func decode(_ raw: Any, css: String, dark: Bool, fontSize: Double) throws -> ChatCodeFencePayload {
        guard let object = raw as? [String: Any], let html = object["html"] as? String,
              html.utf8.count <= 16 * 1024 * 1024,
              let width = (object["width"] as? NSNumber)?.doubleValue,
              let height = (object["height"] as? NSNumber)?.doubleValue,
              width.isFinite, height.isFinite, width > 0, height > 0, width <= 20_000, height <= 100_000 else {
            throw Failure.invalidOutput
        }
        return ChatCodeFencePayload(html: html, css: css, width: width, height: height, fontSize: fontSize, dark: dark)
    }

    private func prepare() async throws -> ChatCodeFenceDocument.Assets {
        if let startup { return try await startup.value }
        let work = Task {
            let prepared = try await Task.detached(priority: .utility) {
                let assets = try ChatCodeFenceDocument.loadAssets()
                return (assets, ChatCodeFenceDocument.workerHTML(assets: assets))
            }.value
            let assets = prepared.0
            let configuration = WKWebViewConfiguration()
            configuration.websiteDataStore = .nonPersistent()
            configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
            let view = WKWebView(frame: CGRect(x: 0, y: 0, width: 1024, height: 768), configuration: configuration)
            view.navigationDelegate = self
            self.webView = view
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                self.navigationContinuation = continuation
                self.navigation = view.loadHTMLString(prepared.1, baseURL: nil)
                self.navigationDeadline = Task { [weak self] in
                    do { try await Task.sleep(for: .seconds(15)) } catch { return }
                    self?.completeNavigation(.failure(Failure.timeout))
                }
            }
            return assets
        }
        startup = work
        do { return try await work.value } catch {
            startup = nil
            webView?.stopLoading()
            webView = nil
            throw error
        }
    }

    private func completeNavigation(_ result: Result<Void, Error>) {
        guard let continuation = navigationContinuation else { return }
        navigationContinuation = nil
        navigationDeadline?.cancel()
        navigationDeadline = nil
        navigation = nil
        continuation.resume(with: result)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard navigation === self.navigation else { return }
        completeNavigation(.success(()))
    }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        guard navigation === self.navigation else { return }
        completeNavigation(.failure(error))
    }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        guard navigation === self.navigation else { return }
        completeNavigation(.failure(error))
    }
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        completeNavigation(.failure(Failure.unavailable))
        startup = nil
        self.webView = nil
    }
    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        decisionHandler(action.navigationType == .other && action.request.url?.absoluteString == "about:blank" ? .allow : .cancel)
    }
}
