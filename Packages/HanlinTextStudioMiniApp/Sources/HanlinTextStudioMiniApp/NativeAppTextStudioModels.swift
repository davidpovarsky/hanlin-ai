import Foundation

public enum NativeAppTextStudioTransform: String, CaseIterable, Codable, Identifiable, Sendable {
    case uppercase
    case lowercase
    case titleCase
    case sentenceCase
    case trimWhitespace
    case sortLines
    case reverseLines

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .uppercase: return "UPPERCASE"
        case .lowercase: return "lowercase"
        case .titleCase: return "Title Case"
        case .sentenceCase: return "Sentence case"
        case .trimWhitespace: return "Trim Whitespace"
        case .sortLines: return "Sort Lines"
        case .reverseLines: return "Reverse Lines"
        }
    }
}

public struct NativeAppTextStudioWordFrequency: Identifiable, Hashable, Codable, Sendable {
    public var id: String { word }
    public let word: String
    public let count: Int

    public init(word: String, count: Int) {
        self.word = word
        self.count = count
    }
}

public struct NativeAppTextStudioAnalysis: Hashable, Codable, Sendable {
    public let characters: Int
    public let charactersWithoutSpaces: Int
    public let words: Int
    public let sentences: Int
    public let paragraphs: Int
    public let lines: Int
    public let links: [String]
    public let emails: [String]
    public let numbers: [String]
    public let topWords: [NativeAppTextStudioWordFrequency]

    public init(
        characters: Int,
        charactersWithoutSpaces: Int,
        words: Int,
        sentences: Int,
        paragraphs: Int,
        lines: Int,
        links: [String],
        emails: [String],
        numbers: [String],
        topWords: [NativeAppTextStudioWordFrequency]
    ) {
        self.characters = characters
        self.charactersWithoutSpaces = charactersWithoutSpaces
        self.words = words
        self.sentences = sentences
        self.paragraphs = paragraphs
        self.lines = lines
        self.links = links
        self.emails = emails
        self.numbers = numbers
        self.topWords = topWords
    }
}

public struct NativeAppTextStudioHistoryItem: Identifiable, Hashable, Codable, Sendable {
    public let id: UUID
    public let createdAt: Date
    public let operation: String
    public let input: String
    public let output: String

    public init(operation: String, input: String, output: String) {
        self.id = UUID()
        self.createdAt = Date()
        self.operation = operation
        self.input = input
        self.output = output
    }
}
