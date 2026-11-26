import AISDKProviderUtils
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import HanlinChatCore

/// Intercepted provider wire, through the original adapters and agent engine.
/// These are protocol/metadata tests, not claims about live model quality.
@Suite("Generated metadata provider protocols")
struct GeneratedConversationMetadataProviderTests {
    private actor Calls {
        var count = 0
        func requested() { count += 1 }
    }

    @Test("One request supplies title and icon through the configured provider",
          arguments: ["openai", "compatible", "anthropic", "gemini", "responses"])
    func metadataUsesTheOriginalProviderWire(api: String) async throws {
        let text = #"{"title":"נסיעה לירושלים","icon":"bus"}"#
        let company = api == "openai" ? "OPENAI" : "CUSTOM"
        let apiType = api == "responses" ? "OpenAI-Response" : api
        let endpoint = api == "openai" ? "https://api.openai.com/v1/chat/completions" :
            (api == "gemini" ? "https://metadata.invalid/v1beta" : "https://metadata.invalid/v1")
        let model = api == "anthropic" ? "claude-3-5-sonnet-20241022" :
            (api == "gemini" ? "gemini-2.0-flash" : "gpt-4o")
        let configuration = HanlinChatModelConfiguration(modelID: model, company: company,
            apiType: apiType, endpoint: endpoint, credential: "synthetic-fixture",
            maxTokens: 2048, supportsToolUse: false)
        let calls = Calls()
        let fetch: FetchFunction = { request in
            await calls.requested()
            let url = try #require(request.url)
            let data = try #require(request.httpBody)
            let body = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
            #expect((body["tools"] as? [Any])?.isEmpty ?? true)
            let chunks: [String]
            switch api {
            case "anthropic":
                #expect(url.path == "/v1/messages")
                #expect(request.value(forHTTPHeaderField: "x-api-key") == "synthetic-fixture")
                #expect(body["messages"] != nil && body["system"] != nil)
                chunks = ProviderResponseFixtures.anthropicTextChunks(text: text)
            case "gemini":
                #expect(url.path.contains(":streamGenerateContent"))
                #expect(body["contents"] != nil && body["messages"] == nil)
                chunks = ProviderResponseFixtures.googleTextChunks(text: text)
            case "responses":
                #expect(url.path == "/v1/responses")
                #expect(body["input"] != nil && body["messages"] == nil)
                #expect(body["store"] as? Bool == false)
                chunks = try Self.responsesChunks(text)
            default:
                #expect(url.path == "/v1/chat/completions")
                #expect(body["messages"] != nil && body["stream"] as? Bool == true)
                chunks = ProviderResponseFixtures.openAIChatTextChunks(text: text)
            }
            let stream = AsyncThrowingStream<Data, Error> { continuation in
                for chunk in chunks { continuation.yield(Data(chunk.utf8)) }
                continuation.finish()
            }
            return FetchResponse(body: .stream(stream), urlResponse: HTTPURLResponse(url: url,
                statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "text/event-stream"])!)
        }
        let engine = try HanlinAISDKAgentEngine(configuration: configuration, fetch: fetch)
        let metadata = try await HanlinConversationMetadata.generate(using: engine,
            historyMessage: "תכנן נסיעה לירושלים", languageTag: "he-IL")
        #expect(metadata.title == "נסיעה לירושלים" && metadata.icon == "bus")
        #expect(await calls.count == 1)
    }

    @Test
    func incompleteTruncatedAndOversizedStreamsCannotBecomeMetadata() async throws {
        let text = #"{"title":"Reading list","icon":"book"}"#
        let invalid: [[HanlinAISDKStreamEvent]] = [
            [.textDelta(text)],
            [.textDelta(text), .finished(reason: "length", usage: .init())],
            [.textDelta(String(repeating: "🙂", count: 1025)), .finished(reason: "stop", usage: .init())]
        ]
        for events in invalid {
            do {
                _ = try await HanlinConversationMetadata.decodeCompletedStream(stream(events))
                Issue.record("Incomplete, truncated or oversized metadata was accepted")
            } catch {
                #expect(error is HanlinConversationMetadata.ResponseError)
            }
        }
    }

    @Test
    func cancellationCannotApplyEvenAnOtherwiseValidJSONResponse() async throws {
        do {
            _ = try await HanlinConversationMetadata.decodeCompletedStream(stream([
                .textDelta(#"{"title":"Reading list","icon":"book"}"#), .cancelled]))
            Issue.record("Cancelled metadata was accepted")
        } catch { #expect(error is CancellationError) }
    }

    @Test
    func reasoningIsNotIncludedInTheMetadataJSON() async throws {
        let metadata = try await HanlinConversationMetadata.decodeCompletedStream(stream([
            .reasoningDelta("Provider-private reasoning is not JSON."),
            .textDelta(#"{"title":"Reading "#),
            .textDelta(#"list","icon":"book"}"#),
            .finished(reason: "stop", usage: .init())]))
        #expect(metadata.title == "Reading list" && metadata.icon == "book")
    }

    private func stream(_ events: [HanlinAISDKStreamEvent]) -> AsyncThrowingStream<HanlinAISDKStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            for event in events { continuation.yield(event) }
            continuation.finish()
        }
    }

    private static func responsesChunks(_ text: String) throws -> [String] {
        func event(_ object: [String: Any]) throws -> String {
            "data: " + String(decoding: try JSONSerialization.data(withJSONObject: object), as: UTF8.self) + "\n\n"
        }
        return [
            try event(["type": "response.output_item.added", "output_index": 0,
                "item": ["id": "metadata-message", "type": "message", "status": "in_progress",
                         "role": "assistant", "content": []]]),
            try event(["type": "response.output_text.delta", "item_id": "metadata-message",
                "output_index": 0, "content_index": 0, "delta": text]),
            try event(["type": "response.output_item.done", "output_index": 0,
                "item": ["id": "metadata-message", "type": "message", "status": "completed",
                         "role": "assistant", "content": [["type": "output_text", "text": text, "annotations": []]]]]),
            try event(["type": "response.completed", "response": ["id": "metadata-response",
                "status": "completed", "incomplete_details": NSNull(),
                "usage": ["input_tokens": 4, "output_tokens": 8]]])
        ]
    }
}
