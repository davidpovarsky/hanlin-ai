import HanlinChatUI
import SwiftUI
import UIKit

// The original native preview/presentation lives in the shared product.
// This adapter only supplies Hanlin's host-specific Markdown/citation context.
typealias ChatMessagePreviewPresenter = HanlinMessagePreviewPresenter

extension HanlinMessagePreviewPresenter {
    static func present(from source: UIView, at point: CGPoint, preferredWidth: CGFloat,
                        text: String, citations: HanlinMessageCitations?, style: Style, actions: [Action]) {
        present(from: source, at: point, preferredWidth: preferredWidth,
                style: style, actions: actions) {
            ChatMarkdownView(text: text)
                .environment(\.hanlinMessageCitations, citations)
        }
    }
}
