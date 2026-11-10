import Foundation
import Synchronization

/// A queued native call can be cancelled before its engine/process-directory lock is
/// available. Running native calls still complete cooperatively after yielding.
final class RuntimeQueuedExecution<Input: Sendable, Output: Sendable>: Sendable {
    private struct State: Sendable {
        var continuation: CheckedContinuation<Output, any Error>?
        var payload: Input?
        var started = false
        var cancelled = false
        var finished = false
    }
    private let state = Mutex(State())

    func bind(_ continuation: CheckedContinuation<Output, any Error>, input: Input) -> Bool {
        let accepted = state.withLock { value in
            guard !value.cancelled, !value.finished else { return false }
            value.continuation = continuation
            value.payload = input
            return true
        }
        if !accepted { continuation.resume(throwing: CancellationError()) }
        return accepted
    }

    /// Called only after the native execution queue and directory lock are owned.
    func takeForRunning() -> Input? {
        state.withLock { value in
            guard !value.started, !value.cancelled, !value.finished else { return nil }
            value.started = true
            let payload = value.payload
            value.payload = nil
            return payload
        }
    }

    func cancelBeforeStarting() {
        let continuation = state.withLock { value -> CheckedContinuation<Output, any Error>? in
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

    func complete(_ result: Result<Output, any Error>) {
        let continuation = state.withLock { value -> CheckedContinuation<Output, any Error>? in
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
