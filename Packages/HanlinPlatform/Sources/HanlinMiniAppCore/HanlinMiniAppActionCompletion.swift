import Foundation
import HanlinPlatformContracts
import Synchronization

/// Resolves one native callback exactly once. Cancellation may arrive before
/// registration, and a JavaScript callback may arrive after cancellation.
public final class HanlinMiniAppActionCompletion: Sendable {
    private struct State {
        var continuation: CheckedContinuation<HanlinValue, any Error>?
        var result: Result<HanlinValue, any Error>?
    }
    private let state = Mutex(State())

    public init() {}

    /// False means cancellation/completion already won; do not start the action.
    public func install(_ continuation: CheckedContinuation<HanlinValue, any Error>) -> Bool {
        let result = state.withLock { state -> Result<HanlinValue, any Error>? in
            if let result = state.result { return result }
            precondition(state.continuation == nil, "An action completion has one waiter")
            state.continuation = continuation
            return nil
        }
        if let result {
            continuation.resume(with: result)
            return false
        }
        return true
    }

    public func resolve(_ result: Result<HanlinValue, any Error>) {
        let continuation = state.withLock { state -> CheckedContinuation<HanlinValue, any Error>? in
            guard state.result == nil else { return nil }
            state.result = result
            let continuation = state.continuation
            state.continuation = nil
            return continuation
        }
        continuation?.resume(with: result)
    }
}
