import Foundation

public enum HanlinAISDKProviderKind: String, Codable, Hashable, Sendable {
    case openAI
    case anthropic
    case google
    case openAICompatible
}

public struct HanlinAISDKProviderDescriptor: Codable, Hashable, Sendable {
    public let kind: HanlinAISDKProviderKind
    public let modelID: String
    public let baseURL: URL
    public let headers: [String: String]
    public let queryParameters: [String: String]

    public init(
        kind: HanlinAISDKProviderKind,
        modelID: String,
        baseURL: URL,
        headers: [String: String] = [:],
        queryParameters: [String: String] = [:]
    ) {
        self.kind = kind
        self.modelID = modelID
        self.baseURL = baseURL
        self.headers = headers
        self.queryParameters = queryParameters
    }
}

public enum HanlinAISDKMessagePart: Hashable, Sendable {
    case text(String)
    case imageURL(URL, mediaType: String? = nil)
    case imageData(Data, mediaType: String? = nil)
}

public struct HanlinAISDKMessage: Hashable, Sendable {
    public enum Role: String, Hashable, Sendable {
        case system
        case user
        case assistant
    }

    public let role: Role
    public let parts: [HanlinAISDKMessagePart]

    public init(role: Role, text: String) {
        self.role = role
        self.parts = [.text(text)]
    }

    public init(role: Role, parts: [HanlinAISDKMessagePart]) {
        self.role = role
        self.parts = parts
    }
}

public struct HanlinAISDKToolExecutionOutput: Hashable, Sendable {
    public let modelText: String
    public let resultReference: String?
    public let isError: Bool

    public init(modelText: String, resultReference: String? = nil, isError: Bool = false) {
        self.modelText = modelText
        self.resultReference = resultReference
        self.isError = isError
    }
}

public struct HanlinAISDKToolDefinition: Sendable {
    public typealias Executor = @MainActor @Sendable (
        _ argumentsJSON: String,
        _ callID: String
    ) async throws -> HanlinAISDKToolExecutionOutput

    public let name: String
    public let description: String
    public let inputSchemaData: Data
    public let execute: Executor

    public init(
        name: String,
        description: String,
        inputSchemaData: Data,
        execute: @escaping Executor
    ) {
        self.name = name
        self.description = description
        self.inputSchemaData = inputSchemaData
        self.execute = execute
    }
}

public struct HanlinAISDKStepPreparation: Hashable, Sendable {
    public let activeToolAliases: [String]
    public let loadedSkillIDs: [String]
    public let loadedSkillInstructions: [String]
    public let visibleSchemaBytes: Int

    public init(
        activeToolAliases: [String],
        loadedSkillIDs: [String] = [],
        loadedSkillInstructions: [String] = [],
        visibleSchemaBytes: Int = 0
    ) {
        self.activeToolAliases = activeToolAliases
        self.loadedSkillIDs = loadedSkillIDs
        self.loadedSkillInstructions = loadedSkillInstructions
        self.visibleSchemaBytes = visibleSchemaBytes
    }
}

public struct HanlinAISDKToolCall: Hashable, Sendable {
    public let id: String
    public let name: String
    public let argumentsJSON: String

    public init(id: String, name: String, argumentsJSON: String) {
        self.id = id
        self.name = name
        self.argumentsJSON = argumentsJSON
    }
}

public enum HanlinAISDKStreamEvent: Sendable {
    case runStarted
    case stepStarted(index: Int, preparation: HanlinAISDKStepPreparation)
    case textDelta(String)
    case reasoningDelta(String)
    case toolCallArgumentsStarted(id: String, name: String)
    case toolCallArgumentsDelta(id: String, delta: String)
    case toolCall(HanlinAISDKToolCall)
    case toolResult(callID: String, name: String, modelText: String, resultReference: String?, isError: Bool)
    case stepFinished(index: Int, finishReason: String, usage: HanlinChatTokenUsage, meaningfulEventCount: Int)
    case finished(reason: String, usage: HanlinChatTokenUsage)
    case cancelled
}

public enum HanlinAISDKError: LocalizedError, Sendable {
    case invalidToolSchema(name: String)
    case invalidConversation(String)
    case emptyProviderResponse(attempts: Int)

    public var errorDescription: String? {
        switch self {
        case .invalidToolSchema(let name):
            return "Invalid JSON schema for tool '\(name)'."
        case .invalidConversation(let detail):
            return "Invalid SDK conversation: \(detail)"
        case .emptyProviderResponse(let attempts):
            return "The provider returned an empty successful response after \(attempts) attempt(s)."
        }
    }
}
