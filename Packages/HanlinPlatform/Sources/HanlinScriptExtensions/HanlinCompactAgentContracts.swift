// HanlinCompactAgentContracts.swift
// HanlinScriptExtensions
//
// Extension-safe agent configuration, persistence, and minimal streaming client.
// Designed to run in App Extensions (Translation UI Provider) without depending
// on SwiftData, UIKit, or main-app application layers.

import CryptoKit
import Foundation

// MARK: - Message Model

public struct HanlinCompactChatMessage: Codable, Hashable, Identifiable, Sendable {
    public let id: UUID
    public let role: String // "user", "assistant", "system"
    public var content: String
    public let timestamp: Date

    public init(
        id: UUID = UUID(),
        role: String,
        content: String,
        timestamp: Date = .now
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.timestamp = timestamp
    }
}

// MARK: - Configuration Model

public struct HanlinCompactAgentConfiguration: Codable, Hashable, Sendable {
    public let endpoint: URL
    public let apiKey: String
    public let modelID: String
    public let company: String?
    public let displayName: String?
    public let systemPrompt: String?
    public let apiType: String?
    public let updatedAt: Date

    public init(
        endpoint: URL,
        apiKey: String,
        modelID: String,
        company: String? = nil,
        displayName: String? = nil,
        systemPrompt: String? = nil,
        apiType: String? = "OpenAI",
        updatedAt: Date = .now
    ) {
        self.endpoint = endpoint
        self.apiKey = apiKey
        self.modelID = modelID
        self.company = company
        self.displayName = displayName
        self.systemPrompt = systemPrompt
        self.apiType = apiType
        self.updatedAt = updatedAt
    }
}

// MARK: - Configuration Store

public struct HanlinCompactAgentConfigStore: Sendable {
    public static let appGroupIdentifier = "group.com.itorah.chavrusachat"
    private let fileURL: URL

    public init(appGroupIdentifier: String = Self.appGroupIdentifier) throws {
        guard let container = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupIdentifier
        ) else {
            throw HanlinCompactAgentError.appGroupUnavailable
        }
        let dir = container.appending(path: "ScriptingExtensions", directoryHint: .isDirectory)
        fileURL = dir.appending(path: "compact-agent-config.json", directoryHint: .notDirectory)
    }

    public init(customURL: URL) {
        self.fileURL = customURL
    }

    public func save(_ config: HanlinCompactAgentConfiguration) throws {
        let dir = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(config)
        try data.write(to: fileURL, options: [.atomic, .completeFileProtection])
    }

    public func clear() throws {
        let path = fileURL.path(percentEncoded: false)
        if FileManager.default.fileExists(atPath: path) {
            try FileManager.default.removeItem(at: fileURL)
        }
    }

    public func load() throws -> HanlinCompactAgentConfiguration? {
        guard FileManager.default.fileExists(atPath: fileURL.path(percentEncoded: false)) else {
            return nil
        }
        let data = try Data(contentsOf: fileURL, options: .mappedIfSafe)
        guard !data.isEmpty else { return nil }
        let decoder = JSONDecoder()
        let config = try decoder.decode(HanlinCompactAgentConfiguration.self, from: data)
        guard !config.apiKey.isEmpty, !config.modelID.isEmpty else {
            return nil
        }
        return config
    }
}

// MARK: - Errors

public enum HanlinCompactAgentError: LocalizedError, Sendable {
    case appGroupUnavailable
    case notConfigured
    case invalidRequest
    case networkFailure(String)
    case serverError(statusCode: Int, message: String)
    case cancelled

    public static let unconfigured: HanlinCompactAgentError = .notConfigured

    public var errorDescription: String? {
        switch self {
        case .appGroupUnavailable:
            return "Shared App Group container is unavailable."
        case .notConfigured:
            return "No active AI model is configured. Please configure an API key in ChavrusaChat."
        case .invalidRequest:
            return "Unable to encode the chat request."
        case let .networkFailure(msg):
            return "Network connection failed: \(msg)"
        case let .serverError(code, msg):
            return "AI service returned HTTP \(code): \(msg)"
        case .cancelled:
            return "Request was cancelled."
        }
    }
}

// MARK: - Minimal Streaming Agent Client

public actor HanlinCompactAgentClient {
    private var config: HanlinCompactAgentConfiguration?

    public init(configuration: HanlinCompactAgentConfiguration? = nil) {
        self.config = configuration
    }

    public func stream(
        messages: [HanlinCompactChatMessage],
        systemContext: String? = nil
    ) throws -> AsyncThrowingStream<String, Error> {
        let activeConfig: HanlinCompactAgentConfiguration
        if let config = self.config {
            activeConfig = config
        } else if let loaded = try HanlinCompactAgentConfigStore().load() {
            activeConfig = loaded
            self.config = loaded
        } else {
            throw HanlinCompactAgentError.notConfigured
        }

        let (stream, continuation) = AsyncThrowingStream<String, Error>.makeStream()

        let task = Task.detached(priority: .userInitiated) { [config = activeConfig] in
            do {
                let apiType = (config.apiType ?? "OpenAI").lowercased()
                let request: URLRequest

                switch apiType {
                case "anthropic":
                    var endpointURL = config.endpoint
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

                    var req = URLRequest(url: endpointURL)
                    req.httpMethod = "POST"
                    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    req.setValue(config.apiKey, forHTTPHeaderField: "x-api-key")
                    req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
                    req.timeoutInterval = 60

                    var systemContent: String? = nil
                    if let systemPrompt = config.systemPrompt, !systemPrompt.isEmpty {
                        var fullSystem = systemPrompt
                        if let context = systemContext, !context.isEmpty {
                            fullSystem += "\n\nContext:\n\(context)"
                        }
                        systemContent = fullSystem
                    } else if let context = systemContext, !context.isEmpty {
                        systemContent = "Context:\n\(context)"
                    }

                    var anthropicMessages: [[String: String]] = []
                    for msg in messages {
                        let role = (msg.role == "assistant" ? "assistant" : "user")
                        anthropicMessages.append(["role": role, "content": msg.content])
                    }
                    if anthropicMessages.isEmpty {
                        anthropicMessages.append(["role": "user", "content": "Hello"])
                    }

                    var body: [String: Any] = [
                        "model": config.modelID,
                        "stream": true,
                        "max_tokens": 4096,
                        "messages": anthropicMessages
                    ]
                    if let systemContent = systemContent, !systemContent.isEmpty {
                        body["system"] = systemContent
                    }
                    req.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])
                    request = req

                case "gemini":
                    var endpointURL = config.endpoint
                    let urlStr = endpointURL.absoluteString
                    if urlStr.contains(":streamGenerateContent") {
                        var components = URLComponents(url: endpointURL, resolvingAgainstBaseURL: false)
                        var items = components?.queryItems ?? []
                        if !items.contains(where: { $0.name == "alt" }) {
                            items.append(URLQueryItem(name: "alt", value: "sse"))
                        }
                        if !items.contains(where: { $0.name == "key" }) {
                            items.append(URLQueryItem(name: "key", value: config.apiKey))
                        }
                        components?.queryItems = items
                        if let u = components?.url { endpointURL = u }
                    } else {
                        let scheme = endpointURL.scheme ?? "https"
                        let host = endpointURL.host ?? "generativelanguage.googleapis.com"
                        let urlString = "\(scheme)://\(host)/v1beta/models/\(config.modelID):streamGenerateContent?alt=sse&key=\(config.apiKey)"
                        if let u = URL(string: urlString) { endpointURL = u }
                    }

                    var req = URLRequest(url: endpointURL)
                    req.httpMethod = "POST"
                    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    req.timeoutInterval = 60

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
                    if let systemPrompt = config.systemPrompt, !systemPrompt.isEmpty {
                        var fullSystem = systemPrompt
                        if let context = systemContext, !context.isEmpty {
                            fullSystem += "\n\nContext:\n\(context)"
                        }
                        body["systemInstruction"] = ["parts": [["text": fullSystem]]]
                    } else if let context = systemContext, !context.isEmpty {
                        body["systemInstruction"] = ["parts": [["text": "Context:\n\(context)"]]]
                    }
                    req.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])
                    request = req

                default: // OpenAI, OpenAI-Response, and default
                    var messagePayloads: [[String: String]] = []
                    if let systemPrompt = config.systemPrompt, !systemPrompt.isEmpty {
                        var fullSystem = systemPrompt
                        if let context = systemContext, !context.isEmpty {
                            fullSystem += "\n\nContext:\n\(context)"
                        }
                        messagePayloads.append(["role": "system", "content": fullSystem])
                    } else if let context = systemContext, !context.isEmpty {
                        messagePayloads.append(["role": "system", "content": "Context:\n\(context)"])
                    }

                    for msg in messages {
                        messagePayloads.append(["role": msg.role, "content": msg.content])
                    }

                    let body: [String: Any] = [
                        "model": config.modelID,
                        "stream": true,
                        "messages": messagePayloads
                    ]

                    var req = URLRequest(url: config.endpoint)
                    req.httpMethod = "POST"
                    req.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])
                    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    req.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
                    req.timeoutInterval = 60
                    request = req
                }

                let session = URLSession(configuration: .ephemeral)
                defer { session.finishTasksAndInvalidate() }

                let (bytes, response) = try await session.bytes(for: request)
                guard let httpResponse = response as? HTTPURLResponse else {
                    continuation.finish(throwing: HanlinCompactAgentError.networkFailure("Invalid response"))
                    return
                }

                guard (200...299).contains(httpResponse.statusCode) else {
                    var errorDetail = ""
                    for try await line in bytes.lines {
                        errorDetail += line
                        if errorDetail.count > 1024 { break }
                    }
                    continuation.finish(throwing: HanlinCompactAgentError.serverError(
                        statusCode: httpResponse.statusCode,
                        message: errorDetail.isEmpty ? "Request rejected" : errorDetail
                    ))
                    return
                }

                for try await line in bytes.lines {
                    try Task.checkCancellation()
                    guard line.hasPrefix("data:") else { continue }
                    let dataText = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                    if dataText == "[DONE]" { break }

                    guard let chunkData = dataText.data(using: .utf8),
                          let json = try? JSONSerialization.jsonObject(with: chunkData) as? [String: Any] else {
                        continue
                    }

                    switch apiType {
                    case "anthropic":
                        if let type = json["type"] as? String, type == "message_stop" {
                            continuation.finish()
                            return
                        }
                        if let delta = json["delta"] as? [String: Any],
                           let text = delta["text"] as? String,
                           !text.isEmpty {
                            continuation.yield(text)
                        }

                    case "gemini":
                        if let candidates = json["candidates"] as? [[String: Any]],
                           let firstCandidate = candidates.first,
                           let content = firstCandidate["content"] as? [String: Any],
                           let parts = content["parts"] as? [[String: Any]],
                           let firstPart = parts.first,
                           let text = firstPart["text"] as? String,
                           !text.isEmpty {
                            continuation.yield(text)
                        }

                    default: // OpenAI
                        if let choices = json["choices"] as? [[String: Any]],
                           let first = choices.first,
                           let delta = first["delta"] as? [String: Any],
                           let text = delta["content"] as? String,
                           !text.isEmpty {
                            continuation.yield(text)
                        }
                    }
                }
                continuation.finish()
            } catch is CancellationError {
                continuation.finish(throwing: HanlinCompactAgentError.cancelled)
            } catch {
                continuation.finish(throwing: error)
            }
        }

        continuation.onTermination = { @Sendable _ in task.cancel() }
        return stream
    }
}
