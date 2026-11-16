import Foundation
import HanlinAgentCore
import HanlinChatCore
import HanlinHostContracts
import HanlinPlatformContracts
import Observation
import SwiftData

private struct HanlinAppAgentStoredRowReference: Codable {
    let reference: HanlinAppAgentRowReference
    let session: HanlinHostSession
}

/// One conversation owner retained by the existing ChatView state and injected into request
/// APIManagers. It owns one current Session/engine/Host/store; no extra presentation engine runs.
@MainActor @Observable
final class HanlinAppAgentSessionOwner {
    let consent = HanlinAppToolConsent()
    private(set) var session: HanlinAgentSession?
    private(set) var bindings: [HanlinAppAgentRowBinding] = []
    @ObservationIgnored weak var presentation: (any HanlinAppAgentPresentationConsumer)? {
        didSet { if let session { presentation?.installed(session: session) } }
    }
    @ObservationIgnored private var host: HanlinAppHostIntegration?
    @ObservationIgnored private var engine: HanlinAISDKAgentEngine?
    @ObservationIgnored private var store: HanlinAppConversationStore?
    @ObservationIgnored private var modelConfiguration: HanlinChatModelConfiguration?
    @ObservationIgnored private var contextGeneration: UUID?
    @ObservationIgnored private var activeUIRunID: UUID?
    @ObservationIgnored private var activeReference: HanlinAppAgentRowReference?
    @ObservationIgnored private var completion: HanlinAgentRunCompletion?
    @ObservationIgnored private var starting = false
    @ObservationIgnored private var historyGeneration: UUID?

    /// Read-only history on conversation open. No engine, Host, Session or interaction admission
    /// is created. The caller supplies its original row/context, never a current-selection lookup.
    func restoreHistory(conversation: ChatRecords, conversationID: UUID, sceneID: UUID,
                        temporary: Bool, modelContext: ModelContext) async throws {
        try Task.checkCancellation()
        guard !starting, activeUIRunID == nil else { throw HanlinHostError.staleContext }
        let namespace = try Self.namespace(conversationID: conversationID, temporary: temporary)
        if let session {
            guard session.identity.conversationID == conversationID,
                  session.identity.context.namespace == namespace,
                  session.identity.context.sceneID == sceneID else { throw HanlinHostError.staleContext }
        }
        let originalSession = session?.identity
        let originalGeneration = contextGeneration
        let token = UUID()
        historyGeneration = token
        let originalStore: HanlinAppConversationStore
        if let store, store.namespace == namespace,
           store.belongsTo(context: modelContext, conversation: conversation, temporary: temporary) {
            originalStore = store
        } else {
            guard session == nil else { throw HanlinHostError.staleContext }
            originalStore = HanlinAppConversationStore(context: modelContext, conversation: conversation,
                namespace: namespace, conversationID: conversationID, temporary: temporary)
            store = originalStore
        }
        let record = try await originalStore.load(conversationID, namespace: namespace)
        try Task.checkCancellation()
        guard historyGeneration == token, !starting, activeUIRunID == nil,
              session?.identity == originalSession, contextGeneration == originalGeneration,
              store === originalStore else { throw HanlinHostError.staleContext }
        _ = try originalStore.requireOriginalConversation()
        guard let record else { return }
        let restored = try Self.restoredBindings(record)
        try presentation?.replay(record, bindings: restored)
        bindings = restored
    }

    private static func namespace(conversationID: UUID, temporary: Bool) throws -> HanlinConversationNamespace {
        try HanlinConversationNamespace(app: "hanlin", account: "local-personal-library",
            workspace: temporary ? "temporary" : "swiftdata", space: conversationID.uuidString)
    }

    /// Called with the already-created original response row, real conversation and scene.
    /// The UI must keep this owner for that conversation instead of recreating it each request.
    struct Request {
        let conversation: ChatRecords
        let conversationID: UUID
        let sceneID: UUID
        let rowID: UUID
        let uiRunID: UUID
        let temporary: Bool
        let interaction: HanlinHostInteractionRequest?
    }

    func canRequestNativeStructured(_ configuration: HanlinChatModelConfiguration) -> Bool {
        guard presentation != nil else { return false }
        let descriptor = HanlinAISDKProviderFactory.descriptor(for: configuration)
        return HanlinNativeStructuredResponse.supports(descriptor)
            || (descriptor.kind == .openAI && descriptor.modelID == HanlinNativeStructuredResponse.modelID
                && descriptor.baseURL.absoluteString == "https://api.openai.com/v1")
    }

    /// Select the real Responses adapter for the already-selected eligible model when the
    /// application has explicitly installed structured presentation. No model is substituted.
    func configurationForPresentation(_ original: HanlinChatModelConfiguration) -> HanlinChatModelConfiguration {
        guard canRequestNativeStructured(original) else { return original }
        return .init(modelID: original.modelID, baseModelID: original.baseModelID, displayName: original.displayName,
            company: original.company, apiType: "openai-responses", endpoint: original.endpoint, apiKey: original.apiKey,
            temperature: original.temperature, topP: original.topP, maxTokens: original.maxTokens,
            supportsReasoning: original.supportsReasoning, supportReasoningChange: original.supportReasoningChange,
            thinkingLength: original.thinkingLength, reasoningEffort: original.reasoningEffort,
            supportsToolUse: original.supportsToolUse, supportsTextGen: original.supportsTextGen,
            systemPrompt: original.systemPrompt, updatedAt: original.updatedAt)
    }

    func stream(request: Request, modelContext: ModelContext, configuration: HanlinChatModelConfiguration,
                engineFactory: @MainActor () async throws -> HanlinAISDKAgentEngine, toolAdapter: HanlinAISDKToolAdapter?,
                messages: [HanlinAISDKMessage], systemPrompt: String?) async throws -> AsyncThrowingStream<HanlinAgentEvent, Error> {
        guard !starting, activeUIRunID == nil else { throw HanlinHostError.duplicateInvocation }
        guard request.conversation.id == request.conversationID else { throw HanlinHostError.staleContext }
        historyGeneration = nil
        starting = true
        defer { starting = false }
        let namespace = try Self.namespace(conversationID: request.conversationID, temporary: request.temporary)
        let matches = session?.identity.conversationID == request.conversationID
            && session?.identity.context.namespace == namespace && session?.identity.context.sceneID == request.sceneID
            && Self.sameEngineConfiguration(modelConfiguration, configuration)
        if !matches {
            guard request.interaction == nil else { throw HanlinHostError.staleContext }
            await invalidate()
            let generation = UUID()
            contextGeneration = generation
            let originalEngine = try await engineFactory()
            guard contextGeneration == generation else { throw HanlinHostError.staleContext }
            let context = HanlinHostContext(namespace: namespace, sceneID: request.sceneID, generation: generation,
                objectReference: request.conversationID.uuidString, localeIdentifier: Locale.current.identifier)
            let identity = HanlinHostSession(conversationID: request.conversationID, context: context)
            let originalStore: HanlinAppConversationStore
            if let store, store.namespace == namespace,
               store.belongsTo(context: modelContext, conversation: request.conversation, temporary: request.temporary) {
                originalStore = store
            } else {
                originalStore = HanlinAppConversationStore(context: modelContext, conversation: request.conversation,
                    namespace: namespace, conversationID: request.conversationID, temporary: request.temporary)
                bindings = []
            }
            let originalHost = HanlinAppHostIntegration(identity: identity, store: originalStore, isCurrent: { [weak self] in
                self?.contextGeneration == generation
            })
            originalHost.confirmInvocation = { [weak self] invocation in
                guard let self, self.contextGeneration == generation else { return false }
                return await self.consent.request(invocation)
            }
            let originalSession = HanlinAgentSession(identity: identity, host: originalHost, engine: originalEngine,
                store: originalStore, capabilities: originalHost)
            store = originalStore; host = originalHost; session = originalSession; engine = originalEngine; modelConfiguration = configuration
            let priorCompletion = originalSession.onRunCompletion
            originalSession.onRunCompletion = { [weak self] value in
                priorCompletion?(value)
                if self?.session?.identity == value.session { self?.completion = value }
                self?.presentation?.completed(value)
            }
            let priorInvalidation = originalSession.onSessionInvalidated
            originalSession.onSessionInvalidated = { [weak self] value in
                priorInvalidation?(value)
                self?.presentation?.invalidated(value)
            }
            let priorResult = originalSession.onHostResult
            originalSession.onHostResult = { [weak self] value in
                priorResult?(value)
                self?.presentation?.hostResult(value)
            }
            let priorProgress = originalSession.onHostProgress
            originalSession.onHostProgress = { [weak self] value in
                priorProgress?(value); self?.presentation?.hostProgress(value)
            }
            presentation?.installed(session: originalSession)
            if let record = try await originalStore.load(request.conversationID, namespace: namespace) {
                guard contextGeneration == generation else { throw HanlinHostError.staleContext }
                let restored = try Self.restoredBindings(record)
                bindings = restored
                try presentation?.replay(record, bindings: restored)
            }
        }
        guard let session, let host, let engine, contextGeneration == session.identity.context.generation else { throw HanlinHostError.staleContext }
        host.toolAdapter = toolAdapter
        let reference = HanlinAppAgentRowReference(rowID: request.rowID, uiRunID: request.uiRunID, messageID: request.rowID)
        let referenceData = "hanlin.app.row.v1:" + (try JSONEncoder().encode(HanlinAppAgentStoredRowReference(reference: reference, session: session.identity))).base64EncodedString()
        let descriptor = await engine.providerDescriptor
        let native: HanlinNativeStructuredResponse?
        if presentation != nil, HanlinNativeStructuredResponse.supports(descriptor) {
            native = .init(messageID: reference.messageID, validateCompleteParts: { [weak self] parts in
                guard let self, let presentation = self.presentation,
                      self.session?.identity == session.identity else { throw HanlinHostError.staleContext }
                try presentation.validateCompleteParts(parts)
            })
        } else { native = nil }
        activeUIRunID = request.uiRunID; activeReference = reference; completion = nil
        do {
            if let interaction = request.interaction {
                guard bindings.contains(where: { $0.session == interaction.origin.session && $0.canonicalRunID == interaction.origin.runID
                    && $0.reference.messageID == interaction.origin.messageID }) else { throw HanlinHostError.staleContext }
                return try await session.continueInteraction(interaction, messages: messages,
                    modelReference: .init(provider: descriptor.kind.rawValue, modelID: descriptor.modelID),
                    systemPrompt: systemPrompt, structuredResponse: native, presentationReference: referenceData)
            }
            return try await session.stream(messages: messages, systemPrompt: systemPrompt,
                modelReference: .init(provider: descriptor.kind.rawValue, modelID: descriptor.modelID),
                structuredResponse: native, presentationReference: referenceData)
        } catch { activeUIRunID = nil; activeReference = nil; throw error }
    }

    func receive(_ event: HanlinAgentEvent, uiRunID: UUID) throws {
        guard activeUIRunID == uiRunID, let reference = activeReference,
              event.session == session?.identity, contextGeneration == event.session.context.generation else { throw HanlinHostError.staleContext }
        let binding: HanlinAppAgentRowBinding
        if let existing = bindings.first(where: { $0.session == event.session && $0.canonicalRunID == event.runID }) {
            guard existing.reference == reference else { throw HanlinHostError.resultMismatch }
            binding = existing
        } else {
            guard bindings.count < 256 else { throw HanlinHostError.storageLimitExceeded }
            binding = .init(reference: reference, session: event.session, canonicalRunID: event.runID)
            bindings.append(binding)
        }
        if case .structuredPart(let part) = event.event {
            guard part.messageID == binding.reference.messageID else { throw HanlinHostError.resultMismatch }
        }
        try presentation?.receive(event, binding: binding)
    }

    func producerStreamDrained(uiRunID: UUID) throws {
        guard activeUIRunID == uiRunID, let completion, completion.session == session?.identity else { throw HanlinHostError.staleContext }
        guard case .completed = completion.outcome else { throw HanlinHostError.cancelled }
        presentation?.producerStreamDrained(runID: completion.runID)
        activeUIRunID = nil; activeReference = nil
    }

    /// Synchronous authority revocation precedes any asynchronous cancellation/host cleanup.
    func revoke() {
        consent.revoke()
        historyGeneration = nil
        contextGeneration = nil
        if let session { presentation?.invalidated(session.identity) }
        activeUIRunID = nil; activeReference = nil
    }

    func invalidate() async {
        revoke()
        if let session { await session.invalidate() }
        session = nil; host = nil; engine = nil; modelConfiguration = nil; completion = nil
    }

    func invalidate(uiRunID: UUID) async {
        guard activeUIRunID == uiRunID else { return }
        await invalidate()
    }

    func cancel() {
        let originalSession = session
        revoke()
        session = nil; host = nil; engine = nil; modelConfiguration = nil; completion = nil
        Task { await originalSession?.invalidate() }
    }

    /// Reuses the one original private decoder for cold read-only correlation, never admission.
    static func historicalBindings(in record: HanlinConversationRecord) throws -> [HanlinAppAgentRowBinding] {
        try restoredBindings(record)
    }

    private static func restoredBindings(_ record: HanlinConversationRecord) throws -> [HanlinAppAgentRowBinding] {
        try record.validate()
        var result = [HanlinAppAgentRowBinding]()
        for entry in record.entries {
            guard case .presentationReference(let version, let opaque) = entry.payload, version == 1,
                  opaque.hasPrefix("hanlin.app.row.v1:"),
                  let data = Data(base64Encoded: String(opaque.dropFirst("hanlin.app.row.v1:".count))), data.count <= 4096 else { continue }
            // Historical session/context must come from the original canonical parts, never the
            // newly installed session. This binding is for read-only replay, not live authority.
            let stored = try JSONDecoder().decode(HanlinAppAgentStoredRowReference.self, from: data)
            let reference = stored.reference
            guard reference.messageID == reference.rowID, stored.session.conversationID == record.conversationID,
                  stored.session.context.namespace == record.namespace else { throw HanlinHostError.invalidRecord }
            let binding = HanlinAppAgentRowBinding(reference: reference, session: stored.session, canonicalRunID: entry.runID)
            guard !result.contains(where: { $0.canonicalRunID == entry.runID }) else { throw HanlinHostError.invalidRecord }
            result.append(binding)
        }
        return result
    }

    private static func sameEngineConfiguration(_ one: HanlinChatModelConfiguration?, _ two: HanlinChatModelConfiguration) -> Bool {
        guard let one else { return false }
        // updatedAt is bookkeeping, not an engine input. Compare the complete real input closure.
        return one.modelID == two.modelID && one.baseModelID == two.baseModelID && one.company == two.company
            && one.apiType == two.apiType && one.endpoint == two.endpoint && one.apiKey == two.apiKey
            && one.temperature == two.temperature && one.topP == two.topP && one.maxTokens == two.maxTokens
            && one.supportsReasoning == two.supportsReasoning && one.supportReasoningChange == two.supportReasoningChange
            && one.thinkingLength == two.thinkingLength && one.reasoningEffort == two.reasoningEffort
            && one.supportsToolUse == two.supportsToolUse && one.supportsTextGen == two.supportsTextGen
            && one.systemPrompt == two.systemPrompt
    }
}
