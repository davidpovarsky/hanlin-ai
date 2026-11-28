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
    private func run(kind: HanlinAISDKProviderKind, input: String,
                     requiresApproval: Bool) async -> Outcome {
        let model = InputModel(input: input)
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
                requestApproval: { _ in state.approvals += 1; return true },
                prepareStep: { .init(activeToolAliases: ["boundary_tool"]) })
            for try await event in stream {
                if case .toolCall = event { state.toolEvents += 1 }
                if case .textDelta(let text) = event { state.response += text }
            }
        } catch { state.failure = String(describing: error) }
        state.providerCalls = await model.calls
        return state
    }

    @MainActor
    private final class Outcome {
        var effects = 0, approvals = 0, toolEvents = 0, providerCalls = 0
        var response = ""
        var failure: String?
        var arguments: [String] = []
        var callIDs: [String] = []
        var provenances: [HanlinAISDKToolInputProvenance] = []
    }

    private actor InputModel: LanguageModelV3 {
        nonisolated let provider = "hanlin-boundary-fixture"
        nonisolated let modelId = "boundary-fixture"
        nonisolated var supportedUrls: [String: [NSRegularExpression]] { [:] }
        let input: String
        var calls = 0
        init(input: String) { self.input = input }
        func doGenerate(options: LanguageModelV3CallOptions) async throws -> LanguageModelV3GenerateResult {
            throw HanlinAISDKError.invalidConversation("The boundary fixture only streams.")
        }
        func doStream(options: LanguageModelV3CallOptions) async throws -> LanguageModelV3StreamResult {
            calls += 1
            let first = calls == 1
            let input = self.input
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
                continuation.yield(.finish(finishReason: .init(unified: first ? .toolCalls : .stop),
                    usage: .init(inputTokens: .init(total: nil), outputTokens: .init(total: nil)),
                    providerMetadata: nil))
                continuation.finish()
            })
        }
    }
}
