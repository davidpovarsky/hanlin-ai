// HanlinCompactAgentContracts.swift
// HanlinScriptExtensions
//
// Extension-safe agent configuration, persistence, and compact streaming client.
// Reuses the shared HanlinChatCore production engine for model execution.

import CryptoKit
import Foundation
@_exported import HanlinChatCore

// MARK: - Message Model Typealias

public typealias HanlinCompactChatMessage = HanlinChatMessage

// MARK: - Configuration Model

public struct HanlinCompactAgentConfiguration: Codable, Hashable, Sendable {
    public let endpoint: URL
    public let apiKey: String
    public let modelID: String
    public let company: String?
    public let displayName: String?
    public let systemPrompt: String?
    public let apiType: String?
    public let temperature: Double
    public let topP: Double
    public let maxTokens: Int
    public let supportsReasoning: Bool
    public let supportReasoningChange: Bool
    public let thinkingLength: Int
    public let supportsToolUse: Bool
    public let updatedAt: Date

    public init(
        endpoint: URL,
        apiKey: String,
        modelID: String,
        company: String? = nil,
        displayName: String? = nil,
        systemPrompt: String? = nil,
        apiType: String? = "OpenAI",
        temperature: Double = HanlinChatGenerationDefaults.temperature,
        topP: Double = HanlinChatGenerationDefaults.topP,
        maxTokens: Int = HanlinChatGenerationDefaults.maxTokens,
        supportsReasoning: Bool = false,
        supportReasoningChange: Bool = false,
        thinkingLength: Int = HanlinChatGenerationDefaults.thinkingLength,
        supportsToolUse: Bool = false,
        updatedAt: Date = .now
    ) {
        self.endpoint = endpoint
        self.apiKey = apiKey
        self.modelID = modelID
        self.company = company
        self.displayName = displayName
        self.systemPrompt = systemPrompt
        self.apiType = apiType
        self.temperature = temperature
        self.topP = topP
        self.maxTokens = maxTokens > 0 ? maxTokens : HanlinChatGenerationDefaults.maxTokens
        self.supportsReasoning = supportsReasoning
        self.supportReasoningChange = supportReasoningChange
        self.thinkingLength = thinkingLength
        self.supportsToolUse = supportsToolUse
        self.updatedAt = updatedAt
    }

    public var chatModelConfiguration: HanlinChatModelConfiguration {
        HanlinChatModelConfiguration(
            modelID: modelID,
            displayName: displayName,
            company: company,
            apiType: apiType,
            endpoint: endpoint,
            apiKey: apiKey,
            temperature: temperature,
            topP: topP,
            maxTokens: maxTokens,
            supportsReasoning: supportsReasoning,
            supportReasoningChange: supportReasoningChange,
            thinkingLength: thinkingLength,
            supportsToolUse: supportsToolUse,
            systemPrompt: systemPrompt,
            updatedAt: updatedAt
        )
    }

    private enum CodingKeys: String, CodingKey {
        case endpoint, apiKey, modelID, company, displayName, systemPrompt, apiType
        case temperature, topP, maxTokens, supportsReasoning, supportReasoningChange
        case thinkingLength, supportsToolUse, updatedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        endpoint = try container.decode(URL.self, forKey: .endpoint)
        apiKey = try container.decode(String.self, forKey: .apiKey)
        modelID = try container.decode(String.self, forKey: .modelID)
        company = try container.decodeIfPresent(String.self, forKey: .company)
        displayName = try container.decodeIfPresent(String.self, forKey: .displayName)
        systemPrompt = try container.decodeIfPresent(String.self, forKey: .systemPrompt)
        apiType = try container.decodeIfPresent(String.self, forKey: .apiType)
        temperature = try container.decodeIfPresent(Double.self, forKey: .temperature) ?? HanlinChatGenerationDefaults.temperature
        topP = try container.decodeIfPresent(Double.self, forKey: .topP) ?? HanlinChatGenerationDefaults.topP
        let decodedMaxTokens = try container.decodeIfPresent(Int.self, forKey: .maxTokens)
            ?? HanlinChatGenerationDefaults.maxTokens
        maxTokens = decodedMaxTokens > 0 ? decodedMaxTokens : HanlinChatGenerationDefaults.maxTokens
        supportsReasoning = try container.decodeIfPresent(Bool.self, forKey: .supportsReasoning) ?? false
        supportReasoningChange = try container.decodeIfPresent(Bool.self, forKey: .supportReasoningChange) ?? false
        thinkingLength = try container.decodeIfPresent(Int.self, forKey: .thinkingLength) ?? 0
        supportsToolUse = try container.decodeIfPresent(Bool.self, forKey: .supportsToolUse) ?? false
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? .now
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

// MARK: - Compact Streaming Agent Client (Facade over HanlinChatEngine)

public actor HanlinCompactAgentClient {
    private var config: HanlinCompactAgentConfiguration?
    private let engine = HanlinChatEngine()

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

        let chatConfig = activeConfig.chatModelConfiguration
        let (textStream, continuation) = AsyncThrowingStream<String, Error>.makeStream()

        let task = Task.detached(priority: .userInitiated) { [engine] in
            do {
                let stream = try await engine.stream(
                    messages: messages,
                    configuration: chatConfig,
                    systemContext: systemContext,
                    tools: nil
                )
                for try await event in stream {
                    if let content = event.content, !content.isEmpty {
                        continuation.yield(content)
                    }
                }
                continuation.finish()
            } catch is CancellationError {
                continuation.finish(throwing: HanlinCompactAgentError.cancelled)
            } catch let err as HanlinChatError {
                switch err {
                case .notConfigured:
                    continuation.finish(throwing: HanlinCompactAgentError.notConfigured)
                case .cancelled:
                    continuation.finish(throwing: HanlinCompactAgentError.cancelled)
                case let .serverError(code, msg):
                    continuation.finish(throwing: HanlinCompactAgentError.serverError(statusCode: code, message: msg))
                case let .networkFailure(msg):
                    continuation.finish(throwing: HanlinCompactAgentError.networkFailure(msg))
                default:
                    continuation.finish(throwing: err)
                }
            } catch {
                continuation.finish(throwing: error)
            }
        }

        continuation.onTermination = { @Sendable _ in
            task.cancel()
        }

        return textStream
    }
}
