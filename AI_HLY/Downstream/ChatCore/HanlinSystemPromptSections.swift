import Foundation

/// Keeps reusable instructions and current-turn context in distinct system
/// messages. The distinction is structural; prompt text is never parsed for
/// magic delimiters, and retrieved context keeps its original system authority.
struct HanlinSystemPromptSections: Equatable, Sendable {
    let stable: String
    let context: String

    init(stableSections: [String], contextSections: [String]) {
        stable = stableSections.filter { !$0.isEmpty }.joined(separator: "\n\n")
        context = contextSections.filter { !$0.isEmpty }.joined(separator: "\n\n")
    }

    var messageTexts: [String] { [stable, context].filter { !$0.isEmpty } }
    var rendered: String { messageTexts.joined(separator: "\n\n") }
}
