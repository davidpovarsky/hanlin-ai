import Foundation

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
    public let modelID: String
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
