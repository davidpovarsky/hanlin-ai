#if HANLIN_A2UI_POC
import HanlinPlatformContracts
import SwiftUI

/// All ordered model parts share the same native selection document. Every
/// embedded Surface retains its existing SDK owner inline and expanded.
@MainActor
struct HanlinChatContentView: View {
    let projection: HanlinChatContentProjection
    var savePersonal: (@MainActor @Sendable (ChatTextQuote) -> Void)?
    var saveKnowledge: (@MainActor @Sendable (String) -> Void)?

    var body: some View {
        HanlinInlineMessageDocument(parts: projection.parts.map(documentPart),
            messageText: projection.plainText, savePersonal: savePersonal, saveKnowledge: saveKnowledge)
    }

    private func documentPart(_ part: HanlinChatContentProjection.Part) -> HanlinInlineMessageDocument.Part {
        let id = part.id.uuidString
        switch part.content {
        case .markdown(let text):
            return .init(id: id, content: .markdown(text: text, sourcePrefix: "hanlin-part:\(id):"))
        case .surface, .unavailable:
            return .init(id: id, content: .embedded { AnyView(embeddedPart(part)) })
        }
    }

    @ViewBuilder
    private func embeddedPart(_ part: HanlinChatContentProjection.Part) -> some View {
        if case .surface = part.content, let surface = projection.surface(for: part) {
            ChatEmbeddedResultHost(
                expansions: [.init(mode: .sheet), .init(mode: .fullScreen)],
                containerStyle: .neutral,
                onLaunchRequest: Optional<((NativeAppLaunchRequest) -> Void)>.none
            ) {
                HanlinA2UIProjectedResultView(projection: surface)
            } expandedContent: {
                HanlinA2UIProjectedResultView(projection: surface)
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("hanlin-a2ui-model-part-\(part.id.uuidString)")
        } else {
            ContentUnavailableView("Content unavailable", systemImage: "rectangle.slash",
                description: Text("This content could not be displayed."))
                .accessibilityIdentifier("hanlin-a2ui-model-fallback")
        }
    }
}
#endif
