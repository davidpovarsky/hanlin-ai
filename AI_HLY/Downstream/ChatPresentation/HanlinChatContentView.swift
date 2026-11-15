#if HANLIN_A2UI_POC
import HanlinPlatformContracts
import SwiftUI

/// Ordered siblings in the existing assistant bubble. Every Surface uses the same official
/// SDK owner inline and expanded; looking up or expanding never replays a frame.
@MainActor
struct HanlinChatContentView: View {
    let projection: HanlinChatContentProjection
    var savePersonal: (@MainActor @Sendable (ChatTextQuote) -> Void)?
    var saveKnowledge: (@MainActor @Sendable (String) -> Void)?

    var body: some View {
        ForEach(projection.parts) { part in
            switch part.content {
            case .markdown(let text):
                ChatMarkdownView(text: text, selectionPartID: part.id, messageText: projection.plainText,
                    savePersonal: savePersonal, saveKnowledge: saveKnowledge)
            case .surface:
                if let surface = projection.surface(for: part) {
                    ChatEmbeddedResultHost(
                        expansions: [.init(mode: .sheet), .init(mode: .fullScreen)],
                        containerStyle: .neutral,
                        onLaunchRequest: Optional<((NativeAppLaunchRequest) -> Void)>.none
                    ) {
                        HanlinA2UIProjectedResultView(projection: surface)
                    } expandedContent: {
                        HanlinA2UIProjectedResultView(projection: surface)
                    }
                    .accessibilityIdentifier("hanlin-a2ui-model-part-\(part.id.uuidString)")
                } else {
                    ContentUnavailableView("Content unavailable", systemImage: "rectangle.slash",
                        description: Text("This content could not be displayed."))
                        .accessibilityIdentifier("hanlin-a2ui-model-fallback")
                }
            }
        }
    }
}
#endif
