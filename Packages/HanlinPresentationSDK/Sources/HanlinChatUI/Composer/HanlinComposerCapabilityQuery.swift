import Foundation

/// A transient @ or / query at the native insertion point. This is not a tool
/// identity: selecting a result creates a typed attachment in the draft.
public struct HanlinComposerCapabilityQuery: Equatable, Sendable {
    public enum Trigger: String, Sendable { case mention = "@", command = "/" }
    public let trigger: Trigger
    public let query: String
    public let range: NSRange
    private let originalToken: String

    public static func parse(
        text: String,
        selection: NSRange,
        hasMarkedText: Bool = false
    ) -> Self? {
        guard !hasMarkedText, selection.length == 0, selection.location != NSNotFound,
              selection.location >= 0, selection.location <= text.utf16.count,
              let prefixRange = Range(NSRange(location: 0, length: selection.location), in: text)
        else { return nil }
        let caret = prefixRange.upperBound
        let prefix = text[..<caret]
        let start = prefix.lastIndex(where: \.isWhitespace).map { text.index(after: $0) }
            ?? text.startIndex
        let tokenPrefix = text[start..<caret]
        guard let first = tokenPrefix.first, let trigger = Trigger(rawValue: String(first))
        else { return nil }
        let end = text[caret...].firstIndex(where: \.isWhitespace) ?? text.endIndex
        return Self(trigger: trigger, query: String(tokenPrefix.dropFirst()),
                    range: NSRange(start..<end, in: text), originalToken: String(text[start..<end]))
    }

    /// Returns nil if the document changed while the user chose a result.
    public func replacingToken(in text: String, with replacement: String = "") -> String? {
        guard let tokenRange = Range(range, in: text),
              text[tokenRange].utf8.elementsEqual(originalToken.utf8) else { return nil }
        var result = text
        result.replaceSubrange(tokenRange, with: replacement)
        return result
    }

    public func selectionAfterReplacing(with replacement: String = "") -> NSRange {
        NSRange(location: range.location + replacement.utf16.count, length: 0)
    }
}
