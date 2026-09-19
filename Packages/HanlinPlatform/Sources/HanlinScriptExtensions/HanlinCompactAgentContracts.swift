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
    public let updatedAt: Date

    public init(
        endpoint: URL,
        apiKey: String,
        modelID: String,
        company: String? = nil,
        displayName: String? = nil,
        systemPrompt: String? = nil,
        updatedAt: Date = .now
    ) {
        self.endpoint = endpoint
        self.apiKey = apiKey
        self.modelID = modelID
        self.company = company
        self.displayName = displayName
        self.systemPrompt = systemPrompt
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
            throw HanlinCompactAgentError.unconfigured
        }

        let (stream, continuation) = AsyncThrowingStream<String, Error>.makeStream()

        let task = Task.detached(priority: .userInitiated) { [config = activeConfig] in
            do {
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

                var requestBody: [String: Any] = [
                    "model": config.modelID,
                    "stream": true,
                    "messages": messagePayloads
                ]

                let jsonData = try JSONSerialization.data(withJSONObject: requestBody, options: [])
                var request = URLRequest(url: config.endpoint)
                request.httpMethod = "POST"
                request.httpBody = jsonData
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
                request.timeoutInterval = 60

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
                          let json = try? JSONSerialization.jsonObject(with: chunkData) as? [String: Any],
                          let choices = json["choices"] as? [[String: Any]],
                          let first = choices.first,
                          let delta = first["delta"] as? [String: Any],
                          let text = delta["content"] as? String else {
                        continue
                    }
                    if !text.isEmpty {
                        continuation.yield(text)
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
