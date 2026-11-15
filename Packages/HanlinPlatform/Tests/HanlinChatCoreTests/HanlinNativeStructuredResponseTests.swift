import AISDKProviderUtils
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import HanlinPlatformContracts
import Testing
@testable import HanlinChatCore

/// These tests execute the pinned production Responses adapter with intercepted HTTP.
/// They prove provider-wire mapping and canonical delivery, not live-model/renderer acceptance.
@Suite struct HanlinNativeStructuredResponseTests {
    private static func configuration(model: String = HanlinNativeStructuredResponse.modelID,
                                      api: String = "openai-responses") -> HanlinChatModelConfiguration {
        .init(modelID: model, company: "OPENAI", apiType: api,
              endpoint: "https://api.openai.com/v1/responses", credential: "fixture-only", supportsToolUse: true)
    }

    private static func event(_ object: [String: Any]) throws -> String {
        "data: " + String(decoding: try JSONSerialization.data(withJSONObject: object), as: UTF8.self) + "\n\n"
    }

    private static func response(_ text: String, url: URL, complete: Bool = true,
                                 truncated: Bool = false) throws -> FetchResponse {
        let middle = text.index(text.startIndex, offsetBy: text.count / 2)
        var chunks = [try event(["type": "response.output_item.added", "output_index": 0,
            "item": ["id": "msg_fixture", "type": "message", "status": "in_progress", "role": "assistant", "content": []]])]
        for delta in [String(text[..<middle]), String(text[middle...])] {
            chunks.append(try event(["type": "response.output_text.delta", "item_id": "msg_fixture",
                "output_index": 0, "content_index": 0, "delta": delta]))
        }
        if complete {
            chunks.append(try event(["type": "response.output_item.done", "output_index": 0,
                "item": ["id": "msg_fixture", "type": "message", "status": "completed", "role": "assistant",
                    "content": [["type": "output_text", "text": text, "annotations": []]]]]))
            chunks.append(try event(["type": truncated ? "response.incomplete" : "response.completed", "response": [
                "id": "resp_fixture", "status": truncated ? "incomplete" : "completed",
                "incomplete_details": truncated ? (["reason": "max_output_tokens"] as Any) : (NSNull() as Any),
                "usage": ["input_tokens": 4, "output_tokens": 8]]]))
        }
        return sse(chunks, url: url)
    }

    private static func sse(_ chunks: [String], url: URL) -> FetchResponse {
        let stream = AsyncThrowingStream<Data, Error> { continuation in
            for chunk in chunks { continuation.yield(Data(chunk.utf8)) }
            continuation.finish()
        }
        return FetchResponse(body: .stream(stream), urlResponse: HTTPURLResponse(url: url, statusCode: 200,
            httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "text/event-stream"])!)
    }

    private actor Calls {
        var requests = 0; var effects = 0
        func request() -> Int { requests += 1; return requests }
        func effect() { effects += 1 }
    }

    @Test func nativeSchemaKeepsTheExistingToolContinuationAndExactlyOneEffect() async throws {
        let calls = Calls()
        let wire = try Self.wire([Self.text])
        let fetch: FetchFunction = { request in
            let index = await calls.request()
            let requestData = try #require(request.httpBody)
            let body = try #require(JSONSerialization.jsonObject(with: requestData) as? [String: Any])
            let url = try #require(request.url)
            #expect((body["text"] as? [String: Any])?["format"] != nil)
            if index == 1 {
                return Self.sse([
                    try Self.event(["type": "response.output_item.added", "output_index": 0,
                        "item": ["id": "fc1", "type": "function_call", "status": "in_progress", "name": "lookup", "call_id": "call1"]]),
                    try Self.event(["type": "response.function_call_arguments.delta", "output_index": 0, "delta": "{}"]),
                    try Self.event(["type": "response.output_item.done", "output_index": 0,
                        "item": ["id": "fc1", "type": "function_call", "status": "completed", "name": "lookup",
                            "call_id": "call1", "arguments": "{}"]]),
                    try Self.event(["type": "response.completed", "response": ["id": "r1", "status": "completed",
                        "usage": ["input_tokens": 2, "output_tokens": 2]]])
                ], url: url)
            }
            #expect(index == 2)
            let input = try #require(body["input"] as? [[String: Any]])
            let results = input.filter { $0["type"] as? String == "function_call_output" }
            #expect(results.count == 1)
            #expect(results.first?["call_id"] as? String == "call1")
            return try Self.response(wire, url: #require(request.url))
        }
        let tool = HanlinAISDKToolDefinition(name: "lookup", description: "Synthetic read",
            inputSchemaData: Data(#"{"type":"object","properties":{},"additionalProperties":false}"#.utf8),
            execute: { _, _ in await calls.effect(); return .init(modelText: "Synthetic result") })
        let engine = try HanlinAISDKAgentEngine(configuration: Self.configuration(), fetch: fetch)
        let source = try await engine.stream(messages: [.init(role: .user, text: "Read then answer")], baseSystemPrompt: nil,
            tools: [tool], maxSteps: 3, structuredResponse: .init(messageID: UUID(), validateCompleteParts: { _ in }),
            prepareStep: { .init(activeToolAliases: ["lookup"]) })
        var results = 0; var parts = 0
        for try await event in source {
            if case .toolResult = event { results += 1 }
            if case .structuredPart = event { parts += 1 }
            if case .textDelta = event { Issue.record("Provider schema JSON leaked") }
        }
        #expect(results == 1 && parts == 1)
        #expect(await calls.effects == 1)
        #expect(await calls.requests == 2)
    }

    private static func wire(_ parts: [[String: Any]]) throws -> String {
        String(decoding: try JSONSerialization.data(withJSONObject: ["parts": parts]), as: UTF8.self)
    }

    private static var text: [String: Any] {
        ["part": "before", "kind": "text", "text": "Before", "a2uiJSON": NSNull()]
    }

    @Test func realResponsesAdapterRequestsStrictSchemaAndPublishesOnlyCanonicalParts() async throws {
        let message = UUID()
        let official = #"{"version":"1.0","createSurface":{"surfaceId":"surface","catalogId":"https://a2ui.org/specification/v1_0/catalogs/basic/catalog.json"}}"#
        let wire = try Self.wire([Self.text,
            ["part": "surface", "kind": "a2ui", "text": NSNull(), "a2uiJSON": official],
            ["part": "after", "kind": "text", "text": "After", "a2uiJSON": NSNull()]])
        let fetch: FetchFunction = { request in
            #expect(request.url?.absoluteString == "https://api.openai.com/v1/responses")
            let body = try #require(request.httpBody)
            let json = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
            #expect(json["model"] as? String == HanlinNativeStructuredResponse.modelID)
            #expect(json["stream"] as? Bool == true)
            #expect(json["response_format"] == nil)
            let format = try #require((json["text"] as? [String: Any])?["format"] as? [String: Any])
            #expect(format["type"] as? String == "json_schema")
            #expect(format["strict"] as? Bool == true)
            #expect(format["name"] as? String == "hanlin_chat_parts_v1")
            let schema = try #require(format["schema"] as? [String: Any])
            #expect(schema["additionalProperties"] as? Bool == false)
            #expect(schema["required"] as? [String] == ["parts"])
            return try Self.response(wire, url: #require(request.url))
        }
        let contract = HanlinNativeStructuredResponse(messageID: message) { parts in
            // Fixture validation only; the application must supply the official A2UI validator.
            #expect(parts.count == 3)
            #expect(parts.allSatisfy { $0.messageID == message })
        }
        let engine = try HanlinAISDKAgentEngine(configuration: Self.configuration(), fetch: fetch)
        let source = try await engine.stream(messages: [.init(role: .user, text: "Show the result")],
            baseSystemPrompt: nil, tools: [], structuredResponse: contract, prepareStep: { .init(activeToolAliases: []) })
        var parts = [HanlinChatStructuredPart](); var advertised = 0; var finishes = 0
        for try await event in source {
            switch event {
            case .textDelta: Issue.record("Provider schema JSON leaked into visible prose")
            case .structuredResponseStarted(let id, let channel):
                #expect(id == message); #expect(channel == HanlinChatStructuredPart.channel); advertised += 1
            case .structuredPart(let part): parts.append(part)
            case .finished: finishes += 1
            default: break
            }
        }
        #expect(advertised == 1); #expect(finishes == 1)
        #expect(parts.map(\.sequence) == [0, 1, 2])
        #expect(Set(parts.map(\.partID)).count == 3)
        #expect(parts.map(\.payload) == [.textDelta("Before"),
            .a2uiMessage(protocolVersion: "1.0", json: Data(official.utf8)), .textDelta("After")])
    }

    @Test func malformedRepairedAndTruncatedResponsesPublishNoParts() async throws {
        let valid = try Self.wire([Self.text])
        for (wire, complete, truncated) in [(String(valid.dropLast()), true, false),
                                            (valid, false, false), (valid, true, true)] {
            let fetch: FetchFunction = { request in try Self.response(wire, url: #require(request.url),
                complete: complete, truncated: truncated) }
            let engine = try HanlinAISDKAgentEngine(configuration: Self.configuration(), fetch: fetch)
            let contract = HanlinNativeStructuredResponse(messageID: UUID()) { _ in Issue.record("Invalid response reached admission") }
            let source = try await engine.stream(messages: [.init(role: .user, text: "Fixture")],
                baseSystemPrompt: nil, tools: [], structuredResponse: contract, prepareStep: { .init(activeToolAliases: []) })
            var failed = false
            do {
                for try await event in source {
                    if case .structuredPart = event { Issue.record("Incomplete JSON became a part") }
                    if case .textDelta = event { Issue.record("Incomplete JSON became prose") }
                }
            } catch { failed = true }
            #expect(failed)
        }
    }

    @Test func officialValidationFailureIsAtomic() async throws {
        enum Rejected: Error { case fixture }
        let wire = try Self.wire([Self.text])
        let fetch: FetchFunction = { request in try Self.response(wire, url: #require(request.url)) }
        let engine = try HanlinAISDKAgentEngine(configuration: Self.configuration(), fetch: fetch)
        let contract = HanlinNativeStructuredResponse(messageID: UUID()) { _ in throw Rejected.fixture }
        let source = try await engine.stream(messages: [.init(role: .user, text: "Fixture")],
            baseSystemPrompt: nil, tools: [], structuredResponse: contract, prepareStep: { .init(activeToolAliases: []) })
        var failed = false
        do {
            for try await event in source {
                if case .structuredPart = event { Issue.record("Rejected batch partially published") }
            }
        } catch { #expect(error as? HanlinNativeStructuredResponseError == .invalidResponse); failed = true }
        #expect(failed)
    }

    @Test func unsupportedModelsFailBeforeAnyHTTPRequest() async throws {
        let fetch: FetchFunction = { _ in Issue.record("Unsupported model reached HTTP"); throw URLError(.badURL) }
        for config in [Self.configuration(model: "other-model"), Self.configuration(api: "openai")] {
            let engine = try HanlinAISDKAgentEngine(configuration: config, fetch: fetch)
            do {
                _ = try await engine.stream(messages: [.init(role: .user, text: "Fixture")], baseSystemPrompt: nil,
                    tools: [], structuredResponse: .init(messageID: UUID(), validateCompleteParts: { _ in }), prepareStep: { .init(activeToolAliases: []) })
                Issue.record("Unsupported model accepted native contract")
            } catch { #expect(error as? HanlinNativeStructuredResponseError == .unsupportedProviderOrModel) }
        }
        #expect(HanlinAISDKProviderFactory.descriptor(for: Self.configuration()).structuredPartChannel == nil)
    }
}
