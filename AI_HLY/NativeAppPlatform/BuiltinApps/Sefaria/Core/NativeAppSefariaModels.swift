import Foundation

enum NativeAppSefariaLanguage: String, CaseIterable, Codable, Identifiable {
    case bilingual
    case english
    case hebrew

    var id: String { rawValue }

    var title: String {
        switch self {
        case .bilingual: return "Bilingual"
        case .english: return "English"
        case .hebrew: return "Hebrew"
        }
    }
}

struct NativeAppSefariaSearchResult: Identifiable, Hashable, Codable {
    var id: String { ref }
    let ref: String
    let title: String
    let snippet: String
    let url: URL?
}

struct NativeAppSefariaNameResolution: Hashable {
    let resolvedRef: String?
    let completions: [NativeAppSefariaNameCompletion]
}

struct NativeAppSefariaNameCompletion: Hashable {
    let title: String
    let ref: String?
    let type: String?
    let url: URL?
}

struct NativeAppSefariaSource: Identifiable, Hashable, Codable {
    var id: String { ref }
    let ref: String
    let text: String
    let heText: String?
    let url: URL?

    var combinedText: String {
        [heText, text]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
    }
}
