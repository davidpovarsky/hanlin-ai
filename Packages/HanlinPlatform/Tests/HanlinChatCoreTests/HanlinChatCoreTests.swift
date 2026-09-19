import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import HanlinChatCore
import Testing

@Suite("HanlinChatCore Tests")
struct HanlinChatCoreTests {

    @Test("HanlinChatModelConfiguration bounds maxTokens to prevent OpenRouter HTTP 402")
    func testModelConfigurationBoundsMaxTokens() {
        // Default maxTokens should be 2048
        let configDefault = HanlinChatModelConfiguration(
            modelID: "openai/gpt-4o",
            displayName: "GPT-4o",
            company: "OpenRouter",
            apiType: "openai",
            endpoint: "https://openrouter.ai/api/v1",
            credential: "test-api-key"
        )
        #expect(configDefault.maxTokens == 2048)

        // Nil maxTokens defaults to 2048
        let configNil = HanlinChatModelConfiguration(
            modelID: "anthropic/claude-3.5-sonnet",
            displayName: "Claude 3.5 Sonnet",
            company: "OpenRouter",
            apiType: "openai",
            endpoint: "https://openrouter.ai/api/v1",
            credential: "test-api-key",
            maxTokens: nil
        )
        #expect(configNil.maxTokens == 2048)

        // Explicit reasonable maxTokens is preserved
        let configExplicit = HanlinChatModelConfiguration(
            modelID: "meta-llama/llama-3.1-70b-instruct",
            displayName: "Llama 3.1",
            company: "OpenRouter",
            apiType: "openai",
            endpoint: "https://openrouter.ai/api/v1",
            credential: "test-api-key",
            maxTokens: 4096
        )
        #expect(configExplicit.maxTokens == 4096)

        // Excessive maxTokens is capped to 8192
        let configExcessive = HanlinChatModelConfiguration(
            modelID: "deepseek/deepseek-r1",
            displayName: "DeepSeek R1",
            company: "OpenRouter",
            apiType: "openai",
            endpoint: "https://openrouter.ai/api/v1",
            credential: "test-api-key",
            maxTokens: 128_000
        )
        #expect(configExcessive.maxTokens == 8192)
    }

    @Test("HanlinChatRequestBuilder creates correct OpenAI/OpenRouter request with bounded max_tokens")
    func testOpenAIRequestBuilder() throws {
        let config = HanlinChatModelConfiguration(
            modelID: "google/gemini-2.0-flash-001",
            displayName: "Gemini 2.0 Flash",
            company: "OpenRouter",
            apiType: "openai",
            endpoint: "https://openrouter.ai/api/v1",
            credential: "sk-or-v1-testkey123",
            temperature: 0.7,
            topP: 0.95,
            maxTokens: 2048,
            supportsReasoning: true,
            reasoningEffort: "medium"
        )

        let messages: [HanlinChatMessage] = [
            .system("You are a helpful translation assistant."),
            .user("Translate 'Shalom' to English.")
        ]

        let request = try HanlinChatRequestBuilder.buildRequest(
            messages: messages,
            configuration: config,
            stream: true
        )

        #expect(request.httpMethod == "POST")
        #expect(request.url?.absoluteString == "https://openrouter.ai/api/v1/chat/completions")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer sk-or-v1-testkey123")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
        #expect(request.value(forHTTPHeaderField: "HTTP-Referer") != nil)
        #expect(request.value(forHTTPHeaderField: "X-Title") == "Hanlin")

        guard let bodyData = request.httpBody else {
            Issue.record("Missing HTTP body in request")
            return
        }

        let json = try JSONSerialization.jsonObject(with: bodyData) as? [String: Any]
        let model = json?["model"] as? String
        #expect(model == "google/gemini-2.0-flash-001")
        let stream = json?["stream"] as? Bool
        #expect(stream == true)
        let maxTokens = json?["max_tokens"] as? Int
        #expect(maxTokens == 2048)
        let temp = json?["temperature"] as? Double
        #expect(temp == 0.7)
        let topP = json?["top_p"] as? Double
        #expect(topP == 0.95)

        // Verify reasoning parameters for OpenRouter
        let reasoning = json?["reasoning"] as? [String: Any]
        let effort = reasoning?["effort"] as? String
        #expect(effort == "medium")

        // Verify formatted messages
        let msgs = json?["messages"] as? [[String: Any]]
        #expect(msgs?.count == 2)
        let role0 = msgs?[0]["role"] as? String
        #expect(role0 == "system")
        let content0 = msgs?[0]["content"] as? String
        #expect(content0 == "You are a helpful translation assistant.")
        let role1 = msgs?[1]["role"] as? String
        #expect(role1 == "user")
        let content1 = msgs?[1]["content"] as? String
        #expect(content1 == "Translate 'Shalom' to English.")
    }

    @Test("HanlinChatRequestBuilder creates correct Anthropic native request")
    func testAnthropicRequestBuilder() throws {
        let config = HanlinChatModelConfiguration(
            modelID: "claude-3-5-sonnet-20241022",
            displayName: "Claude 3.5 Sonnet",
            company: "Anthropic",
            apiType: "anthropic",
            endpoint: "https://api.anthropic.com/v1",
            credential: "sk-ant-api03-testkey",
            temperature: 0.5,
            maxTokens: 2048
        )

        let messages: [HanlinChatMessage] = [
            .system("You are an expert Torah scholar."),
            .user("What does Bereshit mean?")
        ]

        let request = try HanlinChatRequestBuilder.buildRequest(
            messages: messages,
            configuration: config,
            stream: true
        )

        #expect(request.httpMethod == "POST")
        #expect(request.url?.absoluteString == "https://api.anthropic.com/v1/messages")
        #expect(request.value(forHTTPHeaderField: "x-api-key") == "sk-ant-api03-testkey")
        #expect(request.value(forHTTPHeaderField: "anthropic-version") == "2023-06-01")

        guard let bodyData = request.httpBody else {
            Issue.record("Missing HTTP body")
            return
        }

        let json = try JSONSerialization.jsonObject(with: bodyData) as? [String: Any]
        let model = json?["model"] as? String
        #expect(model == "claude-3-5-sonnet-20241022")
        let maxTokens = json?["max_tokens"] as? Int
        #expect(maxTokens == 2048)
        let system = json?["system"] as? String
        #expect(system == "You are an expert Torah scholar.")
        let stream = json?["stream"] as? Bool
        #expect(stream == true)

        let msgs = json?["messages"] as? [[String: Any]]
        #expect(msgs?.count == 1)
        let role0 = msgs?[0]["role"] as? String
        #expect(role0 == "user")
        let content0 = msgs?[0]["content"] as? String
        #expect(content0 == "What does Bereshit mean?")
    }

    @Test("HanlinChatRequestBuilder creates correct Gemini native request")
    func testGeminiRequestBuilder() throws {
        let config = HanlinChatModelConfiguration(
            modelID: "gemini-2.0-flash",
            displayName: "Gemini 2.0 Flash",
            company: "Google",
            apiType: "gemini",
            endpoint: "https://generativelanguage.googleapis.com/v1beta",
            credential: "AIzaSyTestKey123",
            temperature: 0.2,
            maxTokens: 2048
        )

        let messages: [HanlinChatMessage] = [
            .user("Explain the Talmudic principle of Kal Vachomer.")
        ]

        let request = try HanlinChatRequestBuilder.buildRequest(
            messages: messages,
            configuration: config,
            stream: true
        )

        #expect(request.httpMethod == "POST")
        #expect(request.url?.absoluteString.contains(":streamGenerateContent?alt=sse") == true)
        #expect(request.value(forHTTPHeaderField: "x-goog-api-key") == "AIzaSyTestKey123")

        guard let bodyData = request.httpBody else {
            Issue.record("Missing HTTP body")
            return
        }

        guard let json = try JSONSerialization.jsonObject(with: bodyData) as? [String: Any],
              let genConfig = json["generationConfig"] as? [String: Any],
              let contents = json["contents"] as? [[String: Any]] else {
            Issue.record("Malformed JSON body")
            return
        }
        let maxOutputTokens = genConfig["maxOutputTokens"] as? Int
        #expect(maxOutputTokens == 2048)
        let temp = genConfig["temperature"] as? Double
        #expect(temp == 0.2)

        #expect(contents.count == 1)
        let role = contents.first?["role"] as? String
        #expect(role == "user")
    }

    @Test("HanlinChatStreamParser correctly parses OpenAI SSE content, reasoning, and done events")
    func testOpenAIStreamParsing() {
        let parser = HanlinChatStreamParser(apiType: "openai")

        // Standard content chunk
        let event1 = "data: {\"choices\":[{\"delta\":{\"content\":\"Hello \"}}]}\n\n"
        let events1 = parser.parse(chunk: event1)
        #expect(events1.count == 1)
        #expect(events1.first?.content == "Hello ")

        // Reasoning chunk (e.g. DeepSeek R1 / OpenRouter reasoning)
        let event2 = "data: {\"choices\":[{\"delta\":{\"reasoning_content\":\"I think therefore I am\"}}]}\n\n"
        let events2 = parser.parse(chunk: event2)
        #expect(events2.count == 1)
        #expect(events2.first?.reasoning == "I think therefore I am")

        // Usage chunk
        let event3 = "data: {\"choices\":[],\"usage\":{\"prompt_tokens\":15,\"completion_tokens\":42,\"total_tokens\":57}}\n\n"
        let events3 = parser.parse(chunk: event3)
        #expect(events3.count == 1)
        #expect(events3.first?.tokenUsage?.promptTokens == 15)
        #expect(events3.first?.tokenUsage?.completionTokens == 42)
        #expect(events3.first?.tokenUsage?.totalTokens == 57)

        // Done chunk
        let event4 = "data: [DONE]\n\n"
        let events4 = parser.parse(chunk: event4)
        #expect(events4.count == 1)
        #expect(events4.first?.isDone == true)
    }

    @Test("HanlinChatStreamParser extracts <think> tags into reasoning events")
    func testThinkTagParsing() {
        let parser = HanlinChatStreamParser(apiType: "openai")

        let chunk = "data: {\"choices\":[{\"delta\":{\"content\":\"<think>Analyzing question...</think>The translation is Peace.\"}}]}\n\n"
        let events = parser.parse(chunk: chunk)

        var foundReasoning = false
        var foundContent = false

        for event in events {
            if let r = event.reasoning, r == "Analyzing question..." {
                foundReasoning = true
            }
            if let c = event.content, c == "The translation is Peace." {
                foundContent = true
            }
        }

        #expect(foundReasoning)
        #expect(foundContent)
    }

    @Test("HanlinChatStreamParser correctly parses Anthropic SSE events")
    func testAnthropicStreamParsing() {
        let parser = HanlinChatStreamParser(apiType: "anthropic")

        let chunk = "data: {\"type\":\"content_block_delta\",\"index\":0,\"delta\":{\"type\":\"text_delta\",\"text\":\"Shalom means Peace.\"}}\n\n"
        let events = parser.parse(chunk: chunk)

        #expect(events.count == 1)
        #expect(events.first?.content == "Shalom means Peace.")

        let stopChunk = "data: {\"type\":\"message_stop\"}\n\n"
        let stopEvents = parser.parse(chunk: stopChunk)
        #expect(stopEvents.contains { $0.isDone })
    }

    @Test("HanlinChatStreamParser correctly parses Gemini SSE events")
    func testGeminiStreamParsing() {
        let parser = HanlinChatStreamParser(apiType: "gemini")

        let chunk = "data: {\"candidates\":[{\"content\":{\"parts\":[{\"text\":\"Bereshit translates to In the beginning.\"}]}}]}\n\n"
        let events = parser.parse(chunk: chunk)

        #expect(events.count == 1)
        #expect(events.first?.content == "Bereshit translates to In the beginning.")
    }
}
