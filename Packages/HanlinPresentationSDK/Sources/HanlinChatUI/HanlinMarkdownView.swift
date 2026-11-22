#if canImport(UIKit)
import SwiftUI
import UIKit
import ImageIO
import UniformTypeIdentifiers
import SwiftStreamingMarkdown
import HanlinPresentationKit

/// The original Hanlin paragraph, code, LaTeX, media and selection renderer.
/// Host persistence/navigation stays in callbacks and the original renderer's
/// environment modifiers. This does not introduce another Markdown parser.
@MainActor
public struct HanlinMarkdownView: View {
    public let text: String
    private let imageConfig: ImageConfig
    private let citationGroups: [HanlinCitationGroup]
    private let contextMenuItems: [TextContextMenuItem]
    private let onRendered: (@MainActor @Sendable () -> Void)?
    private let onSelectionAction: (@MainActor @Sendable (String, MarkdownTextSelection) -> Void)?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.layoutDirection) private var layoutDirection
    @State private var listener = HanlinMarkdownListener()
    @State private var citationIcons: [String: Data] = [:]

    public init(text: String, imageConfig: ImageConfig = .disabled,
                citationGroups: [HanlinCitationGroup] = [],
                contextMenuItems: [TextContextMenuItem] = [],
                onRendered: (@MainActor @Sendable () -> Void)? = nil,
                onSelectionAction: (@MainActor @Sendable (String, MarkdownTextSelection) -> Void)? = nil) {
        self.text = text; self.imageConfig = imageConfig
        self.citationGroups = citationGroups; self.contextMenuItems = contextMenuItems
        self.onRendered = onRendered; self.onSelectionAction = onSelectionAction
    }

    public var body: some View {
        let _ = dynamicTypeSize
        let _ = listener.update(onSelectionAction: onSelectionAction, onRendered: onRendered)
        MarkdownView(text: text, config: config, listener: listener)
            .task(id: citationGroups.map(\.url)) { await loadCitationIcons() }
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var config: MarkdownRenderConfig {
        func fonts(_ style: UIFont.TextStyle) -> TextFonts {
            let normal = HanlinTypography.uiFont(style)
            func variant(_ traits: UIFontDescriptor.SymbolicTraits) -> UIFont? {
                normal.fontDescriptor.withSymbolicTraits(traits).map { UIFont(descriptor: $0, size: 0) }
            }
            return TextFonts(normal: normal, italic: variant(.traitItalic), bold: variant(.traitBold),
                boldItalic: variant([.traitBold, .traitItalic]), preferredLetterSpacing: nil, preferredLineHeight: nil)
        }
        let body = MarkdownRenderConfig.MarkdownTextStyle(textFonts: fonts(.body), textColor: .primary)
        let codeStyle = CodeBlockConfig.default
        let codeFonts = TextFonts(normal: UIFont.monospacedSystemFont(ofSize: HanlinTypography.uiFont(.callout).pointSize, weight: .regular),
            italic: nil, bold: nil, boldItalic: nil, preferredLetterSpacing: nil, preferredLineHeight: nil)
        return MarkdownRenderConfig.default
            .withCitationConfig(value: .init(font: HanlinTypography.uiFont(.caption2),
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
            .withTextSelectionConfig(value: .init(isEnabled: false, continuousSelection: true))
            .withTextContextMenu(value: contextMenuItems.isEmpty ? nil : TextContextMenu(menuGroups: [
                TextContextMenuGroup(title: nil, image: nil, displayInline: true, items: contextMenuItems)
            ]))
    }

    private func loadCitationIcons() async {
        let groups = Array(citationGroups.prefix(24))
        let visibleKeys = Set(groups.map { $0.url.absoluteString })
        var loaded = citationIcons.filter { visibleKeys.contains($0.key) }
        for group in groups {
            guard loaded[group.url.absoluteString] == nil,
                  let url = group.sources.first?.iconURL, url.scheme == "https" else { continue }
            do {
                if let png = try await HanlinCitationIconLoader.png(from: url) {
                    try Task.checkCancellation()
                    loaded[group.url.absoluteString] = png
                }
            } catch { if Task.isCancelled { return } }
        }
        // One publication per source batch. Each icon must not rebuild the full
        // Markdown layout while the answer is being streamed.
        guard !Task.isCancelled, loaded != citationIcons else { return }
        citationIcons = loaded
    }
}

/// Decode the bounded thumbnail away from the main actor. No icon carries tool
/// authority, and only the caller's existing, scoped source URLs are consulted.
private enum HanlinCitationIconLoader {
    static func png(from url: URL) async throws -> Data? {
        var request = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 6)
        request.httpShouldHandleCookies = false
        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200,
              response.url?.scheme == "https" else { return nil }
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
              ] as CFDictionary) else { return nil }
        let png = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(png, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, icon, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return png as Data
    }
}

/// The renderer retains its listener while streaming. Update callbacks without replacing
/// the native text view, so menu actions always save against the current source snapshot.
@MainActor
private final class HanlinMarkdownListener: MarkdownListener {
    private var onSelectionAction: (@MainActor @Sendable (String, MarkdownTextSelection) -> Void)?
    private var onRendered: (@MainActor @Sendable () -> Void)?

    func update(onSelectionAction: (@MainActor @Sendable (String, MarkdownTextSelection) -> Void)?,
                onRendered: (@MainActor @Sendable () -> Void)?) {
        self.onSelectionAction = onSelectionAction
        self.onRendered = onRendered
    }
    func onRender(markdown: RenderableDocument) async {
        if markdown != .empty { onRendered?() }
    }
    func onTextSelectionAction(id: String, selection: MarkdownTextSelection) async {
        guard !selection.text.isEmpty else { return }
        onSelectionAction?(id, selection)
    }

    func onContextMenuAppear(id: String, selectedContent: String) async {}
    func onContextMenuTap(id: String, selectedContent: String) async {}
    func onTableCopyTap(content: String) async { UIPasteboard.general.string = content }
    func onTableDownloadTap(content: String) async { UIPasteboard.general.string = content }
    func onImageTap(image: MarkdownImage) async {}
}


#endif
