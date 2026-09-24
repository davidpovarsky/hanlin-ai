import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import AISDKProvider
import AISDKProviderUtils
import SwiftAISDK
@testable import HanlinChatCore
import Testing

// MARK: - Mock Language Model for HanlinNonEmptyLanguageModel Testing

private final class MockLanguageModelV3: LanguageModelV3, @unchecked Sendable {
    let provider: String = "mock-provider"
    let modelId: String = "mock-model"
    let supportedUrls: [String: [NSRegularExpression]] = [:]

    var streamGenerator: @Sendable (Int) -> AsyncThrowingStream<LanguageModelV3StreamPart, Error>
    private var _callCount: Int = 0
    private let lock = NSLock()

    init(streamGenerator: @escaping @Sendable (Int) -> AsyncThrowingStream<LanguageModelV3StreamPart, Error>) {
        self.streamGenerator = streamGenerator
    }

    private func incrementAndGetCallCount() -> Int {
        lock.lock()
        defer { lock.unlock() }
        _callCount += 1
        return _callCount
    }

    var callCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return _callCount
    }

    func doGenerate(options: LanguageModelV3CallOptions) async throws -> LanguageModelV3GenerateResult {
        fatalError("Not needed for stream tests")
    }

    func doStream(options: LanguageModelV3CallOptions) async throws -> LanguageModelV3StreamResult {
        let count = incrementAndGetCallCount()

        return LanguageModelV3StreamResult(
            stream: streamGenerator(count),
            request: nil,
            response: nil
        )
    }
}

// MARK: - HanlinAISDKProviderFactory Tests

@Suite("HanlinAISDK Provider Factory Tests")
struct HanlinAISDKProviderFactoryTests {

    @Test("OpenAI direct descriptor and options")
    func testOpenAIDescriptorAndOptions() {
        let config = HanlinChatModelConfiguration(
            modelID: "gpt-4o",
            displayName: "GPT-4o",
            company: "OpenAI",
            apiType: "openai",
            endpoint: "https://api.openai.com/v1/chat/completions",
            credential: "sk-proj-test123",
            supportsReasoning: true,
            reasoningEffort: "high"
        )

        let desc = HanlinAISDKProviderFactory.descriptor(for: config)
        #expect(desc.kind == .openAI)
        #expect(desc.modelID == "gpt-4o")
        #expect(desc.baseURL.absoluteString == "https://api.openai.com/v1")
        #expect(desc.headers.isEmpty)
    }

    @Test("Anthropic direct descriptor and options")
    func testAnthropicDescriptorAndOptions() {
        let config = HanlinChatModelConfiguration(
            modelID: "claude-3-7-sonnet-20250219",
            displayName: "Claude 3.7 Sonnet",
            company: "Anthropic",
            apiType: "anthropic",
            endpoint: "https://api.anthropic.com/v1/messages",
            credential: "sk-ant-test123",
            supportsReasoning: true,
            thinkingLength: 4096
        )

        let desc = HanlinAISDKProviderFactory.descriptor(for: config)
        #expect(desc.kind == .anthropic)
        #expect(desc.modelID == "claude-3-7-sonnet-20250219")
        #expect(desc.baseURL.absoluteString == "https://api.anthropic.com/v1")
    }

    @Test("Google Gemini descriptor and options")
    func testGeminiDescriptorAndOptions() {
        let config = HanlinChatModelConfiguration(
            modelID: "gemini-2.5-pro",
            displayName: "Gemini 2.5 Pro",
            company: "Google",
            apiType: "gemini",
            endpoint: "https://generativelanguage.googleapis.com/v1beta/chat/completions",
            credential: "AIza-test123",
            supportsReasoning: true,
            thinkingLength: 2048
        )

        let desc = HanlinAISDKProviderFactory.descriptor(for: config)
        #expect(desc.kind == .google)
        #expect(desc.modelID == "gemini-2.5-pro")
        #expect(desc.baseURL.absoluteString == "https://generativelanguage.googleapis.com/v1beta")
    }

    @Test("OpenRouter descriptor includes HTTP-Referer and X-Title headers")
    func testOpenRouterDescriptor() {
        let config = HanlinChatModelConfiguration(
            modelID: "anthropic/claude-3.5-sonnet",
            displayName: "Claude 3.5 Sonnet",
            company: "OpenRouter",
            apiType: "openai",
            endpoint: "https://openrouter.ai/api/v1/chat/completions",
            credential: "sk-or-test123"
        )

        let desc = HanlinAISDKProviderFactory.descriptor(for: config)
        #expect(desc.kind == .openAICompatible)
        #expect(desc.modelID == "anthropic/claude-3.5-sonnet")
        #expect(desc.baseURL.absoluteString == "https://openrouter.ai/api/v1")
        #expect(desc.headers["HTTP-Referer"] == "https://hanlin.ai")
        #expect(desc.headers["X-Title"] == "Hanlin")
    }

    @Test("Custom OpenAI compatible endpoint normalization")
    func testCustomOpenAICompatibleDescriptor() {
        let config = HanlinChatModelConfiguration(
            modelID: "local-llama-3",
            displayName: "Local Llama",
            company: "Ollama",
            apiType: "openai",
            endpoint: "http://localhost:11434/v1/chat/completions",
            credential: "test"
        )

        let desc = HanlinAISDKProviderFactory.descriptor(for: config)
        #expect(desc.kind == .openAICompatible)
        #expect(desc.modelID == "local-llama-3")
        #expect(desc.baseURL.absoluteString == "http://localhost:11434/v1")
    }
}

// MARK: - HanlinNonEmptyLanguageModel Tests

@Suite("HanlinNonEmptyLanguageModel Retry Tests")
struct HanlinNonEmptyLanguageModelTests {

    @Test("Retries once on empty stream and succeeds when second stream yields text")
    func testRetryOnceOnEmptyStream() async throws {
        let mock = MockLanguageModelV3 { attempt in
            AsyncThrowingStream(LanguageModelV3StreamPart.self) { (continuation: AsyncThrowingStream<LanguageModelV3StreamPart, Error>.Continuation) in
                if attempt == 1 {
                    // Empty stream (no meaningful chunks)
                    continuation.finish()
                } else {
                    continuation.yield(.textDelta(id: "t1", delta: "Hello world", providerMetadata: nil))
                    continuation.finish()
                }
            }
        }

        let model = HanlinNonEmptyLanguageModel(base: mock)
        let streamResult = try await model.doStream(options: LanguageModelV3CallOptions(prompt: []))

        var textChunks: [String] = []
        for try await part in streamResult.stream {
            if case .textDelta(_, let text, _) = part {
                textChunks.append(text)
            }
        }

        #expect(mock.callCount == 2)
        #expect(textChunks == ["Hello world"])
    }

    @Test("Throws emptyProviderResponse when two consecutive streams are empty")
    func testThrowsAfterTwoEmptyStreams() async throws {
        let mock = MockLanguageModelV3 { _ in
            AsyncThrowingStream(LanguageModelV3StreamPart.self) { (continuation: AsyncThrowingStream<LanguageModelV3StreamPart, Error>.Continuation) in
                continuation.finish()
            }
        }

        let model = HanlinNonEmptyLanguageModel(base: mock)
        let streamResult = try await model.doStream(options: LanguageModelV3CallOptions(prompt: []))

        var didThrowExpectedError = false
        do {
            for try await _ in streamResult.stream {}
        } catch let error as HanlinAISDKError {
            if case .emptyProviderResponse(let attempts) = error {
                #expect(attempts == 2)
                didThrowExpectedError = true
            }
        } catch {
            // Unexpected error
        }

        #expect(didThrowExpectedError)
        #expect(mock.callCount == 2)
    }

    @Test("Tool call in first stream is meaningful and prevents retrying")
    func testToolCallIsMeaningful() async throws {
        let mock = MockLanguageModelV3 { _ in
            AsyncThrowingStream(LanguageModelV3StreamPart.self) { (continuation: AsyncThrowingStream<LanguageModelV3StreamPart, Error>.Continuation) in
                continuation.yield(.toolCall(LanguageModelV3ToolCall(
                    toolCallId: "call_1",
                    toolName: "test_tool",
                    input: "{\"arg\":\"val\"}"
                )))
                continuation.finish()
            }
        }

        let model = HanlinNonEmptyLanguageModel(base: mock)
        let streamResult = try await model.doStream(options: LanguageModelV3CallOptions(prompt: []))

        var toolCallIds: [String] = []
        for try await part in streamResult.stream {
            if case .toolCall(let call) = part {
                toolCallIds.append(call.toolCallId)
            }
        }

        #expect(mock.callCount == 1)
        #expect(toolCallIds == ["call_1"])
    }
}

// MARK: - HanlinAISDKAgentEngine Integration Tests

@Suite("HanlinAISDKAgentEngine Integration Tests")
struct HanlinAISDKAgentEngineTests {

    private static func makeSSEResponse(chunks: [String], url: URL) -> FetchResponse {
        let stream = AsyncThrowingStream<Data, Error> { continuation in
            for chunk in chunks {
                continuation.yield(Data(chunk.utf8))
            }
            continuation.finish()
        }
        let response = HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "text/event-stream"]
        )!
        return FetchResponse(body: .stream(stream), urlResponse: response)
    }

    @Test("Tool continuation regression test: provider-native tool call and response pairing")
    func testToolContinuationRegression() async throws {
        let interceptedRequests = ManagedAtomicArray<URLRequest>()

        let fetch: FetchFunction = { request in
            interceptedRequests.append(request)
            let step = interceptedRequests.count

            if step == 1 {
                // Step 1: Model issues a tool call
                let sse = [
                    "data: {\"id\":\"c1\",\"choices\":[{\"index\":0,\"delta\":{\"tool_calls\":[{\"index\":0,\"id\":\"call_abc123\",\"type\":\"function\",\"function\":{\"name\":\"lookup\",\"arguments\":\"{\\\"word\\\":\\\"shalom\\\"}\"}}]},\"finish_reason\":null}]}\n\n",
                    "data: {\"id\":\"c1\",\"choices\":[{\"index\":0,\"delta\":{},\"finish_reason\":\"tool_calls\"}]}\n\n",
                    "data: [DONE]\n\n"
                ]
                return Self.makeSSEResponse(chunks: sse, url: request.url!)
            } else {
                // Step 2: Model receives tool result and completes answer
                let sse = [
                    "data: {\"id\":\"c2\",\"choices\":[{\"index\":0,\"delta\":{\"content\":\"Shalom means Peace.\"},\"finish_reason\":null}]}\n\n",
                    "data: {\"id\":\"c2\",\"choices\":[{\"index\":0,\"delta\":{},\"finish_reason\":\"stop\"}]}\n\n",
                    "data: [DONE]\n\n"
                ]
                return Self.makeSSEResponse(chunks: sse, url: request.url!)
            }
        }

        let config = HanlinChatModelConfiguration(
            modelID: "gpt-4o",
            company: "OpenAI",
            apiType: "openai",
            endpoint: "https://api.openai.com/v1/chat/completions",
            credential: "sk-test"
        )

        let engine = try HanlinAISDKAgentEngine(configuration: config, fetch: fetch)

        let toolDefinition = HanlinAISDKToolDefinition(
            name: "lookup",
            description: "Look up a word definition",
            inputSchemaData: try JSONSerialization.data(withJSONObject: [
                "type": "object",
                "properties": [
                    "word": ["type": "string"]
                ],
                "required": ["word"]
            ]),
            execute: { args, callID in
                #expect(callID == "call_abc123")
                return HanlinAISDKToolExecutionOutput(
                    modelText: "Definition: peace, completeness",
                    resultReference: "ref_1"
                )
            }
        )

        let messages: [HanlinAISDKMessage] = [
            .init(role: .user, text: "What does shalom mean?")
        ]

        let stream = try await engine.stream(
            messages: messages,
            baseSystemPrompt: "You are a translator.",
            tools: [toolDefinition],
            prepareStep: {
                HanlinAISDKStepPreparation(activeToolAliases: ["lookup"])
            }
        )

        var events: [HanlinAISDKStreamEvent] = []
        for try await event in stream {
            events.append(event)
        }

        // Verify captured requests:
        // Request 1: initial user message
        // Request 2: must contain assistant message with tool_calls AND tool message with tool_call_id
        #expect(interceptedRequests.count == 2)
        let step2BodyData = try #require(interceptedRequests.all[1].httpBody)
        let step2JSON = try #require(JSONSerialization.jsonObject(with: step2BodyData) as? [String: Any])
        let step2Messages = try #require(step2JSON["messages"] as? [[String: Any]])

        // Verify there is an assistant message with tool_calls
        let assistantMsg = try #require(step2Messages.first { ($0["role"] as? String) == "assistant" })
        let toolCalls = try #require(assistantMsg["tool_calls"] as? [[String: Any]])
        #expect(toolCalls.first?["id"] as? String == "call_abc123")

        // Verify there is a tool message with matching tool_call_id (NOT synthetic role=user!)
        let toolMsg = try #require(step2Messages.first { ($0["role"] as? String) == "tool" })
        #expect(toolMsg["tool_call_id"] as? String == "call_abc123")
        #expect((toolMsg["content"] as? String)?.contains("peace") == true)

        // Verify no synthetic role=user was inserted for the tool result
        let userMsgs = step2Messages.filter { ($0["role"] as? String) == "user" }
        #expect(userMsgs.count == 1) // only the original user prompt

        // Verify stream events
        let hasToolCall = events.contains {
            if case .toolCall(let call) = $0 { return call.id == "call_abc123" }
            return false
        }
        let hasToolResult = events.contains {
            if case .toolResult(let callID, _, let text, _) = $0 {
                return callID == "call_abc123" && text.contains("peace")
            }
            return false
        }
        let hasText = events.contains {
            if case .textDelta(let text) = $0 { return text.contains("Peace") }
            return false
        }

        #expect(hasToolCall)
        #expect(hasToolResult)
        #expect(hasText)
    }

    @Test("Parallel tool execution in a single model step")
    func testParallelToolExecution() async throws {
        let interceptedRequests = ManagedAtomicArray<URLRequest>()

        let fetch: FetchFunction = { request in
            interceptedRequests.append(request)
            let step = interceptedRequests.count

            if step == 1 {
                // Model issues 2 parallel tool calls
                let sse = [
                    "data: {\"id\":\"p1\",\"choices\":[{\"index\":0,\"delta\":{\"tool_calls\":[{\"index\":0,\"id\":\"call_1\",\"type\":\"function\",\"function\":{\"name\":\"calc\",\"arguments\":\"{\\\"op\\\":\\\"add\\\"}\"}},{\"index\":1,\"id\":\"call_2\",\"type\":\"function\",\"function\":{\"name\":\"calc\",\"arguments\":\"{\\\"op\\\":\\\"sub\\\"}\"}}]},\"finish_reason\":null}]}\n\n",
                    "data: {\"id\":\"p1\",\"choices\":[{\"index\":0,\"delta\":{},\"finish_reason\":\"tool_calls\"}]}\n\n",
                    "data: [DONE]\n\n"
                ]
                return Self.makeSSEResponse(chunks: sse, url: request.url!)
            } else {
                let sse = [
                    "data: {\"id\":\"p2\",\"choices\":[{\"index\":0,\"delta\":{\"content\":\"Results calculated.\"},\"finish_reason\":\"stop\"}]}\n\n",
                    "data: [DONE]\n\n"
                ]
                return Self.makeSSEResponse(chunks: sse, url: request.url!)
            }
        }

        let config = HanlinChatModelConfiguration(
            modelID: "gpt-4o",
            company: "OpenAI",
            apiType: "openai",
            endpoint: "https://api.openai.com/v1/chat/completions",
            credential: "sk-test"
        )

        let engine = try HanlinAISDKAgentEngine(configuration: config, fetch: fetch)

        let tool = HanlinAISDKToolDefinition(
            name: "calc",
            description: "Calculator",
            inputSchemaData: try JSONSerialization.data(withJSONObject: [
                "type": "object",
                "properties": ["op": ["type": "string"]]
            ]),
            execute: { args, callID in
                HanlinAISDKToolExecutionOutput(modelText: "Result for \(callID)")
            }
        )

        let stream = try await engine.stream(
            messages: [.init(role: .user, text: "Calculate both")],
            baseSystemPrompt: "Helper",
            tools: [tool],
            prepareStep: { HanlinAISDKStepPreparation(activeToolAliases: ["calc"]) }
        )

        var toolResults: [String: String] = [:]
        for try await event in stream {
            if case .toolResult(let callID, _, let text, _) = event {
                toolResults[callID] = text
            }
        }

        #expect(toolResults["call_1"] == "Result for call_1")
        #expect(toolResults["call_2"] == "Result for call_2")

        // Inspect second request messages
        #expect(interceptedRequests.count == 2)
        let step2Body = try #require(interceptedRequests.all[1].httpBody)
        let step2JSON = try #require(JSONSerialization.jsonObject(with: step2Body) as? [String: Any])
        let messages = try #require(step2JSON["messages"] as? [[String: Any]])

        let toolMsgs = messages.filter { ($0["role"] as? String) == "tool" }
        #expect(toolMsgs.count == 2)
        let callIDs = Set(toolMsgs.compactMap { $0["tool_call_id"] as? String })
        #expect(callIDs == ["call_1", "call_2"])
    }

    @Test("Dynamic tool exposure via prepareStep filters active tools")
    func testDynamicToolExposure() async throws {
        let stepCount = ManagedAtomicInt()

        let fetch: FetchFunction = { request in
            let count = stepCount.increment()
            if count == 1 {
                // Step 1: Model calls load_skill
                let sse = [
                    "data: {\"id\":\"s1\",\"choices\":[{\"index\":0,\"delta\":{\"tool_calls\":[{\"index\":0,\"id\":\"call_load\",\"type\":\"function\",\"function\":{\"name\":\"load_skill\",\"arguments\":\"{\\\"skill\\\":\\\"code\\\"}\"}}]},\"finish_reason\":\"tool_calls\"}]}\n\n",
                    "data: [DONE]\n\n"
                ]
                return Self.makeSSEResponse(chunks: sse, url: request.url!)
            } else {
                // Step 2: Model finishes with explanation
                let sse = [
                    "data: {\"id\":\"s2\",\"choices\":[{\"index\":0,\"delta\":{\"content\":\"Python tool is now ready.\"},\"finish_reason\":\"stop\"}]}\n\n",
                    "data: [DONE]\n\n"
                ]
                return Self.makeSSEResponse(chunks: sse, url: request.url!)
            }
        }

        let config = HanlinChatModelConfiguration(
            modelID: "gpt-4o",
            company: "OpenAI",
            apiType: "openai",
            endpoint: "https://api.openai.com/v1/chat/completions",
            credential: "sk-test"
        )

        let engine = try HanlinAISDKAgentEngine(configuration: config, fetch: fetch)

        let loadSkillTool = HanlinAISDKToolDefinition(
            name: "load_skill",
            description: "Load a skill",
            inputSchemaData: try JSONSerialization.data(withJSONObject: [
                "type": "object",
                "properties": ["skill": ["type": "string"]]
            ]),
            execute: { _, _ in
                HanlinAISDKToolExecutionOutput(modelText: "Skill 'code' loaded.")
            }
        )

        let pythonTool = HanlinAISDKToolDefinition(
            name: "execute_python",
            description: "Run python code",
            inputSchemaData: try JSONSerialization.data(withJSONObject: [
                "type": "object",
                "properties": ["code": ["type": "string"]]
            ]),
            execute: { _, _ in
                HanlinAISDKToolExecutionOutput(modelText: "python output")
            }
        )

        let preparedSteps = ManagedAtomicArray<HanlinAISDKStepPreparation>()

        let stream = try await engine.stream(
            messages: [.init(role: .user, text: "Load python skill")],
            baseSystemPrompt: "System",
            tools: [loadSkillTool, pythonTool],
            prepareStep: {
                let current = preparedSteps.count
                if current == 0 {
                    let prep = HanlinAISDKStepPreparation(
                        activeToolAliases: ["load_skill"],
                        loadedSkillIDs: []
                    )
                    preparedSteps.append(prep)
                    return prep
                } else {
                    let prep = HanlinAISDKStepPreparation(
                        activeToolAliases: ["load_skill", "execute_python"],
                        loadedSkillIDs: ["code"],
                        loadedSkillInstructions: ["Use execute_python for code execution"]
                    )
                    preparedSteps.append(prep)
                    return prep
                }
            }
        )

        var stepStartedPreparations: [HanlinAISDKStepPreparation] = []
        for try await event in stream {
            if case .stepStarted(_, let prep) = event {
                stepStartedPreparations.append(prep)
            }
        }

        #expect(stepStartedPreparations.count == 2)
        #expect(stepStartedPreparations[0].activeToolAliases == ["load_skill"])
        #expect(stepStartedPreparations[1].activeToolAliases == ["load_skill", "execute_python"])
        #expect(stepStartedPreparations[1].loadedSkillIDs == ["code"])
    }
}

// MARK: - Thread-safe Helpers for Testing

private final class ManagedAtomicArray<T>: @unchecked Sendable {
    private var elements: [T] = []
    private let lock = NSLock()

    func append(_ element: T) {
        lock.lock()
        elements.append(element)
        lock.unlock()
    }

    var all: [T] {
        lock.lock()
        defer { lock.unlock() }
        return elements
    }

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return elements.count
    }
}

private final class ManagedAtomicInt: @unchecked Sendable {
    private var value: Int = 0
    private let lock = NSLock()

    @discardableResult
    func increment() -> Int {
        lock.lock()
        value += 1
        let val = value
        lock.unlock()
        return val
    }
}
