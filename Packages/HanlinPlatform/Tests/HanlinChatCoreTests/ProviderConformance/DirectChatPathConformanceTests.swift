import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import HanlinChatCore
import Testing

@Suite("Direct Chat Path Conformance Tests")
struct DirectChatPathConformanceTests {

    // MARK: - OpenAI / OpenRouter Direct Chat Path

    @Test("Direct chat path parses OpenAI plain streamed text and reasoning")
    func testOpenAIDirectChatStreamParser() {
        let parser = HanlinChatStreamParser(apiType: "OpenAI")

        let chunk1 = "data: {\"choices\":[{\"delta\":{\"reasoning_content\":\"Thinking step\"}}]}\n\n"
        let events1 = parser.parse(chunk: chunk1)
        #expect(events1.count == 1)
        #expect(events1[0].reasoning == "Thinking step")

        let chunk2 = "data: {\"choices\":[{\"delta\":{\"content\":\"Final answer text\"},\"finish_reason\":\"stop\"}]}\n\n"
        let events2 = parser.parse(chunk: chunk2)
        #expect(events2.count == 1)
        #expect(events2[0].content == "Final answer text")
        #expect(events2[0].finishReason == "stop")
        #expect(events2[0].isDone == true)

        let doneEvent = parser.parse(line: "data: [DONE]")
        #expect(doneEvent?.isDone == true)
    }

    @Test("Direct chat path normalizes inline <think> tags")
    func testInlineThinkTagNormalization() {
        let parser = HanlinChatStreamParser(apiType: "OpenAI")

        let chunk1 = "data: {\"choices\":[{\"delta\":{\"content\":\"<think>internal reasoning\"}}]}\n\n"
        let events1 = parser.parse(chunk: chunk1)
        #expect(events1[0].reasoning == "internal reasoning")
        #expect(events1[0].content == nil)

        let chunk2 = "data: {\"choices\":[{\"delta\":{\"content\":\"</think>Visible answer\"}}]}\n\n"
        let events2 = parser.parse(chunk: chunk2)
        #expect(events2[0].content == "Visible answer")
    }

    @Test("Direct chat path tolerates empty deltas, malformed lines, and tool-shaped payloads")
    func testDirectChatStreamFaults() {
        let parser = HanlinChatStreamParser(apiType: "OpenAI")

        // Empty delta
        let emptyDelta = parser.parse(line: "data: {\"choices\":[{\"delta\":{}}]}")
        #expect(emptyDelta != nil)
        #expect(emptyDelta?.content == nil)

        // Malformed line
        let malformed = parser.parse(line: "data: {invalid json}")
        #expect(malformed == nil)

        // Non-data line
        let nonData = parser.parse(line: ": ping keepalive")
        #expect(nonData == nil)

        // Tool-shaped payload in direct chat path: parsed safely into toolCalls field without crashing
        let toolLine = "data: {\"choices\":[{\"delta\":{\"tool_calls\":[{\"id\":\"call_1\",\"function\":{\"name\":\"calc\",\"arguments\":\"{}\"}}]}}]}"
        let toolEvent = parser.parse(line: toolLine)
        #expect(toolEvent?.toolCalls != nil)
    }

    // MARK: - Anthropic Direct Chat Path

    @Test("Direct chat path parses Anthropic SSE events")
    func testAnthropicDirectChatStreamParser() {
        let parser = HanlinChatStreamParser(apiType: "anthropic")

        let start = parser.parse(line: "data: {\"type\":\"content_block_start\",\"index\":0,\"content_block\":{\"type\":\"text\",\"text\":\"\"}}")
        #expect(start != nil)

        let delta = parser.parse(line: "data: {\"type\":\"content_block_delta\",\"index\":0,\"delta\":{\"type\":\"text_delta\",\"text\":\"Hello from Claude\"}}")
        #expect(delta?.content == "Hello from Claude")

        let stop = parser.parse(line: "data: {\"type\":\"message_stop\"}")
        #expect(stop?.isDone == true)
    }

    // MARK: - Gemini Direct Chat Path

    @Test("Direct chat path parses Gemini SSE events")
    func testGeminiDirectChatStreamParser() {
        let parser = HanlinChatStreamParser(apiType: "gemini")

        let line = "data: {\"candidates\":[{\"content\":{\"parts\":[{\"text\":\"Hello from Gemini\"}]},\"finishReason\":\"STOP\"}]}"
        let event = parser.parse(line: line)
        #expect(event?.content == "Hello from Gemini")
        #expect(event?.finishReason == "stop")
        #expect(event?.isDone == true)
    }

    @Test("Gemini direct finish reason normalization matrix", arguments: [
        ("STOP", "stop"),
        ("MAX_TOKENS", "length"),
        ("MALFORMED_FUNCTION_CALL", "malformed_function_call"),
        ("SAFETY", "safety"),
        ("BLOCKLIST", "blocklist"),
        ("PROHIBITED_CONTENT", "prohibited_content"),
        ("SPII", "spii"),
        ("RECITATION", "recitation"),
        ("OTHER", "other"),
        ("FINISH_REASON_UNSPECIFIED", "finish_reason_unspecified")
    ])
    func testGeminiFinishReasonMatrix(rawReason: String, expectedNormalized: String) {
        let parser = HanlinChatStreamParser(apiType: "gemini")
        let line = "data: {\"candidates\":[{\"content\":{\"parts\":[{\"text\":\"Hello from Gemini\"}]},\"finishReason\":\"\(rawReason)\"}]}"
        let event = parser.parse(line: line)
        #expect(event?.finishReason == expectedNormalized)
        if rawReason == "STOP" {
            #expect(event?.isDone == true)
        }
    }

    // MARK: - Request Builder Parity

    @Test("Direct chat request builder generates correct headers and URL for OpenRouter")
    func testDirectChatRequestBuilderOpenRouter() throws {
        let config = HanlinChatModelConfiguration(
            modelID: "openai/gpt-4o",
            company: "OpenRouter",
            apiType: "openai",
            endpoint: "https://openrouter.ai/api/v1/chat/completions",
            credential: "test-or-key"
        )
        let request = try HanlinChatRequestBuilder.buildRequest(
            messages: [.user("Hello")],
            configuration: config,
            stream: true
        )
        #expect(request.value(forHTTPHeaderField: "HTTP-Referer") == "https://hanlin.ai")
        #expect(request.value(forHTTPHeaderField: "X-Title") == "Hanlin")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-or-key")
    }
}
