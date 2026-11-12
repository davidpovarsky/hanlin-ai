import Foundation
import Testing
@testable import HanlinChatCore

@Suite("Offline captured SSE replay")
struct HanlinCapturedStreamReplayTests {
    private var configuration: HanlinChatModelConfiguration {
        .init(modelID: "fixture", company: "OpenRouter", apiType: "OpenAI",
              endpoint: "https://offline-replay.invalid/v1/chat/completions", credential: "offline-placeholder")
    }

    @Test func byteSplitsReplayThroughBothActualParsersWithoutMutation() async throws {
        let content = "שָׁלוֹם🙂مرحبا中文", reasoning = "Checking Unicode"
        let wire = try sse(["choices": [["delta": ["reasoning_content": reasoning]]]])
            + sse(["choices": [["delta": ["content": content]]]])
            + sse(["choices": [["delta": [:], "finish_reason": "stop"]]])
            + Data("data: [DONE]\n\n".utf8)
        let chunks = wire.enumerated().map { HanlinCapturedStreamChunk(bytes: Data([$0.element]), offsetNanoseconds: UInt64($0.offset)) }
        let result = try await HanlinCapturedStreamReplay.replay(chunks: chunks, configuration: configuration)
        #expect(result.directContent == content && result.sdkContent == content)
        #expect(result.directReasoning == reasoning && result.sdkReasoning == reasoning)
        #expect(result.firstContentMismatchByteOffset == nil)
        #expect(result.sdkError == nil && result.fetchCount == 1)
        #expect(result.directFinishReason == "stop" && result.sdkFinishReason == "stop")
    }

    @Test func reasoningOnlyCaptureCannotSilentlyReplayTheSameAttemptTwice() async throws {
        let wire = try sse(["choices": [["delta": ["reasoning_content": "Reasoning only"]]]])
            + sse(["choices": [["delta": [:], "finish_reason": "stop"]]]) + Data("data: [DONE]\n\n".utf8)
        let result = try await HanlinCapturedStreamReplay.replay(chunks: [.init(bytes: wire)], configuration: configuration)
        #expect(result.directContent.isEmpty && result.sdkContent.isEmpty)
        #expect(result.sdkError != nil)
        #expect(result.fetchCount > 1)
        #expect(result.warnings.contains(where: { $0.contains("no recorded response was replayed twice") }))
        #expect(result.sdkReasoning == "Reasoning only")
    }

    @Test func incompleteAndMalformedSourceRemainVisibleAsFailures() async throws {
        let wire = try sse(["choices": [["delta": ["content": "Partial"]]]]) + Data([0x64, 0x61, 0x74, 0x61, 0x3A, 0xC3])
        let result = try await HanlinCapturedStreamReplay.replay(chunks: [.init(bytes: wire)], configuration: configuration)
        #expect(result.directContent == "Partial")
        #expect(result.warnings.contains(where: { $0.contains("Invalid source UTF-8") }))
        #expect(result.warnings.contains(where: { $0.contains("no observed completion boundary") }))
    }

    @Test func toolCallsRemainDataWithNoRegisteredExecutorOrSecondStep() async throws {
        let wire = try sse(["choices": [["delta": ["tool_calls": [["index": 0, "id": "call-1", "type": "function", "function": ["name": "execute_shell_command", "arguments": "{\"command\":\"should-never-run\"}"]]]]]]])
            + sse(["choices": [["delta": [:], "finish_reason": "tool_calls"]]]) + Data("data: [DONE]\n\n".utf8)
        let result = try await HanlinCapturedStreamReplay.replay(chunks: [.init(bytes: wire)], configuration: configuration)
        #expect(result.fetchCount == 1)
        for event in result.sdkEvents {
            if case .toolResult(_, _, _, _, let isError) = event { #expect(isError) }
        }
        #expect(result.sdkError != nil || result.sdkEvents.contains(where: { if case .toolCall = $0 { return true }; return false }))
    }

    @Test func invalidTimelineAndCancellationRejectBeforeReplay() async throws {
        await #expect(throws: (any Error).self) {
            _ = try await HanlinCapturedStreamReplay.replay(chunks: [.init(bytes: Data(), offsetNanoseconds: 2), .init(bytes: Data(), offsetNanoseconds: 1)], configuration: configuration)
        }
        let task = Task {
            try Task.checkCancellation()
            return try await HanlinCapturedStreamReplay.replay(chunks: [.init(bytes: Data(), offsetNanoseconds: 60_000_000_000)], configuration: configuration, playbackSpeed: 1)
        }
        task.cancel()
        await #expect(throws: CancellationError.self) { _ = try await task.value }
    }

    private func sse(_ object: [String: Any]) throws -> Data {
        Data("data: ".utf8) + (try JSONSerialization.data(withJSONObject: object)) + Data("\r\n\r\n".utf8)
    }
}
