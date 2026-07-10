import Foundation
import Combine

@MainActor
final class NativeAppTextStudioStore: ObservableObject {
    @Published var draft: String {
        didSet { defaults.set(draft, forKey: draftKey) }
    }
    @Published private(set) var history: [NativeAppTextStudioHistoryItem]

    private let defaults: UserDefaults
    private let draftKey = "nativeapp.textstudio.draft"
    private let historyKey = "nativeapp.textstudio.history"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.draft = defaults.string(forKey: draftKey) ?? ""
        if let data = defaults.data(forKey: historyKey),
           let decoded = try? JSONDecoder().decode([NativeAppTextStudioHistoryItem].self, from: data) {
            self.history = decoded
        } else {
            self.history = []
        }
    }

    func addHistory(operation: String, input: String, output: String) {
        history.insert(NativeAppTextStudioHistoryItem(operation: operation, input: input, output: output), at: 0)
        history = Array(history.prefix(40))
        persistHistory()
    }

    func clearHistory() {
        history = []
        defaults.removeObject(forKey: historyKey)
    }

    func removeHistory(at offsets: IndexSet) {
        for index in offsets.sorted(by: >) {
            history.remove(at: index)
        }
        persistHistory()
    }

    private func persistHistory() {
        if let data = try? JSONEncoder().encode(history) {
            defaults.set(data, forKey: historyKey)
        }
    }
}
