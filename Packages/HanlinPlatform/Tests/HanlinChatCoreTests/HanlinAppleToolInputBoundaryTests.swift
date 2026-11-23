import AISDKProvider
import Foundation
import Testing
@testable import HanlinChatCore

/// Exercises the real shared engine and pinned producer; the model only supplies deterministic parts.
@Suite("Apple native input provenance at the original engine boundary")
struct HanlinAppleToolInputBoundaryTests {
    @Test("Native reserialized input never becomes acceptedOriginal", arguments: [false, true])
    @MainActor
    func nativeInputStaysNormalized(_ requiresApproval: Bool) async throws {
        let input = #"{"message":"שלום","nested":[true,null,"9007199254740993"]}"#
        let result = await run(kind: .appleOnDevice, input: input, requiresApproval: requiresApproval)
        #expect(result.failure == nil)
        #expect(result.effects == 1)
        #expect(result.approvals == (requiresApproval ? 1 : 0))
        #expect(result.provenances == [.normalized])
        #expect(result.arguments == [input])
        #expect(result.callIDs == ["native_call_1"])
        #expect(result.response == "CONTINUATION_COMPLETE")
        #expect(result.providerCalls == 2)
    }

    @Test("Native numeric leaves fail before approval or host effect", arguments: [
        #"{"number":0}"#,
        #"{"nested":[{"number":1.25}]}"#,
        #"{"number":9007199254740993}"#,
        #"{"nested":{"number":1e100}}"#
    ], [false, true])
    @MainActor
    func nativeNumericInputCannotReachApprovalOrExecutor(_ input: String, _ requiresApproval: Bool) async throws {
        let result = await run(kind: .appleOnDevice, input: input, requiresApproval: requiresApproval)
        #expect(result.failure != nil)
        #expect(result.effects == 0)
        #expect(result.approvals == 0)
        #expect(result.provenances.isEmpty)
        #expect(result.callIDs.isEmpty)
        #expect(result.toolEvents == 0)
        #expect(result.providerCalls == 1)
    }

    @Test("Cloud accepted original numeric JSON remains unchanged", arguments: [false, true])
    @MainActor
    func cloudOriginalInputStillHasExactProvenance(_ requiresApproval: Bool) async throws {
        let input = #"{ "number": 1.2500e+2, "text": "שלום" }"#
        let result = await run(kind: .openAI, input: input, requiresApproval: requiresApproval)
        #expect(result.failure == nil)
        #expect(result.effects == 1)
        #expect(result.approvals == (requiresApproval ? 1 : 0))
        #expect(result.provenances == [.acceptedOriginal])
        #expect(result.arguments == [input])
        #expect(result.callIDs == ["native_call_1"])
        #expect(result.providerCalls == 2)
    }

    @MainActor
    fileprivate func run(kind: HanlinAISDKProviderKind, input: String,
                         requiresApproval: Bool, approved: Bool = true,
                         firstFinishReason: LanguageModelV3FinishReason.Unified = .toolCalls) async -> Outcome {
        let model = InputModel(input: input, firstFinishReason: firstFinishReason)
        let state = Outcome()
        let configuration = HanlinChatModelConfiguration(modelID: "boundary-fixture",
            company: "OpenAI", apiType: "openai",
            endpoint: "https://example.invalid/v1", credential: "unused-fixture")
        let engine = HanlinAISDKAgentEngine(configuration: configuration, model: .v3(model),
            descriptor: .init(kind: kind, modelID: "boundary-fixture", baseURL: URL(filePath: "/fixture")))
        let tool = HanlinAISDKToolDefinition(name: "boundary_tool", description: "Fixture host operation",
            inputSchemaData: Data(#"{"type":"object"}"#.utf8),
            execute: { _, _ in
                state.effects += 1
                throw HanlinAISDKError.invalidConversation("Provenance executor was not used.")
            },
            executeWithInputProvenance: { arguments, callID, provenance in
                state.effects += 1
                state.arguments.append(arguments)
                state.callIDs.append(callID)
                state.provenances.append(provenance)
                return .init(modelText: "HOST_RESULT")
            }, requiresApproval: requiresApproval)
        do {
            let stream = try await engine.stream(messages: [.init(role: .user, text: "Run the fixture")],
                baseSystemPrompt: nil, tools: [tool], maxSteps: 3,
                requestApproval: { _ in state.approvals += 1; return approved },
                prepareStep: { .init(activeToolAliases: ["boundary_tool"]) })
            for try await event in stream {
                if case .toolCall = event { state.toolEvents += 1 }
                if case .textDelta(let text) = event { state.response += text }
                if case .toolOutputDenied(let id, let name) = event {
                    state.denials.append((id: id, name: name))
                }
                if case .stepFinished(_, let reason, _, _) = event {
                    state.stepFinishReasons.append(reason)
                }
            }
        } catch { state.failure = String(describing: error) }
        state.providerCalls = await model.calls
        state.prompts = await model.prompts
        state.providerFinishReasons = await model.finishReasons
        return state
    }

    @MainActor
    fileprivate final class Outcome {
        var effects = 0, approvals = 0, toolEvents = 0, providerCalls = 0
        var response = ""
        var failure: String?
        var arguments: [String] = []
        var callIDs: [String] = []
        var provenances: [HanlinAISDKToolInputProvenance] = []
        var denials: [(id: String, name: String)] = []
        var prompts: [[LanguageModelV3Message]] = []
        var providerFinishReasons: [LanguageModelV3FinishReason.Unified] = []
        var stepFinishReasons: [String] = []
    }

    private actor InputModel: LanguageModelV3 {
        nonisolated let provider = "hanlin-boundary-fixture"
        nonisolated let modelId = "boundary-fixture"
        nonisolated var supportedUrls: [String: [NSRegularExpression]] { [:] }
        let input: String
        let firstFinishReason: LanguageModelV3FinishReason.Unified
        var calls = 0
        var prompts: [[LanguageModelV3Message]] = []
        var finishReasons: [LanguageModelV3FinishReason.Unified] = []
        init(input: String, firstFinishReason: LanguageModelV3FinishReason.Unified) {
            self.input = input
            self.firstFinishReason = firstFinishReason
        }
        func doGenerate(options: LanguageModelV3CallOptions) async throws -> LanguageModelV3GenerateResult {
            throw HanlinAISDKError.invalidConversation("The boundary fixture only streams.")
        }
        func doStream(options: LanguageModelV3CallOptions) async throws -> LanguageModelV3StreamResult {
            calls += 1
            prompts.append(options.prompt)
            let first = calls == 1
            let input = self.input
            let finishReason: LanguageModelV3FinishReason.Unified = first ? firstFinishReason : .stop
            finishReasons.append(finishReason)
            return .init(stream: AsyncThrowingStream { continuation in
                continuation.yield(.streamStart(warnings: []))
                if first {
                    continuation.yield(.toolCall(.init(toolCallId: "native_call_1",
                        toolName: "boundary_tool", input: input,
                        // Untrusted metadata cannot upgrade native provenance.
                        providerMetadata: ["fixture": ["inputProvenance": .string("acceptedOriginal")]])))
                } else {
                    continuation.yield(.textStart(id: "text", providerMetadata: nil))
                    continuation.yield(.textDelta(id: "text", delta: "CONTINUATION_COMPLETE", providerMetadata: nil))
                    continuation.yield(.textEnd(id: "text", providerMetadata: nil))
                }
                continuation.yield(.finish(finishReason: .init(unified: finishReason),
                    usage: .init(inputTokens: .init(total: nil), outputTokens: .init(total: nil)),
                    providerMetadata: nil))
                continuation.finish()
            })
        }
    }
}


/// Only the new non-toolCalls finish-label branch; the original12 cases keep their defaults.
@Suite("Original engine continuation after a completed tool labeled stop")
struct HanlinProducerStopContinuationTests {
    @Test("An authorized tool without an additional approval prompt continues after stop with its canonical output")
    @MainActor
    func allowedStopToolContinuesThroughOriginalEngine() async throws {
        let input = #"{ "number": 1.2500e+2, "text": "שלום" }"#
        let outcome = await HanlinAppleToolInputBoundaryTests().run(
            kind: .openAI, input: input, requiresApproval: false,
            approved: true, firstFinishReason: .stop)
        #expect(outcome.failure == nil)
        #expect(outcome.effects == 1)
        #expect(outcome.approvals == 0)
        #expect(outcome.provenances == [.acceptedOriginal])
        #expect(outcome.arguments == [input])
        #expect(outcome.callIDs == ["native_call_1"])
        #expect(outcome.denials.isEmpty)
        try assertCorrelatedContinuation(outcome, output: .text(value: "HOST_RESULT"))
    }

    @Test("Denied stop-labeled tool continues with a correlated denial and no host effect")
    @MainActor
    func deniedStopToolContinuesWithCorrelatedResult() async throws {
        let outcome = await HanlinAppleToolInputBoundaryTests().run(
            kind: .openAI, input: #"{"message":"deny this fixture"}"#,
            requiresApproval: true, approved: false, firstFinishReason: .stop)
        #expect(outcome.failure == nil)
        #expect(outcome.effects == 0)
        #expect(outcome.approvals == 1)
        #expect(outcome.provenances.isEmpty)
        #expect(outcome.arguments.isEmpty)
        #expect(outcome.callIDs.isEmpty)
        #expect(outcome.denials.map(\.id) == ["native_call_1"])
        #expect(outcome.denials.map(\.name) == ["boundary_tool"])
        try assertCorrelatedContinuation(outcome, output: .executionDenied(reason: "Not approved by the user."))
    }

    @Test("Rejected native numeric stop-labeled tool cannot reach approval, effect or another provider request")
    @MainActor
    func nativeNumericStopToolCannotContinueOrReachHost() async throws {
        let outcome = await HanlinAppleToolInputBoundaryTests().run(
            kind: .appleOnDevice, input: #"{"nested":[{"number":1.25}]}"#,
            requiresApproval: true, approved: true, firstFinishReason: .stop)
        #expect(outcome.failure != nil)
        #expect(outcome.effects == 0)
        #expect(outcome.approvals == 0)
        #expect(outcome.provenances.isEmpty)
        #expect(outcome.arguments.isEmpty)
        #expect(outcome.callIDs.isEmpty)
        #expect(outcome.toolEvents == 0)
        #expect(outcome.denials.isEmpty)
        #expect(outcome.response.isEmpty)
        #expect(outcome.providerCalls == 1)
        #expect(outcome.prompts.count == 1)
        #expect(outcome.providerFinishReasons == [.stop])
    }

    @MainActor
    private func assertCorrelatedContinuation(
        _ outcome: HanlinAppleToolInputBoundaryTests.Outcome,
        output expected: LanguageModelV3ToolResultOutput
    ) throws {
        #expect(outcome.response == "CONTINUATION_COMPLETE")
        #expect(outcome.providerCalls == 2)
        #expect(outcome.prompts.count == 2)
        #expect(outcome.providerFinishReasons == [.stop, .stop])
        #expect(outcome.stepFinishReasons.first == "stop")
        for prompt in outcome.prompts {
            let userText = prompt.flatMap { message -> [String] in
                guard case .user(let parts, _) = message else { return [] }
                return parts.compactMap { if case .text(let text) = $0 { text.text } else { nil } }
            }
            #expect(userText == ["Run the fixture"])
        }
        let resumed = try #require(outcome.prompts.last)
        let calls = resumed.flatMap { message -> [LanguageModelV3ToolCallPart] in
            guard case .assistant(let parts, _) = message else { return [] }
            return parts.compactMap { if case .toolCall(let call) = $0 { call } else { nil } }
        }
        let outputs = resumed.flatMap { message -> [LanguageModelV3ToolResultPart] in
            guard case .tool(let parts, _) = message else { return [] }
            return parts.compactMap { if case .toolResult(let result) = $0 { result } else { nil } }
        }
        #expect(calls.count == 1)
        #expect(calls.first?.toolCallId == "native_call_1")
        #expect(calls.first?.toolName == "boundary_tool")
        #expect(outputs.count == 1)
        #expect(outputs.first?.toolCallId == "native_call_1")
        #expect(outputs.first?.toolName == "boundary_tool")
        #expect(outputs.first?.output == expected)
    }
}
