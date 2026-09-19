// HanlinChatRequestBuilder.swift
// HanlinChatCore
//
// Single authoritative remote model request builder for the Hanlin Chat Engine.
// Preserves production APIManager request structure and bounds max_tokens
// to eliminate HTTP 402 errors on OpenRouter and multi-provider endpoints.

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
        let apiType = (configuration.apiType ?? "OpenAI").lowercased()

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

        switch apiType {
        case "anthropic":
            return try buildAnthropicRequest(
                messages: messages,
                configuration: configuration,
                systemContent: combinedSystem
            )
        case "gemini":
            return try buildGeminiRequest(
                messages: messages,
                configuration: configuration,
                systemContent: combinedSystem
            )
        default:
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
            return try buildOpenAIRequest(
                formattedMessages: messagePayloads,
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
        let maxTokens = configuration.maxTokens > 0 ? configuration.maxTokens : 2048

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
        messages: [HanlinChatMessage],
        configuration: HanlinChatModelConfiguration,
        systemContent: String?
    ) throws -> URLRequest {
        var endpointURL = configuration.endpoint
        let urlStr = endpointURL.absoluteString
        if urlStr.hasSuffix("/chat/completions") {
            if let newURL = URL(string: urlStr.replacingOccurrences(of: "/chat/completions", with: "/messages")) {
                endpointURL = newURL
            }
        } else if !urlStr.contains("/messages") {
            let base = urlStr.hasSuffix("/") ? String(urlStr.dropLast()) : urlStr
            if let newURL = URL(string: "\(base)/v1/messages") {
                endpointURL = newURL
            }
        }

        var anthropicMessages: [[String: String]] = []
        for msg in messages {
            let role = (msg.role == "assistant" ? "assistant" : "user")
            anthropicMessages.append(["role": role, "content": msg.content])
        }
        if anthropicMessages.isEmpty {
            anthropicMessages.append(["role": "user", "content": "Hello"])
        }

        let baseName = configuration.baseModelID.isEmpty ? restoreBaseModelName(from: configuration.modelID) : configuration.baseModelID
        let maxTokens = configuration.maxTokens > 0 ? configuration.maxTokens : 4096

        var body: [String: Any] = [
            "model": baseName,
            "stream": true,
            "max_tokens": maxTokens,
            "messages": anthropicMessages
        ]
        if let systemContent, !systemContent.isEmpty {
            body["system"] = systemContent
        }
        if configuration.supportsReasoning {
            body["think"] = ["type": "enabled"]
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
        messages: [HanlinChatMessage],
        configuration: HanlinChatModelConfiguration,
        systemContent: String?
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

        var contents: [[String: Any]] = []
        for msg in messages {
            let role = (msg.role == "assistant" ? "model" : "user")
            contents.append([
                "role": role,
                "parts": [["text": msg.content]]
            ])
        }
        if contents.isEmpty {
            contents.append(["role": "user", "parts": [["text": "Hello"]]])
        }

        var body: [String: Any] = [
            "contents": contents
        ]
        if let systemContent, !systemContent.isEmpty {
            body["systemInstruction"] = ["parts": [["text": systemContent]]]
        }

        var genConfig: [String: Any] = [:]
        if configuration.maxTokens > 0 {
            genConfig["maxOutputTokens"] = configuration.maxTokens
        }
        if configuration.temperature > 0 {
            genConfig["temperature"] = configuration.temperature
        }
        if !genConfig.isEmpty {
            body["generationConfig"] = genConfig
        }

        var req = URLRequest(url: endpointURL)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(configuration.apiKey, forHTTPHeaderField: "x-goog-api-key")
        req.timeoutInterval = 60
        req.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])
        return req
    }
}
