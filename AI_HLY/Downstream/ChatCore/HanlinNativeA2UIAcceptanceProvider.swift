import Foundation
import HanlinChatCore
import SwiftData

/// Opt-in deterministic HTTP data for the ORIGINAL app/provider path. It creates no Session,
/// renderer, row callback or tool engine. A2UI owns the payloads and actual UI assertions.
enum HanlinNativeA2UIAcceptanceProvider {
    static let environmentKey = "HANLIN_NATIVE_A2UI_ACCEPTANCE"
    static let planEnvironmentKey = "HANLIN_NATIVE_A2UI_FIXTURE_PLAN"
    static let chatName = "Native A2UI Acceptance"
    static var isEnabled: Bool {
#if DEBUG && targetEnvironment(simulator)
        ProcessInfo.processInfo.environment[environmentKey] == "1"
#else
        false
#endif
    }

    enum BootstrapError: Error { case incompatibleClassicAcceptance }
    struct Plan: Codable, Sendable { let steps: [Step] }
    struct Step: Codable, Sendable {
        /// Match decoded input string content; follow-up MUST name the expected original action
        /// and submitted fixture value. The stub validates these before returning any SSE bytes.
        let expectedInputContains: [String]
        let forbiddenInputContains: [String]
        let expectedActionID: String?
        let expectedSubmittedValue: String?
        /// Complete native {parts:[...]} wire object. Official production validation remains active.
        let structuredObjectJSON: String
        let delayMilliseconds: Int
    }

    @MainActor static func configureIfRequested(context: ModelContext) throws {
        guard isEnabled else { return }
        guard !AgentRuntimeUIAcceptanceProvider.isEnabled else { throw BootstrapError.incompatibleClassicAcceptance }
        // Called only on the new in-memory container. Reopen in this process preserves history;
        // no rows, preferences, user keys or external stores are reset by this fixture.
        guard try context.fetch(FetchDescriptor<ChatRecords>()).isEmpty else { return }
        let optimizer = ProcessInfo.processInfo.environment["HANLIN_NATIVE_A2UI_NO_OPTIMIZER"] == "1"
            ? "" : HanlinNativeStructuredResponse.modelID
        context.insert(UserInfo(optimizationTextModel: optimizer, optimizationVisualModel: optimizer))
        context.insert(AllModels(name: HanlinNativeStructuredResponse.modelID, displayName: "Native A2UI Fixture",
            position: 0, company: "OPENAI", supportsTextGen: true, supportsToolUse: false))
        context.insert(APIKeys(name: "Isolated HTTP fixture", company: "OPENAI", key: "fixture-only-never-network",
            requestURL: "https://api.openai.com/v1/responses", isHidden: false, apiType: .openAIResponse,
            from: .custom, autoProbeCapabilities: false))
        context.insert(ChatRecords(name: chatName, type: "chat", useModel: 0))
        context.insert(ChatRecords(name: "Native A2UI Other Conversation", type: "chat", useModel: 0))
        try context.save()
    }

    static func makeChatEngine() -> HanlinChatEngine {
#if DEBUG && targetEnvironment(simulator)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [HanlinNativeA2UIAcceptanceURLProtocol.self]
        return HanlinChatEngine(sessionConfiguration: configuration)
#else
        return HanlinChatEngine()
#endif
    }

    static var observedRequestCount: Int {
#if DEBUG && targetEnvironment(simulator)
        HanlinNativeA2UIAcceptanceURLProtocol.snapshot().count
#else
        0
#endif
    }
    @MainActor private static var engineFailure: String?
    @MainActor static func recordEngineFailure(_ error: Error) {
        guard isEnabled else { return }
        // Type identity only; never source, submitted values or raw provider text.
        engineFailure = "engine:" + String(reflecting: type(of: error))
    }
    @MainActor static var lastRequestFailure: String? {
#if DEBUG && targetEnvironment(simulator)
        HanlinNativeA2UIAcceptanceURLProtocol.snapshot().failure ?? engineFailure
#else
        nil
#endif
    }
}

#if DEBUG && targetEnvironment(simulator)
private final class HanlinNativeA2UIAcceptanceURLProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    private nonisolated(unsafe) static var requestCount = 0
    private nonisolated(unsafe) static var failure: String?
    private let stopLock = NSLock()
    private var stopped = false
    private enum FixtureError: Error { case invalidPlan, unexpectedRequest, exhaustedPlan, invalidSchema, wrongInput }

    static func snapshot() -> (count: Int, failure: String?) {
        lock.lock(); defer { lock.unlock() }
        return (requestCount, failure)
    }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        // Count every intercepted HTTP attempt, including malformed/unexpected/extra calls.
        Self.lock.lock()
        let index = Self.requestCount; Self.requestCount += 1
        Self.lock.unlock()
        do {
            let bytes = try Self.bodyData(request)
            guard HanlinNativeA2UIAcceptanceProvider.isEnabled,
                  request.url?.absoluteString == "https://api.openai.com/v1/responses", request.httpMethod == "POST",
                  let body = try JSONSerialization.jsonObject(with: bytes) as? [String: Any],
                  body["model"] as? String == HanlinNativeStructuredResponse.modelID,
                  body["stream"] as? Bool == true else { throw FixtureError.unexpectedRequest }
            let text = body["text"] as? [String: Any], format = text?["format"] as? [String: Any]
            let schema = format?["schema"] as? [String: Any]
            let properties = schema?["properties"] as? [String: Any]
            let parts = properties?["parts"] as? [String: Any], items = parts?["items"] as? [String: Any]
            guard format?["type"] as? String == "json_schema", format?["strict"] as? Bool == true,
                  schema?["type"] as? String == "object", schema?["additionalProperties"] as? Bool == false,
                  schema?["required"] as? [String] == ["parts"], parts?["type"] as? String == "array",
                  items?["additionalProperties"] as? Bool == false,
                  Set(items?["required"] as? [String] ?? []) == ["part", "kind", "text", "a2uiJSON"],
                  Set(properties?.keys.map { $0 } ?? []) == ["parts"],
                  parts?["minItems"] as? Int == 1, parts?["maxItems"] as? Int == 128,
                  let fields = items?["properties"] as? [String: [String: Any]],
                  Set(fields.keys) == ["part", "kind", "text", "a2uiJSON"],
                  fields["part"]?["type"] as? String == "string",
                  fields["part"]?["pattern"] as? String == "^[A-Za-z0-9_-]+$",
                  fields["kind"]?["type"] as? String == "string",
                  Set(fields["kind"]?["enum"] as? [String] ?? []) == ["text", "a2ui"],
                  Set(fields["text"]?["type"] as? [String] ?? []) == ["string", "null"],
                  Set(fields["a2uiJSON"]?["type"] as? [String] ?? []) == ["string", "null"] else { throw FixtureError.invalidSchema }
            guard let raw = ProcessInfo.processInfo.environment[HanlinNativeA2UIAcceptanceProvider.planEnvironmentKey],
                  raw.utf8.count <= 262_144 else { throw FixtureError.invalidPlan }
            let plan = try JSONDecoder().decode(HanlinNativeA2UIAcceptanceProvider.Plan.self, from: Data(raw.utf8))
            guard !plan.steps.isEmpty, plan.steps.count <= 8 else { throw FixtureError.invalidPlan }
            guard plan.steps.indices.contains(index) else { throw FixtureError.exhaustedPlan }
            let step = plan.steps[index]
            guard step.expectedInputContains.count <= 16, step.forbiddenInputContains.count <= 16,
                  !step.expectedInputContains.isEmpty, step.structuredObjectJSON.utf8.count <= 131_072,
                  (0...2_000).contains(step.delayMilliseconds) else { throw FixtureError.invalidPlan }
            let input = Self.strings(body["input"] ?? NSNull()).joined(separator: "\n")
            let guidance = input + Self.strings(body["instructions"] ?? NSNull()).joined(separator: "\n")
            guard guidance.contains("https://hanlin.ai/a2ui/catalogs/media/v1"),
                  guidance.contains("ImageGallery"), guidance.contains("LinkPreview"),
                  guidance.contains("sourceUrl") else { throw FixtureError.wrongInput }
            let inputBytes = Data(input.utf8)
            func contains(_ marker: String) -> Bool { inputBytes.range(of: Data(marker.utf8)) != nil }
            guard step.expectedInputContains.allSatisfy({ !$0.isEmpty && $0.utf8.count <= 1024 && contains($0) }),
                  step.forbiddenInputContains.allSatisfy({ !$0.isEmpty && !contains($0) }) else { throw FixtureError.wrongInput }
            if index > 0 {
                guard let action = step.expectedActionID, !action.isEmpty, action.utf8.count <= 512,
                      let value = step.expectedSubmittedValue, !value.isEmpty, value.utf8.count <= 1024,
                      contains("The user activated the displayed action \(action). User-provided action data:"),
                      contains(value) else { throw FixtureError.wrongInput }
            }
            let payload = try Self.response(step.structuredObjectJSON, index: index)
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "text/event-stream"])!
            DispatchQueue.global().asyncAfter(deadline: .now() + .milliseconds(step.delayMilliseconds)) { [weak self] in
                guard let self else { return }
                self.stopLock.lock(); let stopped = self.stopped; self.stopLock.unlock()
                guard !stopped else { return }
                self.client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                self.client?.urlProtocol(self, didLoad: payload)
                self.client?.urlProtocolDidFinishLoading(self)
            }
        } catch {
            Self.lock.lock(); Self.failure = String(describing: error); Self.lock.unlock()
            // Every unexpected/missing/extra request fails closed. There is no network fallback.
            client?.urlProtocol(self, didFailWithError: error)
        }
    }
    override func stopLoading() { stopLock.lock(); stopped = true; stopLock.unlock() }

    private static func bodyData(_ request: URLRequest) throws -> Data {
        if let data = request.httpBody {
            guard data.count <= 2 * 1_048_576 else { throw FixtureError.unexpectedRequest }
            return data
        }
        guard let stream = request.httpBodyStream else { throw FixtureError.unexpectedRequest }
        stream.open(); defer { stream.close() }
        var data = Data(), buffer = [UInt8](repeating: 0, count: 4096)
        while data.count <= 2 * 1_048_576 {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count >= 0 else { throw FixtureError.unexpectedRequest }
            if count == 0 { return data }
            data.append(contentsOf: buffer.prefix(count))
        }
        throw FixtureError.unexpectedRequest
    }

    private static func strings(_ value: Any) -> [String] {
        if let text = value as? String { return [text] }
        if let array = value as? [Any] { return array.flatMap(strings) }
        if let object = value as? [String: Any] { return object.keys.sorted().flatMap { strings(object[$0] ?? NSNull()) } }
        return []
    }
    private static func response(_ text: String, index: Int) throws -> Data {
        func event(_ body: [String: Any]) throws -> String {
            "data: " + String(decoding: try JSONSerialization.data(withJSONObject: body), as: UTF8.self) + "\n\n"
        }
        let id = "msg_native_fixture_\(index)", split = text.index(text.startIndex, offsetBy: text.count / 2)
        var chunks = [try event(["type": "response.output_item.added", "output_index": 0,
            "item": ["id": id, "type": "message", "status": "in_progress", "role": "assistant", "content": []]])]
        for delta in [String(text[..<split]), String(text[split...])] {
            chunks.append(try event(["type": "response.output_text.delta", "item_id": id, "output_index": 0, "content_index": 0, "delta": delta]))
        }
        chunks.append(try event(["type": "response.output_item.done", "output_index": 0,
            "item": ["id": id, "type": "message", "status": "completed", "role": "assistant",
                "content": [["type": "output_text", "text": text, "annotations": []]]]]))
        chunks.append(try event(["type": "response.completed", "response": ["id": "resp_native_fixture_\(index)",
            "status": "completed", "usage": ["input_tokens": 4, "output_tokens": 8]]]))
        return Data(chunks.joined().utf8)
    }
}
#endif
