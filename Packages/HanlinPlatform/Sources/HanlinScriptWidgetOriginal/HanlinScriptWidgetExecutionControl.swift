import Foundation

/// The caller owns execution lifetime. A missing deadline follows the caller or
/// platform lifetime; cancellation is delivered independently of JavaScript.
public final class HanlinScriptWidgetExecutionControl: @unchecked Sendable {
    public enum Interruption: Error, Equatable, Sendable, LocalizedError {
        case cancelled, deadlineExceeded

        public var errorDescription: String? {
            switch self {
            case .cancelled: return "ScriptWidget execution was cancelled."
            case .deadlineExceeded: return "The caller's ScriptWidget execution deadline expired."
            }
        }
    }

    public let deadline: ContinuousClock.Instant?
    private let lock = NSLock()
    private var interruption: Interruption?
    private var handlers: [UUID: @Sendable (Interruption) -> Void] = [:]
    private var deadlineTask: Task<Void, Never>?

    public init(deadline: ContinuousClock.Instant? = nil) {
        self.deadline = deadline
        if let deadline {
            if deadline <= .now {
                interruption = .deadlineExceeded
            } else {
                // This task must run outside the runtime's serial callback lane:
                // the first synchronous JavaScript call may itself be a loop.
                deadlineTask = Task.detached { [weak self] in
                    do { try await ContinuousClock().sleep(until: deadline) }
                    catch { return }
                    self?.interrupt(.deadlineExceeded)
                }
            }
        }
    }

    deinit { deadlineTask?.cancel() }

    public func cancel() { interrupt(.cancelled) }

    public func checkCancellation() throws {
        if let deadline, ContinuousClock.now >= deadline { interrupt(.deadlineExceeded) }
        lock.lock(); let reason = interruption; lock.unlock()
        if let reason { throw reason }
    }

    @discardableResult
    public func onCancellation(_ handler: @escaping @Sendable (Interruption) -> Void) -> UUID? {
        if let deadline, ContinuousClock.now >= deadline { interrupt(.deadlineExceeded) }
        lock.lock()
        if let reason = interruption {
            lock.unlock()
            handler(reason)
            return nil
        }
        let id = UUID()
        handlers[id] = handler
        lock.unlock()
        return id
    }

    public func removeCancellationHandler(_ id: UUID?) {
        guard let id else { return }
        lock.lock(); handlers.removeValue(forKey: id); lock.unlock()
    }

    private func interrupt(_ reason: Interruption) {
        lock.lock()
        guard interruption == nil else { lock.unlock(); return }
        interruption = reason
        let callbacks = Array(handlers.values)
        handlers.removeAll()
        lock.unlock()
        // Native provider cancellation may call back synchronously. Never invoke
        // a provider, JavaScript, or completion while holding this control lock.
        callbacks.forEach { $0(reason) }
    }

    /// Existing async owners forward their actual Task cancellation and await
    /// the worker's cleanup before returning. No replacement deadline is added.
    public func perform<Value: Sendable>(
        _ operation: @escaping @Sendable () throws -> Value
    ) async throws -> Value {
        try await withTaskCancellationHandler {
            try checkCancellation()
            let worker = Task.detached(priority: Task.currentPriority) {
                try self.checkCancellation()
                let value = try operation()
                try self.checkCancellation()
                return value
            }
            return try await worker.value
        } onCancel: {
            self.cancel()
        }
    }
}
