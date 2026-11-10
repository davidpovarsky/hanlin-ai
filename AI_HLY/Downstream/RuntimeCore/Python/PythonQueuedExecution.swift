import Foundation
import Synchronization

/// A queued call can be cancelled before CPython/the process-directory lock is
/// available. Running native calls still complete cooperatively after yielding.
final class PythonQueuedExecution: Sendable {
    private struct State: Sendable {
        var continuation: CheckedContinuation<Data, any Error>?
        var payload: String?
        var started = false
        var cancelled = false
        var finished = false
    }
    private let state = Mutex(State())

    func bind(_ continuation: CheckedContinuation<Data, any Error>, requestJSON: String) -> Bool {
        let accepted = state.withLock { value in
            guard !value.cancelled, !value.finished else { return false }
            value.continuation = continuation
            value.payload = requestJSON
            return true
        }
        if !accepted { continuation.resume(throwing: CancellationError()) }
        return accepted
    }

    /// Called only after the native execution queue and directory lock are owned.
    func takeForRunning() -> String? {
        state.withLock { value in
            guard !value.started, !value.cancelled, !value.finished else { return nil }
            value.started = true
            let payload = value.payload
            value.payload = nil
            return payload
        }
    }

    func cancelBeforeStarting() {
        let continuation = state.withLock { value -> CheckedContinuation<Data, any Error>? in
            value.cancelled = true
            guard !value.started, !value.finished else { return nil }
            value.payload = nil
            let continuation = value.continuation
            value.continuation = nil
            if continuation != nil { value.finished = true }
            return continuation
        }
        continuation?.resume(throwing: CancellationError())
    }

    func complete(_ result: Result<Data, any Error>) {
        let continuation = state.withLock { value -> CheckedContinuation<Data, any Error>? in
            guard !value.finished else { return nil }
            value.finished = true
            value.payload = nil
            let continuation = value.continuation
            value.continuation = nil
            return continuation
        }
        continuation?.resume(with: result)
    }
}
