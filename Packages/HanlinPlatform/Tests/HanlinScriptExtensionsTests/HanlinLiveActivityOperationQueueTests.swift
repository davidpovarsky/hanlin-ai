import Foundation
@testable import HanlinScriptExtensions
import Testing

@Suite("Live Activity mutation serialization")
struct HanlinLiveActivityOperationQueueTests {
    @Test func sameActivityNeverOverlapsAndFailureDoesNotBlockLaterWork() async throws {
        let queue = HanlinLiveActivityOperationQueue()
        let trace = MutationTrace()
        let key = HanlinLiveActivityOperationQueue.Key(installation: "one", activity: "same")
        await withTaskGroup(of: Void.self) { group in
            for index in 0..<12 {
                group.addTask {
                    do {
                        _ = try await queue.perform(key: key) {
                            await trace.begin()
                            try await Task.sleep(for: .milliseconds(2))
                            await trace.end()
                            if index == 4 { throw MutationFailure.expected }
                            return index
                        }
                    } catch {
                        #expect(index == 4)
                    }
                }
            }
        }
        let values = await trace.snapshot()
        #expect(values.maximum == 1)
        #expect(values.finished == 12)
        #expect(try await queue.perform(key: key) { 42 } == 42)
    }

    @Test func differentActivityCanCompleteWhileFirstActivityIsSuspended() async throws {
        let queue = HanlinLiveActivityOperationQueue()
        let entered = MutationLatch()
        let release = MutationLatch()
        let first = Task {
            try await queue.perform(key: .init(installation: "one", activity: "a")) {
                await entered.open()
                await release.wait()
                return "a"
            }
        }
        await entered.wait()
        let second = try await queue.perform(key: .init(installation: "one", activity: "b")) { "b" }
        #expect(second == "b")
        await release.open()
        #expect(try await first.value == "a")
    }

    @Test func canceledWaiterDoesNotRunOrCancelThePrecedingMutation() async throws {
        let queue = HanlinLiveActivityOperationQueue()
        let entered = MutationLatch()
        let release = MutationLatch()
        let trace = MutationTrace()
        let key = HanlinLiveActivityOperationQueue.Key(installation: "one", activity: "same")
        let first = Task {
            try await queue.perform(key: key) {
                await entered.open()
                await release.wait()
                return 1
            }
        }
        await entered.wait()
        let second = Task {
            try await queue.perform(key: key) {
                await trace.begin()
                await trace.end()
                return 2
            }
        }
        second.cancel()
        await release.open()
        #expect(try await first.value == 1)
        do {
            _ = try await second.value
            Issue.record("Canceled queued mutation executed")
        } catch is CancellationError {
        } catch {
            Issue.record("Unexpected cancellation error: \(error)")
        }
        #expect(await trace.snapshot().finished == 0)
        #expect(try await queue.perform(key: key) { 3 } == 3)
    }
}

private enum MutationFailure: Error { case expected }

private actor MutationTrace {
    private var active = 0
    private var maximum = 0
    private var finished = 0
    func begin() { active += 1; maximum = max(maximum, active) }
    func end() { active -= 1; finished += 1 }
    func snapshot() -> (maximum: Int, finished: Int) { (maximum, finished) }
}

private actor MutationLatch {
    private var opened = false
    private var waiting: [CheckedContinuation<Void, Never>] = []
    func wait() async {
        if opened { return }
        await withCheckedContinuation { waiting.append($0) }
    }
    func open() {
        opened = true
        let pending = waiting
        waiting.removeAll()
        for waiter in pending { waiter.resume() }
    }
}
