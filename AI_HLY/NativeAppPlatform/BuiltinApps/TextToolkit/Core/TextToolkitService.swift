import Foundation

struct TextToolkitService {
    func analyze(_ text: String) -> TextToolkitAnalysis {
        let words = text.components(separatedBy: CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters)).filter { !$0.isEmpty }
        let sentences = text.components(separatedBy: CharacterSet(charactersIn: ".!?״؟。")) .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        let lines = text.components(separatedBy: .newlines)
        let links = extractLinks(from: text)
        return TextToolkitAnalysis(
            characters: text.count,
            words: words.count,
            sentences: sentences.count,
            lines: max(text.isEmpty ? 0 : 1, lines.count),
            links: links
        )
    }

    func transform(_ text: String, transform: TextToolkitTransform) -> String {
        switch transform {
        case .uppercase:
            return text.uppercased()
        case .lowercase:
            return text.lowercased()
        case .titleCase:
            return text.capitalized
        case .trimLines:
            return text.components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .joined(separator: "\n")
        case .removeExtraSpaces:
            return text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    private func extractLinks(from text: String) -> [String] {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return [] }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return detector.matches(in: text, range: range).compactMap { $0.url?.absoluteString }
    }
}
