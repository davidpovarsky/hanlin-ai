import Foundation
import Combine

@MainActor
final class NativeAppSefariaStore: ObservableObject {
    @Published private(set) var recentQueries: [String]
    @Published private(set) var savedSources: [NativeAppSefariaSource]
    @Published var preferredLanguage: NativeAppSefariaLanguage {
        didSet { defaults.set(preferredLanguage.rawValue, forKey: languageKey) }
    }

    private let defaults: UserDefaults
    private let recentKey = "nativeapp.sefaria.recent"
    private let savedKey = "nativeapp.sefaria.saved"
    private let languageKey = "nativeapp.sefaria.language"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.recentQueries = defaults.stringArray(forKey: recentKey) ?? []
        if let data = defaults.data(forKey: savedKey),
           let decoded = try? JSONDecoder().decode([NativeAppSefariaSource].self, from: data) {
            self.savedSources = decoded
        } else {
            self.savedSources = []
        }
        self.preferredLanguage = NativeAppSefariaLanguage(
            rawValue: defaults.string(forKey: languageKey) ?? "bilingual"
        ) ?? .bilingual
    }

    func addRecentQuery(_ query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        recentQueries.removeAll { $0.caseInsensitiveCompare(trimmed) == .orderedSame }
        recentQueries.insert(trimmed, at: 0)
        recentQueries = Array(recentQueries.prefix(12))
        defaults.set(recentQueries, forKey: recentKey)
    }

    func isSaved(_ source: NativeAppSefariaSource) -> Bool {
        savedSources.contains { $0.ref == source.ref }
    }

    func toggleSaved(_ source: NativeAppSefariaSource) {
        if let index = savedSources.firstIndex(where: { $0.ref == source.ref }) {
            savedSources.remove(at: index)
        } else {
            savedSources.insert(source, at: 0)
        }
        persistSavedSources()
    }

    func clearRecentQueries() {
        recentQueries = []
        defaults.removeObject(forKey: recentKey)
    }

    func clearSavedSources() {
        savedSources = []
        defaults.removeObject(forKey: savedKey)
    }

    private func persistSavedSources() {
        if let data = try? JSONEncoder().encode(savedSources) {
            defaults.set(data, forKey: savedKey)
        }
    }
}
