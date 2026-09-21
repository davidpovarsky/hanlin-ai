// HanlinChatModelConfiguration.swift
// HanlinChatCore
//
// Extension-safe immutable model configuration for the shared Hanlin chat engine.

import Foundation

public enum HanlinChatGenerationDefaults {
    public static let temperature: Double = -999
    public static let topP: Double = -999
    public static let maxTokens: Int = 2048
    public static let thinkingLength: Int = 0
}

public func restoreBaseModelName(from agentModelName: String) -> String {
    guard let baseName = agentModelName.components(separatedBy: "_agent_").first else {
        return agentModelName
    }
    guard let repeatStripped = baseName.components(separatedBy: "_repeat_").first else {
        return baseName
    }
    if repeatStripped.hasSuffix("_hanlin") {
        return String(repeatStripped.dropLast("_hanlin".count))
    } else {
        return repeatStripped
    }
}

public struct HanlinChatTokenUsage: Codable, Hashable, Sendable {
    public let inputTokens: Int?
    public let outputTokens: Int?
    public let reasoningTokens: Int?
    public let cachedInputTokens: Int?
    public let totalTokens: Int?

    public var promptTokens: Int? { inputTokens }
    public var completionTokens: Int? { outputTokens }

    public init(
        inputTokens: Int? = nil,
        outputTokens: Int? = nil,
        reasoningTokens: Int? = nil,
        cachedInputTokens: Int? = nil,
        totalTokens: Int? = nil
    ) {
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.reasoningTokens = reasoningTokens
        self.cachedInputTokens = cachedInputTokens
        self.totalTokens = totalTokens
    }

    public init(
        promptTokens: Int? = nil,
        completionTokens: Int? = nil,
        reasoningTokens: Int? = nil,
        cachedInputTokens: Int? = nil,
        totalTokens: Int? = nil
    ) {
        self.inputTokens = promptTokens
        self.outputTokens = completionTokens
        self.reasoningTokens = reasoningTokens
        self.cachedInputTokens = cachedInputTokens
        self.totalTokens = totalTokens
    }
}

public struct HanlinChatModelConfiguration: Codable, Hashable, Sendable {
    public let modelID: String
    public let baseModelID: String
    public let displayName: String?
    public let company: String?
    public let apiType: String?
    public let endpoint: URL
    public let apiKey: String
    public let temperature: Double
    public let topP: Double
    public let maxTokens: Int
    public let supportsReasoning: Bool
    public let supportReasoningChange: Bool
    public let thinkingLength: Int
    public let reasoningEffort: String?
    public let supportsToolUse: Bool
    public let supportsTextGen: Bool
    public let systemPrompt: String?
    public let updatedAt: Date

    public init(
        modelID: String,
        baseModelID: String? = nil,
        displayName: String? = nil,
        company: String? = nil,
        apiType: String? = "OpenAI",
        endpoint: URL,
        apiKey: String,
        temperature: Double = HanlinChatGenerationDefaults.temperature,
        topP: Double = HanlinChatGenerationDefaults.topP,
        maxTokens: Int? = HanlinChatGenerationDefaults.maxTokens,
        supportsReasoning: Bool = false,
        supportReasoningChange: Bool = false,
        thinkingLength: Int = HanlinChatGenerationDefaults.thinkingLength,
        reasoningEffort: String? = nil,
        supportsToolUse: Bool = false,
        supportsTextGen: Bool = true,
        systemPrompt: String? = nil,
        updatedAt: Date = .now
    ) {
        self.modelID = modelID
        self.baseModelID = baseModelID ?? restoreBaseModelName(from: modelID)
        self.displayName = displayName ?? modelID
        self.company = company
        self.apiType = apiType
        self.endpoint = endpoint
        self.apiKey = apiKey
        self.temperature = temperature
        self.topP = topP
        let rawTokens = maxTokens ?? HanlinChatGenerationDefaults.maxTokens
        self.maxTokens = rawTokens > 0 ? rawTokens : HanlinChatGenerationDefaults.maxTokens
        self.supportsReasoning = supportsReasoning
        self.supportReasoningChange = supportReasoningChange
        self.thinkingLength = thinkingLength
        self.reasoningEffort = reasoningEffort
        self.supportsToolUse = supportsToolUse
        self.supportsTextGen = supportsTextGen
        self.systemPrompt = systemPrompt
        self.updatedAt = updatedAt
    }

    public init(
        modelID: String,
        baseModelID: String? = nil,
        displayName: String? = nil,
        company: String? = nil,
        apiType: String? = "OpenAI",
        endpoint: String,
        apiKey: String? = nil,
        credential: String? = nil,
        temperature: Double = HanlinChatGenerationDefaults.temperature,
        topP: Double = HanlinChatGenerationDefaults.topP,
        maxTokens: Int? = HanlinChatGenerationDefaults.maxTokens,
        supportsReasoning: Bool = false,
        supportReasoningChange: Bool = false,
        thinkingLength: Int = HanlinChatGenerationDefaults.thinkingLength,
        reasoningEffort: String? = nil,
        supportsToolUse: Bool = false,
        supportsTextGen: Bool = true,
        systemPrompt: String? = nil,
        updatedAt: Date = .now
    ) {
        let key = apiKey ?? credential ?? ""
        let url = URL(string: endpoint) ?? URL(string: "https://openrouter.ai/api/v1")!
        self.init(
            modelID: modelID,
            baseModelID: baseModelID,
            displayName: displayName,
            company: company,
            apiType: apiType,
            endpoint: url,
            apiKey: key,
            temperature: temperature,
            topP: topP,
            maxTokens: maxTokens,
            supportsReasoning: supportsReasoning,
            supportReasoningChange: supportReasoningChange,
            thinkingLength: thinkingLength,
            reasoningEffort: reasoningEffort,
            supportsToolUse: supportsToolUse,
            supportsTextGen: supportsTextGen,
            systemPrompt: systemPrompt,
            updatedAt: updatedAt
        )
    }
}

public enum HanlinChatError: LocalizedError, Sendable {
    case appGroupUnavailable
    case notConfigured
    case invalidRequest(String)
    case networkFailure(String)
    case serverError(statusCode: Int, message: String)
    case cancelled

    public var errorDescription: String? {
        switch self {
        case .appGroupUnavailable:
            return "Shared App Group container is unavailable."
        case .notConfigured:
            return "No active AI model is configured. Please configure an API key in ChavrusaChat."
        case let .invalidRequest(msg):
            return "Invalid chat request: \(msg)"
        case let .networkFailure(msg):
            return "Network connection failed: \(msg)"
        case let .serverError(code, msg):
            return "AI service returned HTTP \(code): \(msg)"
        case .cancelled:
            return "Request was cancelled."
        }
    }
}
