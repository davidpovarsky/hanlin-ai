import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import AISDKProvider
import AISDKProviderUtils
import SwiftAISDK
@testable import HanlinChatCore
import Testing

@Suite("Provider Fault Injection & Finish Reason Tests")
struct ProviderFaultInjectionTests {

    private static func makeEngine(
        profile: ProviderConformanceProfile = .openAINativeChat,
        emulator: StatefulProviderEmulator
    ) throws -> HanlinAISDKAgentEngine {
        let config: HanlinChatModelConfiguration
        switch profile {
        case .openAINativeChat:
            config = HanlinChatModelConfiguration(
                modelID: "gpt-4o",
                company: "OpenAI",
                apiType: "openai",
                endpoint: "https://api.openai.com/v1/chat/completions",
                credential: "test-openai-key"
            )
        case .openAICompatiblePlain:
            config = HanlinChatModelConfiguration(
                modelID: "llama-3-70b",
                company: "CustomProvider",
                apiType: "openai",
                endpoint: "https://api.custom.org/v1/chat/completions",
                credential: "test-custom-key"
            )
        case .openAICompatibleReasoningContent:
            config = HanlinChatModelConfiguration(
                modelID: "deepseek-reasoner",
                company: "DeepSeek",
                apiType: "openai",
                endpoint: "https://api.deepseek.com/v1/chat/completions",
                credential: "test-deepseek-key",
                supportsReasoning: true
            )
        case .openAICompatibleReasoning:
            config = HanlinChatModelConfiguration(
                modelID: "qwen-qwq-32b",
                company: "Qwen",
                apiType: "openai",
                endpoint: "https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions",
                credential: "test-qwen-key",
                supportsReasoning: true
            )
        case .openRouterReasoningDetails:
            config = HanlinChatModelConfiguration(
                modelID: "nvidia/llama-3.1-nemotron-70b-instruct",
                company: "OpenRouter",
                apiType: "openai",
                endpoint: "https://openrouter.ai/api/v1/chat/completions",
                credential: "sk-or-v1-testkey",
                supportsReasoning: true
            )
        case .anthropicNative:
            config = HanlinChatModelConfiguration(
                modelID: "claude-3-5-sonnet-20241022",
                company: "Anthropic",
                apiType: "anthropic",
                endpoint: "https://api.anthropic.com/v1/messages",
                credential: "sk-ant-testkey",
                supportsReasoning: true
            )
        case .googleNative:
            config = HanlinChatModelConfiguration(
                modelID: "gemini-2.0-flash-exp",
                company: "Google",
                apiType: "gemini",
                endpoint: "https://generativelanguage.googleapis.com/v1beta/chat/completions",
                credential: "AIza-testkey",
                supportsReasoning: true
            )
        }
        return try HanlinAISDKAgentEngine(configuration: config, fetch: emulator.makeFetchFunction())
    }

    // MARK: - F01: Empty Provider Stream Across Profiles (Section 17)

    @Test("F01: Empty provider stream retries once and throws emptyProviderResponse after 2 empty streams", arguments: [
        ProviderConformanceProfile.openAINativeChat,
        ProviderConformanceProfile.openAICompatiblePlain,
        ProviderConformanceProfile.openRouterReasoningDetails,
        ProviderConformanceProfile.anthropicNative,
        ProviderConformanceProfile.googleNative
    ])
    func testF01EmptyProviderStream(profile: ProviderConformanceProfile) async throws {
        let emulator = StatefulProviderEmulator(
            profile: profile,
            scenarioName: "F01_EmptyStream_\(profile.rawValue)",
            roundExpectations: [
                0: RoundExpectation(),
                1: RoundExpectation()
            ],
            roundResponses: [
                0: .emptyStream,
                1: .emptyStream
            ]
        )
        let engine = try Self.makeEngine(profile: profile, emulator: emulator)

        let stream = try await engine.stream(
            messages: [.init(role: .user, text: "Ping")],
            baseSystemPrompt: nil,
            tools: [],
            prepareStep: { _ in HanlinAISDKStepPreparation(activeToolAliases: []) }
        )

        var didCatchExpectedError = false
        do {
            for try await _ in stream {}
        } catch let err as HanlinAISDKError {
            if case .emptyProviderResponse(let attempts) = err {
                #expect(attempts == 2)
                didCatchExpectedError = true
            }
        } catch {
            // Other error
        }

        #expect(didCatchExpectedError)
        #expect(emulator.requestCount == 2, "HanlinNonEmptyLanguageModel must retry an empty stream exactly once.")
    }

    // MARK: - F02: HTTP 200 Finish-Only No Semantic Content

    @Test("F02: HTTP 200 with finish_reason='other' and 0 text/tools is characterized")
    func testF02FinishOnlyOtherCharacterization() async throws {
        let emulator = StatefulProviderEmulator(
            profile: .openAINativeChat,
            scenarioName: "F02_FinishOnlyOther",
            roundExpectations: [0: RoundExpectation()],
            roundResponses: [
                0: .sseChunks(ProviderResponseFixtures.openAIFinishOnlyChunks(finishReason: "other"))
            ]
        )
        let engine = try Self.makeEngine(profile: .openAINativeChat, emulator: emulator)

        let stream = try await engine.stream(
            messages: [.init(role: .user, text: "Ping")],
            baseSystemPrompt: nil,
            tools: [],
            prepareStep: { _ in HanlinAISDKStepPreparation(activeToolAliases: []) }
        )

        var textCollected = ""
        var finishEventReason: String?
        for try await event in stream {
            if case .textDelta(let text) = event { textCollected += text }
            if case .finished(let reason, _) = event { finishEventReason = reason }
        }

        #expect(textCollected.isEmpty, "Observed behavior: No text was produced.")
        #expect(finishEventReason == "other", "Characterization: raw/normalized finish reason 'other' surfaced in finished event.")
    }

    // MARK: - F03: Abrupt Close Before Terminal Event Across Profiles (Section 17)

    @Test("F03: Abrupt stream close mid-text terminates with transport error and no completed event", arguments: [
        ProviderConformanceProfile.openAINativeChat,
        ProviderConformanceProfile.openAICompatiblePlain,
        ProviderConformanceProfile.openRouterReasoningDetails,
        ProviderConformanceProfile.anthropicNative,
        ProviderConformanceProfile.googleNative
    ])
    func testF03AbruptCloseMidStream(profile: ProviderConformanceProfile) async throws {
        let partialChunk: String
        switch profile {
        case .openAINativeChat, .openAICompatiblePlain, .openRouterReasoningDetails, .openAICompatibleReasoningContent, .openAICompatibleReasoning:
            partialChunk = "data: {\"id\":\"c1\",\"choices\":[{\"index\":0,\"delta\":{\"content\":\"Partial incomplete\"},\"finish_reason\":null}]}\n\n"
        case .anthropicNative:
            partialChunk = "event: content_block_delta\ndata: {\"type\":\"content_block_delta\",\"index\":0,\"delta\":{\"type\":\"text_delta\",\"text\":\"Partial incomplete\"}}\n\n"
        case .googleNative:
            partialChunk = "data: {\"candidates\":[{\"content\":{\"parts\":[{\"text\":\"Partial incomplete\"}],\"role\":\"model\"}}]}\n\n"
        }

        let emulator = StatefulProviderEmulator(
            profile: profile,
            scenarioName: "F03_AbruptClose_\(profile.rawValue)",
            roundExpectations: [0: RoundExpectation()],
            roundResponses: [
                0: .abruptCloseAfter(chunks: [partialChunk])
            ]
        )
        let engine = try Self.makeEngine(profile: profile, emulator: emulator)

        let stream = try await engine.stream(
            messages: [.init(role: .user, text: "Ping")],
            baseSystemPrompt: nil,
            tools: [],
            prepareStep: { _ in HanlinAISDKStepPreparation(activeToolAliases: []) }
        )

        var didThrow = false
        var completedReceived = false
        do {
            for try await event in stream {
                if case .finished = event { completedReceived = true }
            }
        } catch {
            didThrow = true
        }

        #expect(didThrow, "Abrupt close must terminate stream with an error.")
        #expect(!completedReceived, "Must not emit a false completed finished event.")
    }

    // MARK: - F04: [DONE] / Terminal Ordering Variations (OpenAI SSE Specific)

    @Test("F04: Stream ending after finish without explicit [DONE] still terminates cleanly")
    func testF04StreamWithoutDoneMarker() async throws {
        let chunks = [
            "data: {\"id\":\"c1\",\"choices\":[{\"index\":0,\"delta\":{\"content\":\"Hello world\"},\"finish_reason\":null}]}\n\n",
            "data: {\"id\":\"c1\",\"choices\":[{\"index\":0,\"delta\":{},\"finish_reason\":\"stop\"}]}\n\n"
        ]
        let emulator = StatefulProviderEmulator(
            profile: .openAINativeChat,
            scenarioName: "F04_NoDoneMarker",
            roundExpectations: [0: RoundExpectation()],
            roundResponses: [0: .sseChunks(chunks)]
        )
        let engine = try Self.makeEngine(profile: .openAINativeChat, emulator: emulator)

        let stream = try await engine.stream(
            messages: [.init(role: .user, text: "Ping")],
            baseSystemPrompt: nil,
            tools: [],
            prepareStep: { _ in HanlinAISDKStepPreparation(activeToolAliases: []) }
        )

        var text = ""
        var finished = false
        for try await event in stream {
            if case .textDelta(let t) = event { text += t }
            if case .finished = event { finished = true }
        }

        #expect(text == "Hello world")
        #expect(finished)
    }

    // MARK: - F05: Empty Delta Noise

    @Test("F05: Empty delta noise does not corrupt parser or yield empty text events")
    func testF05EmptyDeltaNoise() async throws {
        let chunks = [
            "data: {\"id\":\"c1\",\"choices\":[{\"index\":0,\"delta\":{},\"finish_reason\":null}]}\n\n",
            "data: {\"id\":\"c1\",\"choices\":[{\"index\":0,\"delta\":{\"content\":\"Useful \"},\"finish_reason\":null}]}\n\n",
            "data: {\"id\":\"c1\",\"choices\":[{\"index\":0,\"delta\":{},\"finish_reason\":null}]}\n\n",
            "data: {\"id\":\"c1\",\"choices\":[{\"index\":0,\"delta\":{\"content\":\"Text\"},\"finish_reason\":null}]}\n\n",
            "data: {\"id\":\"c1\",\"choices\":[{\"index\":0,\"delta\":{},\"finish_reason\":\"stop\"}]}\n\n",
            "data: [DONE]\n\n"
        ]
        let emulator = StatefulProviderEmulator(
            profile: .openAINativeChat,
            scenarioName: "F05_EmptyDeltaNoise",
            roundExpectations: [0: RoundExpectation()],
            roundResponses: [0: .sseChunks(chunks)]
        )
        let engine = try Self.makeEngine(profile: .openAINativeChat, emulator: emulator)

        let stream = try await engine.stream(
            messages: [.init(role: .user, text: "Ping")],
            baseSystemPrompt: nil,
            tools: [],
            prepareStep: { _ in HanlinAISDKStepPreparation(activeToolAliases: []) }
        )

        var textDeltas: [String] = []
        for try await event in stream {
            if case .textDelta(let t) = event { textDeltas.append(t) }
        }

        #expect(textDeltas == ["Useful ", "Text"])
    }

    // MARK: - F06: Usage-Only Final Chunk

    @Test("F06: Final usage-only chunk is processed for token usage and not treated as text")
    func testF06UsageOnlyFinalChunk() async throws {
        let chunks = [
            "data: {\"id\":\"c1\",\"choices\":[{\"index\":0,\"delta\":{\"content\":\"Answer\"},\"finish_reason\":\"stop\"}]}\n\n",
            ProviderResponseFixtures.openAIUsageOnlyChunk(promptTokens: 12, completionTokens: 8),
            "data: [DONE]\n\n"
        ]
        let emulator = StatefulProviderEmulator(
            profile: .openAINativeChat,
            scenarioName: "F06_UsageOnlyChunk",
            roundExpectations: [0: RoundExpectation()],
            roundResponses: [0: .sseChunks(chunks)]
        )
        let engine = try Self.makeEngine(profile: .openAINativeChat, emulator: emulator)

        let stream = try await engine.stream(
            messages: [.init(role: .user, text: "Ping")],
            baseSystemPrompt: nil,
            tools: [],
            prepareStep: { _ in HanlinAISDKStepPreparation(activeToolAliases: []) }
        )

        var text = ""
        var capturedUsage: HanlinChatTokenUsage?
        for try await event in stream {
            if case .textDelta(let t) = event { text += t }
            if case .finished(_, let usage) = event { capturedUsage = usage }
        }

        #expect(text == "Answer")
        #expect(capturedUsage?.totalTokens != nil)
    }

    // MARK: - F07: Duplicate Provider Chunk

    @Test("F07: Duplicate content chunk delta does not abort parser")
    func testF07DuplicateChunk() async throws {
        let chunks = [
            "data: {\"id\":\"c1\",\"choices\":[{\"index\":0,\"delta\":{\"content\":\"Echo\"},\"finish_reason\":null}]}\n\n",
            "data: {\"id\":\"c1\",\"choices\":[{\"index\":0,\"delta\":{\"content\":\"Echo\"},\"finish_reason\":null}]}\n\n",
            "data: {\"id\":\"c1\",\"choices\":[{\"index\":0,\"delta\":{},\"finish_reason\":\"stop\"}]}\n\n",
            "data: [DONE]\n\n"
        ]
        let emulator = StatefulProviderEmulator(
            profile: .openAINativeChat,
            scenarioName: "F07_DuplicateChunk",
            roundExpectations: [0: RoundExpectation()],
            roundResponses: [0: .sseChunks(chunks)]
        )
        let engine = try Self.makeEngine(profile: .openAINativeChat, emulator: emulator)

        let stream = try await engine.stream(
            messages: [.init(role: .user, text: "Ping")],
            baseSystemPrompt: nil,
            tools: [],
            prepareStep: { _ in HanlinAISDKStepPreparation(activeToolAliases: []) }
        )

        var text = ""
        for try await event in stream {
            if case .textDelta(let t) = event { text += t }
        }

        #expect(text == "EchoEcho")
    }

    // MARK: - F08: HTTP Error Codes Across Profiles (Section 17)

    @Test("F08: HTTP error codes 400, 401, 429, 500 abort stream without tool execution", arguments: [
        (ProviderConformanceProfile.openAINativeChat, 400),
        (ProviderConformanceProfile.openAINativeChat, 401),
        (ProviderConformanceProfile.openAINativeChat, 429),
        (ProviderConformanceProfile.openAINativeChat, 500),
        (ProviderConformanceProfile.openAINativeChat, 503),
        (ProviderConformanceProfile.anthropicNative, 400),
        (ProviderConformanceProfile.anthropicNative, 401),
        (ProviderConformanceProfile.anthropicNative, 429),
        (ProviderConformanceProfile.anthropicNative, 500),
        (ProviderConformanceProfile.googleNative, 400),
        (ProviderConformanceProfile.googleNative, 401),
        (ProviderConformanceProfile.googleNative, 429),
        (ProviderConformanceProfile.googleNative, 500)
    ])
    func testF08HTTPErrorCodes(profile: ProviderConformanceProfile, statusCode: Int) async throws {
        let ledger = ToolExecutionLedger()
        let tool = HanlinAISDKToolDefinition(
            name: "should_not_run",
            description: "Noop",
            inputSchemaData: try JSONSerialization.data(withJSONObject: ["type": "object"]),
            execute: { args, callID in
                ledger.recordStart(toolName: "should_not_run", callID: callID, arguments: args)
                return HanlinAISDKToolExecutionOutput(modelText: "oops")
            }
        )

        let errorBody = "{\"error\":{\"message\":\"HTTP error \(statusCode)\",\"type\":\"api_error\"}}".data(using: .utf8)
        let emulator = StatefulProviderEmulator(
            profile: profile,
            scenarioName: "F08_HTTPError_\(profile.rawValue)_\(statusCode)",
            roundExpectations: [
                0: RoundExpectation(),
                1: RoundExpectation(),
                2: RoundExpectation()
            ],
            roundResponses: [
                0: .httpError(statusCode: statusCode, body: errorBody),
                1: .httpError(statusCode: statusCode, body: errorBody),
                2: .httpError(statusCode: statusCode, body: errorBody)
            ],
            ledger: ledger
        )
        let engine = try Self.makeEngine(profile: profile, emulator: emulator)

        let stream = try await engine.stream(
            messages: [.init(role: .user, text: "Ping")],
            baseSystemPrompt: nil,
            tools: [tool],
            prepareStep: { _ in HanlinAISDKStepPreparation(activeToolAliases: ["should_not_run"]) }
        )

        var didThrow = false
        do {
            for try await _ in stream {}
        } catch {
            didThrow = true
        }

        #expect(didThrow, "HTTP \(statusCode) on \(profile.rawValue) must cause stream to throw.")
        #expect(ledger.allRecords.isEmpty, "No tool must execute when HTTP request failed.")
    }

    // MARK: - Section 18: Finish-Reason Matrices (OpenAI, Anthropic, Google)

    @Test("Section 18: OpenAI finish_reason mapping table", arguments: [
        ("stop", "stop"),
        ("length", "length"),
        ("content_filter", "content-filter"),
        ("tool_calls", "tool-calls"),
        ("function_call", "tool-calls"),
        ("unrecognized_raw_finish", "other")
    ])
    func testOpenAIFinishReasonTable(rawReason: String, expectedUnified: String) async throws {
        let chunks = [
            "data: {\"id\":\"c1\",\"choices\":[{\"index\":0,\"delta\":{\"content\":\"Text\"},\"finish_reason\":null}]}\n\n",
            "data: {\"id\":\"c1\",\"choices\":[{\"index\":0,\"delta\":{},\"finish_reason\":\"\(rawReason)\"}]}\n\n",
            "data: [DONE]\n\n"
        ]
        let emulator = StatefulProviderEmulator(
            profile: .openAINativeChat,
            scenarioName: "FinishReason_OpenAI_\(rawReason)",
            roundExpectations: [0: RoundExpectation()],
            roundResponses: [0: .sseChunks(chunks)]
        )
        let engine = try Self.makeEngine(profile: .openAINativeChat, emulator: emulator)

        let stream = try await engine.stream(
            messages: [.init(role: .user, text: "Ping")],
            baseSystemPrompt: nil,
            tools: [],
            prepareStep: { _ in HanlinAISDKStepPreparation(activeToolAliases: []) }
        )

        var finishedReason: String?
        for try await event in stream {
            if case .finished(let reason, _) = event {
                finishedReason = reason
            }
        }

        #expect(finishedReason == rawReason || finishedReason == expectedUnified)
    }

    @Test("Section 18: Anthropic finish_reason mapping table", arguments: [
        ("end_turn", "stop"),
        ("stop_sequence", "stop"),
        ("tool_use", "tool-calls"),
        ("max_tokens", "length"),
        ("model_context_window_exceeded", "length"),
        ("refusal", "content-filter"),
        ("pause_turn", "other"),
        ("unrecognized_reason", "other")
    ])
    func testAnthropicFinishReasonTable(rawReason: String, expectedUnified: String) async throws {
        let chunks = ProviderResponseFixtures.anthropicTextChunks(text: "Text", stopReason: rawReason)
        let emulator = StatefulProviderEmulator(
            profile: .anthropicNative,
            scenarioName: "FinishReason_Anthropic_\(rawReason)",
            roundExpectations: [0: RoundExpectation()],
            roundResponses: [0: .sseChunks(chunks)]
        )
        let engine = try Self.makeEngine(profile: .anthropicNative, emulator: emulator)

        let stream = try await engine.stream(
            messages: [.init(role: .user, text: "Ping")],
            baseSystemPrompt: nil,
            tools: [],
            prepareStep: { _ in HanlinAISDKStepPreparation(activeToolAliases: []) }
        )

        var finishedReason: String?
        for try await event in stream {
            if case .finished(let reason, _) = event {
                finishedReason = reason
            }
        }

        #expect(finishedReason == rawReason || finishedReason == expectedUnified)
    }

    @Test("Section 18: Google finish_reason mapping table", arguments: [
        ("STOP", "stop"),
        ("MAX_TOKENS", "length"),
        ("MALFORMED_FUNCTION_CALL", "other"),
        ("SAFETY", "content-filter"),
        ("BLOCKLIST", "content-filter"),
        ("PROHIBITED_CONTENT", "content-filter"),
        ("SPII", "content-filter"),
        ("RECITATION", "other"),
        ("OTHER", "other"),
        ("FINISH_REASON_UNSPECIFIED", "other")
    ])
    func testGoogleFinishReasonTable(rawReason: String, expectedUnified: String) async throws {
        let chunks = ProviderResponseFixtures.googleTextChunks(text: "Text", finishReason: rawReason)
        let emulator = StatefulProviderEmulator(
            profile: .googleNative,
            scenarioName: "FinishReason_Google_\(rawReason)",
            roundExpectations: [0: RoundExpectation()],
            roundResponses: [0: .sseChunks(chunks)]
        )
        let engine = try Self.makeEngine(profile: .googleNative, emulator: emulator)

        let stream = try await engine.stream(
            messages: [.init(role: .user, text: "Ping")],
            baseSystemPrompt: nil,
            tools: [],
            prepareStep: { _ in HanlinAISDKStepPreparation(activeToolAliases: []) }
        )

        var finishedReason: String?
        for try await event in stream {
            if case .finished(let reason, _) = event {
                finishedReason = reason
            }
        }

        #expect(finishedReason == rawReason || finishedReason == expectedUnified)
    }
}
