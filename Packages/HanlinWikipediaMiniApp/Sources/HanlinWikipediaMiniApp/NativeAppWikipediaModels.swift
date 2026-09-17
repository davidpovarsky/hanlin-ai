import Foundation

public enum NativeAppWikipediaLanguage: String, CaseIterable, Codable, Identifiable, Sendable {
    case english = "en"
    case hebrew = "he"
    case french = "fr"
    case german = "de"
    case spanish = "es"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .english: return "English"
        case .hebrew: return "עברית"
        case .french: return "Français"
        case .german: return "Deutsch"
        case .spanish: return "Español"
        }
    }
}

public struct NativeAppWikipediaSearchResult: Identifiable, Hashable, Codable, Sendable {
    public var id: String { "\(languageCode):\(title)" }
    public let title: String
    public let description: String
    public let url: URL?
    public let languageCode: String

    public init(title: String, description: String, url: URL?, languageCode: String) {
        self.title = title
        self.description = description
        self.url = url
        self.languageCode = languageCode
    }
}

public struct NativeAppWikipediaSummary: Identifiable, Hashable, Codable, Sendable {
    public var id: String { "\(languageCode):\(title)" }
    public let title: String
    public let extract: String
    public let description: String?
    public let url: URL?
    public let thumbnailURL: URL?
    public let languageCode: String

    public init(
        title: String,
        extract: String,
        description: String?,
        url: URL?,
        thumbnailURL: URL?,
        languageCode: String
    ) {
        self.title = title
        self.extract = extract
        self.description = description
        self.url = url
        self.thumbnailURL = thumbnailURL
        self.languageCode = languageCode
    }
}
