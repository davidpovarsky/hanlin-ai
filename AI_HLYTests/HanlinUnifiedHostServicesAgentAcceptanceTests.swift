import Testing
@testable import AI_Hanlin
import HanlinPlatformContracts
import HanlinMiniAppCore

@MainActor
@Suite("Agent Host Services Acceptance", .serialized)
struct HanlinUnifiedHostServicesAgentAcceptanceTests {

    @Test func agentContextCreation() {
        let context = HanlinHostCallContext.forAgent()
        #expect(context.effectiveCapabilities.contains("all"))
        #expect(context.origin == .assistantModel)
        if case .agent = context.storageScope {
            // Expected
        } else {
            Issue.record("Agent context should have .agent storage scope")
        }
    }

    @Test func agentAdapterMakesContextWithAllCapabilities() {
        let context = AgentHostServicesAdapter.makeContext()
        #expect(context.effectiveCapabilities.contains("all"))
        #expect(context.origin == .assistantModel)
        #expect(context.appID == nil)
        #expect(context.canPresentUI == false)
        #expect(context.runtimeWorkspaceIdentifier == "agent-\(context.runtimeSessionID.rawValue)")
    }

    @Test func agentContextSessionIDsAreUnique() {
        let c1 = AgentHostServicesAdapter.makeContext()
        let c2 = AgentHostServicesAdapter.makeContext()
        #expect(c1.appSessionID != c2.appSessionID)
        #expect(c1.runtimeSessionID != c2.runtimeSessionID)
    }

    @Test func runtimeBrokerAutoStartsStoppedRuntime() async throws {
        let store = RuntimeAvailabilityStore.shared
        let kind = RuntimeKind.javaScriptCore
        let original = store.isAvailable(kind)
        defer { store.setAvailable(original, for: kind) }

        store.setAvailable(false, for: kind)
        #expect(!store.isAvailable(kind))

        let context = AgentHostServicesAdapter.makeContext()
        let result = try await HanlinRuntimeBroker.shared.execute(
            kind: kind,
            source: "1+1",
            context: context
        )
        #expect(result.value == .number(2))
        #expect(store.isAvailable(kind))
    }

    @Test func runtimeBrokerRunsPythonWithoutInternalGrants() async throws {
        let context = HanlinHostCallContext.forMiniApp(
            appID: try HanlinAppID(validating: "unauthorized.agent"),
            origin: .system,
            capabilities: [],
            canPresentUI: false
        )
        let result = try await HanlinRuntimeBroker.shared.execute(
            kind: .localPython, source: "print(6 * 7)", context: context
        )
        #expect(result.exitCode == 0)
        #expect(result.stdout.contains("42"))
    }

    @Test func agentToolExecutesJavaScriptCore() async {
        let tool = ExecuteJavaScriptTool()
        let context = NativeToolExecutionContext(localeIdentifier: "en")
        let result = await tool.execute(
            argumentsJSON: "{\"source\": \"6 * 7\", \"runtime\": \"jscore\"}",
            context: context
        )
        #expect(result.outcome == .succeeded)
        #expect(result.modelText.contains("42"))
    }

    @Test func agentToolExecutesNode() async {
        let tool = ExecuteJavaScriptTool()
        let context = NativeToolExecutionContext(localeIdentifier: "en")
        let result = await tool.execute(
            argumentsJSON: "{\"source\": \"console.log(14 * 3);\", \"runtime\": \"node\"}",
            context: context
        )
        #expect(result.outcome == .succeeded)
        #expect(result.modelText.contains("42"))
    }

    @Test func agentToolExecutesPython() async {
        let tool = ExecuteLocalPythonTool()
        let context = NativeToolExecutionContext(localeIdentifier: "en")
        let result = await tool.execute(
            argumentsJSON: "{\"source\": \"print(40 + 2)\"}",
            context: context
        )
        #expect(result.outcome == .succeeded)
        #expect(result.modelText.contains("42"))
    }

    @Test func agentToolExecutesTypeScript() async {
        let tool = ExecuteTypeScriptTool()
        let context = NativeToolExecutionContext(localeIdentifier: "en")
        let result = await tool.execute(
            argumentsJSON: "{\"source\": \"const ans: number = 42; console.log(ans);\"}",
            context: context
        )
        #expect(result.outcome == .succeeded)
        #expect(result.modelText.contains("42"))
    }

    @Test func agentToolExecutesShell() async {
        let tool = ExecuteShellCommandTool()
        let context = NativeToolExecutionContext(localeIdentifier: "en")
        let result = await tool.execute(
            argumentsJSON: "{\"program\": \"ls\", \"arguments\": []}",
            context: context
        )
        #expect(result.outcome == .succeeded)
    }

    @Test func shellAllApprovedCommandsAndPolicies() async throws {
        let report = try await AppRuntimeCore.shared.shell.runSmokeSuite(node: AppRuntimeCore.shared.node)
        #expect(report.passed, "\(String(decoding: try JSONEncoder().encode(report), as: UTF8.self))")
        #expect(report.testedCommands.count == 23)
        #expect(report.commandResults.allSatisfy { $0.passed })
        #expect(report.policyResults.allSatisfy { $0.passed })
        #expect(report.policyResults.contains { $0.policy == "verified_command_catalog" && $0.passed })
        #expect(report.policyResults.contains { $0.policy == "native_pipeline_and_redirection" && $0.passed })
        #expect(report.policyResults.contains { $0.policy == "portable_command_chaining" && $0.passed })
        #expect(report.policyResults.contains { $0.policy == "curl_http_native_dispatch" && $0.passed })
        #expect(report.policyResults.contains { $0.policy == "curl_https_native_dispatch" && $0.passed })
        let hostContext = AgentHostServicesAdapter.makeContext()
        let workspace = try RuntimeFileLayout.default.workspace(client: .executions, identifier: hostContext.runtimeWorkspaceIdentifier)
        defer { try? FileManager.default.removeItem(at: workspace) }
        let tool = ExecuteShellCommandTool(hostContext: hostContext)
        let result = await tool.execute(argumentsJSON: try Self.json([
            "command": "printf first > chain-output.txt && printf second >> chain-output.txt && cat chain-output.txt"
        ]), context: NativeToolExecutionContext(localeIdentifier: "en"))
        #expect(result.outcome == .succeeded, "\(result.modelText)")
        #expect(result.modelText.contains("firstsecond"))
    }

    @Test func agentToolRespectsDisabledRuntimeToggle() async {
        let tool = ExecuteJavaScriptTool()
        let entry = await MainActor.run {
            NativeToolCatalog.shared.ensureBuiltinsRegistered()
            return NativeToolCatalog.shared.entry(named: tool.name)!
        }
        let originalEnabled = await MainActor.run { NativeToolCatalog.shared.isEnabled(entry) }
        defer {
            Task { @MainActor in
                NativeToolCatalog.shared.setEnabled(originalEnabled, for: entry)
            }
        }

        await MainActor.run {
            NativeToolCatalog.shared.setEnabled(false, for: entry)
        }

        let context = NativeToolExecutionContext(localeIdentifier: "en")
        let result = await tool.execute(
            argumentsJSON: "{\"source\": \"6 * 7\", \"runtime\": \"jscore\"}",
            context: context
        )
        #expect(result.outcome == .rejectedByCapability)
        #expect(result.modelText.lowercased().contains("disabled") || result.modelText.lowercased().contains("capability"))
    }

    @Test func pythonFullContract() async throws {
        let store = RuntimeAvailabilityStore.shared
        let original = store.isAvailable(.localPython)
        defer { store.setAvailable(original, for: .localPython) }
        store.setAvailable(true, for: .localPython)
        let tool = ExecuteLocalPythonTool()
        let context = NativeToolExecutionContext(localeIdentifier: "en")

        let output = await tool.execute(
            argumentsJSON: #"{"source":"import sys; print('שלום'); print(sys.argv[1]); print('second-line'); print('stderr-ok', file=sys.stderr)","arguments":["argv-ok"],"timeout_seconds":20}"#,
            context: context
        )
        #expect(output.outcome == .succeeded)
        #expect(output.modelText.contains("שלום"))
        #expect(output.modelText.contains("argv-ok"))
        #expect(output.modelText.contains("second-line"))
        #expect(output.modelText.contains("stderr-ok"))

        let fileRoundTrip = await tool.execute(
            argumentsJSON: #"{"source":"from pathlib import Path\np=Path('python-acceptance.txt')\np.write_text('workspace-ok', encoding='utf-8')\nprint(p.read_text(encoding='utf-8'))"}"#,
            context: context
        )
        #expect(fileRoundTrip.outcome == .succeeded)
        #expect(fileRoundTrip.modelText.contains("workspace-ok"))

        let noOutput = await tool.execute(argumentsJSON: #"{"source":"answer = 42"}"#, context: context)
        #expect(noOutput.outcome == .succeeded)
        #expect(noOutput.modelText.localizedCaseInsensitiveContains("without output"))

        let exception = await tool.execute(argumentsJSON: #"{"source":"raise RuntimeError('python-boom')"}"#, context: context)
        #expect(exception.outcome == .failed)
        #expect(exception.modelText.contains("python-boom"))
        let syntax = await tool.execute(argumentsJSON: #"{"source":"def broken(:"}"#, context: context)
        #expect(syntax.outcome == .failed)

        let timeout = await tool.execute(
            argumentsJSON: #"{"source":"while True: pass","timeout_seconds":1}"#,
            context: context
        )
        #expect(timeout.outcome == .timedOut)

        let limited = try await AgentHostServicesAdapter.executeRuntime(
            .localPython,
            source: "print('x' * 5000)",
            limits: RuntimeExecutionLimits(timeout: .seconds(20), maximumOutputBytes: 1_024)
        )
        #expect(limited.outputWasTruncated)
        #expect(limited.stdout.utf8.count <= 1_024)
    }

    @Test func javaScriptBackendsFullContract() async throws {
        let store = RuntimeAvailabilityStore.shared
        let kinds: [RuntimeKind] = [.javaScriptCore, .node]
        let originals = Dictionary(uniqueKeysWithValues: kinds.map { ($0, store.isAvailable($0)) })
        defer { for kind in kinds { store.setAvailable(originals[kind] ?? true, for: kind) } }
        kinds.forEach { store.setAvailable(true, for: $0) }
        let tool = ExecuteJavaScriptTool()
        let context = NativeToolExecutionContext(localeIdentifier: "en")

        let jsc = try await HanlinRuntimeBroker.shared.execute(
            kind: .javaScriptCore,
            source: "console.log(arguments[0]); console.warn(environment.HANLIN_ACCEPTANCE); 6 * 7",
            context: AgentHostServicesAdapter.makeContext(),
            arguments: ["jsc-argv"],
            environment: ["HANLIN_ACCEPTANCE": "jsc-env"]
        )
        #expect(jsc.stdout.contains("jsc-argv"))
        #expect(jsc.stderr.contains("jsc-env"))
        #expect(jsc.value == .number(42))

        let unsupportedTimer = await tool.execute(
            argumentsJSON: #"{"source":"setTimeout(() => {}, 1)","runtime":"jscore"}"#,
            context: context
        )
        #expect(unsupportedTimer.outcome == .failed)
        let noNodeGlobals = await tool.execute(
            argumentsJSON: #"{"source":"[typeof process, typeof require, typeof document]","runtime":"jscore"}"#,
            context: context
        )
        #expect(noNodeGlobals.outcome == .succeeded)
        #expect(noNodeGlobals.modelText.contains("undefined"))

        let autoJSC = await tool.execute(argumentsJSON: #"{"source":"40 + 2","runtime":"auto"}"#, context: context)
        #expect(autoJSC.outcome == .succeeded)
        #expect(autoJSC.diagnostics.runtimeKind == RuntimeKind.javaScriptCore.rawValue)
        let autoNode = await tool.execute(
            argumentsJSON: #"{"source":"console.log(process.version)","runtime":"auto","timeout_seconds":20}"#,
            context: context
        )
        #expect(autoNode.outcome == .succeeded)
        #expect(autoNode.diagnostics.runtimeKind == RuntimeKind.node.rawValue)

        let node = try await HanlinRuntimeBroker.shared.execute(
            kind: .node,
            source: "await new Promise(resolve => setTimeout(resolve, 10)); console.log(process.argv.at(-1)); console.error(process.env.HANLIN_ACCEPTANCE);",
            context: AgentHostServicesAdapter.makeContext(),
            arguments: ["node-argv"],
            environment: ["HANLIN_ACCEPTANCE": "node-env"],
            limits: RuntimeExecutionLimits(timeout: .seconds(20))
        )
        #expect(node.exitCode == 0)
        #expect(node.stdout.contains("node-argv"))
        #expect(node.stderr.contains("node-env"))

        let nodeException = await tool.execute(
            argumentsJSON: #"{"source":"throw new Error('node-boom')","runtime":"node"}"#,
            context: context
        )
        #expect(nodeException.outcome == .failed)
        let nodeTimeout = await tool.execute(
            argumentsJSON: #"{"source":"while (true) {}","runtime":"node","timeout_seconds":1}"#,
            context: context
        )
        #expect(nodeTimeout.outcome == .timedOut)

        let cancellationTask = Task {
            await tool.execute(
                argumentsJSON: #"{"source":"await new Promise(resolve => setTimeout(resolve, 30000))","runtime":"node","timeout_seconds":30}"#,
                context: context
            )
        }
        try await Task.sleep(for: .milliseconds(150))
        cancellationTask.cancel()
        let cancelled = await cancellationTask.value
        #expect(cancelled.outcome == .cancelled)
    }

    @Test func typeScriptFullContract() async {
        let store = RuntimeAvailabilityStore.shared
        let kinds: [RuntimeKind] = [.typeScript, .node]
        let originals = Dictionary(uniqueKeysWithValues: kinds.map { ($0, store.isAvailable($0)) })
        defer { for kind in kinds { store.setAvailable(originals[kind] ?? true, for: kind) } }
        kinds.forEach { store.setAvailable(true, for: $0) }
        let tool = ExecuteTypeScriptTool()
        let context = NativeToolExecutionContext(localeIdentifier: "en")

        let compileOnly = await tool.execute(
            argumentsJSON: #"{"source":"const answer: number = 42;","file_name":"typed-acceptance.ts","compile_only":true}"#,
            context: context
        )
        #expect(compileOnly.outcome == .succeeded)
        #expect(compileOnly.modelText.contains("42"))
        let execute = await tool.execute(
            argumentsJSON: #"{"source":"const answer: number = 42; console.log(answer);","file_name":"typed-run.ts","compile_only":false,"timeout_seconds":20}"#,
            context: context
        )
        #expect(execute.outcome == .succeeded)
        #expect(execute.modelText.contains("42"))

        let diagnostics = await tool.execute(
            argumentsJSON: #"{"source":"const answer: number = 'wrong';","compile_only":true}"#,
            context: context
        )
        #expect(diagnostics.outcome == .failed)
        #expect(diagnostics.modelText.contains("TS"))
        let syntax = await tool.execute(
            argumentsJSON: #"{"source":"const = ;","compile_only":true}"#,
            context: context
        )
        #expect(syntax.outcome == .failed)
        let timeout = await tool.execute(
            argumentsJSON: #"{"source":"while (true) {}","compile_only":false,"timeout_seconds":1}"#,
            context: context
        )
        #expect(timeout.outcome == .timedOut)

        store.setAvailable(false, for: .node)
        let stillCompiles = await tool.execute(
            argumentsJSON: #"{"source":"const value: number = 1;","compile_only":true}"#,
            context: context
        )
        #expect(stillCompiles.outcome == .succeeded)
        let executionAutoStartsNode = await tool.execute(
            argumentsJSON: #"{"source":"console.log(1);","compile_only":false}"#,
            context: context
        )
        #expect(executionAutoStartsNode.outcome == .succeeded)
        #expect(executionAutoStartsNode.modelText.contains("1"))
        #expect(store.isAvailable(.node))
    }

    @Test func shellRejectionMatrix() async throws {
        let store = RuntimeAvailabilityStore.shared
        let original = store.isAvailable(.shell)
        defer { store.setAvailable(original, for: .shell) }
        store.setAvailable(true, for: .shell)
        let shellSession = try HanlinRuntimeSessionID(validating: UUID().uuidString.lowercased())
        let shellContext = HanlinHostCallContext.forAgent(runtimeSessionID: shellSession)
        let tool = ExecuteShellCommandTool(hostContext: shellContext)
        let context = NativeToolExecutionContext(localeIdentifier: "en")

        for program in ["echo", "date", "bash", "sh", "python", "node"] {
            let result = await tool.execute(
                argumentsJSON: try Self.json(["program": program, "arguments": []]),
                context: context
            )
            #expect(result.outcome == .invalidArguments)
        }
        // Missing both program and command
        let missingBoth = await tool.execute(
            argumentsJSON: "{}",
            context: context
        )
        #expect(missingBoth.outcome == .invalidArguments)

        // Supplying both program and command
        let supplyingBoth = await tool.execute(
            argumentsJSON: try Self.json(["program": "ls", "command": "ls"]),
            context: context
        )
        #expect(supplyingBoth.outcome == .invalidArguments)

        // Structured arguments cannot accompany command string form
        let argsWithCommand = await tool.execute(
            argumentsJSON: try Self.json(["command": "ls", "arguments": ["-la"]]),
            context: context
        )
        #expect(argsWithCommand.outcome == .invalidArguments)

        let workspace = try RuntimeFileLayout.default.workspace(
            client: .executions,
            identifier: shellContext.runtimeWorkspaceIdentifier
        )
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        let nonce = "native-argv-\(UUID().uuidString)"
        let input = workspace.appending(path: "many-arguments.txt")
        try (nonce + "\n").write(to: input, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: input) }
        let manyArguments = await tool.execute(
            argumentsJSON: try Self.json(["program": "cat", "arguments": Array(repeating: "many-arguments.txt", count: 128)]),
            context: context
        )
        #expect(manyArguments.outcome == .succeeded)
        #expect((manyArguments.userText ?? "").components(separatedBy: nonce).count - 1 == 128)
        // Port0 cannot host a server. This executes real curl locally, with an
        // explicit fixture timeout and no inherited proxy/public request. A
        // transport failure must not become a fabricated argument/permission error.
        let httpTransportFailure = await tool.execute(
            argumentsJSON: try Self.json(["program": "curl", "arguments": ["--noproxy", "*", "--max-time", "2", "--connect-timeout", "1", "http://127.0.0.1:0"], "allow_network": false]),
            context: context
        )
        #expect(httpTransportFailure.outcome == .failed)
        #expect(httpTransportFailure.diagnostics.exitCode != nil)
        let networkFlagAccepted = await tool.execute(
            argumentsJSON: try Self.json(["program": "curl", "arguments": ["--version"], "allow_network": true]),
            context: context
        )
        #expect(networkFlagAccepted.outcome == .succeeded)

        let outside = FileManager.default.temporaryDirectory.appending(path: "hanlin-shell-outside-\(UUID().uuidString)")
        let link = workspace.appending(path: "acceptance-escape")
        try Data("secret".utf8).write(to: outside)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outside)
        defer {
            try? FileManager.default.removeItem(at: link)
            try? FileManager.default.removeItem(at: outside)
        }
        let symlink = await tool.execute(
            argumentsJSON: try Self.json(["program": "cat", "arguments": ["acceptance-escape"]]),
            context: context
        )
        #expect(symlink.outcome == .succeeded)
        #expect(symlink.modelText.contains("secret"))
    }

    @Test func legacyRuntimeGrantChangesDoNotDisableTheSameSession() async throws {
        let appID = try HanlinAppID(validating: "runtime-live-capability-\(UUID().uuidString.lowercased())")
        let authority = HanlinHostCapabilityAuthority.shared
        let capability = "runtime.javascript"
        let context = HanlinHostCallContext.forMiniApp(
            appID: appID,
            origin: .system,
            capabilities: [capability],
            canPresentUI: false
        )
        let store = RuntimeAvailabilityStore.shared
        let originalAvailability = store.isAvailable(.javaScriptCore)
        store.setAvailable(true, for: .javaScriptCore)
        defer {
            store.setAvailable(originalAvailability, for: .javaScriptCore)
            Task { await authority.revoke(capability: capability, for: appID) }
        }

        await authority.grant(capability: capability, for: appID)
        let first = try await HanlinRuntimeBroker.shared.execute(
            kind: .javaScriptCore,
            source: "20 + 22",
            context: context
        )
        #expect(first.value == .number(42))
        await authority.revoke(capability: capability, for: appID)
        let afterLegacyRevocation = try await HanlinRuntimeBroker.shared.execute(
            kind: .javaScriptCore,
            source: "20 + 22",
            context: context
        )
        #expect(afterLegacyRevocation.value == .number(42))
        await authority.grant(capability: capability, for: appID)
        let retried = try await HanlinRuntimeBroker.shared.execute(
            kind: .javaScriptCore,
            source: "20 + 22",
            context: context
        )
        #expect(retried.value == .number(42))
    }

    private static func json(_ object: [String: Any]) throws -> String {
        String(decoding: try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]), as: UTF8.self)
    }
}
