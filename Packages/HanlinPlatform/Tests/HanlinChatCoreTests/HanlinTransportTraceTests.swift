import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import HanlinChatCore

private final class TraceFixtureProtocol: URLProtocol, @unchecked Sendable {
    static let text = "שָׁלוֹם🙂مرحبا中文 " + String(repeating: "a", count: 1300)
    static var wire: Data {
        let object: [String: Any] = ["choices": [["delta": ["content": text]]]]
        let json = try! JSONSerialization.data(withJSONObject: object)
        return Data("data: ".utf8) + json + Data("\r\n\r\ndata: [DONE]\n\n".utf8)
    }
    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "trace.invalid" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "text/event-stream", "x-request-id": "fixture-request"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        for byte in Self.wire { client?.urlProtocol(self, didLoad: Data([byte])) }
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

private final class TraceObservations: @unchecked Sendable {
    private let lock = NSLock()
    private var events: [HanlinChatTransportEvent] = []
    func append(_ event: HanlinChatTransportEvent) { lock.lock(); defer { lock.unlock() }; events.append(event) }
    func snapshot() -> [HanlinChatTransportEvent] { lock.lock(); defer { lock.unlock() }; return events }
}

@Suite("Production transport trace")
struct HanlinTransportTraceTests {
    @Test func sdkFetchObserverPreservesTheSameBodyAndAttemptIdentity() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [TraceFixtureProtocol.self]
        let observations = TraceObservations()
        let fetch = HanlinAISDKProviderFactory.makeFetch(sessionConfiguration: configuration,
            transportObserver: { observations.append($0) })
        let response = try await fetch(URLRequest(url: URL(string: "https://trace.invalid/chat")!))
        var consumed = Data()
        switch response.body {
        case .none: Issue.record("Production fetch returned no body for the SSE fixture")
        case .data(let data): consumed.append(data)
        case .stream(let stream): for try await data in stream { consumed.append(data) }
        }
        let events = observations.snapshot()
        var captured = Data(), ids = Set<UUID>(), ends = 0
        for event in events {
            switch event {
            case .request(let id, _), .response(let id, _): ids.insert(id)
            case .bytes(let id, let data): ids.insert(id); captured.append(data)
            case .end(let id, let error): ids.insert(id); ends += 1; #expect(error == nil)
            }
        }
        #expect(consumed == TraceFixtureProtocol.wire && captured == consumed)
        #expect(ids.count == 1 && ends == 1)
    }

    @Test func directChatUsesTheObservedBytesForItsActualParser() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [TraceFixtureProtocol.self]
        let engine = HanlinChatEngine(sessionConfiguration: configuration)
        let observations = TraceObservations()
        let model = HanlinChatModelConfiguration(modelID: "fixture", company: "OpenAI", apiType: "OpenAI",
            endpoint: "https://trace.invalid/chat", credential: "fixture")
        let stream = await engine.stream(request: URLRequest(url: URL(string: "https://trace.invalid/chat")!),
            configuration: model, transportObserver: { observations.append($0) })
        var visible = ""
        for try await event in stream { visible += event.content ?? "" }
        #expect(visible == TraceFixtureProtocol.text)
        #expect(!visible.contains("�"))
        var captured = Data()
        for event in observations.snapshot() { if case .bytes(_, let data) = event { captured.append(data) } }
        #expect(captured == Data(TraceFixtureProtocol.wire.dropLast())) // parser stops at the [DONE] line
    }
}
