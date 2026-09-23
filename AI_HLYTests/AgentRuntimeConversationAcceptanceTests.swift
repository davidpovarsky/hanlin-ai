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
        Self.capturedBodies.append(request.httpBody ?? Data())
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
}

@MainActor
@Suite("Deterministic Agent Runtime Conversation Acceptance", .serialized)
struct AgentRuntimeConversationAcceptanceTests {
    private struct ConversationResult {
        var answer: String
        var events: [AgentEvent]
        var requests: [Data]
        var diagnostics: AgentDiagnosticsSession
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

    private func runConversation(responses: [String]) async throws -> ConversationResult {
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
        for kind in runtimeKinds { availability.setAvailable(true, for: kind) }

        let catalog = NativeToolCatalog.shared
        catalog.ensureBuiltinsRegistered()
        let shellEntry = try #require(catalog.entry(named: "execute_shell_command"))
        let shellWasEnabled = catalog.isEnabled(shellEntry)
        catalog.setEnabled(true, for: shellEntry)
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
        let diagnostics = try #require(await manager.diagnosticsSnapshot())
        return ConversationResult(
            answer: answer,
            events: events,
            requests: ScriptedAgentURLProtocol.bodies(),
            diagnostics: diagnostics
        )
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
