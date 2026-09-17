import Foundation
#if canImport(Combine)
import Combine

@MainActor
public final class NativeAppTextStudioStore: ObservableObject {
    @Published public var draft: String {
        didSet { storage.setPersistentString(draft, forKey: draftKey) }
    }
    @Published public private(set) var history: [NativeAppTextStudioHistoryItem]

    private let storage: any TextStudioStorage
    private let draftKey = "draft"
    private let historyKey = "history"

    public init(storage: any TextStudioStorage = UserDefaultsTextStudioStorage()) {
        self.storage = storage
        self.draft = storage.persistentString(forKey: draftKey) ?? ""
        if let data = storage.persistentData(forKey: historyKey),
           let decoded = try? JSONDecoder().decode([NativeAppTextStudioHistoryItem].self, from: data) {
            self.history = decoded
        } else {
            self.history = []
        }
    }

    public func addHistory(operation: String, input: String, output: String) {
        history.insert(NativeAppTextStudioHistoryItem(operation: operation, input: input, output: output), at: 0)
        history = Array(history.prefix(40))
        persistHistory()
    }

    public func clearHistory() {
        history = []
        storage.removePersistentValue(forKey: historyKey)
    }

    public func removeHistory(at offsets: IndexSet) {
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
#endif
