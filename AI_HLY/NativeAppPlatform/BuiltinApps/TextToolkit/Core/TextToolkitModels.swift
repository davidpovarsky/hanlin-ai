import Foundation

struct TextToolkitAnalysis: Hashable, Codable {
    let characters: Int
    let words: Int
    let sentences: Int
    let lines: Int
    let links: [String]
}

enum TextToolkitTransform: String, Codable, CaseIterable, Hashable {
    case uppercase
    case lowercase
    case titleCase
    case trimLines
    case removeExtraSpaces

    var title: String {
        switch self {
        case .uppercase: return "UPPERCASE"
        case .lowercase: return "lowercase"
        case .titleCase: return "Title Case"
        case .trimLines: return "Trim Lines"
        case .removeExtraSpaces: return "Remove Extra Spaces"
        }
    }
}
