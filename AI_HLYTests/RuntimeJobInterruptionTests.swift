import Foundation
import Testing
@testable import AI_Hanlin

@Suite("Runtime interruption journal ownership")
struct RuntimeJobInterruptionTests {
    @Test func nativeCompletionReadsRootInterruptionEvenBeforeItsAsyncNotification() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "root-interruption-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = RuntimeJobStore(fileLayout: RuntimeFileLayout(root: root))
        let operation = RuntimeUserOperation()
        let id = UUID()
        _ = try await store.create(id: id, kind: .shell)
        try await RuntimeUserOperation.$current.withValue(operation) {
            operation.interrupt(reason: "system ended continuation")
            let result = RuntimeExecutionResult(executionID: id, stdout: "late native bytes", stderr: "", value: nil,
                exitCode: 0, durationMilliseconds: 1, didTimeOut: false, wasCancelled: false, outputWasTruncated: false)
            do {
                try await store.complete(result, kind: .shell)
                Issue.record("Native completion overtook the queued interruption notification")
            } catch let error as RuntimeJobInterruptionError {
                #expect(error.reason == "system ended continuation")
            }
        }
        let saved = try await store.snapshot(id: id, kind: .shell)
        #expect(saved?.state == .interrupted && saved?.result?.stdout == "late native bytes")
    }

    @Test func lateNativeCompletionPreservesSystemInterruptionAndPartialOutput() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "native-interruption-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let layout = RuntimeFileLayout(root: root)
        let store = RuntimeJobStore(fileLayout: layout)
        let id = UUID()
        _ = try await store.create(id: id, kind: .localPython)
        try await store.markRunning(id: id, kind: .localPython)
        let bytes = Data(String(repeating: "שלום🙂", count: 20_000).utf8)
        let file = store.directory(id: id, kind: .localPython).appending(path: "stdout.log")
        try bytes.write(to: file)
        let reason = "The system ended the background continuation."
        try await store.requestInterruption(id: id, kind: .localPython, reason: reason)
        let result = RuntimeExecutionResult(executionID: id, stdout: "retained native preview", stderr: "", value: .string("late value"),
            exitCode: 0, durationMilliseconds: 100, didTimeOut: false, wasCancelled: false, outputWasTruncated: true)
        do {
            try await store.complete(result, kind: .localPython)
            Issue.record("A late native success hid the system interruption")
        } catch let error as RuntimeJobInterruptionError {
            #expect(error.executionID == id && error.reason == reason)
        }
        try await store.fail(id: id, kind: .localPython, error: CancellationError())
        let reopened = RuntimeJobStore(fileLayout: layout)
        try await reopened.recoverInterrupted(.localPython)
        let savedValue = try await reopened.snapshot(id: id, kind: .localPython)
        let saved = try #require(savedValue)
        #expect(saved.state == .interrupted && saved.interruptionReason == reason)
        #expect(saved.error == reason)
        #expect(saved.result?.value == .string("late value"))
        #expect(saved.stdoutBytes == bytes.count)
        #expect(try Data(contentsOf: file) == bytes)
        let page = try await reopened.output(id: id, kind: .localPython, channel: "stdout", offset: 3, limit: 1024)
        #expect(page["base64"].flatMap { Data(base64Encoded: $0) } == bytes.subdata(in: 3..<1027))
    }

    @Test func completedJobsRejectLateFailureAndInterruptionReclassification() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "terminal-ownership-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = RuntimeJobStore(fileLayout: RuntimeFileLayout(root: root))
        let id = UUID()
        _ = try await store.create(id: id, kind: .shell)
        let result = RuntimeExecutionResult(executionID: id, stdout: "original complete value", stderr: "", value: nil,
            exitCode: 0, durationMilliseconds: 1, didTimeOut: false, wasCancelled: false, outputWasTruncated: false)
        try await store.complete(result, kind: .shell)
        try await store.requestInterruption(id: id, kind: .shell, reason: "Too late")
        try await store.fail(id: id, kind: .shell, error: CancellationError())
        let savedValue = try await store.snapshot(id: id, kind: .shell)
        let saved = try #require(savedValue)
        #expect(saved.state == .completed && saved.interruptionReason == nil)
        #expect(saved.result?.stdout == "original complete value")
    }
}
