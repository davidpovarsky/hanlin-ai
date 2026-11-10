import Foundation
import Testing
@testable import AI_Hanlin

@Suite("Original user-operation continuation ownership")
struct RuntimeUserOperationTests {
    @Test func interruptionIsFirstCauseAndCallbacksMayReenterWithoutDeadlock() throws {
        let operation = RuntimeUserOperation()
        let observed = Observations()
        let token = operation.registerInterruption { reason in
            observed.append(reason)
            #expect(operation.snapshot.reason == reason)
        }
        operation.bindProducerCancellation { observed.append("producer cancelled") }
        operation.interrupt(reason: "system or native Cancel")
        operation.interrupt(reason: "must not overwrite")
        #expect(observed.values == ["system or native Cancel", "producer cancelled"])
        #expect(throws: RuntimeOperationInterruptionError.self) { try operation.markSucceeded() }
        operation.unregisterInterruption(token)
        _ = operation.registerInterruption { observed.append("late: " + $0) }
        #expect(observed.values.last == "late: system or native Cancel")
        operation.finish()
        #expect(operation.snapshot.finished && !operation.snapshot.succeeded)
    }

    @Test func actualProgressUsesJournalHighWaterMarksWithoutPollInflation() throws {
        let operation = RuntimeUserOperation()
        let first = UUID(), second = UUID()
        operation.recordStreamBytes(13)
        operation.recordJobOutput(id: first, stdout: 100, stderr: 20)
        for _ in 0..<100 { operation.recordJobOutput(id: first, stdout: 100, stderr: 20) }
        operation.recordJobOutput(id: first, stdout: 80, stderr: 10)
        operation.recordJobOutput(id: first, stdout: 150, stderr: 30)
        operation.recordJobOutput(id: second, stdout: 10, stderr: 5)
        #expect(operation.snapshot.outputBytes == 208)
        operation.recordJobOutput(id: UUID(), stdout: .max, stderr: 1)
        #expect(operation.snapshot.outputBytes == .max)
        try operation.markSucceeded()
        operation.finish()
        operation.interrupt(reason: "after completion")
        #expect(operation.snapshot.succeeded && operation.snapshot.reason == nil)
    }

    @Test @MainActor func producerOwnsOnlyItsOperationAndClearsTheCancellationCycle() async throws {
        var operation: RuntimeUserOperation? = RuntimeUserOperation()
        weak var weakOperation = operation
        let id = try #require(operation?.id)
        var producer: Task<Void, Never>? = RuntimeUserOperation.producerTask(operation: operation) {
            #expect(RuntimeUserOperation.current?.id == id)
            let explicitlyDetached = await Task.detached { RuntimeUserOperation.current?.id }.value
            #expect(explicitlyDetached == nil)
            try? RuntimeUserOperation.current?.markSucceeded()
            RuntimeUserOperation.current?.finish()
        }
        operation?.bindProducerCancellation { [producer] in producer?.cancel() }
        await producer?.value
        operation = nil
        producer = nil
        // Completed Task allocations may retain their locals until released;
        // there must not be a context -> Task -> context cycle.
        #expect(weakOperation == nil)
        #expect(RuntimeUserOperation.current == nil)
    }

    @Test func interruptedOriginalStreamNeverFinishesAsSuccessfulEOF() async throws {
        let operation = RuntimeUserOperation()
        let stream = RuntimeUserOperation.$current.withValue(operation) {
            AsyncThrowingStream<String, Error> { continuation in
                continuation.yield("already received")
                operation.interrupt(reason: "background continuation ended")
                RuntimeUserOperation.finishStream(continuation)
            }
        }
        var received: [String] = []
        do {
            for try await text in stream { received.append(text) }
            Issue.record("Interrupted stream incorrectly finished successfully")
        } catch let error as RuntimeOperationInterruptionError {
            #expect(error.operationID == operation.id)
        }
        #expect(received == ["already received"])
    }

    private final class Observations: @unchecked Sendable {
        private let lock = NSLock()
        private var storage: [String] = []
        var values: [String] { lock.withLock { storage } }
        func append(_ value: String) { lock.withLock { storage.append(value) } }
    }
}
