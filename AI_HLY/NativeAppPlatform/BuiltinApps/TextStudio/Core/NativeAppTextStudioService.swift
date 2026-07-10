import Foundation

struct NativeAppTextStudioService {
    func analyze(_ text: String) -> NativeAppTextStudioAnalysis {
        let words = text
            .split { !$0.isLetter && !$0.isNumber && $0 != "'" }
            .map(String.init)
        let sentences = text
            .split(whereSeparator: { ".!?".contains($0) })
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        let paragraphs = text
            .components(separatedBy: "\n\n")
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        let lines = text.components(separatedBy: .newlines)

        let links = matches(pattern: #"https?://[^\s]+"#, in: text)
        let emails = matches(pattern: #"[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}"#, in: text, options: [.caseInsensitive])
        let numbers = matches(pattern: #"[-+]?\d+(?:[.,]\d+)?"#, in: text)

        var frequency: [String: Int] = [:]
        for word in words.map({ $0.lowercased() }).filter({ $0.count > 2 }) {
            frequency[word, default: 0] += 1
        }
        let frequencyItems: [NativeAppTextStudioWordFrequency] = frequency.map { entry in
            NativeAppTextStudioWordFrequency(
                word: entry.key,
                count: entry.value
            )
        }

        let sortedWords: [NativeAppTextStudioWordFrequency] = frequencyItems.sorted { lhs, rhs in
            if lhs.count == rhs.count {
                return lhs.word < rhs.word
            }

            return lhs.count > rhs.count
        }

        let topWords: [NativeAppTextStudioWordFrequency] = Array(
            sortedWords.prefix(8)
        )

        return NativeAppTextStudioAnalysis(
            characters: text.count,
            charactersWithoutSpaces: text.filter { !$0.isWhitespace }.count,
            words: words.count,
            sentences: sentences.count,
            paragraphs: paragraphs.count,
            lines: lines.count,
            links: links,
            emails: emails,
            numbers: numbers,
            topWords: topWords
        )
    }

    func transform(_ text: String, using transform: NativeAppTextStudioTransform) -> String {
        switch transform {
        case .uppercase:
            return text.uppercased()
        case .lowercase:
            return text.lowercased()
        case .titleCase:
            return text.capitalized
        case .sentenceCase:
            guard let first = text.first else { return text }
            return first.uppercased() + text.dropFirst().lowercased()
        case .trimWhitespace:
            return text
                .components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        case .sortLines:
            return text.components(separatedBy: .newlines).sorted().joined(separator: "\n")
        case .reverseLines:
            return text.components(separatedBy: .newlines).reversed().joined(separator: "\n")
        }
    }

    private func matches(
        pattern: String,
        in text: String,
        options: NSRegularExpression.Options = []
    ) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else { return [] }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.matches(in: text, range: range).compactMap { match in
            guard let swiftRange = Range(match.range, in: text) else { return nil }
            return String(text[swiftRange])
        }
    }
}
