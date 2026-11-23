import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// The public SIWC route has a narrower wire contract than the ordinary
/// Responses API. Keep that adaptation shared, without replacing the agent.
enum HanlinChatGPTPlanWire {
    static let namespace = "hanlin"
    static let unsupportedFields = [
        "background", "conversation", "max_output_tokens", "max_tool_calls",
        "metadata", "moderation", "multi_agent", "prompt", "prompt_cache_retention",
        "safety_identifier", "temperature", "top_logprobs", "top_p", "truncation",
        "user", "previous_response_id"
    ]

    static func prepare(_ request: URLRequest) throws -> URLRequest {
        guard let url = request.url, url.scheme == "https",
              url.host == "api.openai.com", url.path == "/v1/responses",
              url.user == nil, url.password == nil,
              let data = request.httpBody,
              var body = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              var input = body["input"] as? [[String: Any]] else {
            throw HanlinChatGPTPlanWireError.invalidRequest
        }
        for key in unsupportedFields { body.removeValue(forKey: key) }
        body["store"] = false
        body["stream"] = true

        let tools = body["tools"] as? [[String: Any]] ?? []
        let local = tools.filter { ["function", "custom"].contains($0["type"] as? String ?? "") }
        let other = tools.filter { !["function", "custom"].contains($0["type"] as? String ?? "") }
        guard other.allSatisfy({ ["web_search", "web_search_preview"].contains($0["type"] as? String ?? "") }) else {
            throw HanlinChatGPTPlanWireError.unsupportedTool
        }
        if !local.isEmpty {
            body["tools"] = other + [[
                "type": "namespace", "name": namespace,
                "description": "Tools provided by this application. Execute the requested operation using its tool.",
                "tools": local
            ]]
        }
        let localNames = Set(local.compactMap { $0["name"] as? String })
        for index in input.indices {
            if input[index]["role"] as? String == "system" { input[index]["role"] = "developer" }
            if ["function_call", "custom_tool_call"].contains(input[index]["type"] as? String ?? ""),
               let name = input[index]["name"] as? String, localNames.contains(name) {
                input[index]["namespace"] = namespace
            }
        }
        body["input"] = input
        var value = request
        value.httpBody = try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
        value.setValue(nil, forHTTPHeaderField: "Content-Length")
        return value
    }
}

enum HanlinChatGPTPlanWireError: Error, LocalizedError, Sendable, Equatable {
    case invalidRequest
    case unsupportedTool
    case invalidEvent
    case missingCompletion
    case failed(String)
    case incomplete(String)

    var errorDescription: String? {
        switch self {
        case .invalidRequest: "The ChatGPT request is invalid."
        case .unsupportedTool: "This tool is not supported by ChatGPT plan access."
        case .invalidEvent: "ChatGPT returned an invalid response event."
        case .missingCompletion: "The ChatGPT response was interrupted before completion."
        case .failed(let code):
            switch code {
            case "subscription_sharing_usage_limit_exceeded":
                "The ChatGPT usage limit for this app has been reached. Review ChatGPT Settings → Usage."
            case "subscription_sharing_usage_unavailable":
                "ChatGPT plan usage is unavailable for this account or workspace."
            default: "ChatGPT could not complete the response (" + code + ")."
            }
        case .incomplete(let reason): "ChatGPT returned an incomplete response (" + reason + ")."
        }
    }
}

/// Validates complete SSE events before forwarding their unchanged bytes to
/// the canonical provider. A text delta or a clean EOF is not a completed turn.
struct HanlinChatGPTPlanSSEValidator {
    private var pending = Data()
    private var eventBytes = Data()
    private var dataLines: [Data] = []
    private var completed = false
    private let maximumEventBytes = 8 * 1024 * 1024

    mutating func consume(_ bytes: Data) throws -> [Data] {
        pending.append(bytes)
        var ready: [Data] = []
        while let end = pending.firstIndex(of: 0x0A) {
            let lineWithNewline = Data(pending[...end])
            pending.removeSubrange(...end)
            eventBytes.append(lineWithNewline)
            guard eventBytes.count <= maximumEventBytes else {
                throw HanlinChatGPTPlanWireError.invalidEvent
            }
            var line = Data(lineWithNewline.dropLast())
            if line.last == 0x0D { line.removeLast() }
            if line.isEmpty {
                try validateEvent()
                ready.append(eventBytes)
                eventBytes.removeAll(keepingCapacity: true)
                dataLines.removeAll(keepingCapacity: true)
            } else if line.starts(with: Data("data:".utf8)) {
                var data = Data(line.dropFirst(5))
                if data.first == 0x20 { data.removeFirst() }
                dataLines.append(data)
            }
        }
        guard pending.count + eventBytes.count <= maximumEventBytes else {
            throw HanlinChatGPTPlanWireError.invalidEvent
        }
        return ready
    }

    mutating func finish() throws {
        // SSE dispatch requires the blank line delimiter, including for the
        // terminal event. Do not infer success from a truncated JSON prefix.
        guard completed, pending.allSatisfy({ $0 == 0x0D || $0 == 0x0A || $0 == 0x20 }),
              dataLines.isEmpty else {
            throw HanlinChatGPTPlanWireError.missingCompletion
        }
    }

    private mutating func validateEvent() throws {
        guard !dataLines.isEmpty else { return }
        let data = dataLines.enumerated().reduce(into: Data()) { result, entry in
            if entry.offset > 0 { result.append(0x0A) }
            result.append(entry.element)
        }
        if String(data: data, encoding: .utf8) == "[DONE]" { return }
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = object["type"] as? String else {
            throw HanlinChatGPTPlanWireError.invalidEvent
        }
        let response = object["response"] as? [String: Any]
        switch type {
        case "response.completed":
            guard response?["status"] as? String == "completed" else {
                throw HanlinChatGPTPlanWireError.invalidEvent
            }
            completed = true
        case "response.failed", "error":
            let error = (response?["error"] as? [String: Any]) ??
                (object["error"] as? [String: Any]) ?? object
            throw HanlinChatGPTPlanWireError.failed(Self.safeCode(error["code"]))
        case "response.incomplete":
            let detail = response?["incomplete_details"] as? [String: Any]
            throw HanlinChatGPTPlanWireError.incomplete(Self.safeCode(detail?["reason"]))
        case "response.output_item.added", "response.output_item.done":
            if let item = object["item"] as? [String: Any],
               ["function_call", "custom_tool_call"].contains(item["type"] as? String ?? "") {
                guard item["namespace"] as? String == HanlinChatGPTPlanWire.namespace else {
                    throw HanlinChatGPTPlanWireError.invalidEvent
                }
            }
        default: break
        }
    }

    private static func safeCode(_ value: Any?) -> String {
        guard let code = value as? String, !code.isEmpty, code.count <= 128,
              code.unicodeScalars.allSatisfy({ CharacterSet.alphanumerics.contains($0) || $0 == "_" || $0 == "-" }) else {
            return "unknown_error"
        }
        return code
    }
}
