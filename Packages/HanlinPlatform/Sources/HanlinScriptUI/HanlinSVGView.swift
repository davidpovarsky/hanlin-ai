import Foundation
import SwiftUI
import WebKit

struct HanlinSVGView: View {
    private let document: String?

    init(code: String) {
        document = HanlinSVGSanitizer.sanitize(code)
    }

    var body: some View {
        if let document {
            HanlinSVGWebView(document: document)
                .accessibilityLabel("SVG image")
        } else {
            ContentUnavailableView("Invalid SVG", systemImage: "exclamationmark.triangle")
        }
    }
}

private final class HanlinSVGValidationDelegate: NSObject, XMLParserDelegate {
    private(set) var isValid = true
    private var foundRoot = false

    func parser(
        _: XMLParser,
        didStartElement elementName: String,
        namespaceURI _: String?,
        qualifiedName _: String?,
        attributes attributeDict: [String: String]
    ) {
        let name = elementName.lowercased()
        if !foundRoot {
            foundRoot = true
            if name != "svg" { isValid = false }
        }
        if name == "script" || name == "foreignobject" || name == "style" { isValid = false }
        for (attribute, value) in attributeDict {
            let normalizedAttribute = attribute.lowercased()
            let normalizedValue = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if normalizedAttribute.hasPrefix("on") { isValid = false }
            if normalizedAttribute == "href" || normalizedAttribute == "xlink:href" {
                if !normalizedValue.hasPrefix("#") && !normalizedValue.hasPrefix("data:image/") {
                    isValid = false
                }
            }
            if normalizedValue.contains("url(http:")
                || normalizedValue.contains("url(https:")
                || normalizedValue.contains("url(file:") {
                isValid = false
            }
        }
    }

    func parser(_: XMLParser, parseErrorOccurred _: Error) {
        isValid = false
    }
}

enum HanlinSVGSanitizer {
    static func sanitize(_ source: String) -> String? {
        let data = Data(source.utf8)
        guard !data.isEmpty, data.count <= 2 * 1_024 * 1_024 else { return nil }
        let parser = XMLParser(data: data)
        parser.shouldResolveExternalEntities = false
        let delegate = HanlinSVGValidationDelegate()
        parser.delegate = delegate
        guard parser.parse(), delegate.isValid else { return nil }
        return source.replacingOccurrences(
            of: #"<!DOCTYPE[\s\S]*?>"#,
            with: "",
            options: .regularExpression
        )
    }
}

private final class HanlinSVGNavigationDelegate: NSObject, WKNavigationDelegate {
    func webView(
        _: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction
    ) async -> WKNavigationActionPolicy {
        guard let scheme = navigationAction.request.url?.scheme else { return .allow }
        return scheme == "about" ? .allow : .cancel
    }
}

#if os(iOS)
private struct HanlinSVGWebView: UIViewRepresentable {
    let document: String

    func makeCoordinator() -> HanlinSVGNavigationDelegate { .init() }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.isOpaque = false
        view.backgroundColor = .clear
        view.scrollView.isScrollEnabled = false
        view.navigationDelegate = context.coordinator
        return view
    }

    func updateUIView(_ view: WKWebView, context _: Context) {
        view.loadHTMLString(document, baseURL: nil)
    }
}
#else
private struct HanlinSVGWebView: NSViewRepresentable {
    let document: String

    func makeCoordinator() -> HanlinSVGNavigationDelegate { .init() }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.navigationDelegate = context.coordinator
        return view
    }

    func updateNSView(_ view: WKWebView, context _: Context) {
        view.loadHTMLString(document, baseURL: nil)
    }
}
#endif
