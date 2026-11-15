import SwiftUI
import WebKit

/// The sanctioned YouTube player is created only on a user request. Direct native media
/// remains with the official A2UI Video/AudioPlayer components.
struct HanlinYouTubePlayerView: View {
    let video: HanlinYouTubeVideo

    var body: some View {
        HanlinRequestedYouTubePlayer(video: video).id(video.id)
    }
}

/// The request belongs to this video identity before UIKit construction. An onChange reset
/// alone could let a newly identified WebView load before that reset is applied.
private struct HanlinRequestedYouTubePlayer: View {
    let video: HanlinYouTubeVideo
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.isEnabled) private var isEnabled
    @State private var requested = false
    @State private var ready = false
    @State private var failed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if requested && !failed, let origin = HanlinYouTubeDocument.origin(bundleID: Bundle.main.bundleIdentifier) {
                HanlinYouTubeWebView(video: video, origin: origin,
                    onReady: { ready = true }, onFailure: { failed = true })
                    .aspectRatio(16 / 9, contentMode: .fit)
                    .frame(minWidth: 200, minHeight: 200)
                    .accessibilityLabel("YouTube video")
                    .accessibilityIdentifier("hanlin-youtube-player")
                    .id(video.id)
                    .task {
                        do { try await Task.sleep(for: .seconds(15)) } catch { return }
                        if !ready { failed = true }
                    }
            } else {
                Button {
                    ready = false
                    failed = HanlinYouTubeDocument.origin(bundleID: Bundle.main.bundleIdentifier) == nil
                    requested = !failed
                } label: {
                    Label(failed ? String(localized: "Retry YouTube player") : String(localized: "Load YouTube player"), systemImage: "play.rectangle")
                }
                .accessibilityIdentifier("hanlin-youtube-load")
                if failed { Text("This video could not be played here.").foregroundStyle(.secondary) }
            }
            Link("Open in YouTube", destination: video.sourceURL)
                .accessibilityIdentifier("hanlin-youtube-source")
        }
        .onChange(of: video) { requested = false; ready = false; failed = false }
        .onChange(of: scenePhase) { _, phase in if phase != .active { requested = false } }
        .onChange(of: isEnabled) { _, enabled in if !enabled { requested = false } }
        .onDisappear { requested = false }
    }
}

private struct HanlinYouTubeWebView: UIViewRepresentable {
    let video: HanlinYouTubeVideo
    let origin: URL
    let onReady: () -> Void
    let onFailure: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onReady: onReady, onFailure: onFailure) }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = .all
        config.userContentController.add(context.coordinator, name: "hanlinYouTube")
        let view = WKWebView(frame: .zero, configuration: config)
        context.coordinator.webView = view
        context.coordinator.origin = origin
        view.navigationDelegate = context.coordinator
        view.scrollView.isScrollEnabled = false
        view.loadHTMLString(HanlinYouTubeDocument.html(video: video, origin: origin), baseURL: origin)
        return view
    }

    func updateUIView(_ view: WKWebView, context: Context) {
        context.coordinator.onReady = onReady
        context.coordinator.onFailure = onFailure
    }

    static func dismantleUIView(_ view: WKWebView, coordinator: Coordinator) {
        coordinator.isClosed = true
        view.evaluateJavaScript("window.hanlinStopYouTube && window.hanlinStopYouTube()", completionHandler: nil)
        view.stopLoading()
        view.configuration.userContentController.removeScriptMessageHandler(forName: "hanlinYouTube")
        view.navigationDelegate = nil
        view.loadHTMLString("", baseURL: nil)
    }

    @MainActor
    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        weak var webView: WKWebView?
        var origin: URL?
        var isClosed = false
        var onReady: () -> Void
        var onFailure: () -> Void

        init(onReady: @escaping () -> Void, onFailure: @escaping () -> Void) {
            self.onReady = onReady
            self.onFailure = onFailure
        }

        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            guard !isClosed, message.webView === webView, message.frameInfo.isMainFrame,
                  let value = message.body as? [String: Any], let kind = value["kind"] as? String else { return }
            if kind == "ready" { onReady() }
            else if kind == "error" { onFailure() }
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard !isClosed, let url = navigationAction.request.url else { decisionHandler(.cancel); return }
            if navigationAction.targetFrame?.isMainFrame == true {
                let isOwnOrigin = origin != nil && url.scheme == origin?.scheme && url.host == origin?.host
                    && url.user == nil && url.password == nil && url.query == nil && url.fragment == nil
                    && (url.path.isEmpty || url.path == "/")
                decisionHandler(url.absoluteString == "about:blank" || isOwnOrigin ? .allow : .cancel)
            } else {
                // YouTube owns its embedded player navigation, never an arbitrary model URL.
                let host = url.host?.lowercased()
                decisionHandler(url.scheme == "https" && ["www.youtube.com", "www.youtube-nocookie.com"].contains(host ?? "") ? .allow : .cancel)
            }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            if !isClosed { onFailure() }
        }
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            if !isClosed { onFailure() }
        }
        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            if !isClosed { onFailure() }
        }
    }
}
