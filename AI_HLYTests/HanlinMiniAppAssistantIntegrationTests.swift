import Foundation
import HanlinChatCore
import HanlinPlatformContracts
import Testing
@testable import AI_Hanlin

@Suite("Active MiniApp native assistant", .serialized)
struct HanlinMiniAppAssistantIntegrationTests {
    private static func host(_ id: String = "test.assistant") throws -> HanlinHostCallContext {
        .forMiniApp(appID: try HanlinAppID(validating: id), origin: .nativeModule,
                    capabilities: ["assistant"], canPresentUI: false)
    }

    private static func service(events: [HanlinAISDKStreamEvent]) throws -> HanlinMiniAppAssistantAIService {
        .init(context: try host(), makeStream: { _, _ in
            AsyncThrowingStream { continuation in
                for event in events { continuation.yield(event) }
                continuation.finish()
            }
        }, listModels: { [] })
    }

    private static func payload(schema: String? = nil) throws -> String {
        var value: [String: Any] = ["messages": [["role": "user", "content": "Hello"]]]
        if let schema { value["responseSchemaJSON"] = schema }
        return String(decoding: try JSONSerialization.data(withJSONObject: value), as: UTF8.self)
    }

    private static func handle(_ service: HanlinMiniAppAssistantAIService, schema: String? = nil) async throws -> String {
        let receipt = try await service.invoke(operation: "assistant.start", payloadJSON: payload(schema: schema))
        let object = try #require(JSONSerialization.jsonObject(with: Data(receipt.utf8)) as? [String: String])
        return try #require(object["requestID"])
    }

    private static func next(_ service: HanlinMiniAppAssistantAIService, _ id: String) async throws -> [String: Any] {
        let receipt = try await service.invoke(operation: "assistant.next", payloadJSON: #"{"requestID":"\#(id)"}"#)
        let object = try #require(JSONSerialization.jsonObject(with: Data(receipt.utf8)) as? [String: Any])
        return try #require(object["event"] as? [String: Any])
    }

    private static let schema = #"{"type":"object","properties":{"count":{"type":"integer"}},"required":["count"],"additionalProperties":false}"#

    @Test("Schema output stays buffered until exact validation and preserves cache counters")
    func validatedStructuredOutput() async throws {
        let service = try Self.service(events: [
            .textDelta(#"{"cou"#), .textDelta(#"nt":7}"#),
            .finished(reason: "stop", usage: .init(inputTokens: 100, outputTokens: 4,
                                                   cachedInputTokens: 70, cacheWriteTokens: 20))
        ])
        defer { service.invalidate() }
        let id = try await Self.handle(service, schema: Self.schema)
        let structured = try await Self.next(service, id)
        #expect(structured["type"] as? String == "structured")
        #expect((structured["value"] as? [String: Int])?["count"] == 7)
        let finish = try await Self.next(service, id)
        #expect(finish["type"] as? String == "finish")
        let usage = try #require(finish["usage"] as? [String: Int])
        #expect(usage["cachedInputTokens"] == 70)
        #expect(usage["cacheWriteTokens"] == 20)
    }

    @Test("Wrong schema values and lossy JavaScript numbers never become structured events",
           arguments: [#"{"count":"seven"}"#, #"{"count":9007199254740993}"#, #"{"count":7,"extra":true}"#])
    func invalidStructuredOutput(_ text: String) async throws {
        let service = try Self.service(events: [.textDelta(text),
            .finished(reason: "stop", usage: .init(inputTokens: 1))])
        defer { service.invalidate() }
        let id = try await Self.handle(service, schema: Self.schema)
        await #expect(throws: HanlinMiniAppAssistantError.invalidStructuredResponse) {
            _ = try await Self.next(service, id)
        }
    }

    @Test("Truncated JSON is not published as a successful object")
    func incompleteStructuredOutput() async throws {
        let service = try Self.service(events: [.textDelta(#"{"count":7}"#),
            .finished(reason: "length", usage: .init(inputTokens: 1))])
        defer { service.invalidate() }
        let id = try await Self.handle(service, schema: Self.schema)
        await #expect(throws: HanlinMiniAppAssistantError.invalidStructuredResponse) {
            _ = try await Self.next(service, id)
        }
    }

    @Test("A different session cannot consume or cancel an original handle")
    func sessionBoundHandles() async throws {
        let first = try Self.service(events: [.textDelta("original"),
            .finished(reason: "stop", usage: .init(inputTokens: 1))])
        let second = try Self.service(events: [])
        defer { first.invalidate(); second.invalidate() }
        let id = try await Self.handle(first)
        await #expect(throws: HanlinMiniAppAssistantError.unknownRequest) {
            _ = try await Self.next(second, id)
        }
        _ = try await second.invoke(operation: "assistant.cancel", payloadJSON: #"{"requestID":"\#(id)"}"#)
        let original = try await Self.next(first, id)
        #expect(original["text"] as? String == "original")
    }

    @Test("Adapter teardown revokes new admission and cancels a pending native read")
    func teardownCancellation() async throws {
        let (stream, continuation) = AsyncThrowingStream<HanlinAISDKStreamEvent, Error>.makeStream()
        let service = try HanlinMiniAppAssistantAIService(context: Self.host(),
            makeStream: { _, lease in try lease.requireActive(); return stream }, listModels: { [] })
        let id = try await Self.handle(service)
        let pending = Task {
            try await service.invoke(operation: "assistant.next", payloadJSON: #"{"requestID":"\#(id)"}"#)
        }
        service.invalidate()
        await #expect(throws: CancellationError.self) { _ = try await pending.value }
        await #expect(throws: CancellationError.self) {
            _ = try await service.invoke(operation: "assistant.models", payloadJSON: "{}")
        }
        continuation.finish()
    }

    @Test("Unknown credential and implicit tool fields fail before producer creation")
    func noImplicitToolsOrCredentials() async throws {
        let counter = CallCounter()
        let service = try HanlinMiniAppAssistantAIService(context: Self.host(), makeStream: { _, _ in
            await counter.increment()
            return AsyncThrowingStream { $0.finish() }
        }, listModels: { [] })
        defer { service.invalidate() }
        for field in ["tools", "apiKey", "endpoint"] {
            let data = try JSONSerialization.data(withJSONObject:
                ["messages": [["role": "user", "content": "Hello"]], field: "not-accepted"] as [String: Any])
            await #expect(throws: HanlinMiniAppAssistantError.invalidRequest) {
                _ = try await service.invoke(operation: "assistant.start", payloadJSON: String(decoding: data, as: UTF8.self))
            }
        }
        #expect(await counter.value == 0)
    }

    @Test("Both active adapters call their injected host service and revoke it")
    func activeAdapterDispatch() async throws {
        let expoService = try Self.service(events: [])
        let expo = ExpoHostServicesAdapter(appID: try HanlinAppID(validating: "test.expo"),
            grantedCapabilities: ["assistant"], assistantServiceFactory: { _ in expoService })
        #expect(try await expo.invoke(operation: "assistant.models", payloadJSON: "{}") == "[]")
        expo.invalidateAssistantRequests()
        await #expect(throws: CancellationError.self) {
            _ = try await expo.invoke(operation: "assistant.models", payloadJSON: "{}")
        }

        let nativeService = try Self.service(events: [])
        let native = NativeScriptHostServicesAdapter(appID: try HanlinAppID(validating: "test.native"),
            grantedCapabilities: ["assistant"], assistantServiceFactory: { _ in nativeService })
        let receipt: String = try await withCheckedThrowingContinuation { continuation in
            native.sendRequest("hanlin.host-services", action: "assistant.models", capability: "assistant",
                payloadJSON: "{}") { receipt, error in
                if let error { continuation.resume(throwing: NSError(domain: error, code: 1)) }
                else { continuation.resume(returning: receipt ?? "") }
            }
        }
        #expect(receipt == "[]")
        native.invalidateRuntimeRequests()
        await #expect(throws: CancellationError.self) {
            _ = try await nativeService.invoke(operation: "assistant.models", payloadJSON: "{}")
        }
    }

    private actor CallCounter {
        private(set) var value = 0
        func increment() { value += 1 }
    }
}
