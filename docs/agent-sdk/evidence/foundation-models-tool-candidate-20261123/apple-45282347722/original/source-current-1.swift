#if canImport(FoundationModels)
import AISDKProvider
import Foundation
import FoundationModels
import HanlinChatCore
import Testing
@testable import HanlinAgentCore

/// These are real FoundationModels framework controls with an explicitly deterministic
/// public LanguageModelExecutor. They do not establish SystemLanguageModel eligibility
/// or actual on-device model quality/tool selection.
@Suite("FoundationModels handoff through the original provider and engine")
struct HanlinAppleToolSessionBridgeTests {
    @Test("Two same-name calls keep their identities and continue through the original executor")
    @MainActor
    func nativeFrameworkHandoffUsesCanonicalExecutorAndHistory() async throws {
        guard #available(iOS 27.0, macOS 27.0, *) else {
            Issue.record("Native framework acceptance requires iOS 27 or macOS 27.")
            return
        }
        try await NativeToolSessionBridgeChecks().nativeFrameworkHandoffUsesCanonicalExecutorAndHistory()
    }

    @Test("A denied native call has no effect and continues with the correlated tool denial")
    @MainActor
    func nativeDenialReturnsThroughCanonicalHistory() async throws {
        guard #available(iOS 27.0, macOS 27.0, *) else {
            Issue.record("Native framework acceptance requires iOS 27 or macOS 27.")
            return
        }
        try await NativeToolSessionBridgeChecks().nativeDenialReturnsThroughCanonicalHistory()
    }

    @Test("An invalid numeric sibling blocks the complete batch before approval or effect")
    @MainActor
    func nativeNumericSiblingCannotPartiallyExecute() async throws {
        guard #available(iOS 27.0, macOS 27.0, *) else {
            Issue.record("Native framework acceptance requires iOS 27 or macOS 27.")
            return
        }
        try await NativeToolSessionBridgeChecks().nativeNumericSiblingCannotPartiallyExecute()
    }

    @Test("Cancelling a waiting native request reaches its public executor and produces no host effect")
    @MainActor
    func nativeCancellationStopsAwaitingExecutor() async throws {
        guard #available(iOS 27.0, macOS 27.0, *) else {
            Issue.record("Native framework acceptance requires iOS 27 or macOS 27.")
            return
        }
        try await NativeToolSessionBridgeChecks().nativeCancellationStopsAwaitingExecutor()
    }

    @Test("Nonstreaming use of the original provider preserves native handoff calls")
    @MainActor
    func nativeGeneratePreservesToolCalls() async throws {
        guard #available(iOS 27.0, macOS 27.0, *) else {
            Issue.record("Native framework acceptance requires iOS 27 or macOS 27.")
            return
        }
        try await NativeToolSessionBridgeChecks().nativeGeneratePreservesToolCalls()
    }

    @Test("The admitted closed schema constructs through actual public native schema APIs")
    @MainActor
    func nativeSchemaConstructorsAndStructuredNumberRejection() throws {
        guard #available(iOS 27.0, macOS 27.0, *) else {
            Issue.record("Native framework acceptance requires iOS 27 or macOS 27.")
            return
        }
        try NativeToolSessionBridgeChecks().nativeSchemaConstructorsAndStructuredNumberRejection()
    }

    @Test("History rejects duplicate calls, orphan results and incomplete continuations")
    @MainActor
    func invalidCanonicalHistoriesFailBeforeGeneration() throws {
        guard #available(iOS 27.0, macOS 27.0, *) else {
            Issue.record("Native framework acceptance requires iOS 27 or macOS 27.")
            return
        }
        try NativeToolSessionBridgeChecks().invalidCanonicalHistoriesFailBeforeGeneration()
    }

}

@Suite("FoundationModels transport metadata admission")
struct HanlinAppleToolHeaderAdmissionTests {
    @Test("A non-User-Agent header is rejected before native executor entry")
    @MainActor
    func rejectsUnsupportedTransportHeader() async throws {
        guard #available(iOS 27.0, macOS 27.0, *) else {
            Issue.record("Native framework acceptance requires iOS 27 or macOS 27.")
            return
        }
        try await NativeToolSessionBridgeChecks().rejectsUnsupportedTransportHeader()
    }
}

// Availability belongs to the implementation, not to Swift Testing discovery.
@available(iOS 27.0, macOS 27.0, *)
private struct NativeToolSessionBridgeChecks {
    @MainActor
    func nativeFrameworkHandoffUsesCanonicalExecutorAndHistory() async throws {
        let state = FixtureState(mode: .twoCalls)
        let outcome = await run(state: state, approved: true)
        #expect(outcome.failure == nil)
        #expect(outcome.effects.sorted() == ["native_a", "native_b"])
        #expect(outcome.approvals.sorted() == ["native_a", "native_b"])
        #expect(outcome.provenances == [.normalized, .normalized])
        #expect(outcome.text == "NATIVE_CONTINUATION")
        let requests = await state.requests
        #expect(requests.count == 2)
        try assertCanonicalContinuation(requests, outputs: ["native_a", "native_b"])
        let outputs = try #require(requests.last).history.compactMap { entry -> Transcript.ToolOutput? in
            if case .toolOutput(let output) = entry { return output }; return nil
        }
        for output in outputs {
            #expect(output.toolName == "native_echo")
            #expect(output.segments.contains { if case .text(let text) = $0 { text.content == "HOST_RESULT_\(output.id)" } else { false } })
        }
    }

    @MainActor
    func nativeDenialReturnsThroughCanonicalHistory() async throws {
        let state = FixtureState(mode: .oneCall)
        let outcome = await run(state: state, approved: false)
        #expect(outcome.failure == nil)
        #expect(outcome.effects.isEmpty)
        #expect(outcome.approvals == ["native_a"])
        #expect(outcome.provenances.isEmpty)
        #expect(outcome.denials == ["native_a"])
        #expect(outcome.text == "NATIVE_CONTINUATION")
        try assertCanonicalContinuation(await state.requests, outputs: ["native_a"])
    }

    @MainActor
    func nativeNumericSiblingCannotPartiallyExecute() async throws {
        let state = FixtureState(mode: .numericSibling)
        let outcome = await run(state: state, approved: true)
        #expect(outcome.failure != nil)
        #expect(outcome.effects.isEmpty)
        #expect(outcome.approvals.isEmpty)
        #expect(outcome.toolCalls.isEmpty)
        #expect(await state.requests.count == 1)
    }

    @MainActor
    func nativeCancellationStopsAwaitingExecutor() async throws {
        let state = FixtureState(mode: .awaitCancellation)
        let consumer = Task { await run(state: state, approved: true) }
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while await state.requests.isEmpty, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(await state.requests.count == 1)
        consumer.cancel()
        let outcome = await consumer.value
        // Consumer termination and executor acknowledgement are separate signals.
        // The original producer schedules its stop request asynchronously.
        let acknowledgementDeadline = ContinuousClock.now.advanced(by: .seconds(5))
        while !(await state.cancelled), ContinuousClock.now < acknowledgementDeadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(outcome.failure != nil)
        #expect(outcome.effects.isEmpty)
        #expect(outcome.approvals.isEmpty)
        #expect(outcome.text.isEmpty)
        #expect(outcome.toolCalls.isEmpty)
        #expect(await state.requests.count == 1)
        #expect(await state.cancelled)
    }

    func rejectsUnsupportedTransportHeader() async throws {
        let state = FixtureState(mode: .twoCalls)
        let provider = HanlinAppleLanguageModel(toolBridgeModel: FixtureModel(state: state))
        do {
            _ = try await provider.doGenerate(options: .init(
                prompt: [.user(content: [.text(.init(text: "ORIGINAL_USER"))], providerOptions: nil)],
                tools: [.function(.init(name: "native_echo", inputSchema: try Self.schemaValue()))],
                headers: ["uSeR-aGeNt": "fixture-agent", "Authorization": "fixture-unsupported"]))
            Issue.record("An unsupported transport header must be rejected before generation.")
        } catch HanlinAppleProviderError.unsupportedSettings {}
        #expect(await state.requests.isEmpty)
    }

    func nativeGeneratePreservesToolCalls() async throws {
        let state = FixtureState(mode: .twoCalls)
        let provider = HanlinAppleLanguageModel(toolBridgeModel: FixtureModel(state: state))
        let response = try await provider.doGenerate(options: .init(
            prompt: [.user(content: [.text(.init(text: "ORIGINAL_USER"))], providerOptions: nil)],
            tools: [.function(.init(name: "native_echo", inputSchema: try Self.schemaValue()))]))
        #expect(response.finishReason.unified == .toolCalls)
        #expect(response.content.compactMap { part -> String? in
            if case .toolCall(let call) = part { return call.toolCallId }; return nil
        } == ["native_a", "native_b"])
        #expect(await state.requests.count == 1)
    }

    func nativeSchemaConstructorsAndStructuredNumberRejection() throws {
        let json = #"{"type":"object","properties":{"name":{"type":"string","enum":["a","b"]},"flags":{"type":"array","items":{"type":"boolean"},"minItems":1,"maxItems":2},"empty":{"type":"null"}},"required":["name","flags"],"additionalProperties":false}"#
        let value = try JSONDecoder().decode(JSONValue.self, from: Data(json.utf8))
        let schema = try HanlinAppleToolSchema(value)
        _ = try schema.nativeSchema(name: "NativeAdmissionControl")
        let content = try GeneratedContent(json: #"{"nested":[{"number":9007199254740993}]}"#)
        var remaining = 4_096
        #expect(throws: HanlinAppleToolBridgeError.numericArgumentsUnsupported) {
            try HanlinAppleToolHistory.generatedValue(content, remaining: &remaining)
        }
    }

    func invalidCanonicalHistoriesFailBeforeGeneration() throws {
        let user: LanguageModelV3Message = .user(content: [.text(.init(text: "REAL_USER"))], providerOptions: nil)
        let call = LanguageModelV3ToolCallPart(toolCallId: "a", toolName: "native_echo", input: .object(["query": .string("value")]))
        let assistant: LanguageModelV3Message = .assistant(content: [.toolCall(call)], providerOptions: nil)
        let result: LanguageModelV3Message = .tool(content: [.toolResult(.init(toolCallId: "a", toolName: "native_echo", output: .text(value: "RESULT")))], providerOptions: nil)
        let mismatched: LanguageModelV3Message = .tool(content: [.toolResult(.init(toolCallId: "a", toolName: "wrong", output: .text(value: "RESULT")))], providerOptions: nil)
        for prompt in [[user, assistant], [user, result], [user, assistant, mismatched],
                       [user, assistant, result, assistant, result]] {
            #expect(throws: HanlinAppleToolBridgeError.invalidHistory) { try HanlinAppleToolHistory(prompt) }
        }
    }

    private func assertCanonicalContinuation(_ requests: [Transcript], outputs expected: [String]) throws {
        #expect(requests.count == 2)
        for request in requests {
            let instructions = request.compactMap { entry -> String? in
                guard case .instructions(let value) = entry else { return nil }
                return value.segments.compactMap { segment -> String? in
                    if case .text(let text) = segment { return text.content }; return nil
                }.joined()
            }
            #expect(instructions == ["ORIGINAL_SYSTEM"])
            let prompts = request.history.compactMap { entry -> Transcript.Prompt? in
                if case .prompt(let prompt) = entry { return prompt }; return nil
            }
            #expect(prompts.count == 1, "The empty framework trigger must never reach the model executor.")
            #expect(prompts.first?.segments.count == 1)
            #expect(prompts.first?.segments.contains { if case .text(let text) = $0 { text.content == "ORIGINAL_USER" } else { false } } == true)
        }
        let resumed = try #require(requests.last)
        let calls = resumed.history.flatMap { entry -> [Transcript.ToolCall] in
            if case .toolCalls(let calls) = entry { return Array(calls) }; return []
        }
        let outputs = resumed.history.compactMap { entry -> Transcript.ToolOutput? in
            if case .toolOutput(let output) = entry { return output }; return nil
        }
        #expect(calls.map(\.id).sorted() == expected.sorted())
        #expect(outputs.map(\.id).sorted() == expected.sorted())
        #expect(resumed.history.count == 2 + expected.count)
    }

    @MainActor
    private func run(state: FixtureState, approved: Bool) async -> Outcome {
        let outcome = Outcome()
        let provider = HanlinAppleLanguageModel(toolBridgeModel: FixtureModel(state: state))
        let configuration = HanlinChatModelConfiguration(modelID: HanlinAppleOnDeviceProvider.modelID,
            company: "APPLE", apiType: "apple-on-device", endpoint: "https://example.invalid", credential: "")
        let engine = HanlinAISDKAgentEngine(configuration: configuration, model: .v3(provider),
            descriptor: .init(kind: .appleOnDevice, modelID: HanlinAppleOnDeviceProvider.modelID, baseURL: URL(filePath: "/apple-on-device")))
        do {
            let tool = HanlinAISDKToolDefinition(name: "native_echo", description: "Echo the query through the canonical host executor.",
                inputSchemaData: Data(Self.schemaJSON.utf8),
                execute: { _, _ in throw HanlinAppleToolBridgeError.invalidHandoff },
                executeWithInputProvenance: { _, id, provenance in
                    outcome.effects.append(id)
                    outcome.provenances.append(provenance)
                    return .init(modelText: "HOST_RESULT_\(id)")
                }, requiresApproval: true)
            let stream = try await engine.stream(messages: [.init(role: .user, text: "ORIGINAL_USER")],
                baseSystemPrompt: "ORIGINAL_SYSTEM", tools: [tool], maxSteps: 3,
                requestApproval: { request in outcome.approvals.append(request.toolCallID); return approved },
                prepareStep: { .init(activeToolAliases: ["native_echo"]) })
            for try await event in stream {
                switch event {
                case .textDelta(let text): outcome.text += text
                case .toolCall(let call): outcome.toolCalls.append(call.id)
                case .toolOutputDenied(let id, _): outcome.denials.append(id)
                default: break
                }
            }
            // Stream iteration may end normally when its consumer is cancelled.
            // This observes that consumer Task's cancellation, not a provider error.
            try Task.checkCancellation()
        } catch { outcome.failure = String(describing: error) }
        return outcome
    }

    private static let schemaJSON = #"{"type":"object","properties":{"query":{"type":"string"}},"required":["query"],"additionalProperties":false}"#
    private static func schemaValue() throws -> JSONValue { try JSONDecoder().decode(JSONValue.self, from: Data(schemaJSON.utf8)) }

    @MainActor
    private final class Outcome {
        var effects: [String] = [], approvals: [String] = [], toolCalls: [String] = [], denials: [String] = []
        var provenances: [HanlinAISDKToolInputProvenance] = []
        var text = ""
        var failure: String?
    }

    private enum Mode: Sendable { case oneCall, twoCalls, numericSibling, awaitCancellation }
    private actor FixtureState {
        nonisolated let mode: Mode
        var requests: [Transcript] = []
        var cancelled = false
        init(mode: Mode) { self.mode = mode }
        func record(_ transcript: Transcript) -> Int { requests.append(transcript); return requests.count }
        func recordCancellation() { cancelled = true }
    }

    private struct FixtureModel: FoundationModels.LanguageModel {
        typealias Executor = FixtureExecutor
        let state: FixtureState
        private let identity = UUID()
        init(state: FixtureState) { self.state = state }
        var capabilities: LanguageModelCapabilities { .init([.toolCalling, .guidedGeneration]) }
        var executorConfiguration: UUID { identity }
    }

    private struct FixtureExecutor: LanguageModelExecutor {
        typealias Configuration = UUID
        typealias Model = FixtureModel
        init(configuration: UUID) {}

        func respond(to request: LanguageModelExecutorGenerationRequest, model: FixtureModel,
                     streamingInto channel: LanguageModelExecutorGenerationChannel) async throws {
            let count = await model.state.record(request.transcript)
            guard request.enabledToolDefinitions.map(\.name) == ["native_echo"] else {
                throw HanlinAppleToolBridgeError.invalidHandoff
            }
            let mode = model.state.mode
            if mode == .awaitCancellation {
                do {
                    try await Task.sleep(for: .seconds(30))
                    throw HanlinAppleToolBridgeError.invalidHandoff
                } catch is CancellationError {
                    await model.state.recordCancellation()
                    throw CancellationError()
                }
            }
            if count == 1 {
                await channel.send(.toolCalls(entryID: "fixture_batch", action: .toolCall(id: "native_a",
                    name: "native_echo", action: .appendArguments(#"{"query":"first"}"#, tokenCount: 1))))
                if mode == .twoCalls || mode == .numericSibling {
                    let input = mode == .numericSibling ? #"{"query":9007199254740993}"# : #"{"query":"second"}"#
                    await channel.send(.toolCalls(entryID: "fixture_batch", action: .toolCall(id: "native_b",
                        name: "native_echo", action: .appendArguments(input, tokenCount: 1))))
                }
            } else {
                await channel.send(.response(entryID: "fixture_answer",
                    action: .appendText("NATIVE_CONTINUATION", tokenCount: 1)))
            }
        }
    }
}
#endif
