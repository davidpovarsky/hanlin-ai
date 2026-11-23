import AISDKProviderUtils
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import HanlinPlatformContracts
import Testing
@testable import HanlinChatCore

@Suite struct HanlinChatGPTPlanTests {
    private static func event(_ object: [String: Any]) throws -> Data {
        Data(("data: " + String(decoding: try JSONSerialization.data(withJSONObject: object), as: UTF8.self) + "\n\n").utf8)
    }
    private static func complete() throws -> Data {
        try event(["type": "response.completed", "response": ["id": "r1", "status": "completed",
            "usage": ["input_tokens": 2, "output_tokens": 2]]])
    }

    @Test func namespacesToolsAndPreservesFullStatelessHistory() throws {
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/responses")!)
        let arguments = #"{"id":9007199254740993,"text":"שלום"}"#
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": "fixture", "store": true, "stream": false,
            "max_output_tokens": 100, "temperature": 1, "previous_response_id": "old",
            "input": [["role": "system", "content": "Instructions"],
                      ["type": "function_call", "name": "lookup", "call_id": "call1", "arguments": arguments],
                      ["type": "function_call_output", "call_id": "call1", "output": "result"]],
            "tools": [["type": "function", "name": "lookup",
                       "parameters": ["type": "object", "properties": [:]]]]
        ])
        let prepared = try HanlinChatGPTPlanWire.prepare(request)
        let body = try #require(JSONSerialization.jsonObject(with: #require(prepared.httpBody)) as? [String: Any])
        #expect(body["store"] as? Bool == false && body["stream"] as? Bool == true)
        #expect(body["max_output_tokens"] == nil && body["temperature"] == nil && body["previous_response_id"] == nil)
        let tools = try #require(body["tools"] as? [[String: Any]])
        #expect(tools.first?["type"] as? String == "namespace")
        #expect(tools.first?["name"] as? String == "hanlin")
        let input = try #require(body["input"] as? [[String: Any]])
        #expect(input.count == 3 && input[0]["role"] as? String == "developer")
        #expect(input[1]["namespace"] as? String == "hanlin")
        #expect(input[1]["arguments"] as? String == arguments)
        #expect(input[2]["call_id"] as? String == "call1")
    }

    @Test func fragmentedUTF8StreamMustReachCompletion() throws {
        let text = try Self.event(["type": "response.output_text.delta", "delta": "שלום 👋"])
        let complete = try Self.complete()
        let source = text + complete
        var validator = HanlinChatGPTPlanSSEValidator()
        var forwarded = Data()
        for byte in source {
            for event in try validator.consume(Data([byte])) { forwarded.append(event) }
        }
        try validator.finish()
        #expect(forwarded == source)
    }

    @Test func partialTextAndDoneWithoutCompletedAreNotSuccess() throws {
        var validator = HanlinChatGPTPlanSSEValidator()
        _ = try validator.consume(Self.event(["type": "response.output_text.delta", "delta": "partial"]))
        _ = try validator.consume(Data("data: [DONE]\n\n".utf8))
        #expect(throws: HanlinChatGPTPlanWireError.missingCompletion) { try validator.finish() }
    }

    @Test func quotaFailureAndIncompleteAreSurfaced() throws {
        var validator = HanlinChatGPTPlanSSEValidator()
        let failed = try Self.event(["type": "response.failed", "response": ["status": "failed",
            "error": ["code": "subscription_sharing_usage_limit_exceeded"]]])
        #expect(throws: HanlinChatGPTPlanWireError.failed("subscription_sharing_usage_limit_exceeded")) {
            _ = try validator.consume(failed)
        }
        var other = HanlinChatGPTPlanSSEValidator()
        let incomplete = try Self.event(["type": "response.incomplete",
            "response": ["status": "incomplete", "incomplete_details": ["reason": "max_output_tokens"]]])
        #expect(throws: HanlinChatGPTPlanWireError.incomplete("max_output_tokens")) {
            _ = try other.consume(incomplete)
        }
    }

    @Test func mismatchedToolNamespaceIsRejectedBeforeDispatch() throws {
        var validator = HanlinChatGPTPlanSSEValidator()
        let event = try Self.event(["type": "response.output_item.added",
            "item": ["type": "function_call", "name": "lookup", "namespace": "another_app"]])
        #expect(throws: HanlinChatGPTPlanWireError.invalidEvent) { _ = try validator.consume(event) }
    }

    private actor Calls {
        var requests = 0
        var effects = 0
        func request() -> Int { requests += 1; return requests }
        func effect() { effects += 1 }
    }

    @Test func canonicalAgentExecutesNamespacedToolAndContinuesExactlyOnce() async throws {
        let calls = Calls()
        let fetch: FetchFunction = { request in
            let index = await calls.request()
            let body = try #require(JSONSerialization.jsonObject(with: #require(request.httpBody)) as? [String: Any])
            #expect(body["store"] as? Bool == false && body["stream"] as? Bool == true)
            let tools = try #require(body["tools"] as? [[String: Any]])
            #expect(tools.first?["type"] as? String == "namespace")
            var bytes = Data()
            if index == 1 {
                bytes.append(try Self.event(["type": "response.output_item.added", "output_index": 0,
                    "item": ["id": "fc1", "type": "function_call", "status": "in_progress",
                        "name": "lookup", "namespace": "hanlin", "call_id": "call1"]]))
                bytes.append(try Self.event(["type": "response.function_call_arguments.delta",
                    "output_index": 0, "delta": "{}"]))
                bytes.append(try Self.event(["type": "response.output_item.done", "output_index": 0,
                    "item": ["id": "fc1", "type": "function_call", "status": "completed", "name": "lookup",
                        "namespace": "hanlin", "call_id": "call1", "arguments": "{}"]]))
            } else {
                #expect(index == 2)
                let input = try #require(body["input"] as? [[String: Any]])
                #expect(input.contains { $0["type"] as? String == "function_call_output" && $0["call_id"] as? String == "call1" })
                #expect(input.contains { $0["type"] as? String == "function_call" && $0["namespace"] as? String == "hanlin" })
                bytes.append(try Self.event(["type": "response.output_item.added", "output_index": 0,
                    "item": ["id": "msg1", "type": "message", "status": "in_progress", "role": "assistant", "content": []]]))
                bytes.append(try Self.event(["type": "response.output_text.delta", "item_id": "msg1",
                    "output_index": 0, "content_index": 0, "delta": "Done"]))
                bytes.append(try Self.event(["type": "response.output_item.done", "output_index": 0,
                    "item": ["id": "msg1", "type": "message", "status": "completed", "role": "assistant",
                        "content": [["type": "output_text", "text": "Done", "annotations": []]]]]))
            }
            bytes.append(try Self.complete())
            return FetchResponse(body: .data(bytes), urlResponse: HTTPURLResponse(url: request.url!,
                statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "text/event-stream"])!)
        }
        let config = HanlinChatModelConfiguration(modelID: "gpt-6.1-sol", company: "OPENAI",
            apiType: "openai-chatgpt-plan", endpoint: "https://api.openai.com/v1/responses",
            credential: "fixture-only", supportsToolUse: true)
        let tool = HanlinAISDKToolDefinition(name: "lookup", description: "Test lookup",
            inputSchemaData: Data(#"{"type":"object","properties":{},"additionalProperties":false}"#.utf8),
            execute: { _, _ in await calls.effect(); return .init(modelText: "Found") })
        let engine = try HanlinAISDKAgentEngine(configuration: config, fetch: fetch)
        let stream = try await engine.stream(messages: [.init(role: .user, text: "Look up")],
            baseSystemPrompt: "Use the tool", tools: [tool], maxSteps: 3,
            prepareStep: { .init(activeToolAliases: ["lookup"]) })
        var finished = false
        for try await event in stream { if case .finished = event { finished = true } }
        let effectCount = await calls.effects
        let requestCount = await calls.requests
        #expect(finished && effectCount == 1 && requestCount == 2)
    }
}
