import Foundation
import HanlinAgentCore
import HanlinHostContracts
import HanlinPlatformContracts
import Observation
import SwiftData
import UIKit

public struct HanlinConversationRequest: Sendable {
    public var text: String
    public var modelRecordID: UUID?
    public var images: [Data]
    public var documents: [URL]
    public var urls: [URL]
    public var prompts: [PromptCard]
    public var capabilityAttachments: [HanlinCapabilityAttachment]
    public var search: Bool
    public var knowledge: Bool
    public var tools: Bool
    public var reasoning: Bool
    public var audio: Bool
    public var planning: Bool
    public var thinkingLength: Int
    public var temperature: Double?
    public var topP: Double?
    public var maxTokens: Int?
    public var historyLimit: Int?
    public var systemMessage: String?
    public var imageSize: String
    public var imageReversePrompt: String
    public var observation: Bool
    /// An original admitted host action. Session validation is unchanged.
    public var interaction: HanlinHostInteractionRequest?

    public init(text: String, modelRecordID: UUID? = nil, images: [Data] = [],
                documents: [URL] = [], urls: [URL] = [], prompts: [PromptCard] = [],
                search: Bool = false, knowledge: Bool = false, tools: Bool = true,
                reasoning: Bool = false, audio: Bool = false, planning: Bool = false,
                thinkingLength: Int = 0, temperature: Double? = nil, topP: Double? = nil,
                maxTokens: Int? = nil, historyLimit: Int? = nil, systemMessage: String? = nil,
                imageSize: String = "square", imageReversePrompt: String = "",
                observation: Bool = false, interaction: HanlinHostInteractionRequest? = nil,
                capabilityAttachments: [HanlinCapabilityAttachment] = []) {
        self.text = text
        self.modelRecordID = modelRecordID
        self.images = images
        self.documents = documents
        self.urls = urls
        self.prompts = prompts
        self.capabilityAttachments = capabilityAttachments
        self.search = search
        self.knowledge = knowledge
        self.tools = tools
        self.reasoning = reasoning
        self.audio = audio
        self.planning = planning
        self.thinkingLength = thinkingLength
        self.temperature = temperature
        self.topP = topP
        self.maxTokens = maxTokens
        self.historyLimit = historyLimit
        self.systemMessage = systemMessage
        self.imageSize = imageSize
        self.imageReversePrompt = imageReversePrompt
        self.observation = observation
        self.interaction = interaction
    }
}

public struct HanlinConversationApproval: Identifiable, Sendable {
    public let id: UUID
    public let toolName: String
    public let reviewText: String
    public let remembersDecision: Bool

    @MainActor
    init(_ request: HanlinAppToolConsent.Request) {
        id = request.id
        toolName = request.tool
        reviewText = AgentDiagnosticsRedactor.sanitize(
            request.originalArgumentsJSON.map { String(decoding: $0, as: UTF8.self) } ?? "{}")
        remembersDecision = request.remembersDecision
    }
}

public enum HanlinConversationControllerState: Equatable, Sendable {
    case idle, preparing, streaming, completed, cancelled
    case failed(String)
}

public enum HanlinConversationUpdate: Sendable {
    case state(HanlinConversationControllerState)
    case message(HanlinConversationMessageSnapshot)
    case agentEvent(HanlinAgentEvent)
    case approval(HanlinConversationApproval?)
}

public enum HanlinConversationControllerError: LocalizedError {
    case invalidImage, unavailableModel, emptyResponse

    public var errorDescription: String? {
        switch self {
        case .invalidImage: "An attached image could not be decoded."
        case .unavailableModel: "The selected original model is unavailable in this application context."
        case .emptyResponse: "The model returned no visible content."
        }
    }
}

/// Runs the original APIManager and HanlinAppAgentSessionOwner without mounting
/// any SwiftUI view. Its stream projection is the same implementation ChatView
/// uses, including tools, MCP, skills, reasoning, sources and rich message data.
@MainActor @Observable
public final class HanlinConversationController {
    public let conversationID: UUID
    public private(set) var state: HanlinConversationControllerState = .idle
    public private(set) var messages: [HanlinConversationMessageSnapshot] = []
    public private(set) var pendingApproval: HanlinConversationApproval?
    public private(set) var operationalState = ""
    public private(set) var operationalDescription = ""
    public var isRunning: Bool { state == .preparing || state == .streaming }

    @ObservationIgnored let application: HanlinApplicationContext
    @ObservationIgnored let sessionOwner = HanlinAppAgentSessionOwner()
    @ObservationIgnored private let sceneID = UUID()
    @ObservationIgnored private let richPresentation = HanlinAppRichPresentation()
    #if HANLIN_A2UI_POC
    @ObservationIgnored let nativePresentation = HanlinA2UIAppPresentation()
    #endif
    @ObservationIgnored private var conversationWasDeleted = false
    @ObservationIgnored private var activeToken: UUID?
    @ObservationIgnored private var activeLease: HanlinConversationRunLease?
    @ObservationIgnored private var activeTask: Task<Void, Never>?
    @ObservationIgnored private var continuation: AsyncThrowingStream<HanlinConversationUpdate, Error>.Continuation?
    @ObservationIgnored private var apiManager: APIManager?
    @ObservationIgnored var projection: HanlinConversationStreamProjection?

    init(application: HanlinApplicationContext, conversationID: UUID) throws {
        self.application = application
        self.conversationID = conversationID
        let record = try application.record(conversationID)
        messages = (record.messages ?? []).sorted { $0.timestamp < $1.timestamp }
            .map(HanlinConversationMessageSnapshot.init)
        #if HANLIN_A2UI_POC
        sessionOwner.presentation = nativePresentation
        #endif
        sessionOwner.onAgentEvent = { [weak self] event in
            self?.continuation?.yield(.agentEvent(event))
        }
        sessionOwner.onApprovalEvent = { [weak self] rowID, approval in
            guard let self, let projection, activeToken != nil,
                  rowID == projection.groupBeginMessage.id else { return }
            projection.agentCoordinator.consume([.toolApprovalChanged(approval)])
            projection.groupBeginMessage.agentRun = projection.agentCoordinator.run
            pendingApproval = approval.disposition == .awaiting || approval.disposition == .providerRequired
                ? sessionOwner.consent.pending.map(HanlinConversationApproval.init) : nil
            continuation?.yield(.approval(pendingApproval))
            publish(projection)
        }
    }

    /// Consume the returned stream. Cancellation of that consumer stops only
    /// this admitted run; late work cannot cancel a later send.
    public func send(_ request: HanlinConversationRequest) throws
        -> AsyncThrowingStream<HanlinConversationUpdate, Error> {
        guard !conversationWasDeleted else { throw HanlinApplicationError.conversationNotFound(conversationID) }
        guard activeToken == nil else { throw HanlinHostError.duplicateInvocation }
        _ = try application.record(conversationID)
        activeLease = try .acquire(container: application.modelContainer, conversationID: conversationID)
        let token = UUID()
        activeToken = token
        activeLease?.onRevoke { [weak self] in self?.stop(ifCurrent: token) }
        state = .preparing
        return AsyncThrowingStream { continuation in
            self.continuation = continuation
            continuation.yield(.state(.preparing))
            continuation.onTermination = { [weak self] termination in
                if case .cancelled = termination {
                    Task { @MainActor in self?.stop(ifCurrent: token) }
                }
            }
            activeTask = Task { [self] in
                await perform(request, token: token, continuation: continuation)
            }
        }
    }

    public func stop() {
        guard let token = activeToken else { return }
        stop(ifCurrent: token)
    }

    /// Answers the original pending consent, preserving remembered-vs-once
    /// semantics and its original deadline/current-session checks.
    public func answerApproval(id: UUID, allowed: Bool) throws {
        guard activeToken != nil, sessionOwner.consent.pending?.id == id else {
            throw HanlinHostError.staleContext
        }
        sessionOwner.consent.answer(id: id, allowed: allowed)
    }

    public func refreshHistory() throws {
        guard !conversationWasDeleted else { throw HanlinApplicationError.conversationNotFound(conversationID) }
        guard activeToken == nil else { throw HanlinHostError.duplicateInvocation }
        let record = try application.record(conversationID)
        messages = (record.messages ?? []).sorted { $0.timestamp < $1.timestamp }
            .map(HanlinConversationMessageSnapshot.init)
    }

    func conversationDidChange(_ change: HanlinConversationMutation.Change) {
        switch change.kind {
        case .deleted:
            stop()
            conversationWasDeleted = true
            messages = []
            pendingApproval = nil
        case .historyCleared:
            // The writer already revoked the old turn synchronously.
            try? refreshHistory()
        case .metadata:
            guard let messageID = change.messageID,
                  let row = try? application.record(conversationID),
                  let announcement = row.messages?.first(where: { $0.id == messageID }) else { return }
            if let projection {
                if !projection.messages.contains(where: { $0.id == messageID }) {
                    projection.messages.append(announcement)
                }
                publish(projection)
            } else { try? refreshHistory() }
        }
    }

    private func stop(ifCurrent token: UUID) {
        guard activeToken == token else { return }
        activeToken = nil
        activeLease?.release()
        activeLease = nil
        sessionOwner.cancel()
        let manager = apiManager
        manager?.cancelCurrentRequest()
        activeTask?.cancel()
        if let projection {
            projection.cancel()
            synchronizePresentation(projection)
            publish(projection)
        }
        pendingApproval = nil
        state = .cancelled
        continuation?.yield(.approval(nil))
        continuation?.yield(.state(.cancelled))
        continuation?.finish(throwing: CancellationError())
        continuation = nil
        activeTask = nil
        apiManager = nil
        projection = nil
        Task { await manager?.completeAgentDiagnostics(status: "cancelled") }
    }

    private func perform(_ request: HanlinConversationRequest, token: UUID,
                         continuation: AsyncThrowingStream<HanlinConversationUpdate, Error>.Continuation) async {
        defer {
            if activeToken == token {
                activeLease?.release()
                activeLease = nil
                activeToken = nil
                activeTask = nil
                apiManager = nil
                projection = nil
                self.continuation = nil
                pendingApproval = nil
            }
        }
        do {
            await application.prepareApplication()
            try requireCurrent(token)
            let context = application.modelContainer.mainContext
            let record = try application.record(conversationID)
            let models = try context.fetch(FetchDescriptor<AllModels>(
                sortBy: [SortDescriptor(\AllModels.position, order: .forward)]))
            let model: AllModels
            if let requested = request.modelRecordID {
                guard let found = models.first(where: { $0.id == requested && !$0.isHidden }) else {
                    throw HanlinConversationControllerError.unavailableModel
                }
                model = found
            } else {
                let selected = record.useModel ?? -1
                let index = models.indices.contains(selected) && !models[selected].isHidden
                    ? selected : HanlinDefaultChatPolicy.defaultModelIndex(in: models)
                guard let index, models.indices.contains(index) else {
                    throw HanlinConversationControllerError.unavailableModel
                }
                model = models[index]
            }
            guard let modelName = model.name else { throw HanlinConversationControllerError.unavailableModel }
            try HanlinComposerCapabilities.validate(request.capabilityAttachments)
            if !request.capabilityAttachments.isEmpty && !model.supportsToolUse {
                throw HanlinComposerCapabilityError.toolsUnsupported
            }
            let capabilityData = request.capabilityAttachments.isEmpty ? nil : try JSONEncoder().encode(request.capabilityAttachments)
            let images = try request.images.map { data in
                guard let image = UIImage(data: data) else { throw HanlinConversationControllerError.invalidImage }
                return image
            }
            if sessionOwner.session == nil {
                try await sessionOwner.restoreHistory(conversation: record, conversationID: conversationID,
                    sceneID: sceneID, temporary: false, modelContext: context)
            }
            try requireCurrent(token)
            var rows = (record.messages ?? []).sorted { $0.timestamp < $1.timestamp }
            if !request.observation {
                let user = ChatMessages(role: "user", text: request.text, images: images,
                    reasoning: "", documents: request.documents.map(\.absoluteString),
                    modelName: model.name, modelDisplayName: model.displayName,
                    timestamp: Date(), record: record)
                user.promptUse = request.prompts.isEmpty ? nil : request.prompts
                user.capabilityAttachmentsData = capabilityData
                context.insert(user)
                rows.append(user)
            }
            let input = HanlinConversationStreamProjection.requestMessages(
                from: rows, limit: request.historyLimit ?? record.maxMessagesNum)
            let groupID = UUID()
            let assistant = ChatMessages(role: "assistant", text: "", reasoning: "",
                modelName: model.name, modelDisplayName: model.displayName,
                groupID: groupID, timestamp: Date(), record: record)
            context.insert(assistant)
            rows.append(assistant)
            let coordinator = AgentRunCoordinator(groupID: groupID,
                providerID: model.company, modelID: modelName)
            assistant.agentRun = coordinator.run
            let projection = HanlinConversationStreamProjection(record: record, context: context,
                messages: rows, assistant: assistant, coordinator: coordinator, lease: activeLease)
            self.projection = projection
            let manager = APIManager(context: context, agentSessionOwner: sessionOwner)
            manager.presentationInstructions = richPresentation.instructions(
                conversation: record, conversationID: conversationID)
            _ = richPresentation.state(for: assistant, conversation: record,
                conversationID: conversationID, context: context, temporary: false)
            apiManager = manager
            let originalRequest = HanlinAppAgentSessionOwner.Request(
                conversation: record, conversationID: conversationID, sceneID: sceneID,
                rowID: assistant.id, uiRunID: coordinator.runID, temporary: false,
                interaction: request.interaction)
            let originalToolScope = await MCPRuntimeProvider.shared.requestScope(chatID: conversationID, temporary: false)
            let toolScope = try HanlinComposerCapabilities.scope(originalToolScope, attachments: request.capabilityAttachments)
            try requireCurrent(token)
            state = .streaming
            continuation.yield(.state(.streaming))
            publish(projection)
            let stream = try await manager.sendStreamRequest(messages: input, modelName: modelName,
                modelRecordID: model.id, groupID: groupID, runID: coordinator.runID,
                ifSearch: model.supportsSearch && request.search,
                ifKnowledge: model.supportsSearch && request.knowledge,
                ifToolUse: model.supportsToolUse && (request.tools || !request.capabilityAttachments.isEmpty), assistantToolScope: toolScope,
                ifThink: model.supportsReasoning && request.reasoning,
                ifAudio: model.supportsVoiceGen && request.audio,
                ifPlanning: !model.supportsReasoning && request.planning,
                thinkingLength: request.thinkingLength, isObservation: request.observation,
                temperature: request.temperature ?? record.temperature,
                topP: request.topP ?? record.topP, maxTokens: request.maxTokens ?? record.maxTokens,
                canvasData: record.canvas ?? CanvasData(),
                selectedURLs: request.interaction == nil ? request.urls.map(\.absoluteString) : [],
                selectedPromptsContent: request.interaction == nil ? request.prompts.map(\.content) : [],
                systemMessage: request.systemMessage ?? (record.useSystemMessage ? "Default" : record.systemMessage ?? ""),
                selectedImageSize: request.imageSize, imageReversePrompt: request.imageReversePrompt,
                agentSDKRequest: originalRequest)
            try requireCurrent(token)
            let buffer = HanlinChatStreamBuffer { [weak self] chunk in
                guard let self, activeToken == token else { return }
                projection.consume(chunk, hasCanonicalParts: hasCanonicalParts(projection))
                synchronizePresentation(projection)
                publish(projection)
            }
            do {
                for try await chunk in stream {
                    try requireCurrent(token)
                    buffer.append(chunk)
                }
                buffer.flush()
                buffer.cancel()
            } catch {
                buffer.flush()
                buffer.cancel()
                throw error
            }
            try requireCurrent(token)
            do {
                try projection.finish(hasCanonicalParts: hasCanonicalParts(projection),
                                      hasStructuredContent: hasStructuredContent(projection))
            } catch {
                projection.appendPersistenceError(error)
                synchronizePresentation(projection)
                publish(projection)
                state = .failed(error.localizedDescription)
                continuation.yield(.state(state))
                Task { await manager.completeAgentDiagnostics(status: projection.completionStatus) }
                continuation.finish(throwing: error)
                return
            }
            synchronizePresentation(projection)
            publish(projection)
            state = projection.completionStatus == "completed"
                ? .completed : .failed(HanlinConversationControllerError.emptyResponse.localizedDescription)
            continuation.yield(.state(state))
            Task { await manager.completeAgentDiagnostics(status: projection.completionStatus) }
            if projection.completionStatus == "completed" {
                activeLease?.release()
                activeLease = nil
                if !request.observation {
                    HanlinConversationAutoMetadata.schedule(for: record, messages: projection.messages,
                        in: context, fallbackModelID: model.id)
                }
                continuation.finish()
            }
            else { continuation.finish(throwing: HanlinConversationControllerError.emptyResponse) }
        } catch {
            guard activeToken == token else { return }
            if error is CancellationError || Task.isCancelled {
                stop(ifCurrent: token)
                return
            }
            if let projection {
                projection.fail(error)
                synchronizePresentation(projection)
                publish(projection)
            }
            state = .failed(error.localizedDescription)
            continuation.yield(.state(state))
            let manager = apiManager
            Task { await manager?.completeAgentDiagnostics(status: "failed", error: error) }
            continuation.finish(throwing: error)
        }
    }

    private func requireCurrent(_ token: UUID) throws {
        try Task.checkCancellation()
        guard activeToken == token else { throw HanlinHostError.staleContext }
    }

    private func publish(_ projection: HanlinConversationStreamProjection) {
        messages = projection.messages.map(HanlinConversationMessageSnapshot.init)
        operationalState = projection.operationalState
        operationalDescription = projection.operationalDescription
        continuation?.yield(.message(HanlinConversationMessageSnapshot(projection.assistantMessage)))
    }

    private func synchronizePresentation(_ projection: HanlinConversationStreamProjection) {
        #if HANLIN_A2UI_POC
        nativePresentation.synchronizeTools(projection.agentCoordinator.run, isLive: true)
        #endif
    }

    private func hasCanonicalParts(_ projection: HanlinConversationStreamProjection) -> Bool {
        #if HANLIN_A2UI_POC
        nativePresentation.hasCanonicalParts(uiRunID: projection.agentCoordinator.runID,
                                             rowID: projection.groupBeginMessage.id)
        #else
        false
        #endif
    }

    private func hasStructuredContent(_ projection: HanlinConversationStreamProjection) -> Bool {
        #if HANLIN_A2UI_POC
        nativePresentation.hasStructuredContent(uiRunID: projection.agentCoordinator.runID,
            rowID: projection.groupBeginMessage.id,
            text: (hasCanonicalParts(projection) ? projection.groupBeginMessage : projection.assistantMessage).text ?? "")
        #else
        false
        #endif
    }
}

@MainActor
enum HanlinConversationControllerRegistry {
    private final class Entry {
        weak var value: HanlinConversationController?
        init(_ value: HanlinConversationController) { self.value = value }
    }
    private static var entries: [ObjectIdentifier: [UUID: Entry]] = [:]

    static func conversationDidChange(_ change: HanlinConversationMutation.Change, in container: ModelContainer) {
        let matching = entries.compactMap { key, conversations -> (ObjectIdentifier, HanlinConversationController)? in
            guard let value = conversations[change.conversationID]?.value,
                  value.application.modelContainer === container else { return nil }
            return (key, value)
        }
        for (key, value) in matching {
            value.conversationDidChange(change)
            if case .deleted = change.kind { entries[key]?.removeValue(forKey: change.conversationID) }
        }
    }

    static func controller(application: HanlinApplicationContext, conversationID: UUID) throws -> HanlinConversationController {
        entries = entries.mapValues { $0.filter { $0.value.value != nil } }.filter { !$0.value.isEmpty }
        let key = ObjectIdentifier(application)
        if let value = entries[key]?[conversationID]?.value { return value }
        let value = try HanlinConversationController(application: application, conversationID: conversationID)
        entries[key, default: [:]][conversationID] = Entry(value)
        return value
    }
}

public extension HanlinApplicationContext {
    /// Repeated requests for the same conversation return its retained headless
    /// owner. Use either this controller or the original ChatView to own sends.
    func conversationController(_ conversationID: UUID) throws -> HanlinConversationController {
        try HanlinConversationControllerRegistry.controller(application: self, conversationID: conversationID)
    }

    func models() throws -> [HanlinApplicationModel] {
        try modelContainer.mainContext.fetch(FetchDescriptor<AllModels>(
            sortBy: [SortDescriptor(\AllModels.position, order: .forward)]))
            .map(HanlinApplicationModel.init)
    }
}
