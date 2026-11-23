import AISDKProviderUtils
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Structured, credential-free diagnostics for ChatGPT plan admission and terminal events.
public struct HanlinChatGPTPlanFailure: Sendable, Equatable {
    public let status: Int
    public let code: String?
    public let parameter: String?
    public let requestID: String?
    public let bodyShape: String
}

public enum HanlinChatGPTPlanTransportError: Error, LocalizedError, Sendable {
    case invalidRoute
    case invalidBody
    case unsupportedTool(String)
    case response(HanlinChatGPTPlanFailure)
    case incompleteStream

    public var errorDescription: String? {
        switch self {
        case .invalidRoute:
            "ChatGPT plan requests require POST https://api.openai.com/v1/responses."
        case .invalidBody:
            "The ChatGPT plan request or response did not match the Responses contract."
        case .unsupportedTool(let type):
            "This tool type is unavailable through ChatGPT plan usage: \(type)"
        case .response(let error):
            "OpenAI HTTP \(error.status), code: \(error.code ?? "unknown"), parameter: \(error.parameter ?? "none"), request: \(error.requestID ?? "unavailable")."
        case .incompleteStream:
            "The ChatGPT response ended before response.completed."
        }
    }
}

/// Adapts the original Hanlin Responses provider to the documented plan-use contract.
/// Tool schemas and execution stay in the original provider and host dispatcher.
public enum HanlinChatGPTPlanTransport {
    public static func prepareRequest(_ original: URLRequest) throws -> URLRequest {
        guard let url = original.url, url.scheme == "https", url.host == "api.openai.com",
              url.port == nil || url.port == 443, url.path == "/v1/responses",
              url.user == nil, url.password == nil, url.query == nil, url.fragment == nil,
              original.httpMethod == "POST" else {
            throw HanlinChatGPTPlanTransportError.invalidRoute
        }
        guard let bytes = original.httpBody,
              var body = try JSONSerialization.jsonObject(with: bytes) as? [String: Any] else {
            throw HanlinChatGPTPlanTransportError.invalidBody
        }
        var input: [[String: Any]]
        if let items = body["input"] as? [[String: Any]] {
            input = items
        } else if let text = body["input"] as? String {
            input = [["role": "user", "content": text]]
        } else {
            throw HanlinChatGPTPlanTransportError.invalidBody
        }
        for index in input.indices {
            if input[index]["role"] as? String == "system" { input[index]["role"] = "developer" }
            if input[index]["type"] as? String == "additional_tools",
               let tools = input[index]["tools"] as? [[String: Any]] {
                try validateTools(tools)
            }
        }
        let omitted = ["background", "conversation", "max_output_tokens", "max_tool_calls",
                       "metadata", "moderation", "multi_agent", "prompt", "prompt_cache_retention",
                       "safety_identifier", "temperature", "top_logprobs", "top_p", "truncation",
                       "user", "previous_response_id", "service_tier"]
        for key in omitted { body.removeValue(forKey: key) }
        body["store"] = false
        body["stream"] = true

        if let tools = body["tools"] as? [[String: Any]] {
            try validateTools(tools)
            let functions = tools.filter { ["function", "custom"].contains($0["type"] as? String ?? "") }
            let other = tools.filter { !["function", "custom"].contains($0["type"] as? String ?? "") }
            // additional_tools preserves each advertised alias without changing host routing.
            if !functions.isEmpty {
                input.insert(["type": "additional_tools", "role": "developer", "tools": functions], at: 0)
            }
            if other.isEmpty { body.removeValue(forKey: "tools") } else { body["tools"] = other }
        }
        body["input"] = input
        var request = original
        request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        return request
    }

    private static func validateTools(_ tools: [[String: Any]]) throws {
        for tool in tools {
            let type = tool["type"] as? String ?? ""
            switch type {
            case "function", "custom", "web_search", "web_search_preview", "web_search_preview_2025_03_11":
                break
            case "namespace":
                guard let children = tool["tools"] as? [[String: Any]], !children.isEmpty,
                      children.allSatisfy({ ["function", "custom"].contains($0["type"] as? String ?? "") }) else {
                    throw HanlinChatGPTPlanTransportError.unsupportedTool(type)
                }
            default:
                throw HanlinChatGPTPlanTransportError.unsupportedTool(type)
            }
        }
    }

    public static func makeFetch(base: FetchFunction? = nil) -> FetchFunction {
        let transport = base ?? HanlinAISDKProviderFactory.makeFetch(sessionConfiguration: .ephemeral)
        return { request in
            let response = try await transport(prepareRequest(request))
            guard let http = response.urlResponse as? HTTPURLResponse else {
                throw HanlinChatGPTPlanTransportError.invalidBody
            }
            let requestID = http.value(forHTTPHeaderField: "x-request-id")
            guard http.statusCode == 200 else {
                var data = Data()
                for try await chunk in response.body.makeStream() {
                    data.append(chunk.prefix(max(0, 65_536 - data.count)))
                    if data.count >= 65_536 { break }
                }
                throw HanlinChatGPTPlanTransportError.response(
                    failure(data, status: http.statusCode, requestID: requestID))
            }
            guard http.value(forHTTPHeaderField: "content-type")?.lowercased()
                .hasPrefix("text/event-stream") == true else {
                throw HanlinChatGPTPlanTransportError.invalidBody
            }
            let stream = AsyncThrowingStream<Data, Error> { continuation in
                let task = Task {
                    var validator = PlanStreamValidator(status: http.statusCode, requestID: requestID)
                    do {
                        for try await data in response.body.makeStream() {
                            try Task.checkCancellation()
                            try validator.consume(data)
                            continuation.yield(data)
                        }
                        try validator.finish()
                        continuation.finish()
                    } catch {
                        continuation.finish(throwing: error)
                    }
                }
                continuation.onTermination = { @Sendable _ in task.cancel() }
            }
            return FetchResponse(body: .stream(stream), urlResponse: http)
        }
    }

    fileprivate static func failure(_ bytes: Data, status: Int, requestID: String?) -> HanlinChatGPTPlanFailure {
        let object = (try? JSONSerialization.jsonObject(with: bytes)) as? [String: Any]
        return failure(object ?? [:], status: status, requestID: requestID,
                       fallbackShape: object == nil ? "non-json" : "object")
    }

    fileprivate static func failure(_ object: [String: Any], status: Int, requestID: String?,
                                    fallbackShape: String = "event") -> HanlinChatGPTPlanFailure {
        let response = object["response"] as? [String: Any]
        let error = (object["error"] as? [String: Any]) ?? (response?["error"] as? [String: Any])
        let incomplete = response?["incomplete_details"] as? [String: Any]
        let code = error?["code"] as? String ?? object["code"] as? String ??
            object["error"] as? String ?? incomplete?["reason"] as? String
        let shape = object["detail"] != nil ? "detail" :
            error != nil ? "error" : fallbackShape
        return .init(status: status, code: code, parameter: error?["param"] as? String,
                     requestID: requestID, bodyShape: shape)
    }
}

private struct PlanStreamValidator {
    let status: Int
    let requestID: String?
    private var pending = Data()
    private var dataLines: [String] = []
    private var completed = false

    init(status: Int, requestID: String?) {
        self.status = status
        self.requestID = requestID
    }

    mutating func consume(_ bytes: Data) throws {
        pending.append(bytes)
        while let newline = pending.firstIndex(of: 0x0A) {
            let line = Data(pending[..<newline])
            pending.removeSubrange(...newline)
            try consumeLine(line)
        }
    }

    mutating func finish() throws {
        if !pending.isEmpty {
            try consumeLine(pending)
            pending.removeAll()
        }
        try consumeEvent()
        guard completed else { throw HanlinChatGPTPlanTransportError.incompleteStream }
    }

    private mutating func consumeLine(_ bytes: Data) throws {
        var line = String(decoding: bytes, as: UTF8.self)
        if line.hasSuffix("\r") { line.removeLast() }
        if line.isEmpty { try consumeEvent(); return }
        guard line.hasPrefix("data:") else { return }
        var data = String(line.dropFirst(5))
        if data.hasPrefix(" ") { data.removeFirst() }
        dataLines.append(data)
    }

    private mutating func consumeEvent() throws {
        guard !dataLines.isEmpty else { return }
        let data = dataLines.joined(separator: "\n")
        dataLines.removeAll()
        if data == "[DONE]" { return }
        guard let object = try JSONSerialization.jsonObject(with: Data(data.utf8)) as? [String: Any],
              let type = object["type"] as? String else {
            throw HanlinChatGPTPlanTransportError.invalidBody
        }
        switch type {
        case "response.failed", "response.incomplete", "error":
            throw HanlinChatGPTPlanTransportError.response(
                HanlinChatGPTPlanTransport.failure(object, status: status, requestID: requestID))
        case "response.completed":
            completed = true
        default:
            break
        }
    }
}
