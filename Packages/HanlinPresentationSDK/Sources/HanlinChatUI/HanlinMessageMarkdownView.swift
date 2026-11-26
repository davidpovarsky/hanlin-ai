#if canImport(UIKit)
import SwiftUI
import UIKit
import SwiftStreamingMarkdown
import HanlinPresentationKit

/// Hanlin's original document interaction stack. Hosts supply source-scoped
/// callbacks, citation projection and navigation; selection, code previews and
/// long-press routing remain the same implementation in every consumer.
@MainActor
public struct HanlinMessageMarkdownView: View {
    private let text: String
    private let imageConfig: ImageConfig
    private let citationGroups: [HanlinCitationGroup]
    private let contextMenuItems: [TextContextMenuItem]
    private let documentParts: [MarkdownDocumentPart]?
    private let embeddedBlockRenderer: MarkdownEmbeddedBlockRenderer?
    private let onRendered: (@MainActor @Sendable () -> Void)?
    private let onSelectionAction: (@MainActor @Sendable (String, MarkdownTextSelection) -> Void)?
    private let onSelectionActivity: (@MainActor @Sendable (UUID, Bool) -> Void)?
    private let onSelectionChanged: (@MainActor (MarkdownTextSelection) -> Void)?
    private let onTrace: HanlinPresentationTraceHandler?
    private let highlight: MarkdownSelectionHighlight?
    private let documentSelectionMode: Bool
    private let selectAllRequest: Binding<Bool>?
    @Environment(\.chatMessageLongPressPreview) private var messagePreview

    public init(text: String, imageConfig: ImageConfig = .disabled,
                citationGroups: [HanlinCitationGroup] = [],
                contextMenuItems: [TextContextMenuItem] = [],
                documentParts: [MarkdownDocumentPart]? = nil,
                embeddedBlockRenderer: MarkdownEmbeddedBlockRenderer? = nil,
                onRendered: (@MainActor @Sendable () -> Void)? = nil,
                onSelectionAction: (@MainActor @Sendable (String, MarkdownTextSelection) -> Void)? = nil,
                onSelectionActivity: (@MainActor @Sendable (UUID, Bool) -> Void)? = nil,
                onSelectionChanged: (@MainActor (MarkdownTextSelection) -> Void)? = nil,
                onTrace: HanlinPresentationTraceHandler? = nil,
                highlight: MarkdownSelectionHighlight? = nil,
                documentSelectionMode: Bool = false,
                selectAllRequest: Binding<Bool>? = nil) {
        self.text = text; self.imageConfig = imageConfig
        self.citationGroups = citationGroups; self.contextMenuItems = contextMenuItems
        self.documentParts = documentParts; self.embeddedBlockRenderer = embeddedBlockRenderer
        self.onRendered = onRendered; self.onSelectionAction = onSelectionAction
        self.onSelectionActivity = onSelectionActivity; self.onSelectionChanged = onSelectionChanged
        self.onTrace = onTrace; self.highlight = highlight
        self.documentSelectionMode = documentSelectionMode; self.selectAllRequest = selectAllRequest
    }

    public var body: some View {
        highlightedRenderer
            .markdownDocumentSelectionMode(documentSelectionMode)
            .markdownSelectAllRequest(selectAllRequest)
            .markdownSelectionChanged { selection in onSelectionChanged?(selection) }
            .markdownLongPressPreview(documentSelectionMode ? nil : messagePreview)
            .markdownEmbeddedBlockRenderer(embeddedBlockRenderer)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var highlightedRenderer: some View {
        HanlinMarkdownView(text: text, imageConfig: imageConfig,
                           citationGroups: citationGroups, contextMenuItems: contextMenuItems,
                           onRendered: onRendered, onSelectionAction: onSelectionAction,
                           documentParts: documentParts)
            .markdownCodeBlockRenderer(codeBlockRenderer)
            .markdownSelectionHighlight(highlight)
            .markdownSelectionActivity { id, active in onSelectionActivity?(id, active) }
    }

    private var codeBlockRenderer: MarkdownCodeBlockRenderer {
        let onTrace = onTrace
        return { block in
            guard block.isFenceClosed == true else { return nil }
            let language = block.language?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let kind: String
            switch language {
            case "mermaid": kind = "mermaid"
            case "diff", "patch": kind = "diff"
            default: return nil
            }
            return AnyView(ChatCodeFenceView(blockID: block.id, kind: kind,
                                            source: block.code, onTrace: onTrace))
        }
    }
}
#endif
