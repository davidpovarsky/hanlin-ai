#if canImport(UIKit)
import SwiftUI
import UIKit
import SwiftStreamingMarkdown
import HanlinPresentationKit

/// The original Hanlin paragraph, code, LaTeX, media and selection renderer.
/// Host persistence/navigation stays in callbacks and the original renderer's
/// environment modifiers. This does not introduce another Markdown parser.
@MainActor
public struct HanlinMarkdownView: View {
    public let text: String
    private let imageConfig: ImageConfig
    private let documentParts: [MarkdownDocumentPart]?
    private let citationGroups: [HanlinCitationGroup]
    private let contextMenuItems: [TextContextMenuItem]
    private let onRendered: (@MainActor @Sendable () -> Void)?
    private let onSelectionAction: (@MainActor @Sendable (String, MarkdownTextSelection) -> Void)?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.layoutDirection) private var layoutDirection
    @Environment(\.hanlinMarkdownConfigurationTransform) private var configurationTransform
    @State private var listener = HanlinMarkdownListener()
    @State private var citationIcons: [URL: Data] = [:]

    public init(text: String, imageConfig: ImageConfig = .disabled,
                citationGroups: [HanlinCitationGroup] = [],
                contextMenuItems: [TextContextMenuItem] = [],
                onRendered: (@MainActor @Sendable () -> Void)? = nil,
                onSelectionAction: (@MainActor @Sendable (String, MarkdownTextSelection) -> Void)? = nil,
                documentParts: [MarkdownDocumentPart]? = nil) {
        self.text = text; self.imageConfig = imageConfig
        self.documentParts = documentParts
        self.citationGroups = citationGroups; self.contextMenuItems = contextMenuItems
        self.onRendered = onRendered; self.onSelectionAction = onSelectionAction
    }

    public var body: some View {
        let _ = dynamicTypeSize
        let _ = listener.update(onSelectionAction: onSelectionAction, onRendered: onRendered)
        MarkdownView(text: text, config: config, listener: listener, documentParts: documentParts)
            // A growing sentence or a new part changes its scoped link, not
            // the source icon. Do not cancel/restart downloads for each delta.
            .task(id: citationIconURLs) { await loadCitationIcons() }
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
        let original = MarkdownRenderConfig.default
            .withCitationConfig(value: .init(font: HanlinTypography.uiFont(.caption1),
                textColor: .secondary, backgroundColor: Color.secondary.opacity(0.10),
                iconsByCitationURL: iconsByCitationURL, iconOnTrailingEdge: layoutDirection == .rightToLeft))
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
        return configurationTransform(original)
    }

    private var citationIconURLs: [URL] {
        var seen = Set<URL>()
        return Array(citationGroups.compactMap { $0.sources.first?.iconURL }
            .filter { $0.scheme == "https" && seen.insert($0).inserted }.prefix(24))
    }

    private var iconsByCitationURL: [String: Data] {
        var result: [String: Data] = [:]
        for group in citationGroups {
            if let url = group.sources.first?.iconURL, let data = citationIcons[url] {
                result[group.url.absoluteString] = data
            }
        }
        return result
    }

    private func loadCitationIcons() async {
        let visibleKeys = Set(citationIconURLs)
        var loaded = citationIcons.filter { visibleKeys.contains($0.key) }
        let missing = citationIconURLs.filter { loaded[$0] == nil }
        // Each thumbnail already has a byte/decode/time bound. Fetch distinct
        // sites together so one slow favicon cannot block all following sites.
        await withTaskGroup(of: (URL, Data?).self) { group in
            for url in missing {
                group.addTask { (url, try? await HanlinIconThumbnailLoader.png(from: url)) }
            }
            for await (url, data) in group {
                if let data { loaded[url] = data }
            }
        }
        // One publication per source batch. Each icon must not rebuild the full
        // Markdown layout while the answer is being streamed.
        guard !Task.isCancelled, loaded != citationIcons else { return }
        citationIcons = loaded
    }
}


private struct HanlinMarkdownConfigurationKey: EnvironmentKey {
    static let defaultValue: @MainActor @Sendable (MarkdownRenderConfig) -> MarkdownRenderConfig = { $0 }
}

private extension EnvironmentValues {
    var hanlinMarkdownConfigurationTransform: @MainActor @Sendable (MarkdownRenderConfig) -> MarkdownRenderConfig {
        get { self[HanlinMarkdownConfigurationKey.self] }
        set { self[HanlinMarkdownConfigurationKey.self] = newValue }
    }
}

public extension View {
    /// Customizes the original renderer's complete configuration after Hanlin
    /// installs its original fonts, citations, media and selection callbacks.
    /// The identity transform is the default; the parser and view stay shared.
    func hanlinMarkdownConfiguration(
        _ transform: @escaping @MainActor @Sendable (MarkdownRenderConfig) -> MarkdownRenderConfig
    ) -> some View {
        environment(\.hanlinMarkdownConfigurationTransform, transform)
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
