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

    /// Semantic state for the system's continuation UI. Byte and work-unit
    /// counters remain internal accounting, never user-facing descriptions.
    enum ModelPhase: Sendable { case waitingForResponse, thinking, responding }
    enum Presentation: Equatable, Sendable {
        case waitingForResponse, thinking, responding, awaitingApproval
        case tool(String)
        case completed, stopped
    }

    struct Snapshot: Sendable {
        let reason: String?
        let outputBytes: Int64
        let completedWorkUnits: Int64
        let finished: Bool
        let succeeded: Bool
        let presentation: Presentation

        /// Progress covers work discovered so far, plus the real finalization
        /// step. The total grows as the provider discovers additional work;
        /// it is not an estimate of the duration or eventual response length.
        var progressTotalUnits: Int64 { completedWorkUnits + 1 }
        var progressCompletedUnits: Int64 {
            succeeded && finished && reason == nil ? progressTotalUnits : completedWorkUnits
        }
    }

    let id: UUID
    private let lock = NSLock()
    private var reason: String?
    private var outputBytes: Int64 = 0
    private var completedWorkUnits: Int64 = 0
    private var recordedEvents: Set<String> = []
    private var jobBytes: [UUID: Int64] = [:]
    private var handlers: [UUID: @Sendable (String) -> Void] = [:]
    private var cancelProducer: (@Sendable () -> Void)?
    private var finished = false
    private var succeeded = false
    private var modelPhase: ModelPhase = .waitingForResponse
    private var activeToolTitles: [String: String] = [:]
    private var activeToolOrder: [String] = []
    private var pendingApprovals: Set<String> = []

    init(id: UUID = UUID()) { self.id = id }

    @MainActor
    static func producerTask(operation: RuntimeUserOperation?, body: @escaping @MainActor @Sendable () async -> Void) -> Task<Void, Never> {
        Task(priority: .userInitiated) {
            await Self.$current.withValue(operation) { await body() }
        }
    }

    var snapshot: Snapshot {
        lock.withLock { Snapshot(reason: reason, outputBytes: outputBytes,
            completedWorkUnits: completedWorkUnits, finished: finished, succeeded: succeeded,
            presentation: presentationLocked) }
    }

    func updateModelPhase(_ phase: ModelPhase) {
        lock.withLock {
            guard !finished, reason == nil else { return }
            modelPhase = phase
        }
    }

    func beginTool(id: String, title: String) {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty, !title.isEmpty else { return }
        lock.withLock {
            guard !finished, reason == nil else { return }
            if activeToolTitles[id] == nil { activeToolOrder.append(id) }
            activeToolTitles[id] = title
            modelPhase = .waitingForResponse
        }
    }

    func endTool(id: String) {
        lock.withLock {
            guard !finished, reason == nil else { return }
            guard activeToolTitles.removeValue(forKey: id) != nil else { return }
            activeToolOrder.removeAll { $0 == id }
        }
    }

    func updateApproval(id: String, isPending: Bool) {
        guard !id.isEmpty else { return }
        lock.withLock {
            guard !finished, reason == nil else { return }
            if isPending { pendingApprovals.insert(id) }
            else { pendingApprovals.remove(id) }
        }
    }

    /// Access only while holding lock. Concurrent tool completion must reveal
    /// the remaining real tool, and late callbacks cannot revive terminal UI.
    private var presentationLocked: Presentation {
        if reason != nil { return .stopped }
        if finished { return succeeded ? .completed : .stopped }
        if !pendingApprovals.isEmpty { return .awaitingApproval }
        if let id = activeToolOrder.last, let title = activeToolTitles[id] { return .tool(title) }
        switch modelPhase {
        case .waitingForResponse: return .waitingForResponse
        case .thinking: return .thinking
        case .responding: return .responding
        }
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

    /// A provider/Host lifecycle receipt is real progress even when a tool
    /// returns no text. Replayed receipts and polling never add units.
    func recordWorkEvent(id: String) {
        guard !id.isEmpty else { return }
        lock.withLock {
            guard !finished, reason == nil, recordedEvents.insert(id).inserted else { return }
            completeWorkUnit()
        }
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

    /// Finishing a nested stream is a receipt, not cancellation of its owning
    /// conversation. Only cancellation stops that producer; only the root
    /// stream owns cancellation of the shared run.
    static func handleStreamTermination<Element>(
        _ termination: AsyncThrowingStream<Element, Error>.Continuation.Termination,
        ownsRun: Bool,
        cancelProducer: @Sendable () -> Void,
        cancelOwnedRun: @Sendable () -> Void
    ) {
        guard case .cancelled = termination else { return }
        cancelProducer()
        if ownsRun { cancelOwnedRun() }
    }

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
            recordedEvents.removeAll()
            activeToolTitles.removeAll()
            activeToolOrder.removeAll()
            pendingApprovals.removeAll()
        }
    }

    private func addBytes(_ count: Int64) {
        guard !finished, reason == nil else { return }
        let sum = outputBytes.addingReportingOverflow(count)
        outputBytes = sum.overflow ? Int64.max : sum.partialValue
        completeWorkUnit()
    }

    private func completeWorkUnit() {
        if completedWorkUnits < Int64.max - 1 { completedWorkUnits += 1 }
    }
}
