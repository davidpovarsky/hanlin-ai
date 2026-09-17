import Foundation

public enum NativeAppSefariaLanguage: String, CaseIterable, Codable, Identifiable, Sendable {
    case bilingual
    case english
    case hebrew

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .bilingual: return "Bilingual"
        case .english: return "English"
        case .hebrew: return "Hebrew"
        }
    }
}

public struct NativeAppSefariaSearchResult: Identifiable, Hashable, Codable, Sendable {
    public var id: String { ref }
    public let ref: String
    public let title: String
    public let snippet: String
    public let url: URL?

    public init(ref: String, title: String, snippet: String, url: URL?) {
        self.ref = ref
        self.title = title
        self.snippet = snippet
        self.url = url
    }
}

public struct NativeAppSefariaNameResolution: Hashable, Sendable {
    public let resolvedRef: String?
    public let completions: [NativeAppSefariaNameCompletion]

    public init(resolvedRef: String?, completions: [NativeAppSefariaNameCompletion]) {
        self.resolvedRef = resolvedRef
        self.completions = completions
    }
}

public struct NativeAppSefariaNameCompletion: Hashable, Sendable {
    public let title: String
    public let ref: String?
    public let type: String?
    public let url: URL?

    public init(title: String, ref: String?, type: String?, url: URL?) {
        self.title = title
        self.ref = ref
        self.type = type
        self.url = url
    }
}

public struct NativeAppSefariaSource: Identifiable, Hashable, Codable, Sendable {
    public var id: String { ref }
    public let ref: String
    public let text: String
    public let heText: String?
    public let url: URL?

    public init(ref: String, text: String, heText: String?, url: URL?) {
        self.ref = ref
        self.text = text
        self.heText = heText
        self.url = url
    }

    public var combinedText: String {
        [heText, text]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
    }
}
