import Foundation

enum NativeAppWikipediaLanguage: String, CaseIterable, Codable, Identifiable {
    case english = "en"
    case hebrew = "he"
    case french = "fr"
    case german = "de"
    case spanish = "es"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .english: return "English"
        case .hebrew: return "עברית"
        case .french: return "Français"
        case .german: return "Deutsch"
        case .spanish: return "Español"
        }
    }
}

struct NativeAppWikipediaSearchResult: Identifiable, Hashable, Codable {
    var id: String { "\(languageCode):\(title)" }
    let title: String
    let description: String
    let url: URL?
    let languageCode: String
}

struct NativeAppWikipediaSummary: Identifiable, Hashable, Codable {
    var id: String { "\(languageCode):\(title)" }
    let title: String
    let extract: String
    let description: String?
    let url: URL?
    let thumbnailURL: URL?
    let languageCode: String
}
