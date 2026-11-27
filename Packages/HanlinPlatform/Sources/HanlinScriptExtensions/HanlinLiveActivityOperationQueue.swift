import Foundation

/// Serializes mutations of one system activity across asynchronous preparation
/// and ActivityKit calls. Independent activities remain concurrent. A canceled
/// waiter never invokes its operation or cancels the previous activity mutation.
actor HanlinLiveActivityOperationQueue {
    static let shared = HanlinLiveActivityOperationQueue()

    struct Key: Hashable, Sendable {
        let installation: String
        let activity: String
    }

    private struct Entry {
        let id: UUID
        let completion: Task<Void, Never>
    }

    private var entries: [Key: Entry] = [:]

    func perform<Value: Sendable>(
        key: Key, operation: @escaping @Sendable () async throws -> Value
    ) async throws -> Value {
        let predecessor = entries[key]?.completion
        let id = UUID()
        let task = Task {
            await predecessor?.value
            try Task.checkCancellation()
            return try await operation()
        }
        let completion = Task { _ = try? await task.value }
        entries[key] = Entry(id: id, completion: completion)
        defer {
            if entries[key]?.id == id { entries[key] = nil }
        }
        return try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
    }
}
