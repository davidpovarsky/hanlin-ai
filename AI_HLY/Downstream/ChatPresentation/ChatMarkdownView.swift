import SwiftUI
import SwiftStreamingMarkdown
import UIKit

/// The shared renderer inside the original message bubble and translated/transcript text.
struct ChatMarkdownView: View {
    let text: String
    var savePersonal: (@MainActor @Sendable (ChatTextQuote) -> Void)?
    var saveKnowledge: (@MainActor @Sendable (String) -> Void)?
    var onRendered: (@MainActor @Sendable () -> Void)?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.chatExcerptSource) private var source
    @Environment(\.chatSourceDestination) private var destination
    @Environment(\.chatMarkdownSelectionActivity) private var selectionActivity
    @Environment(\.chatMarkdownDidRender) private var markdownDidRender
    @State private var highlightedRequestID: UUID?
    @State private var listener = ChatMarkdownListener()

    var body: some View {
        let _ = dynamicTypeSize
        let _ = listener.update(savePersonal: savePersonal, saveKnowledge: saveKnowledge, onRendered: {
            onRendered?()
            if let messageID = source?.messageID { markdownDidRender?(messageID) }
        })
        MarkdownView(text: text, config: config, listener: listener)
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
              destination.sourceDigest == ChatSavedExcerpt.digest(text),
              let selection = destination.selection, let blockID = selection.sourceBlockID else { return nil }
        return MarkdownSelectionHighlight(sourceBlockID: blockID, renderedText: selection.renderedText, range: selection.range)
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
        return MarkdownRenderConfig.default
            .withShouldAnimateText(value: false)
            .withBlockSpacing(value: 12)
            .withParagraphStyle(value: body)
            .withCodeBlockConfig(value: .init(theme: codeStyle.theme, backgroundColor: codeStyle.backgroundColor,
                foregroundColor: codeStyle.foregroundColor, codeTextFonts: codeFonts, chromeTextFonts: fonts(.caption)))
            .withOrderedListStyle(value: body)
            .withBlockQuoteStyle(value: body)
            .withHeadingStyle(value: .init(h1Font: fonts(.title1), h2Font: fonts(.title2), h3Font: fonts(.title3),
                h4Font: fonts(.headline), h5Font: fonts(.subheadline), h6Font: fonts(.subheadline), textColor: .primary))
            .withTextSelectionConfig(value: .init(isEnabled: false))
            .withTextContextMenu(value: items.isEmpty ? nil : TextContextMenu(menuGroups: [
                TextContextMenuGroup(title: nil, image: nil, displayInline: true, items: items)
            ]))
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
    @State private var link: URL?

    func body(content: Content) -> some View {
        content
            .environment(\.openURL, OpenURLAction { url in
                guard Self.isWebURL(url) else { return .systemAction }
                link = url
                return .handled
            })
            .sheet(item: $link) { SafariView(url: $0).ignoresSafeArea() }
    }

    static func isWebURL(_ url: URL) -> Bool {
        ["https", "http"].contains(url.scheme?.lowercased() ?? "") && url.host?.isEmpty == false
    }
}
