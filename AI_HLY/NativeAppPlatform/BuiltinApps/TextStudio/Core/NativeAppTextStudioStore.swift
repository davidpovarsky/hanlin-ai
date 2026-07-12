import Foundation
import Combine

@MainActor
final class NativeAppTextStudioStore: ObservableObject {
    @Published var draft: String {
        didSet { storage.setPersistentString(draft, forKey: draftKey) }
    }
    @Published private(set) var history: [NativeAppTextStudioHistoryItem]

    private let storage: NativeAppStorageBroker
    private let draftKey = "draft"
    private let historyKey = "history"

    init(storage: NativeAppStorageBroker) {
        self.storage = storage
        self.draft = storage.persistentString(forKey: draftKey) ?? ""
        if let data = storage.persistentData(forKey: historyKey),
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
        storage.removePersistentValue(forKey: historyKey)
    }

    func removeHistory(at offsets: IndexSet) {
        for index in offsets.sorted(by: >) {
            history.remove(at: index)
        }
        persistHistory()
    }

    private func persistHistory() {
        if let data = try? JSONEncoder().encode(history) {
            storage.setPersistentData(data, forKey: historyKey)
        }
    }
}
