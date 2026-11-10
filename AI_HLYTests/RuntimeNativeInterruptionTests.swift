import Foundation
import Darwin
import Testing
@testable import AI_Hanlin

@MainActor
@Suite("Actual shared-engine operation interruption", .serialized)
struct RuntimeNativeInterruptionTests {
    @Test(.timeLimit(.minutes(2)))
    func actualPythonChildThreadsKeepTheirWorkspaceAndFullOutputUntilCompletion() async throws {
        let core = AppRuntimeCore.shared
        let workspace = try RuntimeFileLayout.default.workspace(client: .tools, identifier: "python-threads-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: workspace) }
        let source = #"""
import os, sys, threading, _thread, time, pathlib
workspace = os.getcwd()
def child(label, descendant):
    time.sleep(0.08)
    assert os.getcwd() == workspace
    assert os.environ['HANLIN_THREAD_OWNER_TEST'] == 'owned'
    assert not sys.stdout.closed
    print(label, flush=True)
    pathlib.Path(label).write_text('completed', encoding='utf-8')
    if descendant:
        _thread.start_new_thread(child, ('raw-descendant', False))
threading.Thread(target=child, args=('daemon-child', False), daemon=True).start()
_thread.start_new_thread(child, ('raw-child', True))
print('main-finished', flush=True)
"""#
        let result = try await core.python.execute(RuntimeExecutionRequest(
            source: source, workspace: workspace, environment: ["HANLIN_THREAD_OWNER_TEST": "owned"],
            limits: .init(timeout: .seconds(20))))
        #expect(result.exitCode == 0 && !result.wasCancelled && !result.didTimeOut)
        #expect(Set(result.stdout.split(separator: "\n").map(String.init)) ==
            Set(["main-finished", "daemon-child", "raw-child", "raw-descendant"]))
        for name in ["daemon-child", "raw-child", "raw-descendant"] {
            #expect(try String(contentsOf: workspace.appending(path: name), encoding: .utf8) == "completed")
        }
        // Execute a second actual job only after the first thread states have
        // drained. Its environment and artifacts must belong to the new scope.
        let next = try await core.python.execute(RuntimeExecutionRequest(
            source: "import os\nassert 'HANLIN_THREAD_OWNER_TEST' not in os.environ\nprint('next-job-owned')",
            workspace: workspace, limits: .init(timeout: .seconds(20))))
        #expect(next.exitCode == 0 && next.stdout.trimmingCharacters(in: .whitespacesAndNewlines) == "next-job-owned")
    }

    @Test(.timeLimit(.minutes(2)))
    func actualNodeInterruptionRetainsAuthenticatedJournalAndOutput() async throws {
        try await verify(kind: .node)
    }

    @Test(.timeLimit(.minutes(2)))
    func actualPythonInterruptionRetainsCooperativeNativeOutput() async throws {
        try await verify(kind: .localPython)
    }

    @Test(.timeLimit(.minutes(2)))
    func linkedShellCompletionCannotHideAnEarlierRootInterruption() async throws {
        try await verify(kind: .shell)
    }

    private func verify(kind: RuntimeKind) async throws {
        let core = AppRuntimeCore.shared
        let workspace = try RuntimeFileLayout.default.workspace(client: .tools, identifier: "interruption-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: workspace) }
        let operation = RuntimeUserOperation()
        let id = UUID()
        let reason = "Actual root continuation interrupted after native stdout"
        let shellWriter = kind == .shell ? try makeNativeInput(workspace: workspace, operation: operation) : nil
        defer { shellWriter?.cancel() }
        let reporter: RuntimeJobProgress.Reporter = { snapshot in
            if snapshot.executionID == id, snapshot.stdoutBytes > 0, !snapshot.state.isTerminal {
                operation.interrupt(reason: reason)
            }
        }
        let task = Task {
            try await RuntimeUserOperation.$current.withValue(operation) {
                try await RuntimeJobProgress.$reporter.withValue(reporter) {
                    switch kind {
                    case .node:
                        return try await core.node.executeJavaScript(RuntimeExecutionRequest(
                            id: id, source: "console.log('native started שלום'); await new Promise(() => setInterval(() => {}, 1000));",
                            workspace: workspace, limits: .init(timeout: .seconds(20))), moduleKind: "esm")
                    case .localPython:
                        return try await core.python.execute(RuntimeExecutionRequest(
                            id: id, source: "import time\nprint('native started שלום', flush=True)\nwhile True:\n    time.sleep(0.01)\n",
                            workspace: workspace, limits: .init(timeout: .seconds(20))))
                    case .shell:
                        return try await core.shell.execute(tokens: ["cat", "actual-native-input.fifo"],
                            workspace: workspace, environment: [:], allowNetwork: false, id: id)
                    default: throw RuntimeCoreError.invalidRequest("Unexpected test engine")
                    }
                }
            }
        }
        operation.bindProducerCancellation { task.cancel() }
        defer { task.cancel(); operation.finish() }
        do {
            _ = try await task.value
            Issue.record("Actual \(kind.rawValue) operation incorrectly reported success after interruption")
        } catch {
            #expect(operation.snapshot.reason == reason, "The actual job must produce stdout before the explicit interruption; an unrelated startup failure is insufficient: \(error)")
        }
        try await shellWriter?.value
        let deadline = ContinuousClock.now.advanced(by: .seconds(15))
        var journal: RuntimeJobSnapshot?
        repeat {
            journal = kind == .node
                ? try await core.node.existingExecution(id: id)
                : try await core.jobs.snapshot(id: id, kind: kind)
            if journal?.state.isTerminal == true { break }
            try #require(ContinuousClock.now < deadline, "The actual native cancellation never settled")
            try await Task.sleep(for: .milliseconds(50))
        } while true
        let saved = try #require(journal)
        #expect(saved.state == .interrupted && saved.interruptionReason == reason)
        #expect(saved.stdoutBytes > 0)
        let page = try await core.jobs.output(id: id, kind: kind, channel: "stdout", offset: 0, limit: 65_536)
        let bytes = try #require(page["base64"].flatMap { Data(base64Encoded: $0) })
        #expect(String(decoding: bytes, as: UTF8.self).contains("native started"))
        if kind == .shell {
            // Safe cooperative cancellation waits for the already running linked
            // C command. Keep its later bytes without relabelling it successful.
            #expect(String(decoding: bytes, as: UTF8.self).contains("native finished"))
            #expect(saved.result?.exitCode == 0)
        }
    }

    /// Actual linked BSD cat blocks on real native input. No unregistered sleep
    /// command, timer-based completion assumption or mocked C execution is used.
    private func makeNativeInput(workspace: URL, operation: RuntimeUserOperation) throws -> Task<Void, Error> {
        let fifo = workspace.appending(path: "actual-native-input.fifo")
        let created = fifo.path.withCString { mkfifo($0, mode_t(0o600)) }
        try #require(created == 0, "Creating the native FIFO failed: \(errno)")
        return Task.detached {
            let deadline = ContinuousClock.now.advanced(by: .seconds(15))
            var descriptor: Int32 = -1
            while descriptor < 0 {
                try Task.checkCancellation()
                descriptor = fifo.path.withCString { Darwin.open($0, O_WRONLY | O_NONBLOCK) }
                if descriptor < 0 {
                    let code = errno
                    try #require(code == ENXIO && ContinuousClock.now < deadline,
                        "The actual cat reader did not open its native input: \(code)")
                    try await Task.sleep(for: .milliseconds(10))
                }
            }
            let file = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
            defer { try? file.close() }
            try file.write(contentsOf: Data("native started\n".utf8))
            while operation.snapshot.reason == nil {
                try #require(ContinuousClock.now < deadline, "Actual native output never triggered interruption")
                try await Task.sleep(for: .milliseconds(10))
            }
            try file.write(contentsOf: Data("native finished\n".utf8))
        }
    }
}
