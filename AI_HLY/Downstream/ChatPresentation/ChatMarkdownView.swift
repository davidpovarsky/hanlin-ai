import SwiftUI
import Textual

/// One renderer inside the original chat bubble, also used for translated/transcript text.
/// Textual owns Markdown parsing, inline/block math, streaming layout and native selection.
struct ChatMarkdownView: View {
    let text: String
    var savePersonal: (@MainActor @Sendable (String) -> Void)?
    var saveKnowledge: (@MainActor @Sendable (String) -> Void)?

    var body: some View {
        StructuredText(markdown: text, syntaxExtensions: [.math])
            .textual.textSelection(.enabled)
            .textual.textSelectionActions(selectionActions)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var selectionActions: [TextSelectionAction] {
        var actions: [TextSelectionAction] = []
        if let savePersonal {
            actions.append(TextSelectionAction(title: String(localized: "Save for myself"), systemImage: "bookmark", handler: savePersonal))
        }
        if let saveKnowledge {
            actions.append(TextSelectionAction(title: String(localized: "Save to knowledge"), systemImage: "backpack", handler: saveKnowledge))
        }
        return actions
    }
}

/// Web links use the app's existing Safari controller; other URL schemes retain system routing.
struct ChatLinkPresentation: ViewModifier {
    @State private var link: URL?

    func body(content: Content) -> some View {
        content
            .environment(\.openURL, OpenURLAction { url in
                guard ["https", "http"].contains(url.scheme?.lowercased() ?? "") else { return .systemAction }
                link = url
                return .handled
            })
            .sheet(item: $link) { SafariView(url: $0).ignoresSafeArea() }
    }
}
