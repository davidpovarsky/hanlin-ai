import CryptoKit
import Foundation
import Testing
@testable import AI_Hanlin

@Suite("Actual original JavaScriptCore durable jobs", .serialized)
struct RuntimeJavaScriptCoreTests {
    @Test func largeOriginalSourceAndFullUnicodeOutputSurviveReopenWithoutReplay() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "jsc-full-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let layout = RuntimeFileLayout(root: root)
        let jobs = RuntimeJobStore(fileLayout: layout)
        let engine = JavaScriptCoreRuntimeService(fileLayout: layout, jobs: jobs)
        let nonce = UUID().uuidString
        let source = "/* while (true); for (;;) " + String(repeating: "x", count: 2 * 1_024 * 1_024) + " */\n" +
            "console.log('שלום🙂'.repeat(900001));console.error('\(nonce)');({nonce:'\(nonce)',arg:arguments[0],env:environment.HANLIN_TEST});"
        let request = RuntimeExecutionRequest(source: source, arguments: ["עברית"], workspace: root, environment: ["HANLIN_TEST": nonce], limits: .init(maximumOutputBytes: 64))
        let result = try await engine.execute(request)
        #expect(result.outputWasTruncated && result.exitCode == 0)
        #expect(result.value == .object(["nonce": .string(nonce), "arg": .string("עברית"), "env": .string(nonce)]))
        let expected = Data((String(repeating: "שלום🙂", count: 900001) + "\n").utf8)
        let artifact = try #require(result.outputFiles?["stdout"])
        #expect(artifact.bytes == Int64(expected.count) && artifact.bytes > 10 * 1_024 * 1_024)
        #expect(artifact.sha256 == SHA256.hash(data: expected).map { String(format: "%02x", $0) }.joined())
        let reopened = RuntimeJobStore(fileLayout: layout)
        var offset: Int64 = 0
        var retrieved = Data()
        while offset < artifact.bytes {
            let page = try await reopened.output(id: request.id, kind: .javaScriptCore, channel: "stdout", offset: offset, limit: 65_536)
            let bytes = try #require(page["base64"].flatMap { Data(base64Encoded: $0) })
            #expect(!bytes.isEmpty)
            retrieved.append(bytes)
            offset += Int64(bytes.count)
        }
        #expect(retrieved == expected)
        do {
            _ = try await engine.execute(.init(id: request.id, source: "console.log('MUST_NOT_REPLAY')", workspace: root))
            Issue.record("A completed JavaScriptCore ID was replayed")
        } catch is RuntimeCoreError {}
        #expect(try Data(contentsOf: URL(filePath: artifact.path)) == expected)
        let failed = try await engine.execute(.init(source: "console.log('kept');throw new Error('\(nonce)');", workspace: root))
        #expect(failed.exitCode == 1 && failed.stderr.contains(nonce))
        #expect(try await jobs.snapshot(id: failed.executionID, kind: .javaScriptCore)?.state == .failed)
    }

    @Test func explicitDeadlineFailsBeforeJavaScriptOrOutputFilesAreCreated() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "jsc-deadline-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let layout = RuntimeFileLayout(root: root)
        let engine = JavaScriptCoreRuntimeService(fileLayout: layout)
        let request = RuntimeExecutionRequest(source: "console.log('MUST_NOT_RUN')", workspace: root, limits: .init(timeout: .seconds(1)))
        do { _ = try await engine.execute(request); Issue.record("Unsupported JSC deadline was silently ignored") }
        catch let error as RuntimeCoreError { #expect(error.localizedDescription.contains("Node")) }
        #expect(!FileManager.default.fileExists(atPath: RuntimeJobStore(fileLayout: layout).directory(id: request.id, kind: .javaScriptCore).path))
    }

    @Test func cancelledQueuedJavaScriptCannotExecuteAfterTheActualRunningContextFinishes() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "jsc-queue-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let layout = RuntimeFileLayout(root: root)
        let jobs = RuntimeJobStore(fileLayout: layout)
        let engine = JavaScriptCoreRuntimeService(fileLayout: layout, jobs: jobs)
        let running = RuntimeExecutionRequest(source: "console.log('entered');const until=Date.now()+1500;while(Date.now()<until){};console.log('finished');", workspace: root)
        let first = Task { try await engine.execute(running) }
        try await waitForRunningOutput(jobs, id: running.id)
        let queued = RuntimeExecutionRequest(source: "console.log('MUST_NOT_RUN')", workspace: root)
        let second = Task { try await engine.execute(queued) }
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while try await jobs.snapshot(id: queued.id, kind: .javaScriptCore) == nil, ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(2)) }
        #expect(try await jobs.snapshot(id: queued.id, kind: .javaScriptCore)?.state == .queued)
        try await engine.cancel(id: queued.id)
        do { _ = try await second.value; Issue.record("Cancelled queued source executed") } catch is CancellationError {}
        _ = try await first.value
        _ = try await engine.execute(.init(source: "console.log('queue drained')", workspace: root))
        let saved = try await jobs.snapshot(id: queued.id, kind: .javaScriptCore)
        #expect(saved?.state == .cancelled && saved?.stdoutBytes == 0)
        #expect(!FileManager.default.fileExists(atPath: jobs.directory(id: queued.id, kind: .javaScriptCore).appending(path: "stdout.log").path))
    }

    @Test func actualRunningJavaScriptRetainsLateBytesAndRootInterruptionUntilNaturalReturn() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "jsc-interrupt-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let jobs = RuntimeJobStore(fileLayout: .init(root: root))
        let engine = JavaScriptCoreRuntimeService(fileLayout: .init(root: root), jobs: jobs)
        let owner = RuntimeUserOperation()
        let request = RuntimeExecutionRequest(source: "console.log('entered');const until=Date.now()+1500;while(Date.now()<until){};console.log('actual late bytes');", workspace: root)
        let task = Task {
            try await RuntimeUserOperation.$current.withValue(owner) { try await engine.execute(request) }
        }
        try await waitForRunningOutput(jobs, id: request.id)
        owner.interrupt(reason: "owner ended this operation")
        do { _ = try await task.value; Issue.record("Running JSC completion hid root interruption") }
        catch let error as RuntimeJobInterruptionError { #expect(error.reason == "owner ended this operation") }
        let record = try await jobs.snapshot(id: request.id, kind: .javaScriptCore)
        #expect(record?.state == .interrupted)
        let output = jobs.directory(id: request.id, kind: .javaScriptCore).appending(path: "stdout.log")
        #expect(try String(contentsOf: output, encoding: .utf8) == "entered\nactual late bytes\n")
        #expect(await engine.snapshot().activeExecutionCount == 0)
    }

    private func waitForRunningOutput(_ jobs: RuntimeJobStore, id: UUID) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while ContinuousClock.now < deadline {
            if let record = try await jobs.refresh(id: id, kind: .javaScriptCore), record.state == .running, record.stdoutBytes > 0 { return }
            try await Task.sleep(for: .milliseconds(2))
        }
        throw RuntimeCoreError.runtimeFailure("The actual JSC program never produced its entry bytes.")
    }
}
