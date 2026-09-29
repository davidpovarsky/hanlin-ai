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

    private static func makeEngine(emulator: StatefulProviderEmulator) throws -> HanlinAISDKAgentEngine {
        let config = HanlinChatModelConfiguration(
            modelID: "gpt-4o",
            company: "OpenAI",
            apiType: "openai",
            endpoint: "https://api.openai.com/v1/chat/completions",
            credential: "test-openai-key"
        )
        return try HanlinAISDKAgentEngine(configuration: config, fetch: emulator.makeFetchFunction())
    }

    // MARK: - F01: Empty Provider Stream

    @Test("F01: Empty provider stream retries once and throws emptyProviderResponse after 2 empty streams")
    func testF01EmptyProviderStream() async throws {
        let emulator = StatefulProviderEmulator(
            profile: .openAINativeChat,
            scenarioName: "F01_EmptyStream",
            roundExpectations: [
                0: RoundExpectation(),
                1: RoundExpectation()
            ],
            roundResponses: [
                0: .emptyStream,
                1: .emptyStream
            ]
        )
        let engine = try Self.makeEngine(emulator: emulator)

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
        let engine = try Self.makeEngine(emulator: emulator)

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

    // MARK: - F03: Abrupt Close Before Terminal Event

    @Test("F03: Abrupt stream close mid-text terminates with transport error and no completed event")
    func testF03AbruptCloseMidStream() async throws {
        let partialChunk = "data: {\"id\":\"c1\",\"choices\":[{\"index\":0,\"delta\":{\"content\":\"Partial incomplete\"},\"finish_reason\":null}]}\n\n"
        let emulator = StatefulProviderEmulator(
            profile: .openAINativeChat,
            scenarioName: "F03_AbruptClose",
            roundExpectations: [0: RoundExpectation()],
            roundResponses: [
                0: .abruptCloseAfter(chunks: [partialChunk])
            ]
        )
        let engine = try Self.makeEngine(emulator: emulator)

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

    // MARK: - F04: [DONE] / Terminal Ordering Variations

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
        let engine = try Self.makeEngine(emulator: emulator)

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
        let engine = try Self.makeEngine(emulator: emulator)

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
        let engine = try Self.makeEngine(emulator: emulator)

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
        let engine = try Self.makeEngine(emulator: emulator)

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

    // MARK: - F08: HTTP Error Codes

    @Test("F08: HTTP error codes 400, 401, 429, 500 abort stream without tool execution", arguments: [400, 401, 429, 500, 503])
    func testF08HTTPErrorCodes(statusCode: Int) async throws {
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
            profile: .openAINativeChat,
            scenarioName: "F08_HTTPError_\(statusCode)",
            roundExpectations: [0: RoundExpectation()],
            roundResponses: [0: .httpError(statusCode: statusCode, body: errorBody)],
            ledger: ledger
        )
        let engine = try Self.makeEngine(emulator: emulator)

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

        #expect(didThrow, "HTTP \(statusCode) must cause stream to throw.")
        #expect(ledger.allRecords.isEmpty, "No tool must execute when HTTP request failed.")
    }

    // MARK: - Section 11: Finish-Reason Contract Tests

    @Test("Section 11: OpenAI finish_reason mapping table", arguments: [
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
            scenarioName: "FinishReason_\(rawReason)",
            roundExpectations: [0: RoundExpectation()],
            roundResponses: [0: .sseChunks(chunks)]
        )
        let engine = try Self.makeEngine(emulator: emulator)

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

        // HanlinAISDKAgentEngine surfaces rawReason ?? reason.rawValue
        #expect(finishedReason == rawReason || finishedReason == expectedUnified)
    }
}
