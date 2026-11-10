import CryptoKit
import SwiftData
import Testing
@testable import AI_Hanlin

@MainActor
@Suite("Runtime autonomy V3 persistence", .serialized)
struct RuntimeAutonomyV3Tests {
    @Test(.timeLimit(.minutes(1)))
    func cancellingQueuedPythonNeverExecutesItsSourceAfterTheRunningJobFinishes() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "python-queue-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let layout = RuntimeFileLayout(root: root)
        let jobs = RuntimeJobStore(fileLayout: layout)
        let python = PythonRuntimeService(fileLayout: layout, jobs: jobs)
        let workspace = try layout.workspace(client: .tools, identifier: "queue-proof")
        let started = workspace.appending(path: "first-started")
        let release = workspace.appending(path: "release")
        let forbidden = workspace.appending(path: "must-not-run")
        // This fixture watchdog only prevents a broken test from leaving native
        // execution blocked. Production requests still have no default deadline.
        let firstRequest = RuntimeExecutionRequest(source: """
        import pathlib, time
        pathlib.Path('first-started').touch()
        end = time.monotonic() + 20
        while not pathlib.Path('release').exists() and time.monotonic() < end:
            time.sleep(0.01)
        """, workspace: workspace)
        let first = Task { try await python.execute(firstRequest) }
        defer { try? Data().write(to: release); first.cancel() }
        let firstDeadline = ContinuousClock.now + .seconds(5)
        while !FileManager.default.fileExists(atPath: started.path), ContinuousClock.now < firstDeadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(FileManager.default.fileExists(atPath: started.path))
        let secondRequest = RuntimeExecutionRequest(source: "from pathlib import Path; Path('must-not-run').touch()", workspace: workspace)
        let second = Task { try await python.execute(secondRequest) }
        let queuedDeadline = ContinuousClock.now + .seconds(5)
        while try await jobs.snapshot(id: secondRequest.id, kind: .localPython) == nil, ContinuousClock.now < queuedDeadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        second.cancel()
        do { _ = try await second.value; Issue.record("Queued Python returned success after cancellation") }
        catch is CancellationError { }
        let cancelled = try await jobs.snapshot(id: secondRequest.id, kind: .localPython)
        #expect(cancelled?.state == .cancelled && cancelled?.cancellationRequested == true)
        #expect(try await jobs.snapshot(id: firstRequest.id, kind: .localPython)?.state == .running)
        #expect(!FileManager.default.fileExists(atPath: forbidden.path))
        let empty = try await jobs.output(id: secondRequest.id, kind: .localPython, channel: "stdout", offset: 0, limit: 1024)
        #expect(empty["totalBytes"] == "0" && empty["base64"] == "")
        try Data().write(to: release)
        #expect(try await first.value.exitCode == 0)
        // The queue has advanced; a fresh job proves the cancelled work item was skipped.
        let third = try await python.execute(RuntimeExecutionRequest(source: "print('queue-drained')", workspace: workspace))
        #expect(third.exitCode == 0 && third.stdout.contains("queue-drained"))
        #expect(!FileManager.default.fileExists(atPath: forbidden.path))
    }

    @MainActor private final class JobCapture { var id: UUID? }

    @Test(.timeLimit(.minutes(1)))
    func cancellingShellWhileThePythonDirectoryLockIsBusyNeverRunsTheCommandLater() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "shell-queue-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let layout = RuntimeFileLayout(root: root)
        let jobs = RuntimeJobStore(fileLayout: layout)
        let python = PythonRuntimeService(fileLayout: layout, jobs: jobs)
        let shell = ShellRuntimeService(fileLayout: layout, jobs: jobs)
        _ = try await shell.healthCheck()
        let workspace = try layout.workspace(client: .tools, identifier: "cross-engine-queue")
        let started = workspace.appending(path: "python-started")
        let release = workspace.appending(path: "release")
        let forbidden = workspace.appending(path: "must-not-run")
        let firstRequest = RuntimeExecutionRequest(source: """
        import pathlib, time
        pathlib.Path('python-started').touch()
        end = time.monotonic() + 20
        while not pathlib.Path('release').exists() and time.monotonic() < end:
            time.sleep(0.01)
        """, workspace: workspace)
        let first = Task { try await python.execute(firstRequest) }
        defer { try? Data().write(to: release); first.cancel() }
        let deadline = ContinuousClock.now + .seconds(5)
        while !FileManager.default.fileExists(atPath: started.path), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(FileManager.default.fileExists(atPath: started.path))
        let capture = JobCapture()
        let second = Task {
            try await RuntimeJobProgress.$reporter.withValue({ record in capture.id = record.executionID }) {
                try await shell.execute(tokens: ["touch", "must-not-run"], workspace: workspace, environment: [:], allowNetwork: false)
            }
        }
        let queueDeadline = ContinuousClock.now + .seconds(5)
        while capture.id == nil, ContinuousClock.now < queueDeadline { try await Task.sleep(for: .milliseconds(10)) }
        let id = try #require(capture.id)
        second.cancel()
        do { _ = try await second.value; Issue.record("Queued Shell command returned success after cancellation") }
        catch is CancellationError { }
        #expect(try await jobs.snapshot(id: id, kind: .shell)?.state == .cancelled)
        #expect(try await jobs.snapshot(id: firstRequest.id, kind: .localPython)?.state == .running)
        try Data().write(to: release)
        #expect(try await first.value.exitCode == 0)
        _ = try await shell.execute(tokens: ["pwd"], workspace: workspace, environment: [:], allowNetwork: false)
        #expect(!FileManager.default.fileExists(atPath: forbidden.path))
    }

    @Test func actualEmbeddedNodeExecutesThePinnedPortableShellWithoutJITOrAnOSSubprocess() async throws {
        let workspace = try RuntimeFileLayout.default.workspace(client: .tools, identifier: "portable-shell-\(UUID().uuidString)")
        let result = try await AppRuntimeCore.shared.node.executePortableShell(RuntimeExecutionRequest(source: """
        NAME='שלום'; echo "$NAME" > native-yarn.txt
        echo native-yarn-error 1>&2
        false || echo ACTUAL_PORTABLE_SHELL_COMPLETE
        """, workspace: workspace))
        #expect(result.exitCode == 0)
        #expect(result.stdout.contains("ACTUAL_PORTABLE_SHELL_COMPLETE"))
        #expect(result.stderr.contains("native-yarn-error"))
        #expect(try String(contentsOf: workspace.appending(path: "native-yarn.txt"), encoding: .utf8) == "שלום\n")
        #expect(result.outputFiles?["stdout"] != nil)
    }

    @Test func linkedShellRetainsFullOutputBeyondThePreviewAndReopensLosslessPages() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "shell-full-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let layout = RuntimeFileLayout(root: root)
        let jobs = RuntimeJobStore(fileLayout: layout)
        let shell = ShellRuntimeService(fileLayout: layout, jobs: jobs)
        let workspace = try layout.workspace(client: .tools, identifier: "full-output")
        let payload = Data(String(repeating: "שלום 👨‍👩‍👧‍👦\n", count: 400_000).utf8)
        #expect(payload.count > 10 * 1024 * 1024)
        try payload.write(to: workspace.appending(path: "input.txt"))
        let result = try await shell.execute(tokens: ["cat", "input.txt"], workspace: workspace,
            environment: [:], allowNetwork: false, limits: .init(maximumOutputBytes: 17))
        #expect(result.exitCode == 0 && result.outputWasTruncated)
        #expect(result.stdout.utf8.count <= 17 && !result.stdout.contains("�"))
        let artifact = try #require(result.outputFiles?["stdout"])
        #expect(artifact.bytes == Int64(payload.count))
        #expect(artifact.sha256 == SHA256.hash(data: payload).map { String(format: "%02x", $0) }.joined())
        let reopened = RuntimeJobStore(fileLayout: layout)
        try await reopened.recoverInterrupted(.shell)
        #expect(try await reopened.snapshot(id: result.executionID, kind: .shell)?.state == .completed)
        var restored = Data()
        var offset: Int64 = 0
        while true {
            let page = try await reopened.output(id: result.executionID, kind: .shell, channel: "stdout", offset: offset, limit: 65533)
            restored.append(try #require(Data(base64Encoded: try #require(page["base64"]))))
            if page["hasMore"] == "false" { break }
            offset = try #require(Int64(try #require(page["nextOffset"])))
        }
        #expect(restored == payload)
    }

    @Test func linkedShellActuallyPipesAndRedirectsWithinItsWorkspace() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "shell-pipe-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let layout = RuntimeFileLayout(root: root)
        let shell = ShellRuntimeService(fileLayout: layout)
        let workspace = try layout.workspace(client: .tools, identifier: "pipe-proof")
        let text = "שלום\nworld\n"
        try Data(text.utf8).write(to: workspace.appending(path: "input.txt"))
        let result = try await shell.execute(command: "cat input.txt | wc -c > count.txt", workspace: workspace,
            environment: [:], allowNetwork: false)
        #expect(result.exitCode == 0)
        let count = try String(contentsOf: workspace.appending(path: "count.txt"), encoding: .utf8)
        #expect(Int(count.trimmingCharacters(in: .whitespacesAndNewlines)) == text.utf8.count)
        #expect(result.outputFiles?["stdout"] != nil && result.outputFiles?["stderr"] != nil)
    }

    @Test func linkedShellActuallyAcceptsMoreThan127Arguments() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "shell-argv-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let layout = RuntimeFileLayout(root: root)
        let workspace = try layout.workspace(client: .tools, identifier: "argv-proof")
        try Data("שלום\n".utf8).write(to: workspace.appending(path: "one.txt"))
        let shell = ShellRuntimeService(fileLayout: layout)
        let result = try await shell.execute(tokens: ["cat"] + Array(repeating: "one.txt", count: 256),
            workspace: workspace, environment: [:], allowNetwork: false)
        #expect(result.exitCode == 0)
        #expect(result.stdout == String(repeating: "שלום\n", count: 256))
        #expect(!result.outputWasTruncated)
    }

    @Test func embeddedPythonActuallyDownloadsVerifiesInstallsAndImportsAPureWheel() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "python-pypi-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let layout = RuntimeFileLayout(root: root)
        let python = PythonRuntimeService(fileLayout: layout)
        let manager = PythonPackageManager(fileLayout: layout, python: python)
        let record = try await manager.install(name: "six", version: "1.17.0")
        #expect(record.name == "six" && record.version == "1.17.0")
        #expect(record.sha256.count == 64)
        let probe = try await manager.probe(record)
        #expect(probe.exitCode == 0)
        #expect(probe.stdout.contains("1.17.0"))
        let tlsWorkspace = try layout.workspace(client: .tools, identifier: "tls-policy")
        let tls = try await python.execute(RuntimeExecutionRequest(source: """
        import ssl
        context = ssl.create_default_context()
        assert context.verify_mode == ssl.CERT_REQUIRED
        assert context.check_hostname
        assert context.cert_store_stats()['x509_ca'] > 0
        print('TLS_VERIFICATION_REQUIRED')
        """, workspace: tlsWorkspace))
        #expect(tls.exitCode == 0 && tls.stdout.contains("TLS_VERIFICATION_REQUIRED"))
        #expect(!probe.didTimeOut && !probe.wasCancelled)
        print("EMBEDDED_PYPI_INSTALL six=\(record.version) sha256=\(record.sha256) job=\(probe.executionID)")
    }

    @Test func bundledNativePythonExtensionInstallsAndExecutesARealNonce() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "native-python-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let layout = RuntimeFileLayout(root: root)
        let python = PythonRuntimeService(fileLayout: layout)
        let manager = PythonPackageManager(fileLayout: layout, python: python)
        let record = try await manager.install(name: "hanlin-native")
        #expect(record.importName == "hanlin_native")
        let nonce = UUID().uuidString
        let quoted = String(decoding: try JSONEncoder().encode(nonce), as: UTF8.self)
        let workspace = try layout.workspace(client: .tools, identifier: "native-proof")
        let result = try await python.execute(RuntimeExecutionRequest(source: """
        import hanlin_native, sys
        try:
            __hanlin_result__ = hanlin_native.challenge(\(quoted))
            print(hanlin_native.registry())
        finally:
            sys.modules.pop('hanlin_native', None)
        """, workspace: workspace))
        #expect(result.exitCode == 0)
        guard case .object(let value) = result.value else { Issue.record("Native extension returned no structured result: \(result.stderr)"); return }
        #expect(value["nonce"] == .string(nonce))
        #expect(value["engine"] == .string("cpython-native-extension"))
        #expect(value["linkage"] == .string("signed-app-builtin"))
    }

    @Test(.timeLimit(.minutes(10)))
    func embeddedNodeAndPythonActuallyRunBeyondThreeHundredSeconds() async throws {
        let layout = RuntimeFileLayout.default
        let nodeWorkspace = try layout.workspace(client: .tools, identifier: "long-node-\(UUID().uuidString)")
        let pythonWorkspace = try layout.workspace(client: .tools, identifier: "long-python-\(UUID().uuidString)")
        let start = ContinuousClock.now
        async let node = AppRuntimeCore.shared.node.executeJavaScript(RuntimeExecutionRequest(source: """
        console.log('EMBEDDED_NODE_LONG_START');
        await new Promise(resolve => setTimeout(resolve, 305000));
        console.log('EMBEDDED_NODE_LONG_COMPLETE');
        export default 305;
        """, workspace: nodeWorkspace), moduleKind: "esm")
        async let python = AppRuntimeCore.shared.python.execute(RuntimeExecutionRequest(source: """
        import time
        print('EMBEDDED_PYTHON_LONG_START', flush=True)
        time.sleep(305)
        print('EMBEDDED_PYTHON_LONG_COMPLETE', flush=True)
        __hanlin_result__ = 305
        """, workspace: pythonWorkspace))
        let (nodeResult, pythonResult) = try await (node, python)
        #expect(start.duration(to: .now) >= .seconds(300))
        for result in [nodeResult, pythonResult] {
            #expect(result.exitCode == 0)
            #expect(!result.didTimeOut && !result.wasCancelled)
            #expect(result.durationMilliseconds >= 300_000)
            #expect(result.value == .number(305))
            #expect(result.outputFiles?["stdout"]?.bytes ?? 0 > 0)
        }
        #expect(nodeResult.stdout.contains("EMBEDDED_NODE_LONG_COMPLETE"))
        #expect(pythonResult.stdout.contains("EMBEDDED_PYTHON_LONG_COMPLETE"))
        print("EMBEDDED_LONG_JOBS node=\(nodeResult.executionID) ms=\(nodeResult.durationMilliseconds) python=\(pythonResult.executionID) ms=\(pythonResult.durationMilliseconds)")
    }
    @Test func retainedNativePythonCancellationCallbackRemainsValidAfterItsJobIsReleased() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "python-capsule-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let layout = RuntimeFileLayout(root: root)
        let python = PythonRuntimeService(fileLayout: layout)
        let workspace = try layout.workspace(client: .tools, identifier: "capsule-proof")
        let key = "__hanlin_cancel_probe_" + UUID().uuidString.replacingOccurrences(of: "-", with: "_")
        let literal = String(decoding: try JSONEncoder().encode(key), as: UTF8.self)
        let first = try await python.execute(RuntimeExecutionRequest(source: """
        import builtins, inspect, sys
        callback = inspect.getclosurevars(sys.gettrace()).nonlocals['cancelled']
        setattr(builtins, \(literal), callback)
        """, workspace: workspace))
        #expect(first.exitCode == 0)
        // execute() has now unregistered the first job's native cancellation ID.
        let second = try await python.execute(RuntimeExecutionRequest(source: """
        import builtins, gc
        try:
            gc.collect()
            callback = getattr(builtins, \(literal))
            assert all(callback() is False for _ in range(1024))
            print('RETAINED_NATIVE_CANCELLATION_CONTEXT_VALID')
        finally:
            if hasattr(builtins, \(literal)):
                delattr(builtins, \(literal))
        """, workspace: workspace))
        #expect(second.exitCode == 0)
        #expect(second.stdout.contains("RETAINED_NATIVE_CANCELLATION_CONTEXT_VALID"))
    }

    @Test func runtimeOutputKeepsRetrievalMetadataForTheAgentAndReadableContentForTheUser() throws {
        let id = UUID()
        let execution = RuntimeExecutionResult(executionID: id, stdout: "42\n", stderr: "", value: nil,
            exitCode: 0, durationMilliseconds: 3, didTimeOut: false, wasCancelled: false, outputWasTruncated: false,
            outputFiles: ["stdout": .init(path: "/private/job/stdout.log", bytes: 3, sha256: String(repeating: "a", count: 64))])
        let result = RuntimeToolSupport.result(execution, title: "Local Python", systemImage: "terminal", runtimeKind: .localPython, argumentKeys: ["source"])
        #expect(result.modelText.contains(id.uuidString) && result.modelText.contains("get_runtime_job"))
        #expect(result.modelText.contains("SHA256"))
        #expect(result.userText == "42\n")
        #expect(result.uiBlocks.first?.body == "42\n")
        #expect(result.uiBlocks.first?.subtitle == nil)
    }

    @Test func defaultSchemaExposureDoesNotHideToolsPastOldBudgets() {
        let aliases = (0..<64).map { "tool_\($0)" }
        let sizes = Dictionary(uniqueKeysWithValues: aliases.map { ($0, 1024) })
        let decision = AssistantToolExposurePlanner().plan(candidateAliases: aliases, schemaSizes: sizes)
        #expect(decision.exposedAliases == aliases)
        #expect(decision.deferredAliases.isEmpty)
        #expect(decision.totalExposedBytes == 65536)
    }

    @Test func fullResultsExceedOldCountAndByteCapsAndSurviveReopen() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ToolResultStore(directory: directory)
        let payload = String(repeating: "שלום 👨‍👩‍👧‍👦\n", count: 8192)
        let digest = SHA256.hash(data: Data(payload.utf8))
        var references: [String] = []
        for _ in 0..<64 { references.append(try #require(store.store(payload))) }
        #expect(store.currentTotalBytes > 10 * 1024 * 1024)
        let reopened = ToolResultStore(directory: directory)
        for reference in references {
            let full = try #require(reopened.fullPayload(for: reference))
            #expect(SHA256.hash(data: Data(full.utf8)) == digest)
        }
        let reference = try #require(references.first)
        var reconstructed = ""
        var offset = 0
        while true {
            let slice = try #require(reopened.read(reference: reference, offset: offset, limit: 4093))
            reconstructed += slice.chunk
            if !slice.hasMore { break }
            offset = slice.offset + slice.sliceLength
        }
        #expect(reconstructed == payload)
        #expect(reopened.read(reference: "../../private") == nil)
    }

    @Test func finishingRunKeepsHistoryReferencesButNotExposedSchemas() throws {
        let session = AssistantCapabilitySession()
        defer { session.resultStore.clear() }
        session.exposeTools(aliases: ["private_run_tool"])
        let reference = try #require(session.resultStore.store("saved result שלום"))
        session.finishRun()
        session.reset()
        #expect(!session.isToolExposed("private_run_tool"))
        #expect(session.resultStore.fullPayload(for: reference) == "saved result שלום")
    }

    @Test func capabilityReportNeverPromotesStoppedOrFailedEnginesToReady() throws {
        var failed = RuntimeSnapshot.stopped(.node)
        failed.state = .failed
        failed.lastErrorCode = "startup_failed"
        let report = RuntimeCapabilityContract(snapshots: [.stopped(.localPython), failed])
        let encoded = try JSONEncoder().encode(report)
        let decoded = try JSONDecoder().decode(RuntimeCapabilityContract.self, from: encoded)
        #expect(decoded.snapshots[0].state == .stopped)
        #expect(decoded.snapshots[0].version == nil)
        #expect(decoded.snapshots[1].state == .failed)
        #expect(decoded.snapshots[1].lastErrorCode == "startup_failed")
    }
    @Test func subsequentTurnsCanReadOwnChatResultsWithoutLeakingOtherChats() throws {
        let chatID = UUID().uuidString
        let first = AssistantCapabilitySession(chatID: chatID)
        defer { first.resultStore.clear() }
        let reference = try #require(first.resultStore.store("persisted across turns שלום"))
        first.exposeTools(aliases: ["run_scoped_only"])
        first.finishRun()
        let second = AssistantCapabilitySession(chatID: chatID)
        #expect(second.resultStore.fullPayload(for: reference) == "persisted across turns שלום")
        #expect(!second.isToolExposed("run_scoped_only"))
        let unrelated = AssistantCapabilitySession(chatID: UUID().uuidString)
        defer { unrelated.resultStore.clear() }
        #expect(unrelated.resultStore.fullPayload(for: reference) == nil)
        let temporary = AssistantCapabilitySession(chatID: chatID, isTemporaryChat: true)
        defer { temporary.resultStore.clear() }
        #expect(temporary.resultStore.fullPayload(for: reference) == nil)
    }

    @Test func journalRetainsCompletedJobsAndMarksUnfinishedOnRestart() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let layout = RuntimeFileLayout(root: root)
        let jobs = RuntimeJobStore(fileLayout: layout)
        let id = UUID()
        _ = try await jobs.create(id: id, kind: .localPython)
        try await jobs.markRunning(id: id, kind: .localPython)
        let output = "שלום 👋🏽"
        try Data(output.utf8).write(to: jobs.directory(id: id, kind: .localPython).appending(path: "stdout.log"))
        let progress = try await jobs.refresh(id: id, kind: .localPython)
        #expect(progress?.state == .running)
        #expect(progress?.stdoutBytes == Int64(output.utf8.count))
        let result = RuntimeExecutionResult(executionID: id, stdout: output, stderr: "", value: nil,
            exitCode: 0, durationMilliseconds: 1, didTimeOut: false, wasCancelled: false, outputWasTruncated: false)
        try await jobs.complete(result, kind: .localPython)
        let unfinished = UUID()
        _ = try await jobs.create(id: unfinished, kind: .localPython)
        let reopened = RuntimeJobStore(fileLayout: layout)
        try await reopened.recoverInterrupted(.localPython)
        let preserved = try await reopened.snapshot(id: id, kind: .localPython)
        let interrupted = try await reopened.snapshot(id: unfinished, kind: .localPython)
        #expect(preserved?.state == .completed && preserved?.result?.stdout == output)
        #expect(interrupted?.state == .interrupted)
        #expect(RuntimeExecutionLimits().timeout == nil)
        #expect(try RuntimeExecutionLimits(timeout: .seconds(600)).timeoutMilliseconds() == 600_000)
    }

}
