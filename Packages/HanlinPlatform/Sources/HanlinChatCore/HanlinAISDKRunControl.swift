import Foundation

/// One original engine stream's cancellation and completion boundary. A host may
/// stop a run before its producer is installed; installation observes that stop.
/// Joining does not assert that a host's detached native effects were rolled back.
public final class HanlinAISDKRunControl: @unchecked Sendable {
    private let lock = NSLock()
    private var task: Task<Void, Never>?
    private var stop: (@Sendable () -> Void)?
    private var cancelled = false

    public init() {}

    public var isCancellationRequested: Bool {
        lock.withLock { cancelled }
    }

    public func cancel() {
        let action = lock.withLock {
            cancelled = true
            return stop
        }
        action?()
    }

    /// Call after stream creation has returned or failed. Waiting for this task
    /// preserves the original producer's termination and transport cleanup.
    public func waitUntilFinished() async {
        let producer = lock.withLock { task }
        await producer?.value
    }

    func install(task: Task<Void, Never>, stop: @escaping @Sendable () -> Void) {
        let wasCancelled = lock.withLock {
            precondition(self.task == nil, "A run control belongs to one engine stream.")
            self.task = task
            self.stop = stop
            return cancelled
        }
        if wasCancelled { stop() }
    }
}
