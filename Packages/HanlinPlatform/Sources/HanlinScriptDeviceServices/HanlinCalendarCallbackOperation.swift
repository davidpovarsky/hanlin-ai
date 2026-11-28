import Foundation

/// EventKit may never call a cancelled reminder fetch's completion. This owner
/// resumes the Swift task itself, exactly once, and ignores any late callback.
@MainActor
final class HanlinCalendarCallbackOperation<Value: Sendable> {
    private var continuation: CheckedContinuation<Value, any Error>?
    private var cancelRequest: (@MainActor () -> Void)?
    private var deadlineTask: Task<Void, Never>?
    private var completed = false

    func value(
        timeout: Duration = .seconds(30),
        start: (@escaping @Sendable (Result<Value, any Error>) -> Void) -> (@MainActor () -> Void)?
    ) async throws -> Value {
        try Task.checkCancellation()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
                guard !Task.isCancelled else {
                    finish(.failure(CancellationError()), cancelUnderlying: true)
                    return
                }
                cancelRequest = start { result in
                    Task { @MainActor in self.finish(result) }
                }
                deadlineTask = Task { [weak self] in
                    do { try await Task.sleep(for: timeout) } catch { return }
                    self?.finish(.failure(HanlinCalendarRequestError.timedOut), cancelUnderlying: true)
                }
            }
        } onCancel: {
            Task { @MainActor in self.finish(.failure(CancellationError()), cancelUnderlying: true) }
        }
    }

    private func finish(_ result: Result<Value, any Error>, cancelUnderlying: Bool = false) {
        guard !completed else { return }
        completed = true
        let continuation = continuation
        let cancel = cancelRequest
        self.continuation = nil
        cancelRequest = nil
        deadlineTask?.cancel()
        deadlineTask = nil
        if cancelUnderlying { cancel?() }
        continuation?.resume(with: result)
    }
}
