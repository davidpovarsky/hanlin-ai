// HanlinChatRequestBuilder.swift
// HanlinChatCore
//
// Single authoritative remote model request builder for the Hanlin Chat Engine.
// Preserves production APIManager request structure and configured max_tokens
// semantics across the main app and extension surfaces.

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct HanlinChatRequestBuilder: Sendable {

    public static func buildRequest(
        messages: [HanlinChatMessage],
        configuration: HanlinChatModelConfiguration,
        systemContext: String? = nil,
        stream: Bool = true,
        tools: [[String: Any]]? = nil
    ) throws -> URLRequest {
        var combinedSystem: String? = nil
        if let systemPrompt = configuration.systemPrompt, !systemPrompt.isEmpty {
            if let ctx = systemContext, !ctx.isEmpty {
                combinedSystem = "\(systemPrompt)\n\nContext:\n\(ctx)"
            } else {
                combinedSystem = systemPrompt
            }
        } else if let ctx = systemContext, !ctx.isEmpty {
            combinedSystem = "Context:\n\(ctx)"
        }

        var messagePayloads: [[String: Any]] = []
        if let combinedSystem, !combinedSystem.isEmpty {
            messagePayloads.append([
                "role": "system",
                "content": combinedSystem
            ])
        }
        for msg in messages {
            messagePayloads.append([
                "role": msg.role,
                "content": msg.content
            ])
        }
        if messagePayloads.isEmpty {
            messagePayloads.append(["role": "user", "content": "Hello"])
        }
        return try buildRequest(
            formattedMessages: messagePayloads,
            configuration: configuration,
            tools: tools
        )
    }

    /// Builds a provider request from the production app's already-formatted
    /// messages. This is the single request-format dispatch point used by both
    /// APIManager and compact extension sessions.
    public static func buildRequest(
        formattedMessages: [[String: Any]],
        configuration: HanlinChatModelConfiguration,
        tools: [[String: Any]]? = nil
    ) throws -> URLRequest {
        switch (configuration.apiType ?? "OpenAI").lowercased() {
        case "anthropic":
            return try buildAnthropicRequest(
                formattedMessages: formattedMessages,
                configuration: configuration,
                tools: tools
            )
        case "gemini":
            return try buildGeminiRequest(
                formattedMessages: formattedMessages,
                configuration: configuration,
                tools: tools
            )
        default:
            return try buildOpenAIRequest(
                formattedMessages: formattedMessages,
                configuration: configuration,
                tools: tools
            )
        }
    }

    // MARK: - OpenAI / OpenRouter Request Builder

    public static func buildOpenAIBody(
        formattedMessages: [[String: Any]],
        configuration: HanlinChatModelConfiguration,
        tools: [[String: Any]]? = nil
    ) -> [String: Any] {
        let baseName = configuration.baseModelID.isEmpty ? restoreBaseModelName(from: configuration.modelID) : configuration.baseModelID
        let maxTokens = configuration.maxTokens > 0
            ? configuration.maxTokens
            : HanlinChatGenerationDefaults.maxTokens

        var requestBody: [String: Any] = [
            "model": baseName,
            "messages": formattedMessages,
            "stream": true,
            "max_tokens": maxTokens
        ]

        if configuration.temperature > 0 {
            requestBody["temperature"] = configuration.temperature
        }
        if configuration.topP > 0 {
            requestBody["top_p"] = configuration.topP
        }

        // Tools
        if let tools, !tools.isEmpty, configuration.supportsToolUse {
            requestBody["tools"] = tools
        }

        // Reasoning controls
        let company = (configuration.company ?? "").uppercased()
        if configuration.supportReasoningChange {
            if company == "QWEN" || company == "MODELSCOPE" || company == "SILICONCLOUD" || company == "WENXIN" {
                requestBody["enable_thinking"] = configuration.supportsReasoning
            } else if company == "ANTHROPIC" {
                requestBody["think"] = [
                    "type": configuration.supportsReasoning ? "enabled" : "disabled"
                ]
            } else if company == "ZHIPUAI" || company == "HANLIN" || company == "DOUBAO" || company == "OPENROUTER" {
                requestBody["thinking"] = [
                    "type": configuration.supportsReasoning ? "enabled" : "disabled"
                ]
            }
        }

        // Thinking length / budget
        if configuration.supportsReasoning && configuration.thinkingLength > 0 {
            switch configuration.thinkingLength {
            case 1:
                if company == "OPENAI" || company == "GOOGLE" || company == "XAI" || company == "DOUBAO" || company == "OPENROUTER" {
                    requestBody["reasoning_effort"] = "low"
                } else if company == "QWEN" || company == "MODELSCOPE" || company == "SILICONCLOUD" {
                    requestBody["thinking_budget"] = 1024
                }
            case 2:
                if company == "OPENAI" || company == "GOOGLE" || company == "XAI" || company == "DOUBAO" || company == "OPENROUTER" {
                    requestBody["reasoning_effort"] = "medium"
                } else if company == "QWEN" || company == "MODELSCOPE" || company == "SILICONCLOUD" {
                    requestBody["thinking_budget"] = 8192
                }
            case 3:
                if company == "OPENAI" || company == "GOOGLE" || company == "XAI" {
                    requestBody["reasoning_effort"] = "high"
                } else if company == "QWEN" || company == "MODELSCOPE" || company == "SILICONCLOUD" || company == "OPENROUTER" {
                    requestBody["thinking_budget"] = 16384
                }
            default:
                break
            }
        }

        // Explicit reasoning effort
        if let effort = configuration.reasoningEffort, !effort.isEmpty {
            requestBody["reasoning"] = ["effort": effort]
        }

        return requestBody
    }

    public static func buildOpenAIRequest(
        formattedMessages: [[String: Any]],
        configuration: HanlinChatModelConfiguration,
        tools: [[String: Any]]? = nil
    ) throws -> URLRequest {
        let requestBody = buildOpenAIBody(
            formattedMessages: formattedMessages,
            configuration: configuration,
            tools: tools
        )

        return try buildOpenAIRequest(
            requestBody: requestBody,
            configuration: configuration
        )
    }

    public static func buildOpenAIRequest(
        requestBody: [String: Any],
        configuration: HanlinChatModelConfiguration
    ) throws -> URLRequest {
        var req = URLRequest(url: configuration.endpoint)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(configuration.apiKey)", forHTTPHeaderField: "Authorization")
        req.setValue("https://hanlin.ai", forHTTPHeaderField: "HTTP-Referer")
        req.setValue("Hanlin", forHTTPHeaderField: "X-Title")
        req.timeoutInterval = 60
        req.httpBody = try JSONSerialization.data(withJSONObject: requestBody, options: [])
        return req
    }

    // MARK: - Anthropic Request Builder

    private static func buildAnthropicRequest(
        formattedMessages: [[String: Any]],
        configuration: HanlinChatModelConfiguration,
        tools: [[String: Any]]?
    ) throws -> URLRequest {
        var endpointURL = configuration.endpoint
        let urlStr = endpointURL.absoluteString
        if urlStr.hasSuffix("/chat/completions") {
            if let newURL = URL(string: urlStr.replacingOccurrences(of: "/chat/completions", with: "/messages")) {
                endpointURL = newURL
            }
        } else if !urlStr.contains("/messages") {
            let base = urlStr.hasSuffix("/") ? String(urlStr.dropLast()) : urlStr
            let pathSuffix = base.hasSuffix("/v1") ? "/messages" : "/v1/messages"
            if let newURL = URL(string: "\(base)\(pathSuffix)") {
                endpointURL = newURL
            }
        }

        var systemParts: [String] = []
        var anthropicMessages: [[String: Any]] = []
        for message in formattedMessages {
            let role = message["role"] as? String ?? "user"
            if role == "system" {
                if let content = message["content"] as? String, !content.isEmpty {
                    systemParts.append(content)
                }
                continue
            }
            let normalizedRole = role == "assistant" ? "assistant" : "user"
            if let content = message["content"] {
                anthropicMessages.append(["role": normalizedRole, "content": content])
            }
        }
        if anthropicMessages.isEmpty {
            anthropicMessages.append(["role": "user", "content": "Hello"])
        }

        let baseName = configuration.baseModelID.isEmpty ? restoreBaseModelName(from: configuration.modelID) : configuration.baseModelID
        let maxTokens = configuration.maxTokens > 0
            ? configuration.maxTokens
            : HanlinChatGenerationDefaults.maxTokens

        var body: [String: Any] = [
            "model": baseName,
            "stream": true,
            "max_tokens": maxTokens,
            "messages": anthropicMessages
        ]
        if !systemParts.isEmpty {
            body["system"] = systemParts.joined(separator: "\n\n")
        }
        if configuration.temperature > 0 {
            body["temperature"] = configuration.temperature
        }
        if configuration.topP > 0 {
            body["top_p"] = configuration.topP
        }
        if configuration.supportsReasoning {
            let budget: Int = switch configuration.thinkingLength {
            case 1: 1_024
            case 2: 8_192
            case 3: 16_384
            default: 1_024
            }
            body["thinking"] = ["type": "enabled", "budget_tokens": budget]
        }
        if configuration.supportsToolUse, let tools {
            let converted = anthropicTools(from: tools)
            if !converted.isEmpty { body["tools"] = converted }
        }

        var req = URLRequest(url: endpointURL)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(configuration.apiKey, forHTTPHeaderField: "x-api-key")
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        req.timeoutInterval = 60
        req.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])
        return req
    }

    // MARK: - Gemini Request Builder

    private static func buildGeminiRequest(
        formattedMessages: [[String: Any]],
        configuration: HanlinChatModelConfiguration,
        tools: [[String: Any]]?
    ) throws -> URLRequest {
        let baseName = configuration.baseModelID.isEmpty ? restoreBaseModelName(from: configuration.modelID) : configuration.baseModelID
        var endpointURL = configuration.endpoint
        let urlStr = endpointURL.absoluteString

        if urlStr.contains(":streamGenerateContent") {
            var components = URLComponents(url: endpointURL, resolvingAgainstBaseURL: false)
            var items = components?.queryItems ?? []
            if !items.contains(where: { $0.name == "alt" }) {
                items.append(URLQueryItem(name: "alt", value: "sse"))
            }
            if !items.contains(where: { $0.name == "key" }) {
                items.append(URLQueryItem(name: "key", value: configuration.apiKey))
            }
            components?.queryItems = items
            if let u = components?.url { endpointURL = u }
        } else {
            let scheme = endpointURL.scheme ?? "https"
            let host = endpointURL.host ?? "generativelanguage.googleapis.com"
            let urlString = "\(scheme)://\(host)/v1beta/models/\(baseName):streamGenerateContent?alt=sse&key=\(configuration.apiKey)"
            if let u = URL(string: urlString) { endpointURL = u }
        }

        var systemParts: [String] = []
        var contents: [[String: Any]] = []
        for message in formattedMessages {
            let sourceRole = message["role"] as? String ?? "user"
            if sourceRole == "system" {
                if let content = message["content"] as? String, !content.isEmpty {
                    systemParts.append(content)
                }
                continue
            }
            let role = sourceRole == "assistant" ? "model" : "user"
            guard let content = message["content"] as? String else { continue }
            contents.append([
                "role": role,
                "parts": [["text": content]]
            ])
        }
        if contents.isEmpty {
            contents.append(["role": "user", "parts": [["text": "Hello"]]])
        }

        var body: [String: Any] = [
            "contents": contents
        ]
        if !systemParts.isEmpty {
            body["systemInstruction"] = ["parts": [["text": systemParts.joined(separator: "\n\n")]]]
        }

        var genConfig: [String: Any] = [:]
        if configuration.maxTokens > 0 {
            genConfig["maxOutputTokens"] = configuration.maxTokens
        }
        if configuration.temperature > 0 {
            genConfig["temperature"] = configuration.temperature
        }
        if configuration.topP > 0 {
            genConfig["topP"] = configuration.topP
        }
        if configuration.supportsReasoning {
            var thinkingConfig: [String: Any] = ["includeThoughts": true]
            switch configuration.thinkingLength {
            case 1: thinkingConfig["thinkingBudget"] = 1_024
            case 2: thinkingConfig["thinkingBudget"] = 8_192
            case 3: thinkingConfig["thinkingBudget"] = 16_384
            default: break
            }
            genConfig["thinkingConfig"] = thinkingConfig
        }
        if !genConfig.isEmpty {
            body["generationConfig"] = genConfig
        }
        if configuration.supportsToolUse, let tools {
            let declarations = geminiFunctionDeclarations(from: tools)
            if !declarations.isEmpty {
                body["tools"] = [["functionDeclarations": declarations]]
            }
        }

        var req = URLRequest(url: endpointURL)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(configuration.apiKey, forHTTPHeaderField: "x-goog-api-key")
        req.timeoutInterval = 60
        req.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])
        return req
    }

    private static func anthropicTools(from tools: [[String: Any]]) -> [[String: Any]] {
        tools.compactMap { tool in
            guard let function = tool["function"] as? [String: Any],
                  let name = function["name"] as? String else { return nil }
            var result: [String: Any] = [
                "name": name,
                "input_schema": function["parameters"] as? [String: Any] ?? ["type": "object"]
            ]
            if let description = function["description"] as? String {
                result["description"] = description
            }
            return result
        }
    }

    private static func geminiFunctionDeclarations(from tools: [[String: Any]]) -> [[String: Any]] {
        tools.compactMap { tool in
            guard let function = tool["function"] as? [String: Any],
                  function["name"] is String else { return nil }
            return function
        }
    }
}
