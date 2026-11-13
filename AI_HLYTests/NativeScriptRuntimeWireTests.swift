import CryptoKit
import Foundation
import HanlinNativeScriptCoreSupport
import HanlinNativeScriptRuntime
import HanlinPlatformContracts
import Testing
@testable import AI_Hanlin

@MainActor
extension HanlinUnifiedHostServicesE2ETests {
    // Share the existing suite's .serialized scope with its legacy NS tests.
    // Separate top-level suites can otherwise reset the process-wide NS VM or
    // provider registry while another suite has an actual callback in flight.
    @Test func expoStructuredInvokeUsesTheSharedReceiptBoundaryAndRejectsUnknownKinds() async throws {
        let adapter = ExpoHostServicesAdapter(appID: try HanlinAppID(validating: "expo-wire-\(UUID().uuidString.lowercased())"), grantedCapabilities: [])
        for (kind, source) in [("node", "console.log('EXPO_WIRE_NODE')"),
            ("typeScript", "const n: number = 42; console.log(n)"), ("localPython", "print('EXPO_WIRE_PY')"),
            ("javaScriptCore", "21 * 2"), ("shell", "pwd")] {
            let payload = String(decoding: try JSONSerialization.data(withJSONObject: ["kind": kind, "source": source]), as: UTF8.self)
            let json = try await adapter.invoke(operation: "runtime.execute", payloadJSON: payload)
            let result = try JSONDecoder().decode(RuntimeExecutionResult.self, from: Data(json.utf8))
            #expect(result.exitCode == 0 && !result.wasCancelled && !result.didTimeOut)
            if kind == "javaScriptCore" { #expect(result.value == .number(42)) }
            else { #expect(!result.stdout.isEmpty) }
        }
        await #expect(throws: (any Error).self) {
            _ = try await adapter.invoke(operation: "runtime.execute", payloadJSON: #"{"kind":"unknown","source":"21 * 2"}"#)
        }
    }

    @Test func actualNativeScriptImportsTheGeneratedTypedFacadeAndCallsEveryEngine() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "ns-wire-vm-\(UUID().uuidString.lowercased())")
        let app = directory.appending(path: "app", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: app, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data(#"{"name":"ns-wire-vm","main":"bundle.mjs","hanlinRuntime":"hanlin-nativescript","dependencies":{"@nativescript/core":"9.1.0"}}"#.utf8).write(to: app.appending(path: "package.json"))
        let key = "HanlinNativeWire_" + UUID().uuidString
        UserDefaults.standard.removeObject(forKey: key)
        defer { UserDefaults.standard.removeObject(forKey: key) }
        let script = """
        import { createHostServices } from '@hanlin/host-services';
        const host = createHostServices();
        (async () => {
          const cases = [['node', "console.log('NS_VM_NODE')"],
            ['typeScript', "const n: number = 42; console.log('NS_VM_TS_' + n)"],
            ['localPython', "print('NS_VM_PYTHON')"], ['javaScriptCore', '21 * 2'], ['shell', 'pwd']];
          const results = [];
          for (const [kind, source] of cases) results.push(await host.executeRuntime(kind, source));
          NSUserDefaults.standardUserDefaults.setObjectForKey(JSON.stringify({results}), '\(key)');
        })().catch(error => {
          NSUserDefaults.standardUserDefaults.setObjectForKey(JSON.stringify({error: String(error)}), '\(key)');
        });
        """
        try Data(script.utf8).write(to: app.appending(path: "bundle.mjs"))
        let adapter = NativeScriptHostServicesAdapter(appID: try HanlinAppID(validating: "ns-vm-\(UUID().uuidString.lowercased())"), grantedCapabilities: [], canPresentUI: false)
        HanlinNativeServicesBridge.register(adapter, forSessionID: adapter.sessionID)
        defer { HanlinNativeServicesBridge.unregisterProvider(forSessionID: adapter.sessionID) }
        let session = try HanlinNativeScriptSession(applicationRoot: app, sessionID: adapter.sessionID)
        defer { session.shutdown() }
        try session.start()
        let deadline = ContinuousClock.now + .seconds(120)
        while UserDefaults.standard.string(forKey: key) == nil {
            try #require(ContinuousClock.now < deadline, "Actual NativeScript did not deliver facade receipts")
            try await Task.sleep(for: .milliseconds(25))
        }
        struct Response: Decodable { let results: [RuntimeExecutionResult]?; let error: String? }
        let json = try #require(UserDefaults.standard.string(forKey: key))
        let response = try JSONDecoder().decode(Response.self, from: Data(json.utf8))
        #expect(response.error == nil, "NativeScript metadata/module error: \(response.error ?? "none")")
        let results = try #require(response.results)
        #expect(results.count == 5)
        for result in results { #expect(result.exitCode == 0 && !result.wasCancelled && !result.didTimeOut) }
        #expect(results[0].stdout.contains("NS_VM_NODE"))
        #expect(results[1].stdout.contains("NS_VM_TS_42"))
        #expect(results[2].stdout.contains("NS_VM_PYTHON"))
        #expect(results[3].value == .number(42))
        #expect(results[4].stdout.hasPrefix("/"))
    }

    @Test func boundObjectiveCBridgeReturnsActualReceiptsFromAllFiveEngines() async throws {
        let adapter = NativeScriptHostServicesAdapter(appID: try HanlinAppID(validating: "ns-wire-\(UUID().uuidString.lowercased())"), grantedCapabilities: [])
        let bridge = try bind(adapter)
        defer { HanlinNativeServicesBridge.unregisterProvider(forSessionID: adapter.sessionID) }
        let cases: [(RuntimeKind, String, String)] = [
            (.node, "console.log('NS_NODE_ACTUAL')", "NS_NODE_ACTUAL"),
            (.typeScript, "const n: number = 42; console.log('NS_TS_' + n)", "NS_TS_42"),
            (.localPython, "print('NS_PY_ACTUAL')", "NS_PY_ACTUAL"),
            (.javaScriptCore, "({answer: 42, text: 'שלום🙂'})", ""),
            (.shell, "pwd", "/")
        ]
        for (kind, source, expected) in cases {
            let result = try await execute(bridge, kind: kind.rawValue, source: source)
            #expect(!result.wasCancelled && !result.didTimeOut && result.exitCode == 0)
            #expect(result.stdout.contains(expected))
            if kind == .javaScriptCore {
                #expect(result.value == .object(["answer": .number(42), "text": .string("שלום🙂")]))
            }
        }
        let result = try await execute(bridge, kind: "localPython",
            source: "import sys; print('VISIBLE_STDOUT'); sys.stderr.write('EXACT_STDERR'); sys.exit(23)")
        #expect(result.exitCode == 23 && result.stderr == "EXACT_STDERR" && result.stdout.contains("VISIBLE_STDOUT"))
        #expect(!result.wasCancelled && !result.didTimeOut)
    }

    @Test func fullReceiptsPreserveArgumentsEnvironmentAndOutputArtifacts() async throws {
        let adapter = NativeScriptHostServicesAdapter(appID: try HanlinAppID(validating: "ns-options-\(UUID().uuidString.lowercased())"), grantedCapabilities: [])
        let bridge = try bind(adapter)
        defer { HanlinNativeServicesBridge.unregisterProvider(forSessionID: adapter.sessionID) }
        let payload: [String: Any] = ["kind": "localPython", "source": "import sys,os; print(sys.argv[-1] + ':' + os.environ['NS_WIRE_ENV']); print('שלום🙂' * 4000)",
            "arguments": ["WIRE_ARG"], "environment": ["NS_WIRE_ENV": "WIRE_ENV"],
            "limits": ["maximumOutputBytes": 32]]
        let result = try await execute(bridge, payload: payload)
        #expect(result.exitCode == 0 && result.outputWasTruncated)
        let artifact = try #require(result.outputFiles?["stdout"])
        let bytes = try Data(contentsOf: URL(filePath: artifact.path))
        #expect(Int64(bytes.count) == artifact.bytes)
        #expect(SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined() == artifact.sha256)
        let full = String(decoding: bytes, as: UTF8.self)
        #expect(full.hasPrefix("WIRE_ARG:WIRE_ENV\n") && full.contains(String(repeating: "שלום🙂", count: 4000)))
    }

    @Test func invalidKindsAndInvalidatedSessionsFailBeforeExecution() async throws {
        let adapter = NativeScriptHostServicesAdapter(appID: try HanlinAppID(validating: "ns-invalid-\(UUID().uuidString.lowercased())"), grantedCapabilities: [])
        let bridge = try bind(adapter)
        defer { HanlinNativeServicesBridge.unregisterProvider(forSessionID: adapter.sessionID) }
        for payload: [String: Any] in [
            ["kind": "unknown", "source": "21 * 2 /* PRIVATE_UNKNOWN_MUST_NOT_RUN */"],
            ["kind": "shell", "source": "pwd", "arguments": ["ignored"]],
            ["kind": "node", "source": "21 * 2 /* PRIVATE_INVALID_ENV */", "environment": ["X": 1]]
        ] {
            do { _ = try await execute(bridge, payload: payload); Issue.record("Invalid request reached an engine") }
            catch { #expect(!error.localizedDescription.contains("PRIVATE_")) }
        }
        #expect(!bridge.cancelRuntime(UUID().uuidString))
        HanlinNativeServicesBridge.unregisterProvider(forSessionID: adapter.sessionID)
        var rejected = false
        let handle = bridge.executeRuntime(#"{"kind":"javaScriptCore","source":"1+1"}"#) { result, error in
            rejected = result == nil && error?.contains("no longer active") == true
        }
        #expect(handle == nil && rejected)
        var legacyError: String?
        let legacyHandle = HanlinNativeServicesHostProvider.shared.executeRuntime(#"{"kind":"javaScriptCore","source":"1+1"}"#) { _, error in legacyError = error }
        #expect(legacyHandle == nil && legacyError?.contains("bound NativeScript session") == true)
    }

    @Test func cancellationHandlesCannotCrossSessionBoundaries() async throws {
        let adapter = NativeScriptHostServicesAdapter(appID: try HanlinAppID(validating: "ns-cancel-\(UUID().uuidString.lowercased())"), grantedCapabilities: [])
        let other = NativeScriptHostServicesAdapter(appID: try HanlinAppID(validating: "ns-other-\(UUID().uuidString.lowercased())"), grantedCapabilities: [])
        let bridge = try bind(adapter), otherBridge = try bind(other)
        defer {
            HanlinNativeServicesBridge.unregisterProvider(forSessionID: adapter.sessionID)
            HanlinNativeServicesBridge.unregisterProvider(forSessionID: other.sessionID)
        }
        let workspace = try RuntimeFileLayout.default.workspace(client: .executions, identifier: adapter.context.runtimeWorkspaceIdentifier)
        let started = workspace.appending(path: "wire-started")
        let reply = AsyncThrowingStream<String, any Error>.makeStream()
        let id = try #require(bridge.executeRuntime(#"{"kind":"node","source":"require('fs').writeFileSync('wire-started', 'ready'); setInterval(() => {}, 10)"}"#) { result, error in
            if let result { reply.continuation.yield(result); reply.continuation.finish() }
            else { reply.continuation.finish(throwing: NSError(domain: "NSWire", code: 1, userInfo: [NSLocalizedDescriptionKey: error ?? "No receipt"])) }
        })
        defer { _ = bridge.cancelRuntime(id); reply.continuation.finish() }
        let deadline = ContinuousClock.now + .seconds(60)
        while !FileManager.default.fileExists(atPath: started.path) {
            try #require(ContinuousClock.now < deadline, "Actual Node source did not start")
            try await Task.sleep(for: .milliseconds(25))
        }
        #expect(!otherBridge.cancelRuntime(id))
        #expect(!HanlinNativeServicesHostProvider.shared.cancelRuntime(id))
        #expect(bridge.cancelRuntime(id))
        do {
            var replies = reply.stream.makeAsyncIterator()
            let observed = try await replies.next()
            let json = try #require(observed)
            let receipt = try JSONDecoder().decode(RuntimeExecutionResult.self, from: Data(json.utf8))
            #expect(receipt.wasCancelled)
        } catch { #expect(error.localizedDescription.contains("cancelled")) }
        let unaffected = try await execute(otherBridge, kind: "javaScriptCore", source: "21 * 2")
        #expect(unaffected.value == .number(42) && !unaffected.wasCancelled)
    }

    private func bind(_ adapter: NativeScriptHostServicesAdapter) throws -> HanlinNativeServicesSessionBridge {
        HanlinNativeServicesBridge.register(adapter, forSessionID: adapter.sessionID)
        let token = try #require(HanlinNativeServicesPrepareSessionBootstrap(adapter.sessionID))
        return try #require(HanlinNativeServicesBridge.claimSessionBridge(withToken: token))
    }

    private func execute(_ bridge: HanlinNativeServicesSessionBridge, kind: String, source: String) async throws -> RuntimeExecutionResult {
        try await execute(bridge, payload: ["kind": kind, "source": source])
    }

    private func execute(_ bridge: HanlinNativeServicesSessionBridge, payload: [String: Any]) async throws -> RuntimeExecutionResult {
        let json = String(decoding: try JSONSerialization.data(withJSONObject: payload), as: UTF8.self)
        let result = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, any Error>) in
            _ = bridge.executeRuntime(json) { result, error in
                if let result { continuation.resume(returning: result) }
                else { continuation.resume(throwing: NSError(domain: "NSWire", code: 1, userInfo: [NSLocalizedDescriptionKey: error ?? "No receipt"])) }
            }
        }
        return try JSONDecoder().decode(RuntimeExecutionResult.self, from: Data(result.utf8))
    }
}
