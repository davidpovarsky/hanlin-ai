import Foundation
import HanlinPlatformContracts

public struct HanlinInvocationDispatchError: Error, Sendable {
    public let status: HanlinInvocationReceipt.Status
    public let failure: HanlinInvocationReceipt.Failure
    public init(_ status: HanlinInvocationReceipt.Status, _ failure: HanlinInvocationReceipt.Failure) {
        self.status = status; self.failure = failure
    }
}

/// Trusted Host admission only: the handler has not called package/user code
/// or performed an action side effect. Never use this after execution starts.
public struct HanlinInvocationNotStarted: Error, Sendable {
    public init() {}
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
        return try await execute(claim, releaseUnstarted: true, handler: handler)
    }

    /// The dedicated intent and any ordinary foreground drain use the same
    /// fenced lease. Exact retries retain their original command and receipt.
    public func execute(_ command: HanlinScriptResumeCommand,
                        handler: @escaping Handler) async throws -> HanlinInvocationReceipt? {
        guard let claim = try store.enqueueAndClaim(command) else {
            if let task = active[command.id] { return try await task.value }
            return try store.receipt(for: command.id)
        }
        return try await execute(claim, releaseUnstarted: false, handler: handler)
    }

    private func execute(_ claim: HanlinInvocationClaim, releaseUnstarted: Bool,
                         handler: @escaping Handler) async throws -> HanlinInvocationReceipt? {
        let invocationID = claim.command.id
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
            } catch is HanlinInvocationNotStarted {
                if releaseUnstarted {
                    try store.releaseUnstarted(claim)
                } else {
                    // A live intent returning an admission error must not leave
                    // its action queued for execution after Shortcuts has ended.
                    try store.complete(claim, status: .needsForeground, failure: .unavailableHost)
                }
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
