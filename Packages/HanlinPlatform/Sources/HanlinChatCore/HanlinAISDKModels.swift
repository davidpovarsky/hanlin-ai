import Foundation
import HanlinPlatformContracts

public enum HanlinAISDKProviderKind: String, Codable, Hashable, Sendable {
    case openAI
    case openAIResponses
    case anthropic
    case google
    case openAICompatible
    case appleOnDevice
}

public struct HanlinAISDKProviderDescriptor: Codable, Hashable, Sendable {
    public let kind: HanlinAISDKProviderKind
    public let modelID: String
    public let baseURL: URL
    public let headers: [String: String]
    public let queryParameters: [String: String]
    /// Only an adapter implementing this exact channel may advertise it. Cloud/native defaults are nil.
    public let structuredPartChannel: String?

    public init(
        kind: HanlinAISDKProviderKind,
        modelID: String,
        baseURL: URL,
        headers: [String: String] = [:],
        queryParameters: [String: String] = [:],
        structuredPartChannel: String? = nil
    ) {
        self.kind = kind
        self.modelID = modelID
        self.baseURL = baseURL
        self.headers = headers
        self.queryParameters = queryParameters
        self.structuredPartChannel = structuredPartChannel
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

public enum HanlinAISDKToolInputProvenance: Equatable, Sendable {
    /// Legacy/missing original JSON. Numeric leaves must fail closed in SDK consumers.
    case normalized
    /// Original accepted JSON, correlated and revalidated by the producer executor.
    /// This grants neither host authority nor consent.
    case acceptedOriginal
}

public struct HanlinAISDKToolDefinition: Sendable {
    public typealias Executor = @MainActor @Sendable (
        _ argumentsJSON: String,
        _ callID: String
    ) async throws -> HanlinAISDKToolExecutionOutput
    public typealias ProvenanceExecutor = @MainActor @Sendable (
        _ argumentsJSON: String,
        _ callID: String,
        _ provenance: HanlinAISDKToolInputProvenance
    ) async throws -> HanlinAISDKToolExecutionOutput

    public let name: String
    public let description: String
    public let inputSchemaData: Data
    public let execute: Executor
    public let executeWithInputProvenance: ProvenanceExecutor?
    /// Uses the original SDK approval protocol; host execution policy still applies.
    public let requiresApproval: Bool

    public init(
        name: String,
        description: String,
        inputSchemaData: Data,
        execute: @escaping Executor,
        executeWithInputProvenance: ProvenanceExecutor? = nil,
        requiresApproval: Bool = false
    ) {
        self.name = name
        self.description = description
        self.inputSchemaData = inputSchemaData
        self.execute = execute
        self.executeWithInputProvenance = executeWithInputProvenance
        self.requiresApproval = requiresApproval
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

/// One actual producer approval request. It carries no restored execution grant.
public struct HanlinAISDKToolApprovalRequest: Hashable, Sendable {
    public let approvalID: String
    public let toolCallID: String
    public let toolName: String
    public let argumentsJSON: String
    public let providerExecuted: Bool

    public init(approvalID: String, toolCallID: String, toolName: String,
                argumentsJSON: String, providerExecuted: Bool = false) {
        self.approvalID = approvalID; self.toolCallID = toolCallID
        self.toolName = toolName; self.argumentsJSON = argumentsJSON
        self.providerExecuted = providerExecuted
    }
}

/// Provider-owned annotation on one completed text part. OpenAI Responses
/// indexes are Unicode scalar offsets, as in the provider's Python slicing example.
/// This is transient stream metadata, not another conversation/source store.
public struct HanlinAISDKTextCitation: Sendable {
    public let textPartID: String
    public let text: String
    public let startIndex: Int
    public let endIndex: Int
    public let url: String
    public let title: String

    public init(textPartID: String, text: String, startIndex: Int, endIndex: Int, url: String, title: String) {
        self.textPartID = textPartID; self.text = text; self.startIndex = startIndex
        self.endIndex = endIndex; self.url = url; self.title = title
    }

    public var utf16Range: Range<Int>? {
        guard startIndex >= 0, endIndex > startIndex, endIndex <= text.unicodeScalars.count else { return nil }
        let start = text.unicodeScalars.index(text.unicodeScalars.startIndex, offsetBy: startIndex)
        let end = text.unicodeScalars.index(text.unicodeScalars.startIndex, offsetBy: endIndex)
        return start.utf16Offset(in: text)..<end.utf16Offset(in: text)
    }
}

public enum HanlinAISDKStreamEvent: Sendable {
    case runStarted
    /// Emitted only when this run actually requests the native schema response contract.
    case structuredResponseStarted(messageID: UUID, channel: String)
    case stepStarted(index: Int, preparation: HanlinAISDKStepPreparation)
    case textDelta(String)
    case structuredPart(HanlinChatStructuredPart)
    case reasoningDelta(String)
    case source(id: String, url: String, title: String?)
    case textCitations([HanlinAISDKTextCitation])
    case file(mediaType: String, data: Data)
    case toolCallArgumentsStarted(id: String, name: String)
    case toolCallArgumentsDelta(id: String, delta: String)
    case toolCall(HanlinAISDKToolCall)
    case toolResult(callID: String, name: String, modelText: String, resultReference: String?, isError: Bool)
    case toolApprovalRequest(HanlinAISDKToolApprovalRequest)
    case toolApprovalResolved(HanlinAISDKToolApprovalRequest, allowed: Bool)
    case toolOutputDenied(toolCallID: String, toolName: String)
    case stepFinished(index: Int, finishReason: String, usage: HanlinChatTokenUsage, meaningfulEventCount: Int)
    case finished(reason: String, usage: HanlinChatTokenUsage)
    case cancelled
}

public enum HanlinAISDKError: LocalizedError, Sendable {
    case nativeProviderInjectionRequired
    case nativeUnsupportedContent
    case invalidToolSchema(name: String)
    case invalidConversation(String)
    case emptyProviderResponse(attempts: Int)
    case incompleteProviderResponse(reason: String)

    public var errorDescription: String? {
        switch self {
        case .nativeProviderInjectionRequired:
            return "The on-device provider must be injected locally. No network provider was selected."
        case .nativeUnsupportedContent:
            return "This on-device provider accepts text messages only. No attachment was downloaded."
        case .invalidToolSchema(let name):
            return "Invalid JSON schema for tool '\(name)'."
        case .invalidConversation(let detail):
            return "Invalid SDK conversation: \(detail)"
        case .emptyProviderResponse(let attempts):
            return "The provider returned an empty successful response after \(attempts) attempt(s)."
        case .incompleteProviderResponse:
            return String(localized: "The model returned no visible answer. Please retry.")
        }
    }
}
