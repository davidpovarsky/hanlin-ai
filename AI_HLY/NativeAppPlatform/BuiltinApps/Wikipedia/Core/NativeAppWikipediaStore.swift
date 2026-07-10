import Foundation
import Combine

@MainActor
final class NativeAppWikipediaStore: ObservableObject {
    @Published private(set) var recentQueries: [String]
    @Published private(set) var savedArticles: [NativeAppWikipediaSummary]
    @Published var language: NativeAppWikipediaLanguage {
        didSet { defaults.set(language.rawValue, forKey: languageKey) }
    }

    private let defaults: UserDefaults
    private let recentKey = "nativeapp.wikipedia.recent"
    private let savedKey = "nativeapp.wikipedia.saved"
    private let languageKey = "nativeapp.wikipedia.language"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.recentQueries = defaults.stringArray(forKey: recentKey) ?? []
        if let data = defaults.data(forKey: savedKey),
           let decoded = try? JSONDecoder().decode([NativeAppWikipediaSummary].self, from: data) {
            self.savedArticles = decoded
        } else {
            self.savedArticles = []
        }
        self.language = NativeAppWikipediaLanguage(
            rawValue: defaults.string(forKey: languageKey) ?? "en"
        ) ?? .english
    }

    func addRecentQuery(_ query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        recentQueries.removeAll { $0.caseInsensitiveCompare(trimmed) == .orderedSame }
        recentQueries.insert(trimmed, at: 0)
        recentQueries = Array(recentQueries.prefix(12))
        defaults.set(recentQueries, forKey: recentKey)
    }

    func isSaved(_ article: NativeAppWikipediaSummary) -> Bool {
        savedArticles.contains { $0.id == article.id }
    }

    func toggleSaved(_ article: NativeAppWikipediaSummary) {
        if let index = savedArticles.firstIndex(where: { $0.id == article.id }) {
            savedArticles.remove(at: index)
        } else {
            savedArticles.insert(article, at: 0)
        }
        persistSaved()
    }

    func clearRecentQueries() {
        recentQueries = []
        defaults.removeObject(forKey: recentKey)
    }

    func clearSavedArticles() {
        savedArticles = []
        defaults.removeObject(forKey: savedKey)
    }

    private func persistSaved() {
        if let data = try? JSONEncoder().encode(savedArticles) {
            defaults.set(data, forKey: savedKey)
        }
    }
}
