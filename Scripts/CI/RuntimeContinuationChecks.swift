import Foundation

/// Runs against the real Foundation-only operation owner. OS admission,
/// background lifetime and UIKit geometry require the physical-device build.
@main
struct RuntimeContinuationChecks {
    static func main() async throws {
        var checks = 0
        func check(_ condition: Bool, _ reason: String) {
            precondition(condition, reason)
            checks += 1
        }
        let operation = RuntimeUserOperation()
        check(operation.snapshot.progressTotalUnits == 1, "Finalization remains pending before any provider work")
        operation.recordWorkEvent(id: "step:1:started")
        operation.recordStreamBytes(24)
        operation.recordWorkEvent(id: "tool:route:result")
        let journal = UUID()
        operation.recordJobOutput(id: journal, stdout: 9, stderr: 2)
        for _ in 0..<100 {
            operation.recordWorkEvent(id: "tool:route:result")
            operation.recordJobOutput(id: journal, stdout: 9, stderr: 2)
            let snapshot = operation.snapshot
            check(snapshot.completedWorkUnits == 4 && snapshot.outputBytes == 35,
                "Polling/replayed receipts must not manufacture progress")
        }
        operation.recordJobOutput(id: journal, stdout: 5, stderr: 1)
        check(operation.snapshot.completedWorkUnits == 4, "A truncated journal is not new output")
        operation.recordJobOutput(id: journal, stdout: 15, stderr: 4)
        check(operation.snapshot.completedWorkUnits == 5 && operation.snapshot.outputBytes == 43,
            "Only new output advances the high-water mark")
        let snapshot = operation.snapshot
        let progress = Progress(totalUnitCount: snapshot.progressTotalUnits)
        progress.completedUnitCount = snapshot.progressCompletedUnits
        check(!progress.isIndeterminate && progress.fractionCompleted > 0 && !progress.isFinished,
            "Actual work has finite positive progress, without completing the running operation")
        try operation.markSucceeded()
        check(operation.snapshot.progressCompletedUnits < operation.snapshot.progressTotalUnits,
            "Success receipt alone does not finish finalization")
        operation.finish()
        check(operation.snapshot.progressCompletedUnits == operation.snapshot.progressTotalUnits,
            "Only completed success finishes system progress")
        operation.recordStreamBytes(100)
        operation.recordWorkEvent(id: "late")
        check(operation.snapshot.completedWorkUnits == 5, "Terminal operations reject late progress")

        let cancelled = RuntimeUserOperation()
        cancelled.recordWorkEvent(id: "request")
        cancelled.interrupt(reason: "native Cancel or resource expiry")
        cancelled.interrupt(reason: "second cause must not replace original")
        cancelled.recordStreamBytes(9)
        cancelled.recordWorkEvent(id: "after-cancel")
        check(cancelled.snapshot.reason == "native Cancel or resource expiry", "First cancellation cause is retained")
        check(cancelled.snapshot.completedWorkUnits == 1, "Cancelled work cannot keep a progress heartbeat alive")
        do { try cancelled.markSucceeded(); preconditionFailure("Cancelled operation was marked successful") }
        catch is RuntimeOperationInterruptionError { checks += 1 }
        cancelled.finish()
        check(cancelled.snapshot.progressCompletedUnits < cancelled.snapshot.progressTotalUnits,
            "Interrupted finalization never advertises 100 percent success")

        let owner = RuntimeUserOperation()
        let producer = RuntimeUserOperation.producerTask(operation: owner) {
            precondition(RuntimeUserOperation.current?.id == owner.id)
            let detachedOwner = await Task.detached { RuntimeUserOperation.current?.id }.value
            precondition(detachedOwner == nil, "Unrelated detached work must not inherit a chat's lifetime")
            RuntimeUserOperation.current?.recordWorkEvent(id: "owned")
        }
        await producer.value
        check(owner.snapshot.completedWorkUnits == 1 && RuntimeUserOperation.current == nil,
            "The producer carries only its original operation identity")
        // Exercise Foundation's real termination callbacks: finish (including
        // an error) must never cancel the producer or its ancestor run.
        for ownsRun in [false, true] {
            for fails in [false, true] {
                let receipt = TerminationReceipt()
                let pair = AsyncThrowingStream<Int, Error>.makeStream()
                pair.continuation.onTermination = { termination in
                    RuntimeUserOperation.handleStreamTermination(termination, ownsRun: ownsRun,
                        cancelProducer: { receipt.producerCancelled() },
                        cancelOwnedRun: { receipt.runCancelled() })
                }
                if fails { pair.continuation.finish(throwing: FixtureFailure.expected) }
                else { pair.continuation.finish() }
                check(receipt.snapshot == [0, 0], "A finished stream cannot cancel its producer or ancestor")
            }
            let receipt = TerminationReceipt()
            let pair = AsyncThrowingStream<Int, Error>.makeStream()
            pair.continuation.onTermination = { termination in
                RuntimeUserOperation.handleStreamTermination(termination, ownsRun: ownsRun,
                    cancelProducer: { receipt.producerCancelled() },
                    cancelOwnedRun: { receipt.runCancelled() })
            }
            let consumer = Task {
                var iterator = pair.stream.makeAsyncIterator()
                _ = try? await iterator.next()
            }
            consumer.cancel()
            await consumer.value
            check(receipt.snapshot == [1, ownsRun ? 1 : 0],
                "Actual cancellation stops its producer; only the root stream can cancel the shared run")
        }
        print("PASS: \(checks) production continuation ownership/progress checks")
    }
}

private enum FixtureFailure: Error { case expected }
private final class TerminationReceipt: @unchecked Sendable {
    private let lock = NSLock()
    private var producer = 0
    private var run = 0
    var snapshot: [Int] { lock.withLock { [producer, run] } }
    func producerCancelled() { lock.withLock { producer += 1 } }
    func runCancelled() { lock.withLock { run += 1 } }
}
