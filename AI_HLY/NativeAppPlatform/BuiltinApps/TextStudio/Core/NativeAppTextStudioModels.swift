import Foundation

enum NativeAppTextStudioTransform: String, CaseIterable, Codable, Identifiable {
    case uppercase
    case lowercase
    case titleCase
    case sentenceCase
    case trimWhitespace
    case sortLines
    case reverseLines

    var id: String { rawValue }

    var title: String {
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

struct NativeAppTextStudioWordFrequency: Identifiable, Hashable, Codable {
    var id: String { word }
    let word: String
    let count: Int
}

struct NativeAppTextStudioAnalysis: Hashable, Codable {
    let characters: Int
    let charactersWithoutSpaces: Int
    let words: Int
    let sentences: Int
    let paragraphs: Int
    let lines: Int
    let links: [String]
    let emails: [String]
    let numbers: [String]
    let topWords: [NativeAppTextStudioWordFrequency]
}

struct NativeAppTextStudioHistoryItem: Identifiable, Hashable, Codable {
    let id: UUID
    let createdAt: Date
    let operation: String
    let input: String
    let output: String

    init(operation: String, input: String, output: String) {
        self.id = UUID()
        self.createdAt = Date()
        self.operation = operation
        self.input = input
        self.output = output
    }
}
