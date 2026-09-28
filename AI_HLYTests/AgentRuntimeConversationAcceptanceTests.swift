import Foundation
import HanlinChatCore
import SwiftData
import Testing
@testable import AI_Hanlin

private final class ScriptedAgentURLProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    private nonisolated(unsafe) static var responses: [Data] = []
    private nonisolated(unsafe) static var capturedBodies: [Data] = []

    static func configure(responses: [String]) {
        lock.lock()
        self.responses = responses.map { Data($0.utf8) }
        capturedBodies = []
        lock.unlock()
    }

    static func bodies() -> [Data] {
        lock.lock()
        defer { lock.unlock() }
        return capturedBodies
    }

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host == "agent.acceptance"
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        Self.lock.lock()
        Self.capturedBodies.append(Self.bodyData(from: request))
        let responseData = Self.responses.isEmpty ? nil : Self.responses.removeFirst()
        Self.lock.unlock()

        guard let responseData else {
            client?.urlProtocol(
                self,
                didFailWithError: URLError(.badServerResponse, userInfo: [
                    NSLocalizedDescriptionKey: "No scripted Agent response remains."
                ])
            )
            return
        }

        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: [
                "Content-Type": "text/event-stream",
                "x-request-id": "acceptance-request"
            ]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: responseData)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    private static func bodyData(from request: URLRequest) -> Data {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return Data() }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4_096)
        while true {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count > 0 else { break }
            data.append(contentsOf: buffer.prefix(count))
        }
        return data
    }
private final class ControllableDelayedTool: NativeTool, @unchecked Sendable {
    let name = "controllable_delayed_tool"
    private static let lock = NSLock()
    private nonisolated(unsafe) static var toolStartedContinuation: CheckedContinuation<Void, Never>?
    private nonisolated(unsafe) static var gateContinuation: CheckedContinuation<Void, Never>?

    static func reset() {
        lock.lock()
        defer { lock.unlock() }
        toolStartedContinuation = nil
        gateContinuation = nil
    }

    static func waitForToolStarted() async {
        await withCheckedContinuation { cont in
            lock.lock()
            toolStartedContinuation = cont
            lock.unlock()
        }
    }

    static func releaseGate() {
        lock.lock()
        let cont = gateContinuation
        gateContinuation = nil
        lock.unlock()
        cont?.resume()
    }

    var catalogEntry: NativeToolCatalogEntry {
        .init(
            name: name,
            title: "Controllable Delayed Tool",
            summary: "Gate-controlled delay for acceptance testing",
            categories: ["test"],
            keywords: ["delayed"],
            examples: [],
            systemImage: "clock",
            presentationProfile: .generic(toolName: name)
        )
    }

    func openAIToolSchema() -> [String: Any] {
        NativeToolSchema.function(
            name: name,
            description: "A tool that waits on a gate before completing.",
            parameters: NativeToolSchema.object(properties: [:])
        )
    }

    func execute(argumentsJSON: String, context: NativeToolExecutionContext) async -> NativeToolResult {
        Self.lock.lock()
        let started = Self.toolStartedContinuation
        Self.toolStartedContinuation = nil
        Self.lock.unlock()
        started?.resume()

        await withCheckedContinuation { cont in
            Self.lock.lock()
            Self.gateContinuation = cont
            Self.lock.unlock()
        }

        return NativeToolResult(
            callID: context.callID,
            toolName: name,
            resultForModel: "delayed_tool_finished",
            resultForUser: "Delayed tool finished",
            title: "Delayed Tool",
            systemImage: "clock",
            semanticOutcome: .succeeded
        )
    }
}

@MainActor
@Suite("Deterministic Agent Runtime Conversation Acceptance", .serialized)
struct AgentRuntimeConversationAcceptanceTests {
    private nonisolated(unsafe) static var lastRunDiagnostics: AgentDiagnosticsSession?

    private struct ConversationResult {
        var answer: String
        var events: [AgentEvent]
        var requests: [Data]
        var diagnostics: AgentDiagnosticsSession
        var localPythonAvailableAfterExecution: Bool?
    }

    @Test("Conversation A runs the complete runtime chain through the production loop")
    func successfulRuntimeChain() async throws {
        let result = try await runConversation(
            responses: [
                toolCall("a-python", "execute_local_python_code", ["source": "print(6 * 7)"]),
                toolCall("a-jsc", "execute_javascript_code", ["source": "6 * 7", "runtime": "jscore"]),
                toolCall("a-node", "execute_javascript_code", ["source": "console.log(6 * 7)", "runtime": "node"]),
                toolCall("a-ts", "execute_typescript_code", ["source": "const answer: number = 42; console.log(answer);", "compile_only": false]),
                toolCall("a-shell", "execute_shell_command", ["program": "ls", "arguments": []]),
                finalAnswer("AGENT_RUNTIME_CHAIN_COMPLETE")
            ]
        )

        #expect(result.answer.contains("AGENT_RUNTIME_CHAIN_COMPLETE"))
        #expect(result.requests.count == 6)
        #expect(result.diagnostics.isComplete)
        #expect(result.diagnostics.status == "completed")
        #expect(result.diagnostics.efficiency.toolCallCount == 5)
        #expect(result.diagnostics.efficiency.succeededToolCount == 5)
        #expect(result.diagnostics.efficiency.failedToolCount == 0)
        #expect(result.diagnostics.rounds.flatMap(\.toolCalls).allSatisfy { $0.canonicalLogicalToolID != nil })
        #expect(completedOutcomes(result.events).filter { $0 == .succeeded }.count == 5)
        #expect(requestContains(result.requests[1], "42"), "The Python result was not returned to the provider on the next round.")
    }

    @Test("Conversation B records one failed tool and recovers in the same completed run")
    func recoversAfterRejectedShellCall() async throws {
        let result = try await runConversation(
            responses: [
                toolCall("b-python", "execute_local_python_code", ["source": "print('ready')"]),
                toolCall("b-shell-invalid", "execute_shell_command", ["program": "echo", "arguments": ["not-approved"]]),
                toolCall("b-shell-repair", "execute_shell_command", ["program": "ls", "arguments": []]),
                finalAnswer("AGENT_RECOVERY_COMPLETE")
            ]
        )

        let calls = result.diagnostics.rounds.flatMap(\.toolCalls)
        #expect(result.answer.contains("AGENT_RECOVERY_COMPLETE"))
        #expect(result.diagnostics.status == "completed")
        #expect(calls.map(\.outcome) == [
            NativeToolExecutionOutcome.succeeded.rawValue,
            NativeToolExecutionOutcome.invalidArguments.rawValue,
            NativeToolExecutionOutcome.succeeded.rawValue
        ])
        #expect(result.diagnostics.efficiency.failedToolCount == 1)
        #expect(result.diagnostics.efficiency.invalidArgumentToolCount == 1)
        #expect(requestContains(result.requests[2], "echo") || requestContains(result.requests[2], "approved"))
    }

    @Test("Conversation C preserves every advertised runtime parameter")
    func runtimeParameters() async throws {
        let result = try await runConversation(
            responses: [
                toolCall("c-python", "execute_local_python_code", [
                    "source": "import sys; print(sys.argv[1])", "arguments": ["python-arg"], "timeout_seconds": 20
                ]),
                toolCall("c-jsc", "execute_javascript_code", [
                    "source": "arguments[0]", "runtime": "jscore", "arguments": ["jsc-arg"]
                ]),
                toolCall("c-node", "execute_javascript_code", [
                    "source": "console.log(process.argv.at(-1))", "runtime": "node", "arguments": ["node-arg"], "timeout_seconds": 20
                ]),
                toolCall("c-auto", "execute_javascript_code", [
                    "source": "console.log('auto-node')", "runtime": "auto", "timeout_seconds": 20
                ]),
                toolCall("c-ts-compile", "execute_typescript_code", [
                    "source": "const value: number = 42;", "file_name": "acceptance.ts", "compile_only": true
                ]),
                toolCall("c-ts-run", "execute_typescript_code", [
                    "source": "const value: number = 42; console.log(value);", "file_name": "acceptance-run.ts", "compile_only": false, "timeout_seconds": 20
                ]),
                toolCall("c-shell", "execute_shell_command", [
                    "program": "curl", "arguments": ["--version"], "allow_network": true
                ]),
                finalAnswer("AGENT_PARAMETERS_COMPLETE")
            ]
        )

        let calls = result.diagnostics.rounds.flatMap(\.toolCalls)
        #expect(result.answer.contains("AGENT_PARAMETERS_COMPLETE"))
        #expect(calls.count == 7)
        #expect(calls.allSatisfy { $0.outcome == NativeToolExecutionOutcome.succeeded.rawValue })
        #expect(calls.contains { Set($0.argumentKeys ?? []) == ["arguments", "source", "timeout_seconds"] })
        #expect(calls.contains { Set($0.argumentKeys ?? []).contains("file_name") })
        #expect(calls.contains { Set($0.argumentKeys ?? []).contains("allow_network") })
    }

    @Test("Malformed calls fail semantically and a later corrected call still completes")
    func malformedCallsRecover() async throws {
        let result = try await runConversation(
            responses: [
                toolCall("m-unknown", "runtime_alias_that_does_not_exist", [:]),
                toolCall("m-missing", "execute_local_python_code", [:]),
                toolCall("m-type", "execute_local_python_code", ["source": 42]),
                toolCall("m-extra", "execute_local_python_code", ["source": "print(1)", "mystery": true]),
                toolCall("m-enum", "execute_javascript_code", ["source": "1 + 1", "runtime": "browser"]),
                toolCall("m-timeout", "execute_typescript_code", ["source": "const x = 1", "timeout_seconds": 0]),
                toolCall("m-repair", "execute_javascript_code", ["source": "40 + 2", "runtime": "jscore"]),
                finalAnswer("AGENT_MALFORMED_RECOVERY_COMPLETE")
            ]
        )

        let calls = result.diagnostics.rounds.flatMap(\.toolCalls)
        #expect(result.answer.contains("AGENT_MALFORMED_RECOVERY_COMPLETE"))
        #expect(calls.count == 7)
        #expect(calls.prefix(6).allSatisfy { $0.outcome == NativeToolExecutionOutcome.invalidArguments.rawValue })
        #expect(calls.last?.outcome == NativeToolExecutionOutcome.succeeded.rawValue)
        #expect(result.diagnostics.efficiency.failedToolCount == 6)
        #expect(result.diagnostics.efficiency.invalidArgumentToolCount == 6)
    }

    @Test("Production code skill loads local python and completes in the same user turn without extra nudge")
    func productionCodeSkillLocalPythonCompletesSameUserTurn() async throws {
        let result = try await runConversation(
            responses: [
                toolCall("call-load-code", "load_skill", ["skill_id": "code"]),
                toolCall("call-exec-python", "execute_local_python_code", ["source": "print(6 * 7)"]),
                finalAnswer("42 / LOCAL_PYTHON_COMPLETE")
            ],
            overrideRuntimes: [.localPython: false]
        )

        // Assert round 0 request body does NOT contain execute_local_python_code
        let round0Body = String(decoding: result.requests[0], as: UTF8.self)
        #expect(!round0Body.contains("execute_local_python_code"))
        #expect(!round0Body.contains("execute_remote_python_code"))

        // Round 1 request body DOES contain execute_local_python_code (and not execute_remote_python_code)
        #expect(result.requests.count >= 2)
        let round1Body = String(decoding: result.requests[1], as: UTF8.self)
        #expect(round1Body.contains("execute_local_python_code"))
        #expect(!round1Body.contains("execute_remote_python_code"))

        // Round 2 request body contains tool result 42 with matching call id
        #expect(result.requests.count >= 3)
        let round2Body = String(decoding: result.requests[2], as: UTF8.self)
        #expect(round2Body.contains("42"))
        #expect(round2Body.contains("call-exec-python"))

        // Assert runtime became available after execution
        #expect(result.localPythonAvailableAfterExecution == true)

        #expect(result.answer.contains("42") && result.answer.contains("LOCAL_PYTHON_COMPLETE"))
        #expect(result.diagnostics.status == "completed")
        #expect(result.diagnostics.efficiency.failedToolCount == 0)
        #expect(result.diagnostics.efficiency.succeededToolCount == 2)
    }

    @Test("Production tool failure renders error card and recovers in same turn")
    func productionToolFailureRecoversAndAnswersSameTurn() async throws {
        let result = try await runConversation(
            responses: [
                toolCall("call-load-code", "load_skill", ["skill_id": "code"]),
                toolCall("call-invalid-1", "execute_shell_command", ["program": "not_an_approved_program_binary", "arguments": []]),
                toolCall("call-valid-2", "execute_local_python_code", ["source": "print(40 + 2)"]),
                finalAnswer("TOOL_RECOVERY_COMPLETE")
            ]
        )

        #expect(result.answer.contains("TOOL_RECOVERY_COMPLETE"))
        #expect(result.diagnostics.status == "completed")
        #expect(result.diagnostics.efficiency.failedToolCount == 1)
        #expect(result.diagnostics.efficiency.succeededToolCount == 2)

        let calls = result.diagnostics.rounds.flatMap(\.toolCalls)
        #expect(calls.count == 3)
        #expect(calls[0].name == "load_skill" && calls[0].outcome == NativeToolExecutionOutcome.succeeded.rawValue)
        #expect(calls[1].id == "call-invalid-1")
        #expect(calls[1].resultPresentationSuppressed == false)
        #expect(calls[1].outcome != NativeToolExecutionOutcome.succeeded.rawValue)
        #expect(calls[2].id == "call-valid-2" && calls[2].outcome == NativeToolExecutionOutcome.succeeded.rawValue)

        // Verify request 2 (continuation after invalid call) contains error info
        #expect(result.requests.count >= 4)
        let req2Text = String(decoding: result.requests[2], as: UTF8.self)
        #expect(req2Text.contains("call-invalid-1"))

        // Verify request 3 (continuation after valid call) contains 42 and call-valid-2
        let req3Text = String(decoding: result.requests[3], as: UTF8.self)
        #expect(req3Text.contains("42"))
        #expect(req3Text.contains("call-valid-2"))
    }

    @Test("Cancellation during agent run cancels coordinator and marks run cancelled")
    func cancelDuringAgentWorkStopsAllLaterToolExecution() async throws {
        ControllableDelayedTool.reset()
        let delayedTool = ControllableDelayedTool()
        NativeToolCatalog.shared.register(delayedTool)
        if let entry = NativeToolCatalog.shared.entry(named: delayedTool.name) {
            NativeToolCatalog.shared.setEnabled(true, for: entry)
        }

        ScriptedAgentURLProtocol.configure(responses: [
            toolCall("del-1", "controllable_delayed_tool", [:]),
            finalAnswer("LATE_ANSWER_SHOULD_NOT_APPEAR")
        ])
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ScriptedAgentURLProtocol.self]

        let container = try makeContainer()
        let context = container.mainContext
        context.insert(AllModels(name: "acceptance-model", displayName: "Acceptance Model", position: 0, company: "ACCEPTANCE", supportsTextGen: true, supportsToolUse: true))
        context.insert(APIKeys(name: "Acceptance", company: "ACCEPTANCE", key: "acceptance-fixture-key", requestURL: "https://agent.acceptance/v1/chat/completions", apiType: .openAI))
        try context.save()

        let session = AssistantCapabilitySession()
        session.exposeTools(aliases: [delayedTool.name])

        let manager = APIManager(
            context: context,
            chatEngineFactory: { HanlinChatEngine(sessionConfiguration: configuration) }
        )

        let runTask = Task { @MainActor () -> (String, [AgentEvent], Error?) in
            var text = ""
            var evts: [AgentEvent] = []
            do {
                let stream = try await manager.sendStreamRequest(
                    messages: [RequestMessage(role: "user", text: "Run delayed tool.", modelName: "acceptance-model", modelDisplayName: "Acceptance Model")],
                    modelName: "acceptance-model",
                    groupID: UUID(),
                    runID: UUID(),
                    ifSearch: false,
                    ifKnowledge: false,
                    ifToolUse: true,
                    assistantToolScope: .nativeOnly,
                    ifThink: false,
                    ifAudio: false,
                    ifPlanning: false,
                    thinkingLength: 0,
                    isObservation: false,
                    temperature: 0,
                    topP: 1,
                    maxTokens: 1024,
                    canvasData: CanvasData(),
                    capabilitySession: session
                )
                for try await item in stream {
                    text += item.content ?? ""
                    evts.append(contentsOf: item.agentEvents)
                }
                return (text, evts, nil)
            } catch {
                return (text, evts, error)
            }
        }

        // Wait until tool starts executing
        await ControllableDelayedTool.waitForToolStarted()

        // Cancel the current request while tool is mid-execution!
        manager.cancelCurrentRequest()

        // Release gate after cancellation
        ControllableDelayedTool.releaseGate()

        let (text, _, _) = await runTask.value

        // Assert NO late text arrived from finalAnswer
        #expect(!text.contains("LATE_ANSWER_SHOULD_NOT_APPEAR"))

        let snapshot = try #require(await manager.diagnosticsSnapshot())
        #expect(snapshot.status == "cancelled")
        #expect(snapshot.isComplete)
    }

    @Test("Starting a new run cancels old run without ghost work")
    func startingNewRunCancelsOldRunWithoutGhostWork() async throws {
        ControllableDelayedTool.reset()
        let delayedTool = ControllableDelayedTool()
        NativeToolCatalog.shared.register(delayedTool)
        if let entry = NativeToolCatalog.shared.entry(named: delayedTool.name) {
            NativeToolCatalog.shared.setEnabled(true, for: entry)
        }

        ScriptedAgentURLProtocol.configure(responses: [
            toolCall("del-run-a", "controllable_delayed_tool", [:]),
            finalAnswer("RUN_A_LATE_TEXT")
        ])
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ScriptedAgentURLProtocol.self]

        let container = try makeContainer()
        let context = container.mainContext
        context.insert(AllModels(name: "acceptance-model", displayName: "Acceptance Model", position: 0, company: "ACCEPTANCE", supportsTextGen: true, supportsToolUse: true))
        context.insert(APIKeys(name: "Acceptance", company: "ACCEPTANCE", key: "acceptance-fixture-key", requestURL: "https://agent.acceptance/v1/chat/completions", apiType: .openAI))
        try context.save()

        let sessionA = AssistantCapabilitySession()
        sessionA.exposeTools(aliases: [delayedTool.name])

        let manager = APIManager(
            context: context,
            chatEngineFactory: { HanlinChatEngine(sessionConfiguration: configuration) }
        )

        let runAID = UUID()
        let runATask = Task { @MainActor () -> (String, Error?) in
            var text = ""
            do {
                let stream = try await manager.sendStreamRequest(
                    messages: [RequestMessage(role: "user", text: "Start Run A", modelName: "acceptance-model", modelDisplayName: "Acceptance Model")],
                    modelName: "acceptance-model",
                    groupID: UUID(),
                    runID: runAID,
                    ifSearch: false,
                    ifKnowledge: false,
                    ifToolUse: true,
                    assistantToolScope: .nativeOnly,
                    ifThink: false,
                    ifAudio: false,
                    ifPlanning: false,
                    thinkingLength: 0,
                    isObservation: false,
                    temperature: 0,
                    topP: 1,
                    maxTokens: 1024,
                    canvasData: CanvasData(),
                    capabilitySession: sessionA
                )
                for try await item in stream {
                    text += item.content ?? ""
                }
                return (text, nil)
            } catch {
                return (text, error)
            }
        }

        // Wait until Run A's tool starts executing
        await ControllableDelayedTool.waitForToolStarted()
        #expect(AgentRunLifecycleCoordinator.shared.isCurrentRun(runAID))

        // Before A finishes, configure Run B responses and start Run B on the SAME APIManager!
        ScriptedAgentURLProtocol.configure(responses: [
            toolCall("run-b-calc", "quick_calculate", ["expression": "6 * 7"]),
            finalAnswer("RUN_B_COMPLETE")
        ])

        let runBID = UUID()
        let sessionB = AssistantCapabilitySession()
        var runBText = ""
        let streamB = try await manager.sendStreamRequest(
            messages: [RequestMessage(role: "user", text: "Start Run B", modelName: "acceptance-model", modelDisplayName: "Acceptance Model")],
            modelName: "acceptance-model",
            groupID: UUID(),
            runID: runBID,
            ifSearch: false,
            ifKnowledge: false,
            ifToolUse: true,
            assistantToolScope: .nativeOnly,
            ifThink: false,
            ifAudio: false,
            ifPlanning: false,
            thinkingLength: 0,
            isObservation: false,
            temperature: 0,
            topP: 1,
            maxTokens: 1024,
            canvasData: CanvasData(),
            capabilitySession: sessionB
        )
        for try await item in streamB {
            runBText += item.content ?? ""
        }

        // Run B completed!
        #expect(runBText.contains("RUN_B_COMPLETE"))
        #expect(!AgentRunLifecycleCoordinator.shared.isCurrentRun(runAID))

        // Release Run A's delayed tool gate
        ControllableDelayedTool.releaseGate()
        let (runAText, _) = await runATask.value

        // Assert Run A was cancelled and its text was NOT part of Run B
        #expect(!runBText.contains("RUN_A_LATE_TEXT"))
        #expect(!runAText.contains("RUN_A_LATE_TEXT"))

        let diagB = try #require(await manager.diagnosticsSnapshot())
        #expect(diagB.status == "completed")
        #expect(diagB.isComplete)
        #expect(diagB.efficiency.toolCallCount == 1) // only Run B's quick_calculate, no ghost calls
    }

    @Test("Terminal diagnostics are immutable and reject late mutations across all mutation methods")
    func terminalDiagnosticsAreImmutable() async throws {
        let runID = UUID()
        let recorder = try #require(await AgentDiagnosticsRecorder.start(
            runID: runID,
            groupID: UUID(),
            providerID: "TEST",
            modelID: "test"
        ))

        let roundID = await recorder.beginRound(
            index: 0,
            trigger: "initialUserRequest",
            requestData: Data("req".utf8)
        )

        await recorder.complete(status: "completed")
        let snapshot1 = await recorder.session
        #expect(snapshot1.isComplete)
        #expect(snapshot1.status == "completed")
        #expect(snapshot1.completedAt != nil)

        // Attempt mutations after completion
        _ = await recorder.beginRound(index: 1, trigger: "late", requestData: Data())
        await recorder.recordModelRequest(roundID: roundID, requestData: Data("late-model-req".utf8))
        await recorder.responseStarted(roundID: roundID, httpStatus: 200, providerRequestID: "late-id")
        await recorder.recordStreamEvent(roundID: roundID, visibleContent: "late content", visibleReasoningSummary: nil)
        let lateCall = AgentToolCall.parse(
            id: "late-call",
            name: "quick_calculate",
            argumentsJSON: "{}",
            presentationProfile: .generic(toolName: "quick_calculate")
        )
        await recorder.recordToolCall(roundID: roundID, call: lateCall)
        await recorder.completeToolCall(roundID: roundID, callID: "late-call", resultForModel: "late", resultForUser: nil, duration: 1.0)
        await recorder.finishRound(roundID: roundID, finishReason: "stop", usage: nil)
        await recorder.complete(status: "failed", error: "late error")

        let snapshot2 = await recorder.session
        #expect(snapshot2.isComplete)
        #expect(snapshot2.status == snapshot1.status)
        #expect(snapshot2.completedAt == snapshot1.completedAt)
        #expect(snapshot2.rounds.count == snapshot1.rounds.count)
        #expect(snapshot2.efficiency.toolCallCount == snapshot1.efficiency.toolCallCount)
        #expect(snapshot2.efficiency.failedToolCount == snapshot1.efficiency.failedToolCount)
        #expect(snapshot2.rounds[0].response.visibleContent == nil)
        #expect(snapshot2.rounds[0].toolCalls.isEmpty)
        #expect(snapshot2.lastUpdatedAt == snapshot1.completedAt)
    }

    @Test("Unexpected SDK stream end without terminal event marks diagnostics as failed and throws error")
    func unexpectedSDKStreamEndIsFailureNotCompleted() async throws {
        let unclosedSSE = "data: {\"choices\":[{\"delta\":{\"content\":\"partial answer\"}}]}\n\n"
        do {
            _ = try await runConversation(responses: [unclosedSSE])
            Issue.record("Expected stream failure from unexpected unclosed SSE")
        } catch {
            let diagnostics = try #require(Self.lastRunDiagnostics)
            #expect(diagnostics.status == "failed")
            #expect(diagnostics.isComplete)
        }
    }

    @Test("Round order uses exact SDK step numbers starting at zero")
    func roundOrderUsesExactSDKStepNumbers() async throws {
        let result = try await runConversation(
            responses: [
                toolCall("step-0-call", "load_skill", ["skill_id": "code"]),
                toolCall("step-1-call", "execute_local_python_code", ["source": "print(2 + 2)"]),
                finalAnswer("Answer is 4.")
            ]
        )

        let rounds = result.diagnostics.rounds
        #expect(rounds.count == 3)
        #expect(rounds[0].index == 0)
        #expect(rounds[0].trigger == "initialUserRequest")
        #expect(rounds[1].index == 1)
        #expect(rounds[1].trigger == "continueAfterToolResult")
        #expect(rounds[2].index == 2)
        #expect(rounds[2].trigger == "continueAfterToolResult")
    }

    @Test("Diagnostics capture actual continuation request body and headers")
    func diagnosticsCaptureActualContinuationRequest() async throws {
        let result = try await runConversation(
            responses: [
                toolCall("calc-1", "quick_calculate", ["expression": "10 * 10"]),
                finalAnswer("100")
            ]
        )

        let rounds = result.diagnostics.rounds
        #expect(rounds.count == 2)
        #expect(rounds[0].request.byteCount > 0)
        #expect(rounds[0].request.contentHash.count == 64)
        #expect(rounds[1].request.byteCount > 0)
        #expect(rounds[1].request.contentHash.count == 64)
        if result.requests.count >= 2 {
            let req2Text = String(decoding: result.requests[1], as: UTF8.self)
            #expect(req2Text.contains("100"))
            #expect(req2Text.contains("calc-1"))
            #expect(!req2Text.contains("acceptance-fixture-key"))
        }
    }

    private func runConversation(
        responses: [String],
        overrideRuntimes: [RuntimeKind: Bool]? = nil
    ) async throws -> ConversationResult {
        ScriptedAgentURLProtocol.configure(responses: responses)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ScriptedAgentURLProtocol.self]

        let container = try makeContainer()
        let context = container.mainContext
        context.insert(AllModels(
            name: "acceptance-model",
            displayName: "Acceptance Model",
            position: 0,
            company: "ACCEPTANCE",
            supportsTextGen: true,
            supportsToolUse: true
        ))
        context.insert(APIKeys(
            name: "Acceptance",
            company: "ACCEPTANCE",
            key: "acceptance-fixture-key",
            requestURL: "https://agent.acceptance/v1/chat/completions",
            apiType: .openAI
        ))
        try context.save()

        let availability = RuntimeAvailabilityStore.shared
        let runtimeKinds: [RuntimeKind] = [.localPython, .javaScriptCore, .node, .typeScript, .shell]
        let originalAvailability = Dictionary(uniqueKeysWithValues: runtimeKinds.map { ($0, availability.isAvailable($0)) })
        for kind in runtimeKinds {
            if let custom = overrideRuntimes?[kind] {
                availability.setAvailable(custom, for: kind)
            } else {
                availability.setAvailable(true, for: kind)
            }
        }

        let catalog = NativeToolCatalog.shared
        catalog.ensureBuiltinsRegistered()
        let shellEntry = try #require(catalog.entry(named: "execute_shell_command"))
        let shellWasEnabled = catalog.isEnabled(shellEntry)
        catalog.setEnabled(true, for: shellEntry)
        var capturedPythonAvailable: Bool?
        defer {
            catalog.setEnabled(shellWasEnabled, for: shellEntry)
            for kind in runtimeKinds {
                availability.setAvailable(originalAvailability[kind] ?? true, for: kind)
            }
        }

        let manager = APIManager(
            context: context,
            chatEngineFactory: { HanlinChatEngine(sessionConfiguration: configuration) }
        )
        do {
            let stream = try await manager.sendStreamRequest(
                messages: [RequestMessage(
                    role: "user",
                    text: "Run the deterministic runtime acceptance conversation.",
                    modelName: "acceptance-model",
                    modelDisplayName: "Acceptance Model"
                )],
                modelName: "acceptance-model",
                groupID: UUID(),
                runID: UUID(),
                ifSearch: false,
                ifKnowledge: false,
                ifToolUse: true,
                assistantToolScope: .nativeOnly,
                ifThink: false,
                ifAudio: false,
                ifPlanning: false,
                thinkingLength: 0,
                isObservation: false,
                temperature: 0,
                topP: 1,
                maxTokens: 1_024,
                canvasData: CanvasData(),
                selectedURLs: nil,
                selectedPromptsContent: nil,
                systemMessage: "Deterministic acceptance fixture.",
                selectedImageSize: "1024x1024",
                imageReversePrompt: ""
            )

            var answer = ""
            var events: [AgentEvent] = []
            for try await item in stream {
                answer += item.content ?? ""
                events.append(contentsOf: item.agentEvents)
            }
            capturedPythonAvailable = availability.isAvailable(.localPython)
            let diagnostics = try #require(await manager.diagnosticsSnapshot())
            Self.lastRunDiagnostics = diagnostics
            return ConversationResult(
                answer: answer,
                events: events,
                requests: ScriptedAgentURLProtocol.bodies(),
                diagnostics: diagnostics,
                localPythonAvailableAfterExecution: capturedPythonAvailable
            )
        } catch {
            Self.lastRunDiagnostics = await manager.diagnosticsSnapshot()
            throw error
        }
    }

    private func makeContainer() throws -> ModelContainer {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(
            for: ChatMessages.self,
            APIKeys.self,
            SearchKeys.self,
            AllModels.self,
            ChatRecords.self,
            UserInfo.self,
            PromptRepo.self,
            KnowledgeRecords.self,
            KnowledgeChunk.self,
            MemoryArchive.self,
            TranslationDic.self,
            ToolKeys.self,
            configurations: configuration
        )
    }

    private func toolCall(_ id: String, _ name: String, _ arguments: [String: Any]) -> String {
        let argumentsData = try! JSONSerialization.data(withJSONObject: arguments, options: [.sortedKeys])
        let argumentsJSON = String(decoding: argumentsData, as: UTF8.self)
        let payload: [String: Any] = [
            "choices": [[
                "delta": [
                    "tool_calls": [[
                        "index": 0,
                        "id": id,
                        "type": "function",
                        "function": ["name": name, "arguments": argumentsJSON]
                    ]]
                ],
                "finish_reason": "tool_calls"
            ]]
        ]
        return sse(payload)
    }

    private func finalAnswer(_ text: String) -> String {
        sse([
            "choices": [[
                "delta": ["content": text],
                "finish_reason": "stop"
            ]]
        ])
    }

    private func sse(_ payload: [String: Any]) -> String {
        let data = try! JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        return "data: \(String(decoding: data, as: UTF8.self))\n\ndata: [DONE]\n\n"
    }

    private func requestContains(_ request: Data, _ value: String) -> Bool {
        String(decoding: request, as: UTF8.self).localizedCaseInsensitiveContains(value)
    }

    private func completedOutcomes(_ events: [AgentEvent]) -> [NativeToolExecutionOutcome] {
        events.compactMap { event in
            if case .toolExecutionCompleted(_, let result) = event {
                return result.semanticOutcome
            }
            return nil
        }
    }
}
