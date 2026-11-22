import SwiftUI
import SwiftStreamingMarkdown
import UIKit
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
    var documentSelectionMode = false
    var onSelectionChanged: (@MainActor (ChatTextQuote) -> Void)?
    var selectAllRequest: Binding<Bool>?
    @Environment(\.hanlinMessageCitations) private var citations
    @Environment(\.chatExcerptSource) private var source
    @Environment(\.chatSourceDestination) private var destination
    @Environment(\.chatMarkdownSelectionActivity) private var selectionActivity
    @Environment(\.chatMarkdownDidRender) private var markdownDidRender
    @Environment(\.chatMessageLongPressPreview) private var messagePreview
    @State private var highlightedRequestID: UUID?

    var body: some View {
        let citationProjection = citations?.projection(for: text)
        HanlinMarkdownView(text: citationProjection?.markdown ?? text,
            imageConfig: imageConfig, citationGroups: citationProjection?.groups ?? [],
            contextMenuItems: contextMenuItems,
            onRendered: {
                onRendered?()
                if let messageID = source?.messageID { markdownDidRender?(messageID) }
            }, onSelectionAction: { id, selection in
                if id == "hanlin.savePersonal" {
                    scopedSavePersonal?(ChatTextQuote(text: selection.text, renderedText: selection.renderedText,
                        range: selection.range, sourceBlockID: selection.sourceBlockID))
                } else if id == "hanlin.saveKnowledge" { saveKnowledge?(selection.text) }
            })
            // The native paragraph retains its OpenURLAction. Keep its presenter
            // with the renderer rather than an independently updating bubble.
            .modifier(ChatLinkPresentation(citationGroups: citationProjection?.groups ?? []))
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
            .markdownDocumentSelectionMode(documentSelectionMode)
            .markdownSelectAllRequest(selectAllRequest)
            .markdownSelectionChanged { selection in
                onSelectionChanged?(ChatTextQuote(text: selection.text, renderedText: selection.renderedText,
                    range: selection.range, sourceBlockID: selection.sourceBlockID))
            }
            .markdownLongPressPreview(documentSelectionMode ? nil : messagePreview)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var highlight: MarkdownSelectionHighlight? {
        guard let destination, highlightedRequestID == destination.id, destination.messageID == source?.messageID,
              destination.sourceDigest == ChatSavedExcerpt.digest(messageText ?? text),
              let selection = destination.selection, let storedBlockID = selection.sourceBlockID else { return nil }
        let blockID: String
        let messagePrefix = "hanlin-message:"
        if storedBlockID.hasPrefix(messagePrefix) {
            // Whole-document quotes have their own coordinate space. Reopen
            // that exact surface instead of guessing which model part matched.
            guard documentSelectionMode else { return nil }
            blockID = String(storedBlockID.dropFirst(messagePrefix.count))
        } else if let selectionPartID {
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
        if documentSelectionMode {
            return { quote in
                savePersonal(ChatTextQuote(text: quote.text, renderedText: quote.renderedText, range: quote.range,
                    sourceBlockID: quote.sourceBlockID.map { "hanlin-message:\($0)" }))
            }
        }
        guard let selectionPartID else { return savePersonal }
        return { quote in
            savePersonal(ChatTextQuote(text: quote.text, renderedText: quote.renderedText, range: quote.range,
                sourceBlockID: quote.sourceBlockID.map { "hanlin-part:\(selectionPartID.uuidString):\($0)" }))
        }
    }

    private var contextMenuItems: [TextContextMenuItem] {
        var items: [TextContextMenuItem] = []
        if savePersonal != nil { items.append(TextContextMenuItem(id: "hanlin.savePersonal", title: String(localized: "Save for myself"), image: UIImage(systemName: "bookmark"))) }
        if saveKnowledge != nil { items.append(TextContextMenuItem(id: "hanlin.saveKnowledge", title: String(localized: "Save to knowledge"), image: UIImage(systemName: "backpack"))) }
        return items
    }

    private var imageConfig: ImageConfig {
        #if HANLIN_A2UI_POC
        return ImageConfig(enabled: true,
            allowedImageTypes: [.remote(allowedDomains: [])], fullscreenViewerEnabled: true)
        #else
        return .disabled
        #endif
    }
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
