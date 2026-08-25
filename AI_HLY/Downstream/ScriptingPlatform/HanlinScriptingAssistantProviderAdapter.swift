import Foundation
import SwiftData

@MainActor
final class HanlinScriptingAssistantProviderAdapter {
    private struct Configuration: Sendable {
        let endpoint: URL
        let apiKey: String
        let modelID: String
    }

    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    func load(
        _ request: HanlinScriptingAssistantRequest
    ) async throws -> AsyncThrowingStream<HanlinScriptingAssistantChunk, Error> {
        let configuration = try resolveConfiguration(for: request)
        let nativeRequest = try Self.makeRequest(request, configuration: configuration)
        switch request.kind {
        case .streaming:
            return Self.streamingResponse(for: nativeRequest)
        case .structuredData:
            return Self.structuredResponse(for: nativeRequest)
        }
    }

    private func resolveConfiguration(
        for request: HanlinScriptingAssistantRequest
    ) throws -> Configuration {
        let keys = try context.fetch(FetchDescriptor<APIKeys>())
        let models = try context.fetch(FetchDescriptor<AllModels>())
        let explicitModel = request.modelID.flatMap { requested in
            models.first { $0.name == requested }
        }

        let key: APIKeys?
        switch request.provider {
        case let .builtIn(provider):
            let company = try Self.company(for: provider)
            key = keys.first { $0.company?.caseInsensitiveCompare(company) == .orderedSame }
        case let .custom(identifier):
            key = keys.first { candidate in
                candidate.company?.caseInsensitiveCompare(identifier) == .orderedSame
                    || candidate.name?.caseInsensitiveCompare(identifier) == .orderedSame
                    || candidate.requestURL == identifier
            }
        case nil:
            if let company = explicitModel?.company {
                key = keys.first { $0.company?.caseInsensitiveCompare(company) == .orderedSame }
            } else {
                key = keys
                    .filter { !($0.key?.isEmpty ?? true) && $0.requestURL != nil }
                    .sorted { ($0.isHidden ? 1 : 0, $0.company ?? "") < ($1.isHidden ? 1 : 0, $1.company ?? "") }
                    .first
            }
        }

        guard let key, let secret = key.key, !secret.isEmpty, secret.uppercased() != "LOCAL" else {
            throw Self.failure(
                code: "assistant_credentials_unavailable",
                message: "No configured credentials are available for the requested Assistant provider."
            )
        }
        guard key.apiType == .openAI,
              let endpointText = key.requestURL,
              endpointText.utf8.count <= 4_096,
              let endpoint = URL(string: endpointText),
              let scheme = endpoint.scheme?.lowercased(),
              scheme == "https" || scheme == "http" else {
            throw Self.failure(
                code: "assistant_provider_unsupported",
                message: "The configured Assistant provider does not expose a supported Chat Completions endpoint."
            )
        }

        let company = key.company ?? ""
        let selectedModel = explicitModel ?? models
            .filter {
                $0.supportsTextGen
                    && $0.company?.caseInsensitiveCompare(company) == .orderedSame
            }
            .sorted {
                ($0.isHidden ? 1 : 0, $0.position ?? .max, $0.name ?? "")
                    < ($1.isHidden ? 1 : 0, $1.position ?? .max, $1.name ?? "")
            }
            .first
        guard let modelID = request.modelID ?? selectedModel?.name, !modelID.isEmpty,
              modelID.utf8.count <= 512 else {
            throw Self.failure(
                code: "assistant_model_unavailable",
                message: "No model is configured for the requested Assistant provider."
            )
        }
        return Configuration(
            endpoint: endpoint,
            apiKey: secret,
            modelID: restoreBaseModelName(from: modelID)
        )
    }

    nonisolated private static func company(for provider: String) throws -> String {
        switch provider {
        case "openai": "OPENAI"
        case "gemini": "GOOGLE"
        case "anthropic": "ANTHROPIC"
        case "deepseek": "DEEPSEEK"
        case "openrouter": "OPENROUTER"
        default:
            throw failure(
                code: "assistant_provider_unsupported",
                message: "The requested Assistant provider is unsupported."
            )
        }
    }

    nonisolated private static func makeRequest(
        _ request: HanlinScriptingAssistantRequest,
        configuration: Configuration
    ) throws -> URLRequest {
        var payload: [String: Any] = ["model": configuration.modelID]
        switch request.kind {
        case .streaming:
            payload["stream"] = true
            payload["stream_options"] = ["include_usage": true]
            payload["messages"] = try streamingMessages(request)
        case .structuredData:
            guard let prompt = request.prompt, let schemaData = request.schemaJSON else {
                throw failure(code: "invalid_assistant_request", message: "The structured Assistant request is incomplete.")
            }
            payload["stream"] = false
            payload["messages"] = try structuredMessages(prompt: prompt, images: request.images)
            let sourceSchema = try JSONSerialization.jsonObject(with: schemaData)
            payload["response_format"] = [
                "type": "json_schema",
                "json_schema": [
                    "name": "hanlin_scripting_result",
                    "strict": false,
                    "schema": try providerSchema(sourceSchema),
                ],
            ]
        }
        guard JSONSerialization.isValidJSONObject(payload) else {
            throw failure(code: "invalid_assistant_request", message: "The Assistant request could not be encoded.")
        }
        let body = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        guard body.count <= 8 * 1_024 * 1_024 else {
            throw failure(code: "invalid_assistant_request", message: "The Assistant request is too large.")
        }
        var nativeRequest = URLRequest(url: configuration.endpoint)
        nativeRequest.httpMethod = "POST"
        nativeRequest.httpBody = body
        nativeRequest.timeoutInterval = 300
        nativeRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        nativeRequest.setValue("Bearer \(configuration.apiKey)", forHTTPHeaderField: "Authorization")
        return nativeRequest
    }

    nonisolated private static func streamingMessages(
        _ request: HanlinScriptingAssistantRequest
    ) throws -> [[String: Any]] {
        guard let data = request.messagesJSON,
              let source = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw failure(code: "invalid_assistant_request", message: "Assistant messages are invalid.")
        }
        var messages: [[String: Any]] = []
        if let systemPrompt = request.systemPrompt, !systemPrompt.isEmpty {
            messages.append(["role": "system", "content": systemPrompt])
        }
        for message in source {
            guard let role = message["role"] as? String,
                  role == "user" || role == "assistant",
                  let content = message["content"] else {
                throw failure(code: "invalid_assistant_request", message: "An Assistant message is invalid.")
            }
            messages.append(["role": role, "content": try providerContent(content)])
        }
        return messages
    }

    nonisolated private static func structuredMessages(
        prompt: String,
        images: [String]
    ) throws -> [[String: Any]] {
        guard !images.isEmpty else { return [["role": "user", "content": prompt]] }
        var content: [[String: Any]] = [["type": "text", "text": prompt]]
        content.append(contentsOf: images.map {
            ["type": "image_url", "image_url": ["url": $0]]
        })
        return [["role": "user", "content": content]]
    }

    nonisolated private static func providerContent(_ value: Any) throws -> Any {
        if let text = value as? String { return text }
        let values = value as? [Any] ?? [value]
        return try values.map { item -> [String: Any] in
            if let text = item as? String { return ["type": "text", "text": text] }
            guard let object = item as? [String: Any], let type = object["type"] as? String else {
                throw failure(code: "invalid_assistant_request", message: "Assistant message content is invalid.")
            }
            switch type {
            case "text":
                guard let content = object["content"] as? String else {
                    throw failure(code: "invalid_assistant_request", message: "Assistant text content is invalid.")
                }
                return ["type": "text", "text": content]
            case "image":
                guard let content = object["content"] as? String else {
                    throw failure(code: "invalid_assistant_request", message: "Assistant image content is invalid.")
                }
                return ["type": "image_url", "image_url": ["url": content]]
            case "document":
                throw failure(
                    code: "assistant_content_unsupported",
                    message: "Document message parts are not supported by the configured Chat Completions provider."
                )
            default:
                throw failure(code: "invalid_assistant_request", message: "Assistant message content is invalid.")
            }
        }
    }

    nonisolated static func providerSchema(_ value: Any) throws -> Any {
        guard let object = value as? [String: Any], let type = object["type"] as? String else {
            throw failure(code: "invalid_assistant_request", message: "The Assistant schema is invalid.")
        }
        var result: [String: Any] = ["type": type]
        if let description = object["description"] as? String { result["description"] = description }
        switch type {
        case "object":
            guard let properties = object["properties"] as? [String: Any] else {
                throw failure(code: "invalid_assistant_request", message: "The Assistant object schema is invalid.")
            }
            var mapped: [String: Any] = [:]
            var required: [String] = []
            for key in properties.keys.sorted() {
                guard let property = properties[key] else { continue }
                mapped[key] = try providerSchema(property)
                if (property as? [String: Any])?["required"] as? Bool == true { required.append(key) }
            }
            result["properties"] = mapped
            result["required"] = required
            result["additionalProperties"] = false
        case "array":
            guard let items = object["items"] else {
                throw failure(code: "invalid_assistant_request", message: "The Assistant array schema is invalid.")
            }
            result["items"] = try providerSchema(items)
        case "string", "number", "boolean":
            break
        default:
            throw failure(code: "invalid_assistant_request", message: "The Assistant schema type is invalid.")
        }
        return result
    }

    nonisolated private static func streamingResponse(
        for request: URLRequest
    ) -> AsyncThrowingStream<HanlinScriptingAssistantChunk, Error> {
        let (stream, continuation) = AsyncThrowingStream<HanlinScriptingAssistantChunk, Error>.makeStream()
        // Parsing is intentionally kept off the main actor while the package UI remains interactive.
        let task = Task.detached(priority: .userInitiated) {
            let session = isolatedSession()
            defer { session.finishTasksAndInvalidate() }
            do {
                let (bytes, response) = try await session.bytes(for: request)
                try validate(response)
                var chunkCount = 0
                var byteCount = 0
                for try await line in bytes.lines {
                    try Task.checkCancellation()
                    guard line.hasPrefix("data:") else { continue }
                    let dataText = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                    if dataText == "[DONE]" { break }
                    byteCount += dataText.utf8.count
                    chunkCount += 1
                    guard byteCount <= 16 * 1_024 * 1_024, chunkCount <= 8_192 else {
                        throw failure(code: "assistant_response_too_large", message: "The Assistant response is too large.")
                    }
                    guard let data = dataText.data(using: .utf8),
                          let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                        throw failure(code: "assistant_response_invalid", message: "The Assistant stream returned invalid JSON.")
                    }
                    for chunk in try chunks(from: object) { continuation.yield(chunk) }
                }
                continuation.finish()
            } catch is CancellationError {
                continuation.finish(throwing: failure(
                    name: "AbortError", code: "cancelled", message: "The Assistant request was cancelled."
                ))
            } catch let error as HanlinScriptingNativeError {
                continuation.finish(throwing: error)
            } catch {
                continuation.finish(throwing: failure(
                    code: "assistant_network_failure", message: "The Assistant provider request failed."
                ))
            }
        }
        continuation.onTermination = { @Sendable _ in task.cancel() }
        return stream
    }

    nonisolated private static func structuredResponse(
        for request: URLRequest
    ) -> AsyncThrowingStream<HanlinScriptingAssistantChunk, Error> {
        let (stream, continuation) = AsyncThrowingStream<HanlinScriptingAssistantChunk, Error>.makeStream()
        let task = Task.detached(priority: .userInitiated) {
            let session = isolatedSession()
            defer { session.finishTasksAndInvalidate() }
            do {
                let (data, response) = try await session.data(for: request)
                try validate(response)
                guard data.count <= 16 * 1_024 * 1_024,
                      let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let choices = object["choices"] as? [[String: Any]],
                      let message = choices.first?["message"] as? [String: Any],
                      let content = message["content"] as? String,
                      let result = structuredData(from: content) else {
                    throw failure(code: "assistant_response_invalid", message: "The Assistant provider returned invalid structured data.")
                }
                continuation.yield(.structuredJSON(result))
                continuation.finish()
            } catch is CancellationError {
                continuation.finish(throwing: failure(
                    name: "AbortError", code: "cancelled", message: "The Assistant request was cancelled."
                ))
            } catch let error as HanlinScriptingNativeError {
                continuation.finish(throwing: error)
            } catch {
                continuation.finish(throwing: failure(
                    code: "assistant_network_failure", message: "The Assistant provider request failed."
                ))
            }
        }
        continuation.onTermination = { @Sendable _ in task.cancel() }
        return stream
    }

    nonisolated static func chunks(
        from object: [String: Any]
    ) throws -> [HanlinScriptingAssistantChunk] {
        var result: [HanlinScriptingAssistantChunk] = []
        if let choices = object["choices"] as? [[String: Any]],
           let delta = choices.first?["delta"] as? [String: Any] {
            if let reasoning = delta["reasoning_content"] as? String ?? delta["reasoning"] as? String,
               !reasoning.isEmpty {
                result.append(.reasoning(reasoning))
            }
            if let content = delta["content"] as? String, !content.isEmpty {
                result.append(.text(content))
            }
        }
        if let usage = object["usage"] as? [String: Any] {
            let input = integer(usage["prompt_tokens"] ?? usage["input_tokens"]) ?? 0
            let output = integer(usage["completion_tokens"] ?? usage["output_tokens"]) ?? 0
            let promptDetails = usage["prompt_tokens_details"] as? [String: Any]
            let cacheRead = integer(promptDetails?["cached_tokens"])
            result.append(.usage(.init(
                totalCost: number(usage["total_cost"]),
                cacheReadTokens: cacheRead,
                cacheWriteTokens: nil,
                inputTokens: max(0, input),
                outputTokens: max(0, output)
            )))
        }
        return result
    }

    nonisolated static func structuredData(from content: String) -> Data? {
        var value = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("```") {
            let lines = value.split(separator: "\n", omittingEmptySubsequences: false)
            if lines.count >= 3, lines.last?.trimmingCharacters(in: .whitespacesAndNewlines) == "```" {
                value = lines.dropFirst().dropLast().joined(separator: "\n")
            }
        }
        guard let data = value.data(using: .utf8), data.count <= 8 * 1_024 * 1_024,
              let object = try? JSONSerialization.jsonObject(with: data),
              JSONSerialization.isValidJSONObject([object]) else { return nil }
        return try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }

    nonisolated private static func isolatedSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: configuration)
    }

    nonisolated private static func validate(_ response: URLResponse) throws {
        guard let response = response as? HTTPURLResponse,
              (200 ... 299).contains(response.statusCode) else {
            throw failure(code: "assistant_provider_failure", message: "The Assistant provider rejected the request.")
        }
    }

    nonisolated private static func integer(_ value: Any?) -> Int? {
        guard !(value is Bool), let number = value as? NSNumber else { return nil }
        return number.intValue
    }

    nonisolated private static func number(_ value: Any?) -> Double? {
        guard !(value is Bool), let number = value as? NSNumber,
              number.doubleValue.isFinite else { return nil }
        return number.doubleValue
    }

    nonisolated private static func failure(
        name: String = "Error", code: String, message: String
    ) -> HanlinScriptingNativeError {
        .init(name: name, code: code, message: message)
    }
}
