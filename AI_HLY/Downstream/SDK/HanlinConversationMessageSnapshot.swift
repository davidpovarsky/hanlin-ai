import Foundation
import HanlinChatCore
import HanlinPlatformContracts

/// Immutable projection of an original SwiftData message. Rich payloads keep
/// their original types and serialized forms; no alternate renderer schema is
/// introduced by the headless API.
public struct HanlinConversationMessageSnapshot: Identifiable, Sendable {
    public let id: UUID
    public let role: String
    public let text: String
    public let reasoning: String
    public let reasoningTime: String?
    public let toolContent: String?
    public let toolName: String?
    public let resources: [Resource]
    public let searchEngine: String?
    /// The original JSON-encoded [Data] image representation.
    public let imageData: Data?
    public let documents: [URL]
    public let documentText: String?
    public let prompts: [PromptCard]
    public let capabilityAttachments: [HanlinCapabilityAttachment]
    public let locations: [Location]
    public let routes: [RouteInfo]
    public let events: [EventItem]
    public let html: String?
    public let health: [HealthData]
    public let code: [CodeBlock]
    public let knowledge: [KnowledgeCard]
    public let audio: [AudioAsset]
    public let canvas: CanvasData?
    public let nativeUIBlocksJSON: String?
    public let agentRunJSON: String?
    public let presentationSnapshot: Data?
    public let modelName: String?
    public let modelDisplayName: String?
    public let groupID: UUID
    public let timestamp: Date
    public let finishReason: String?

    /// Creates a presentation snapshot from host-owned state without creating
    /// a conversation, starting a run or granting tool/consent authority. Retain
    /// the actual message identity across streaming updates. Opaque rich fields
    /// keep their original Hanlin encodings; this initializer does not invent an
    /// alternate AgentRun or native-UI schema.
    public init(
        id: UUID, role: String = "assistant", text: String = "",
        reasoning: String = "", reasoningTime: String? = nil,
        toolContent: String? = nil, toolName: String? = nil,
        resources: [Resource] = [], searchEngine: String? = nil,
        imageData: Data? = nil, documents: [URL] = [], documentText: String? = nil,
        prompts: [PromptCard] = [], locations: [Location] = [], routes: [RouteInfo] = [],
        events: [EventItem] = [], html: String? = nil, health: [HealthData] = [],
        code: [CodeBlock] = [], knowledge: [KnowledgeCard] = [], audio: [AudioAsset] = [],
        canvas: CanvasData? = nil, nativeUIBlocksJSON: String? = nil,
        agentRunJSON: String? = nil, presentationSnapshot: Data? = nil,
        modelName: String? = nil, modelDisplayName: String? = nil,
        groupID: UUID? = nil, timestamp: Date = Date(), finishReason: String? = nil,
        capabilityAttachments: [HanlinCapabilityAttachment] = []
    ) {
        self.id = id; self.role = role; self.text = text
        self.reasoning = reasoning; self.reasoningTime = reasoningTime
        self.toolContent = toolContent; self.toolName = toolName
        self.resources = resources; self.searchEngine = searchEngine
        self.imageData = imageData; self.documents = documents; self.documentText = documentText
        self.prompts = prompts; self.locations = locations; self.routes = routes
        self.capabilityAttachments = capabilityAttachments
        self.events = events; self.html = html; self.health = health
        self.code = code; self.knowledge = knowledge; self.audio = audio
        self.canvas = canvas; self.nativeUIBlocksJSON = nativeUIBlocksJSON
        self.agentRunJSON = agentRunJSON; self.presentationSnapshot = presentationSnapshot
        self.modelName = modelName; self.modelDisplayName = modelDisplayName
        self.groupID = groupID ?? id; self.timestamp = timestamp; self.finishReason = finishReason
    }

    @MainActor
    init(_ row: ChatMessages) {
        id = row.id
        role = row.role ?? "system"
        text = row.text ?? ""
        reasoning = row.reasoning ?? ""
        reasoningTime = row.reasoningTime
        toolContent = row.toolContent
        toolName = row.toolName
        resources = row.resources ?? []
        searchEngine = row.searchEngine
        imageData = row.images
        documents = row.documentURLs ?? []
        documentText = row.document_text
        prompts = row.promptUse ?? []
        capabilityAttachments = row.capabilityAttachments
        locations = row.locationsInfo ?? []
        routes = row.routeInfos ?? []
        events = row.events ?? []
        html = row.htmlContent
        health = row.healthData ?? []
        code = row.codeBlockData ?? []
        knowledge = row.knowledgeCard ?? []
        audio = row.audioAssets ?? []
        canvas = row.showCanvas == true ? row.record?.canvas : nil
        nativeUIBlocksJSON = row.nativeUIBlocksJSON
        agentRunJSON = row.agentRunJSON
        presentationSnapshot = row.presentationSnapshotData
        modelName = row.modelName
        modelDisplayName = row.modelDisplayName
        groupID = row.groupID
        timestamp = row.timestamp
        finishReason = row.modelFinishReason
    }

    public func decodedImageData() throws -> [Data] {
        try imageData.map { try JSONDecoder().decode([Data].self, from: $0) } ?? []
    }
}

public struct HanlinApplicationModel: Identifiable, Sendable {
    public let id: UUID
    /// Original stored routing name, including its provider/agent suffix.
    public let modelID: String
    /// Provider wire identifier resolved by the same helper as the engine.
    public var baseModelID: String { restoreBaseModelName(from: modelID) }
    public let identity: String
    public let position: Int?
    public let isBuiltIn: Bool
    public let capabilities: HanlinApplicationModelCapabilities
    public let displayName: String
    public let provider: String
    public let isHidden: Bool
    public let supportsTools: Bool
    public let supportsSearch: Bool
    public let supportsReasoning: Bool
    public let supportsText: Bool
    public let supportsImageInput: Bool
    public let supportsImageGeneration: Bool
    public let supportsVoice: Bool

    @MainActor
    init(_ model: AllModels) {
        id = model.id
        modelID = model.name ?? ""
        identity = model.identity ?? "model"
        position = model.position
        isBuiltIn = model.systemProvision
        capabilities = .init(model)
        displayName = model.presentationName
        provider = model.company ?? ""
        isHidden = model.isHidden
        supportsTools = model.supportsToolUse
        supportsSearch = model.supportsSearch
        supportsReasoning = model.supportsReasoning
        supportsText = model.supportsTextGen
        supportsImageInput = model.supportsMultimodal
        supportsImageGeneration = model.supportsImageGen
        supportsVoice = model.supportsVoiceGen
    }
}
