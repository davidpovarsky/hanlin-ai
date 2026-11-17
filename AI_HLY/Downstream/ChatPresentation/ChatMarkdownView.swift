import SwiftUI
import SwiftStreamingMarkdown
import UIKit
import ImageIO
import HanlinPresentationKit
import HanlinChatUI

/// The shared renderer inside the original message bubble and translated/transcript text.
struct ChatMarkdownView: View {
    let text: String
    /// Ordered model parts parse independently, so their block IDs need a stable namespace.
    var selectionPartID: UUID? = nil
    var messageText: String? = nil
    var savePersonal: (@MainActor @Sendable (ChatTextQuote) -> Void)?
    var saveKnowledge: (@MainActor @Sendable (String) -> Void)?
    var onRendered: (@MainActor @Sendable () -> Void)?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.layoutDirection) private var layoutDirection
    @Environment(\.hanlinMessageCitations) private var citations
    @Environment(\.chatExcerptSource) private var source
    @Environment(\.chatSourceDestination) private var destination
    @Environment(\.chatMarkdownSelectionActivity) private var selectionActivity
    @Environment(\.chatMarkdownDidRender) private var markdownDidRender
    @State private var highlightedRequestID: UUID?
    @State private var listener = ChatMarkdownListener()
    @State private var citationIcons: [String: Data] = [:]

    var body: some View {
        let _ = dynamicTypeSize
        let citationProjection = citations?.projection(for: text)
        let _ = listener.update(savePersonal: scopedSavePersonal, saveKnowledge: saveKnowledge, onRendered: {
            onRendered?()
            if let messageID = source?.messageID { markdownDidRender?(messageID) }
        })
        MarkdownView(text: citationProjection?.markdown ?? text, config: config, listener: listener)
            // The native paragraph retains its OpenURLAction. Keep its presenter
            // with the renderer rather than an independently updating bubble.
            .modifier(ChatLinkPresentation(citationGroups: citationProjection?.groups ?? []))
            .task(id: citationProjection?.groups.map(\.url)) {
                await loadCitationIcons(citationProjection?.groups ?? [])
            }
            .markdownCodeBlockRenderer { block in
                guard block.isFenceClosed == true else { return nil }
                let language = block.language?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                let kind: String
                switch language {
                case "mermaid": kind = "mermaid"
                case "diff", "patch": kind = "diff"
                default: return nil
                }
                return AnyView(ChatCodeFenceView(blockID: block.id, kind: kind, source: block.code))
            }
            .markdownSelectionHighlight(highlight)
            .task(id: destination?.id) {
                highlightedRequestID = destination?.id
                guard let requestID = destination?.id else { return }
                do { try await Task.sleep(for: .seconds(4)) } catch { return }
                if highlightedRequestID == requestID { highlightedRequestID = nil }
            }
            .markdownSelectionActivity { id, active in selectionActivity?(id, active) }
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var highlight: MarkdownSelectionHighlight? {
        guard let destination, highlightedRequestID == destination.id, destination.messageID == source?.messageID,
              destination.sourceDigest == ChatSavedExcerpt.digest(messageText ?? text),
              let selection = destination.selection, let storedBlockID = selection.sourceBlockID else { return nil }
        let blockID: String
        if let selectionPartID {
            let prefix = "hanlin-part:\(selectionPartID.uuidString):"
            guard storedBlockID.hasPrefix(prefix) else { return nil }
            blockID = String(storedBlockID.dropFirst(prefix.count))
        } else {
            guard !storedBlockID.hasPrefix("hanlin-part:") else { return nil }
            blockID = storedBlockID
        }
        return MarkdownSelectionHighlight(sourceBlockID: blockID, renderedText: selection.renderedText, range: selection.range)
    }

    private var scopedSavePersonal: (@MainActor @Sendable (ChatTextQuote) -> Void)? {
        guard let savePersonal else { return nil }
        guard let selectionPartID else { return savePersonal }
        return { quote in
            savePersonal(ChatTextQuote(text: quote.text, renderedText: quote.renderedText, range: quote.range,
                sourceBlockID: quote.sourceBlockID.map { "hanlin-part:\(selectionPartID.uuidString):\($0)" }))
        }
    }

    private var config: MarkdownRenderConfig {
        var items: [TextContextMenuItem] = []
        if savePersonal != nil { items.append(TextContextMenuItem(id: "hanlin.savePersonal", title: String(localized: "Save for myself"), image: UIImage(systemName: "bookmark"))) }
        if saveKnowledge != nil { items.append(TextContextMenuItem(id: "hanlin.saveKnowledge", title: String(localized: "Save to knowledge"), image: UIImage(systemName: "backpack"))) }
        func fonts(_ style: UIFont.TextStyle) -> TextFonts {
            let normal = UIFont.preferredFont(forTextStyle: style)
            func variant(_ traits: UIFontDescriptor.SymbolicTraits) -> UIFont? {
                normal.fontDescriptor.withSymbolicTraits(traits).map { UIFont(descriptor: $0, size: 0) }
            }
            return TextFonts(normal: normal, italic: variant(.traitItalic), bold: variant(.traitBold),
                boldItalic: variant([.traitBold, .traitItalic]), preferredLetterSpacing: nil, preferredLineHeight: nil)
        }
        let body = MarkdownRenderConfig.MarkdownTextStyle(textFonts: fonts(.body), textColor: .primary)
        let codeStyle = CodeBlockConfig.default
        let codeFonts = TextFonts(normal: UIFont.monospacedSystemFont(ofSize: UIFont.preferredFont(forTextStyle: .callout).pointSize, weight: .regular),
            italic: nil, bold: nil, boldItalic: nil, preferredLetterSpacing: nil, preferredLineHeight: nil)
        #if HANLIN_A2UI_POC
        // The pinned renderer owns parsing, loading/failure presentation and fullscreen zoom.
        // Keep this in the existing rich-content prototype until network/resource gates pass.
        let imageConfig = ImageConfig(enabled: true,
            allowedImageTypes: [.remote(allowedDomains: [])], fullscreenViewerEnabled: true)
        #else
        let imageConfig = ImageConfig.disabled
        #endif
        return MarkdownRenderConfig.default
            .withCitationConfig(value: .init(font: UIFont.preferredFont(forTextStyle: .caption2),
                textColor: .secondary, backgroundColor: Color.secondary.opacity(0.10),
                iconsByCitationURL: citationIcons, iconOnTrailingEdge: layoutDirection == .rightToLeft))
            .withImageConfig(imageConfig)
            .withShouldAnimateText(value: false)
            .withBlockSpacing(value: 12)
            .withParagraphStyle(value: body)
            .withCodeBlockConfig(value: .init(theme: codeStyle.theme, backgroundColor: codeStyle.backgroundColor,
                foregroundColor: codeStyle.foregroundColor, codeTextFonts: codeFonts, chromeTextFonts: fonts(.caption1)))
            .withOrderedListStyle(value: body)
            .withBlockQuoteStyle(value: body)
            .withHeadingStyle(value: .init(h1Font: fonts(.title1), h2Font: fonts(.title2), h3Font: fonts(.title3),
                h4Font: fonts(.headline), h5Font: fonts(.subheadline), h6Font: fonts(.subheadline), textColor: .primary))
            .withTextSelectionConfig(value: .init(isEnabled: false))
            .withTextContextMenu(value: items.isEmpty ? nil : TextContextMenu(menuGroups: [
                TextContextMenuGroup(title: nil, image: nil, displayInline: true, items: items)
            ]))
    }

    @MainActor private func loadCitationIcons(_ groups: [HanlinCitationGroup]) async {
        for group in groups.prefix(24) {
            guard citationIcons[group.url.absoluteString] == nil,
                  let url = group.sources.first?.iconURL, url.scheme == "https" else { continue }
            do {
                var request = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 6)
                request.httpShouldHandleCookies = false
                let (bytes, response) = try await URLSession.shared.bytes(for: request)
                guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { continue }
                var data = Data()
                for try await byte in bytes {
                    try Task.checkCancellation()
                    guard data.count < 131_072 else { throw CocoaError(.fileReadTooLarge) }
                    data.append(byte)
                }
                guard let source = CGImageSourceCreateWithData(data as CFData, nil),
                      let icon = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                        kCGImageSourceCreateThumbnailFromImageAlways: true,
                        kCGImageSourceThumbnailMaxPixelSize: 32,
                        kCGImageSourceShouldCacheImmediately: false,
                      ] as CFDictionary), let png = UIImage(cgImage: icon).pngData() else { continue }
                citationIcons[group.url.absoluteString] = png
            } catch { if Task.isCancelled { return } }
        }
    }
}

/// The renderer retains its listener while streaming. Update callbacks without replacing
/// the native text view, so menu actions always save against the current source snapshot.
@MainActor
private final class ChatMarkdownListener: MarkdownListener {
    private var savePersonal: (@MainActor @Sendable (ChatTextQuote) -> Void)?
    private var saveKnowledge: (@MainActor @Sendable (String) -> Void)?
    private var onRendered: (@MainActor @Sendable () -> Void)?

    func update(savePersonal: (@MainActor @Sendable (ChatTextQuote) -> Void)?,
                saveKnowledge: (@MainActor @Sendable (String) -> Void)?,
                onRendered: (@MainActor @Sendable () -> Void)?) {
        self.savePersonal = savePersonal
        self.saveKnowledge = saveKnowledge
        self.onRendered = onRendered
    }
    func onRender(markdown: RenderableDocument) async {
        if markdown != .empty { onRendered?() }
    }
    func onTextSelectionAction(id: String, selection: MarkdownTextSelection) async {
        guard !selection.text.isEmpty else { return }
        if id == "hanlin.savePersonal" {
            savePersonal?(ChatTextQuote(text: selection.text, renderedText: selection.renderedText,
                range: selection.range, sourceBlockID: selection.sourceBlockID))
        } else if id == "hanlin.saveKnowledge" { saveKnowledge?(selection.text) }
    }
    func onContextMenuAppear(id: String, selectedContent: String) async {}
    func onContextMenuTap(id: String, selectedContent: String) async {}
    func onTableCopyTap(content: String) async { UIPasteboard.general.string = content }
    func onTableDownloadTap(content: String) async { UIPasteboard.general.string = content }
    func onImageTap(image: MarkdownImage) async {}
}

/// Web links use the app's existing Safari controller; other URL schemes retain system routing.
struct ChatLinkPresentation: ViewModifier {
    var citationGroups: [HanlinCitationGroup] = []
    @State private var link: URL?
    @State private var citationGroup: HanlinCitationGroup?
    @State private var citationLink: URL?

    func body(content: Content) -> some View {
        content
            .environment(\.openURL, OpenURLAction { url in
                if url.scheme == "hanlin-citation" {
                    citationGroup = citationGroups.first(where: { $0.url == url })
                    return .handled
                }
                guard Self.isWebURL(url) else { return .systemAction }
                link = url
                return .handled
            })
            .sheet(item: $link) { SafariView(url: $0).ignoresSafeArea() }
            .sheet(item: $citationGroup) { group in
                HanlinSourcesList(sources: group.sources, title: String(localized: "reference_materials")) { source in
                    if let url = source.url, Self.isWebURL(url) { citationLink = url }
                }
                .sheet(item: $citationLink) { SafariView(url: $0).ignoresSafeArea() }
            }
    }

    static func isWebURL(_ url: URL) -> Bool {
        ["https", "http"].contains(url.scheme?.lowercased() ?? "") && url.host?.isEmpty == false
    }
}
