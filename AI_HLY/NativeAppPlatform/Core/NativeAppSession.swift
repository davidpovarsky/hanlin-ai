import Combine
import Foundation

@MainActor
final class NativeAppSession: ObservableObject, Identifiable {
    let id: UUID
    let appID: String
    let presentationStyle: NativeAppPresentationStyle
    let createdAt: Date

    @Published private(set) var isClosed = false

    private var activeTasks: [UUID: Task<Void, Never>] = [:]

    init(
        id: UUID = UUID(),
        appID: String,
        presentationStyle: NativeAppPresentationStyle
    ) {
        self.id = id
        self.appID = appID
        self.presentationStyle = presentationStyle
        self.createdAt = Date()
    }

    @discardableResult
    func track(_ task: Task<Void, Never>) -> UUID {
        let token = UUID()
        activeTasks[token] = task
        return token
    }

    func cancelTask(_ token: UUID) {
        activeTasks[token]?.cancel()
        activeTasks[token] = nil
    }

    func cancelAllTasks() {
        for task in activeTasks.values {
            task.cancel()
        }
        activeTasks.removeAll()
    }

    func close() {
        guard !isClosed else { return }
        cancelAllTasks()
        isClosed = true
    }
}
