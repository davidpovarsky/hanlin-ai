import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import HanlinChatCore

private final class CompactResponsesState: @unchecked Sendable {
    private let lock = NSLock()
    private var bodies: [Data] = []
    private var stops = 0
    func record(_ data: Data) { lock.lock(); defer { lock.unlock() }; bodies.append(data) }
    func stop() { lock.lock(); defer { lock.unlock() }; stops += 1 }
    func reset() { lock.lock(); defer { lock.unlock() }; bodies = []; stops = 0 }
    var captured: [Data] { lock.lock(); defer { lock.unlock() }; return bodies }
    var stopCount: Int { lock.lock(); defer { lock.unlock() }; return stops }
}

private final class CompactResponsesProtocol: URLProtocol, @unchecked Sendable {
    static let state = CompactResponsesState()
    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host == "api.openai.com" && request.url?.path == "/v1/responses"
    }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        var body = request.httpBody ?? Data()
        if body.isEmpty, let stream = request.httpBodyStream {
            stream.open()
            defer { stream.close() }
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                if count <= 0 { break }
                body.append(contentsOf: buffer.prefix(count))
            }
        }
        Self.state.record(body)
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "text/event-stream", "x-request-id": "compact-fixture"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        let payloads = [
            #"{"type":"response.output_item.added","output_index":0,"item":{"id":"msg_fixture","type":"message","status":"in_progress","role":"assistant","content":[]}}"#,
            #"{"type":"response.output_text.delta","item_id":"msg_fixture","output_index":0,"content_index":0,"delta":"תשובה🙂"}"#,
            #"{"type":"response.output_item.done","output_index":0,"item":{"id":"msg_fixture","type":"message","status":"completed","role":"assistant","content":[{"type":"output_text","text":"תשובה🙂","annotations":[]}]}}"#,
            #"{"type":"response.completed","response":{"id":"resp_fixture","status":"completed","usage":{"input_tokens":100,"input_tokens_details":{"cached_tokens":30,"cache_write_tokens":50},"output_tokens":8}}}"#
        ]
        for payload in payloads { client?.urlProtocol(self, didLoad: Data("data: \(payload)\n\n".utf8)) }
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() { Self.state.stop() }
}

private final class HangingCompactResponsesProtocol: URLProtocol, @unchecked Sendable {
    static let state = CompactResponsesState()
    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host == "api.openai.com" && request.url?.path == "/v1/responses"
    }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.state.record(Data())
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "text/event-stream"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        for payload in [
            #"{"type":"response.output_item.added","output_index":0,"item":{"id":"msg_wait","type":"message","status":"in_progress","role":"assistant","content":[]}}"#,
            #"{"type":"response.output_text.delta","item_id":"msg_wait","output_index":0,"content_index":0,"delta":"partial"}"#
        ] {
            client?.urlProtocol(self, didLoad: Data("data: \(payload)\n\n".utf8))
        }
        // Keep the real URLSession request open until the consumer cancels.
    }
    override func stopLoading() { Self.state.stop() }
}


#if os(macOS) || os(iOS) || os(tvOS) || os(watchOS) || os(visionOS)
private final class ProviderRedirectState: @unchecked Sendable {
    private let lock = NSLock()
    private var requests: [URLRequest] = []
    private var admissions = 0
    func record(_ request: URLRequest) { lock.withLock { requests.append(request) } }
    func admit() { lock.withLock { admissions += 1 } }
    func reset() { lock.withLock { requests = []; admissions = 0 } }
    var captured: [URLRequest] { lock.withLock { requests } }
    var admissionCount: Int { lock.withLock { admissions } }
}

private final class RedirectingProviderProtocol: URLProtocol, @unchecked Sendable {
    static let state = ProviderRedirectState()
    static let original = URL(string: "https://provider-source.invalid/v1/chat/completions")!
    static let destination = URL(string: "https://unadmitted-destination.invalid/stolen-request")!

    override class func canInit(with request: URLRequest) -> Bool {
        request.url == original || request.url == destination
    }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.state.record(request)
        if request.url == Self.original {
            let response = HTTPURLResponse(url: Self.original, statusCode: 307, httpVersion: "HTTP/1.1",
                headerFields: ["Location": Self.destination.absoluteString, "Content-Length": "0"])!
            var redirect = request
            redirect.url = Self.destination
            // A real redirect callback is essential: merely returning a 3xx
            // response would not exercise URLSession's automatic redirect path.
            client?.urlProtocol(self, wasRedirectedTo: redirect, redirectResponse: response)
            client?.urlProtocolDidFinishLoading(self)
        } else {
            let response = HTTPURLResponse(url: Self.destination, statusCode: 200, httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "text/event-stream"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data("data: [DONE]\n\n".utf8))
            client?.urlProtocolDidFinishLoading(self)
        }
    }
    override func stopLoading() {}
}
#endif

@Suite("Compact Responses canonical SDK route", .serialized)
struct HanlinCompactResponsesTests {
    private func configuration(
        policy: HanlinPromptCachePolicy? = .init(openAI: .init(mode: .explicit, ttl: .twelveHours))
    ) -> HanlinChatModelConfiguration {
        .init(modelID: "gpt-6.2-sol", company: "OpenAI", apiType: "OpenAI-Response",
            endpoint: "https://api.openai.com/v1/responses", credential: "fixture-only",
            systemPrompt: "Stable instructions",
            promptCachePolicy: policy)
    }

    @Test("Compact requests retain original Responses envelope, message order, cache scope and normalized usage")
    func originalResponsesWireAndUsage() async throws {
        CompactResponsesProtocol.state.reset()
        let session = URLSessionConfiguration.ephemeral
        session.protocolClasses = [CompactResponsesProtocol.self]
        let engine = HanlinChatEngine(sessionConfiguration: session)
        let model = configuration()
        let scope = HanlinPromptCacheScope(namespace: ["app", "account", "workspace"],
            conversationID: "conversation", promptVersion: "compact-v1")
        let source = try await engine.stream(
            messages: [.system("Additional instructions"), .user("First question"),
                .assistant("Earlier answer"), .user("Second question")],
            configuration: model, systemContext: "Changing context", cacheScope: scope
        )
        var visible = ""
        var final: HanlinChatStreamEvent?
        var metadata: HanlinChatResponseMetadata?
        for try await event in source {
            visible += event.content ?? ""
            if let response = event.responseMetadata { metadata = response }
            if event.isDone { final = event }
        }
        #expect(visible == "תשובה🙂")
        #expect(metadata?.providerRequestID == "compact-fixture")
        #expect(metadata?.statusCode == 200)
        #expect(final?.tokenUsage?.inputTokens == 100)
        #expect(final?.tokenUsage?.cachedInputTokens == 30)
        #expect(final?.tokenUsage?.cacheWriteTokens == 50)
        #expect(final?.tokenUsage?.outputTokens == 8)
        #expect(final?.tokenUsage?.totalTokens == 108)
        let bodies = CompactResponsesProtocol.state.captured
        #expect(bodies.count == 1)
        let firstBody = try #require(bodies.first)
        let json = try #require(JSONSerialization.jsonObject(with: firstBody) as? [String: Any])
        #expect(json["messages"] == nil)
        #expect(json["max_tokens"] == nil)
        #expect(json["max_output_tokens"] as? Int == HanlinChatGenerationDefaults.maxTokens)
        #expect(json["store"] as? Bool == false)
        #expect(json["prompt_cache_key"] as? String == scope.key(configuration: model))
        #expect((json["prompt_cache_options"] as? [String: String]) == ["mode": "explicit", "ttl": "12h"])
        let input = try #require(json["input"] as? [[String: Any]])
        let text = input.map { item -> String in
            if let value = item["content"] as? String { return value }
            return (item["content"] as? [[String: Any]])?.compactMap { $0["text"] as? String }.joined() ?? ""
        }
        #expect(text == ["Stable instructions", "Context:\nChanging context", "Additional instructions",
            "First question", "Earlier answer", "Second question"])
        let stable = try #require(input.first?["content"] as? [[String: Any]])
        #expect((stable.first?["prompt_cache_breakpoint"] as? [String: String]) == ["mode": "explicit", "ttl": "12h"])
    }

    @Test("Automatic native Responses keeps the same stable boundary across changing context without changing implicit mode")
    func automaticStableBoundaryAcrossRequests() async throws {
        CompactResponsesProtocol.state.reset()
        let session = URLSessionConfiguration.ephemeral
        session.protocolClasses = [CompactResponsesProtocol.self]
        let engine = HanlinChatEngine(sessionConfiguration: session)
        let scope = HanlinPromptCacheScope(namespace: ["app", "account", "workspace"],
            conversationID: "same-conversation", promptVersion: "compact-v1")
        let model = configuration(policy: nil)
        for suffix in ["first", "second"] {
            let stream = try await engine.stream(messages: [.user("Question \(suffix)")],
                configuration: model, systemContext: "Changing context \(suffix)", cacheScope: scope)
            for try await _ in stream {}
        }

        let bodies = CompactResponsesProtocol.state.captured
        try #require(bodies.count == 2)
        var boundaries: [Data] = []
        var contexts: [String] = []
        var questions: [String] = []
        for data in bodies {
            let body = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
            // The request keeps the provider's implicit mode and default lifetime.
            // Only the stable message gains an additional eligible boundary.
            #expect(body["prompt_cache_options"] == nil)
            #expect(body["prompt_cache_retention"] == nil)
            #expect(body["prompt_cache_key"] as? String == scope.key(configuration: model))
            let input = try #require(body["input"] as? [[String: Any]])
            try #require(input.count == 3)
            let stable = try #require(input[0]["content"] as? [[String: Any]])
            #expect(stable.first?["text"] as? String == "Stable instructions")
            #expect((stable.first?["prompt_cache_breakpoint"] as? [String: String]) == ["mode": "explicit"])
            boundaries.append(try JSONSerialization.data(withJSONObject: stable, options: .sortedKeys))
            func contentText(_ item: [String: Any]) -> String {
                if let text = item["content"] as? String { return text }
                return (item["content"] as? [[String: Any]])?.compactMap { $0["text"] as? String }.joined() ?? ""
            }
            contexts.append(contentText(input[1]))
            questions.append(contentText(input[2]))
        }
        #expect(boundaries[0] == boundaries[1])
        #expect(contexts == ["Context:\nChanging context first", "Context:\nChanging context second"])
        #expect(questions == ["Question first", "Question second"])

        // Explicit opt-outs also pass through the original serializer, so their
        // absence is checked on actual request bodies rather than on a flag.
        for policy in [HanlinPromptCachePolicy.providerDefault, .noExplicitCaching] {
            let stream = try await engine.stream(messages: [.user("Question")],
                configuration: configuration(policy: policy), systemContext: "Changing context", cacheScope: scope)
            for try await _ in stream {}
        }
        let allBodies = CompactResponsesProtocol.state.captured
        #expect(allBodies.count == 4)
        for data in allBodies.dropFirst(2) {
            let body = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
            #expect(body["prompt_cache_options"] == nil)
            #expect(body["prompt_cache_key"] == nil)
            #expect(!String(decoding: data, as: UTF8.self).contains("prompt_cache_breakpoint"))
        }
    }

    @Test("Compact facade refuses tool authority and legacy Chat-shaped Responses requests before transport")
    func unsupportedContractsDoNotSend() async throws {
        CompactResponsesProtocol.state.reset()
        let session = URLSessionConfiguration.ephemeral
        session.protocolClasses = [CompactResponsesProtocol.self]
        let engine = HanlinChatEngine(sessionConfiguration: session)
        let model = configuration()
        await #expect(throws: (any Error).self) {
            try await engine.stream(messages: [.user("Question")], configuration: model,
                tools: [["type": "function", "function": ["name": "write"]]])
        }
        await #expect(throws: (any Error).self) {
            try await engine.stream(messages: [.init(role: "tool", content: "Uncorrelated result")],
                configuration: model)
        }
        #expect(throws: (any Error).self) {
            try HanlinChatRequestBuilder.buildRequest(messages: [.user("Question")], configuration: model)
        }
        #expect(CompactResponsesProtocol.state.captured.isEmpty)
    }

    @Test("Cancelling compact consumption cancels the underlying original SDK URLSession request")
    func cancellationStopsNativeTransport() async throws {
        HangingCompactResponsesProtocol.state.reset()
        let session = URLSessionConfiguration.ephemeral
        session.protocolClasses = [HangingCompactResponsesProtocol.self]
        let engine = HanlinChatEngine(sessionConfiguration: session)
        let source = try await engine.stream(messages: [.user("Question")], configuration: configuration())
        actor Progress {
            var receivedText = false
            func received() { receivedText = true }
        }
        let progress = Progress()
        let consumer = Task {
            do {
                for try await event in source {
                    if event.content == "partial" { await progress.received() }
                }
            } catch {}
        }
        defer { consumer.cancel() }
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while !(await progress.receivedText), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        try #require(await progress.receivedText)
        consumer.cancel()
        await consumer.value
        let stopDeadline = ContinuousClock.now.advanced(by: .seconds(5))
        while HangingCompactResponsesProtocol.state.stopCount == 0, ContinuousClock.now < stopDeadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(HangingCompactResponsesProtocol.state.stopCount > 0)
    }
#if os(macOS) || os(iOS) || os(tvOS) || os(watchOS) || os(visionOS)
    @Test("Provider redirects cannot bypass admission or forward credential headers")
    func redirectsCannotEscapeProviderAdmission() async throws {
        for sdkFetch in [true, false] {
            RedirectingProviderProtocol.state.reset()
            let session = URLSessionConfiguration.ephemeral
            session.protocolClasses = [RedirectingProviderProtocol.self]
            session.timeoutIntervalForRequest = 5
            session.timeoutIntervalForResource = 5
            let engine = HanlinChatEngine(sessionConfiguration: session)
            var request = URLRequest(url: RedirectingProviderProtocol.original)
            request.httpMethod = "POST"
            request.httpBody = Data(#"{"model":"fixture","messages":[]}"#.utf8)
            request.setValue("Bearer fixture-only", forHTTPHeaderField: "Authorization")
            request.setValue("fixture-api-key", forHTTPHeaderField: "x-api-key")
            let admission: HanlinChatRequestAdmission = { _ in
                RedirectingProviderProtocol.state.admit()
            }

            if sdkFetch {
                let fetch = await engine.makeAISDKFetch(requestAdmission: admission)
                let response = try await fetch(request)
                #expect((response.urlResponse as? HTTPURLResponse)?.statusCode == 307)
                #expect(response.urlResponse.url == RedirectingProviderProtocol.original)
                if case .stream(let body) = response.body {
                    for try await _ in body {}
                }
            } else {
                let model = HanlinChatModelConfiguration(modelID: "gpt-4o", company: "OpenAI",
                    apiType: "openai", endpoint: RedirectingProviderProtocol.original,
                    apiKey: "fixture-only")
                let stream = await engine.stream(request: request, configuration: model,
                    requestAdmission: admission)
                do {
                    for try await _ in stream {}
                    Issue.record("The original HTTP redirect must be reported as a provider error.")
                } catch HanlinChatError.serverError(let status, _) {
                    #expect(status == 307)
                }
            }

            let captured = RedirectingProviderProtocol.state.captured
            #expect(captured.count == 1)
            #expect(captured.first?.url == RedirectingProviderProtocol.original)
            #expect(captured.first?.value(forHTTPHeaderField: "Authorization") == "Bearer fixture-only")
            #expect(captured.first?.value(forHTTPHeaderField: "x-api-key") == "fixture-api-key")
            #expect(RedirectingProviderProtocol.state.admissionCount == 1)
        }
    }
#endif

}
