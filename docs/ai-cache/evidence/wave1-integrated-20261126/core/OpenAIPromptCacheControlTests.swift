import Foundation
import Testing
@testable import AISDKProvider
@testable import AISDKProviderUtils
@testable import OpenAIProvider
@testable import SwiftAISDK

@Suite("OpenAI current prompt cache controls")
struct OpenAIPromptCacheControlTests {
    private actor Capture {
        var request: URLRequest?
        func store(_ value: URLRequest) { request = value }
    }

    @Test("Responses serializes 12h lifetime, prewarm and diagnostic ID through the real provider")
    func responsesSerializesCurrentCacheControls() async throws {
        let capture = Capture()
        let provider = try createOpenAI(settings: .init(
            apiKey: "fixture-key",
            fetch: { request in
                await capture.store(request)
                let data = Data("""
                {"id":"resp-cache","created_at":1711115037,"model":"gpt-6.2-sol","output":[],"usage":{"input_tokens":100,"input_tokens_details":{"cached_tokens":30,"cache_write_tokens":50},"output_tokens":0},"warnings":[],"incomplete_details":null,"error":null}
                """.utf8)
                return FetchResponse(
                    body: .data(data),
                    urlResponse: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil,
                        headerFields: ["Content-Type": "application/json"])!
                )
            }
        ))
        let result = try await provider.responses("gpt-6.2-sol").doGenerate(options: .init(
            prompt: [.user(content: [.text(.init(text: "Stable reference"))], providerOptions: nil)],
            providerOptions: ["openai": ["promptCacheOptions": .object([
                "mode": .string("explicit"),
                "ttl": .string("12h"),
                "prewarm": .bool(true),
                "comparisonResponseId": .string("resp-previous")
            ])]]
        ))
        let request = try #require(await capture.request)
        let data = try #require(request.httpBody)
        let body = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let cache = try #require(body["prompt_cache_options"] as? [String: Any])
        #expect(cache["ttl"] as? String == "12h")
        #expect(cache["mode"] as? String == "explicit")
        #expect(cache["prewarm"] as? Bool == true)
        #expect(cache["comparison_response_id"] as? String == "resp-previous")
        #expect(cache["comparisonResponseId"] == nil)
        #expect(result.usage.inputTokens.cacheRead == 30)
        #expect(result.usage.inputTokens.cacheWrite == 50)
        #expect(result.usage.inputTokens.noCache == 20)
    }

    @Test("Responses cache option boundary rejects invalid types and unknown lifetimes")
    func responsesRejectsInvalidCacheControls() throws {
        let invalid: [JSONValue] = [
            .object(["ttl": .string("forever")]),
            .object(["prewarm": .string("true")]),
            .object(["comparisonResponseId": .number(42)]),
            .object(["comparisonResponseId": .string("")])
        ]
        for value in invalid {
            #expect(throws: (any Error).self) {
                try parseOpenAIPromptCacheOptions(value, supportsResponsesControls: true)
            }
        }
    }

    @Test("Chat retains 30m controls and rejects Responses-only controls")
    func chatCacheControlsKeepTheirAPIContract() throws {
        let baseline = try parseOpenAIPromptCacheOptions(.object([
            "mode": .string("implicit"), "ttl": .string("30m")
        ]))
        #expect(baseline == .init(mode: .implicit, ttl: .thirtyMinutes))
        let responsesOnly: [JSONValue] = [
            .object(["ttl": .string("12h")]),
            .object(["prewarm": .bool(true)]),
            .object(["comparisonResponseId": .string("resp-previous")])
        ]
        for value in responsesOnly {
            #expect(throws: (any Error).self) { try parseOpenAIPromptCacheOptions(value) }
        }
    }

    @Test("Original stream spans preserve cache writes while excluding prompt and response content",
          .timeLimit(.minutes(1)))
    func streamTelemetryRetainsCacheWriteAccounting() async throws {
        let parts: [LanguageModelV3StreamPart] = [
            .textStart(id: "text", providerMetadata: nil),
            .textDelta(id: "text", delta: "private response", providerMetadata: nil),
            .textEnd(id: "text", providerMetadata: nil),
            .finish(finishReason: .init(unified: .stop, raw: "stop"),
                usage: .init(inputTokens: .init(total: 100, noCache: 20, cacheRead: 30, cacheWrite: 50),
                    outputTokens: .init(total: 4)),
                providerMetadata: nil)
        ]
        let model = MockLanguageModelV3(doStream: .singleValue(.init(
            stream: AsyncThrowingStream { continuation in
                for part in parts { continuation.yield(part) }
                continuation.finish()
            }
        )))
        let (endedRootSpan, endedRootContinuation) = AsyncStream<String>.makeStream(
            bufferingPolicy: .bufferingNewest(1)
        )
        defer { endedRootContinuation.finish() }
        let tracer = MockTracer(onSpanEnd: { name in
            guard name == "ai.streamText" else { return }
            endedRootContinuation.yield(name)
            endedRootContinuation.finish()
        })
        let result: DefaultStreamTextResult<JSONValue, JSONValue> = try streamText(
            model: .v3(model), prompt: "private prompt",
            experimentalTelemetry: .init(isEnabled: true, recordInputs: false, recordOutputs: false, tracer: tracer)
        )
        _ = try await result.readAllText()
        let finish = try await result.waitForFinish()
        #expect(finish.totalUsage.inputTokenDetails.cacheReadTokens == 30)
        #expect(finish.totalUsage.inputTokenDetails.cacheWriteTokens == 50)
        #expect(finish.totalUsage.inputTokenDetails.noCacheTokens == 20)

        // Result completion precedes the provider task's final telemetry writes.
        // Observe the real span lifetime instead of racing an unfinished snapshot.
        var endIterator = endedRootSpan.makeAsyncIterator()
        let endedName = await endIterator.next()
        #expect(endedName == "ai.streamText")
        let span = try #require(tracer.spanRecords.first { $0.name == "ai.streamText" })
        #expect(span.attributes["ai.usage.cachedInputTokens"] == .int(30))
        #expect(span.attributes["ai.usage.cacheWriteTokens"] == .int(50))
        #expect(span.attributes["ai.usage.noCacheTokens"] == .int(20))
        #expect(span.attributes["ai.response.text"] == nil)
        #expect(span.attributes["ai.prompt"] == nil)
    }
}
