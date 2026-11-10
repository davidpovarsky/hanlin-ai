import SwiftUI
import UIKit

struct AgentTranscriptTextView: View {
    let text: String
    let usesMathRenderer: Bool

    var body: some View {
        ChatMarkdownView(text: text)
        .modifier(ChatLinkPresentation())
        .frame(maxWidth: .infinity, alignment: .leading)
        .textSelection(.enabled)
        .contextMenu {
            Button {
                UIPasteboard.general.string = markdownToPlainText(text)
            } label: {
                Label(String(localized: "Copy Content"), systemImage: "square.on.square")
            }
        }
    }
}
