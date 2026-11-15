import Foundation

struct RuntimeOperationInterruptionError: LocalizedError, Sendable {
    let operationID: UUID
    let reason: String
    var errorDescription: String? {
        "\(reason) Partial results are retained. Actions are not replayed automatically."
    }
}

/// An explicitly owned user operation, never a process-wide permission or the
/// TaskLocals of whichever chat happened to launch the shared Host first.
final class RuntimeUserOperation: @unchecked Sendable {
    @TaskLocal static var current: RuntimeUserOperation?

    struct Snapshot: Sendable {
        let reason: String?
        let outputBytes: Int64
        let finished: Bool
        let succeeded: Bool
    }

    let id: UUID
    private let lock = NSLock()
    private var reason: String?
    private var outputBytes: Int64 = 0
    private var jobBytes: [UUID: Int64] = [:]
    private var handlers: [UUID: @Sendable (String) -> Void] = [:]
    private var cancelProducer: (@Sendable () -> Void)?
    private var finished = false
    private var succeeded = false

    init(id: UUID = UUID()) { self.id = id }

    @MainActor
    static func producerTask(operation: RuntimeUserOperation?, body: @escaping @MainActor @Sendable () async -> Void) -> Task<Void, Never> {
        Task(priority: .userInitiated) {
            await Self.$current.withValue(operation) { await body() }
        }
    }

    var snapshot: Snapshot {
        lock.withLock { Snapshot(reason: reason, outputBytes: outputBytes, finished: finished, succeeded: succeeded) }
    }

    func bindProducerCancellation(_ cancel: @escaping @Sendable () -> Void) {
        let shouldCancel = lock.withLock {
            guard !finished else { return false }
            cancelProducer = cancel
            return reason != nil
        }
        if shouldCancel { cancel() }
    }

    /// Register before starting the native job. Late registrations immediately
    /// receive an existing interruption; callbacks never execute under the lock.
    func registerInterruption(_ handler: @escaping @Sendable (String) -> Void) -> UUID {
        let token = UUID()
        let existing = lock.withLock {
            if !finished { handlers[token] = handler }
            return reason
        }
        if let existing { handler(existing) }
        return token
    }

    func unregisterInterruption(_ token: UUID) { lock.withLock { _ = handlers.removeValue(forKey: token) } }

    func interrupt(reason newReason: String) {
        let callbacks: ([@Sendable (String) -> Void], (@Sendable () -> Void)?)? = lock.withLock {
            guard !finished, reason == nil else { return nil }
            reason = newReason
            succeeded = false
            return (Array(handlers.values), cancelProducer)
        }
        guard let callbacks else { return }
        for handler in callbacks.0 { handler(newReason) }
        callbacks.1?()
    }

    func checkInterruption() throws {
        if let reason = snapshot.reason { throw RuntimeOperationInterruptionError(operationID: id, reason: reason) }
    }

    func recordStreamBytes(_ bytes: Int) {
        guard bytes > 0 else { return }
        lock.withLock { addBytes(Int64(bytes)) }
    }

    /// Polling the same durable journal must not manufacture more progress.
    func recordJobOutput(id: UUID, stdout: Int64, stderr: Int64) {
        guard stdout >= 0, stderr >= 0 else { return }
        lock.withLock {
            let sum = stdout.addingReportingOverflow(stderr)
            let total = sum.overflow ? Int64.max : sum.partialValue
            let prior = jobBytes[id] ?? 0
            if total > prior { addBytes(total - prior); jobBytes[id] = total }
        }
    }

    func markSucceeded() throws {
        try lock.withLock {
            if let reason { throw RuntimeOperationInterruptionError(operationID: id, reason: reason) }
            if !finished { succeeded = true }
        }
    }

    func markFailed() { lock.withLock { succeeded = false } }

    static func finishStream<Element>(_ continuation: AsyncThrowingStream<Element, Error>.Continuation) {
        if let operation = current, let reason = operation.snapshot.reason {
            continuation.finish(throwing: RuntimeOperationInterruptionError(operationID: operation.id, reason: reason))
        } else { continuation.finish() }
    }

    func finish() {
        lock.withLock {
            finished = true
            handlers.removeAll()
            cancelProducer = nil // Break the producer Task/context ownership cycle.
            jobBytes.removeAll()
        }
    }

    private func addBytes(_ count: Int64) {
        guard !finished else { return }
        let sum = outputBytes.addingReportingOverflow(count)
        outputBytes = sum.overflow ? Int64.max : sum.partialValue
    }
}
