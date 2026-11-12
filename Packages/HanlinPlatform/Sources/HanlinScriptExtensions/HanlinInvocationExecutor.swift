import Foundation
import HanlinPlatformContracts

public struct HanlinInvocationDispatchError: Error, Sendable {
    public let status: HanlinInvocationReceipt.Status
    public let failure: HanlinInvocationReceipt.Failure
    public init(_ status: HanlinInvocationReceipt.Status, _ failure: HanlinInvocationReceipt.Failure) {
        self.status = status; self.failure = failure
    }
}

/// Delivery ownership around the existing host action dispatcher. This actor
/// creates no engine and does not execute code inside an extension process.
public actor HanlinInvocationExecutor {
    public typealias Handler = @Sendable (HanlinScriptResumeCommand) async throws -> HanlinValue
    private let store: HanlinScriptExtensionStore
    private var active: [UUID: Task<HanlinInvocationReceipt?, Error>] = [:]

    public init(store: HanlinScriptExtensionStore) { self.store = store }

    public func execute(_ invocationID: UUID, handler: @escaping Handler) async throws -> HanlinInvocationReceipt? {
        if let task = active[invocationID] { return try await task.value }
        // No automatic replay is enabled here. A future registered action may
        // opt in only after its installed idempotency declaration is verified.
        guard let claim = try store.claim(invocationID) else { return try store.receipt(for: invocationID) }
        let store = self.store
        let task = Task<HanlinInvocationReceipt?, Error> {
            do {
                let value = try await withThrowingTaskGroup(of: HanlinValue.self) { group in
                    group.addTask { try Task.checkCancellation(); return try await handler(claim.command) }
                    group.addTask {
                        while true {
                            try await Task.sleep(for: .seconds(1))
                            guard let receipt = try store.receipt(for: invocationID), receipt.leaseID == claim.leaseID else {
                                throw HanlinInvocationQueueError.staleLease
                            }
                            if receipt.cancellationRequested { throw CancellationError() }
                            let expiresAt = claim.command.invocation.delivery?.expiresAt
                                ?? claim.command.createdAt.addingTimeInterval(86_400)
                            if expiresAt <= .now { throw HanlinInvocationDispatchError(.expired, .deadlineExceeded) }
                            try store.renew(claim)
                        }
                    }
                    defer { group.cancelAll() }
                    guard let result = try await group.next() else { throw CancellationError() }
                    return result
                }
                try store.complete(claim, status: .succeeded, value: value)
            } catch is CancellationError {
                try store.complete(claim, status: .cancelled)
            } catch let error as HanlinInvocationDispatchError {
                try store.complete(claim, status: error.status, failure: error.failure)
            } catch {
                // Never persist arbitrary Error descriptions: they may contain
                // private source, credentials, URLs or runtime output.
                try store.complete(claim, status: .failed, failure: .actionFailed)
            }
            return try store.receipt(for: invocationID)
        }
        active[invocationID] = task
        defer { active[invocationID] = nil }
        return try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
    }
}
