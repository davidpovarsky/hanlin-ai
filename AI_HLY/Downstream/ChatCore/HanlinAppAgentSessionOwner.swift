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
    @ObservationIgnored private let splitCoordinator: HanlinAppSplitOriginCoordinator
    private(set) var session: HanlinAgentSession?
    private(set) var bindings: [HanlinAppAgentRowBinding] = []
    private(set) var inlineToolIsRunning = false
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
    @ObservationIgnored private weak var activeUserOperation: RuntimeUserOperation?
    @ObservationIgnored private var pendingConsentOperation: (requestID: UUID, operation: RuntimeUserOperation)?
    @ObservationIgnored private var completion: HanlinAgentRunCompletion?
    @ObservationIgnored private var starting = false
    @ObservationIgnored private var historyGeneration: UUID?
    @ObservationIgnored private var dataAccessBinding: DataAccessBinding?
    @ObservationIgnored private var inlineOrigins: [String: HanlinHostInteractionOrigin] = [:]
    @ObservationIgnored private var inlineToolTail: Task<Void, Never>?
    @ObservationIgnored private var inlineToolTasks: [UUID: Task<String, Error>] = [:]
    @ObservationIgnored private var inlineToolRowID: UUID?
    @ObservationIgnored var onApprovalEvent: ((UUID?, AgentToolApproval) -> Void)?
    @ObservationIgnored var onAgentEvent: ((HanlinAgentEvent) -> Void)?

    var pendingApprovalRowID: UUID? {
        consent.pending == nil ? nil : inlineToolRowID ?? activeReference?.messageID
    }

    init(splitCoordinator: HanlinAppSplitOriginCoordinator = .shared) {
        self.splitCoordinator = splitCoordinator
        consent.onChange = { [weak self] request, allowed in
            guard let self else { return }
            // Native Host consent bypasses the adapter's event callback. Bind
            // the original admitted operation, not the TaskLocal of a later
            // user answer or shared Host worker. Retain it across the review.
            if allowed == nil, let operation = activeUserOperation {
                pendingConsentOperation = (request.id, operation)
                operation.updateApproval(id: request.providerCallID, isPending: true)
            } else if allowed != nil, let pending = pendingConsentOperation, pending.requestID == request.id {
                pending.operation.updateApproval(id: request.providerCallID, isPending: false)
            }
            let review = request.originalArgumentsJSON.map { String(decoding: $0, as: UTF8.self) } ?? "{}"
            onApprovalEvent?(pendingApprovalRowID, .init(id: request.activityID,
                canonicalRunID: request.canonicalRunID, callID: request.providerCallID,
                toolName: request.tool, reviewText: AgentDiagnosticsRedactor.sanitize(review),
                disposition: allowed.map { $0 ? (request.remembersDecision ? .allowedAlways : .allowedOnce) : .notApproved } ?? .awaiting))
            if allowed != nil, pendingConsentOperation?.requestID == request.id {
                pendingConsentOperation = nil
            }
        }
    }

    func inlineInteraction(rowID: UUID, partID: String, actionID: String,
                           arguments: HanlinJSONValue) throws -> HanlinHostInteractionRequest {
        guard let session, contextGeneration == session.identity.context.generation,
              let binding = bindings.first(where: { $0.session == session.identity && $0.reference.messageID == rowID }) else {
            throw HanlinHostError.staleContext
        }
        let key = rowID.uuidString + "/" + partID
        let origin = inlineOrigins[key] ?? .init(session: session.identity, runID: binding.canonicalRunID,
            messageID: rowID, partID: UUID())
        try session.admitInlinePresentation(origin)
        inlineOrigins[key] = origin
        return .init(origin: origin, actionID: actionID, arguments: arguments)
    }

    func executeInlineTool(rowID: UUID, partID: String, alias: String, arguments: HanlinJSONValue,
                           onEvent: @escaping @MainActor (AgentEvent) -> Void) async throws -> String {
        // A program may declare several independent Query blocks. Serialize them
        // through the one existing Session; each obtains fresh Host admission.
        let previous = inlineToolTail
        let userOperation = RuntimeUserOperation.current
        let id = UUID()
        let work = Task { @MainActor [weak self] in
            await previous?.value
            try Task.checkCancellation()
            guard let self else { throw HanlinHostError.cancelled }
            let request = try inlineInteraction(rowID: rowID, partID: partID, actionID: alias, arguments: arguments)
            guard let session, let adapter = host?.toolAdapter,
                  let binding = bindings.first(where: { $0.session == session.identity && $0.reference.messageID == rowID }) else { throw HanlinHostError.staleContext }
            inlineToolRowID = rowID
            inlineToolIsRunning = true
            activeUIRunID = binding.reference.uiRunID; activeReference = binding.reference; completion = nil
            activeUserOperation = userOperation
            let previousCallbacks = adapter.callbacks
            let previousApproval = onApprovalEvent
            adapter.callbacks.onAgentEvent = onEvent
            adapter.callbacks.onStreamData = { data in for event in data.agentEvents { onEvent(event) } }
            adapter.callbacks.onProgressMessage = nil
            onApprovalEvent = { _, approval in onEvent(.toolApprovalChanged(approval)) }
            defer {
                adapter.callbacks = previousCallbacks; onApprovalEvent = previousApproval
                inlineToolRowID = nil; inlineToolIsRunning = false
                activeUIRunID = nil; activeReference = nil
                activeUserOperation = nil
            }
            let reference = "hanlin.app.row.v1:" + (try JSONEncoder().encode(HanlinAppAgentStoredRowReference(reference: binding.reference, session: session.identity))).base64EncodedString()
            let output = try await session.executePresentationTool(request, alias: alias,
                argumentsJSON: String(decoding: arguments.canonicalJSONData(), as: UTF8.self),
                presentationReference: reference, onStarted: { [weak self] event in
                    guard let self else { throw HanlinHostError.cancelled }
                    try receive(event, uiRunID: binding.reference.uiRunID)
                    onEvent(.modelRoundStarted(id: event.runID.uuidString))
                })
            try producerStreamDrained(uiRunID: binding.reference.uiRunID)
            guard !output.isError else { throw HanlinInlineToolError(message: output.modelText) }
            return output.modelText
        }
        inlineToolTasks[id] = work
        inlineToolTail = Task { _ = try? await work.value }
        defer { inlineToolTasks.removeValue(forKey: id) }
        return try await withTaskCancellationHandler { try await work.value } onCancel: { work.cancel() }
    }

    /// Read-only history on conversation open. No engine, Host, Session or interaction admission
    /// is created. The caller supplies its original row/context, never a current-selection lookup.
    func restoreHistory(conversation: ChatRecords, conversationID: UUID, sceneID: UUID,
                        temporary: Bool, modelContext: ModelContext) async throws {
        try Task.checkCancellation()
        guard !starting, activeUIRunID == nil else { throw HanlinHostError.staleContext }
        let namespace = try Self.namespace(conversationID: conversationID, temporary: temporary, modelContext: modelContext)
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

    private static func namespace(conversationID: UUID, temporary: Bool,
                                  modelContext: ModelContext) throws -> HanlinConversationNamespace {
        try HanlinApplicationContextRegistry.configuration(for: modelContext.container)
            .namespace(conversationID: conversationID, temporary: temporary)
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

    struct DataAccess: Equatable, Sendable {
        let epoch: UUID
        let namespace: HanlinConversationNamespace
    }

    private struct DataAccessBinding {
        let access: DataAccess
        let request: Request
        let context: ModelContext
        let storageOwner: ModelContainer
    }

    /// The existing request owner admits data preparation before constructing its engine.
    /// This is a revocable request lease, not a fabricated HostSession or a new data store.
    func prepareDataAccess(request: Request, modelContext: ModelContext) throws -> DataAccess {
        try Task.checkCancellation()
        guard !starting, activeUIRunID == nil else { throw HanlinHostError.duplicateInvocation }
        let namespace = try Self.namespace(conversationID: request.conversationID, temporary: request.temporary, modelContext: modelContext)
        if let session {
            guard contextGeneration == session.identity.context.generation,
                  session.identity.conversationID == request.conversationID,
                  session.identity.context.namespace == namespace,
                  session.identity.context.sceneID == request.sceneID else { throw HanlinHostError.staleContext }
        }
        _ = try HanlinAppConversationStore.requireOriginalConversation(context: modelContext,
            conversation: request.conversation, conversationID: request.conversationID, temporary: request.temporary)
        let access = DataAccess(epoch: UUID(), namespace: namespace)
        dataAccessBinding = .init(access: access, request: request, context: modelContext, storageOwner: modelContext.container)
        return access
    }

    func requireDataAccess(_ access: DataAccess, request: Request, modelContext: ModelContext) throws {
        try Task.checkCancellation()
        guard let binding = dataAccessBinding, binding.access == access,
              binding.context === modelContext, binding.request.conversation === request.conversation,
              binding.request.conversationID == request.conversationID,
              binding.request.sceneID == request.sceneID, binding.request.rowID == request.rowID,
              binding.request.uiRunID == request.uiRunID, binding.request.temporary == request.temporary,
              access.namespace == (try Self.namespace(conversationID: request.conversationID, temporary: request.temporary, modelContext: modelContext)) else {
            throw HanlinHostError.staleContext
        }
        _ = try withExtendedLifetime(binding.storageOwner) {
            try HanlinAppConversationStore.requireOriginalConversation(context: modelContext,
                conversation: request.conversation, conversationID: request.conversationID, temporary: request.temporary)
        }
    }

    /// Bind the actual tool adapter after the original HostSession exists. The row currently
    /// admitted by the owner supplies the turn, including a legitimate inline action on an
    /// older row. Diagnostics round IDs are never attachment authorization identities.
    private func bindAttachments(to adapter: HanlinAISDKToolAdapter?, identity: HanlinHostSession) {
        adapter?.sdkAttachmentResolver = { [weak self] handle in
            guard let self else { throw HanlinHostError.staleContext }
            let uiRunID = try self.requireAttachmentOrigin(identity: identity)
            let registry = AuthorizedAttachmentRegistry.shared
            let reference = try await registry.reference(forLegacyHandle: handle, session: identity,
                requestID: uiRunID.uuidString)
            guard try self.requireAttachmentOrigin(identity: identity) == uiRunID else { throw HanlinHostError.staleContext }
            let attachments: any HanlinAttachmentStore = registry
            let data = try await attachments.read(reference, session: identity)
            guard try self.requireAttachmentOrigin(identity: identity) == uiRunID else { throw HanlinHostError.staleContext }
            return data
        }
    }

    private func requireAttachmentOrigin(identity: HanlinHostSession) throws -> UUID {
        try Task.checkCancellation()
        guard session?.identity == identity, contextGeneration == identity.context.generation,
              let activeUIRunID, activeReference?.uiRunID == activeUIRunID,
              let store, store.namespace == identity.context.namespace else { throw HanlinHostError.staleContext }
        _ = try store.requireOriginalConversation()
        return activeUIRunID
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
                messages: [HanlinAISDKMessage], systemPrompt: String?, dataAccess: DataAccess? = nil,
                transport: HanlinAISDKTurnTransport? = nil) async throws -> AsyncThrowingStream<HanlinAgentEvent, Error> {
        let userOperation = RuntimeUserOperation.current
        guard !starting, activeUIRunID == nil else { throw HanlinHostError.duplicateInvocation }
        guard request.conversation.id == request.conversationID else { throw HanlinHostError.staleContext }
        if let dataAccess { try requireDataAccess(dataAccess, request: request, modelContext: modelContext) }
        // Preserve the existing canonical writer before loading/replaying its
        // record into another owner or constructing another model engine.
        guard !splitCoordinator.hasRunningSession(for: request.conversationID) else {
            throw HanlinHostError.unresolvedWrite
        }
        historyGeneration = nil
        starting = true
        defer { starting = false }
        let namespace = try Self.namespace(conversationID: request.conversationID, temporary: request.temporary, modelContext: modelContext)
        let matches = session?.identity.conversationID == request.conversationID
            && session?.identity.context.namespace == namespace && session?.identity.context.sceneID == request.sceneID
            && Self.sameEngineConfiguration(modelConfiguration, configuration)
        if !matches {
            guard request.interaction == nil else { throw HanlinHostError.staleContext }
            await invalidate(preservingDataAccess: dataAccess)
            if let dataAccess { try requireDataAccess(dataAccess, request: request, modelContext: modelContext) }
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
            originalHost.confirmInvocation = { [weak self] invocation, approvalScope in
                guard let self, self.contextGeneration == generation else { return false }
                return await self.consent.request(invocation, approvalScope: approvalScope)
            }
            originalHost.toolAdapter = toolAdapter
            let originalServices = HanlinApplicationHostServices(host: originalHost,
                capabilities: originalHost, interactions: originalHost)
            let applicationConfiguration = HanlinApplicationContextRegistry.configuration(for: modelContext.container)
            let services = try await applicationConfiguration.hostServices?(identity, originalServices) ?? originalServices
            guard contextGeneration == generation else { throw HanlinHostError.staleContext }
            let originalSession = HanlinAgentSession(identity: identity, host: services.host, engine: originalEngine,
                store: originalStore, capabilities: services.capabilities, interactions: services.interactions)
            try splitCoordinator.register(session: originalSession, modelContext: modelContext)
            store = originalStore; host = originalHost; session = originalSession; engine = originalEngine; modelConfiguration = configuration
            originalHost.splitCoordinator = splitCoordinator
            originalHost.splitSession = originalSession
            originalHost.splitRowReference = { [weak self] in
                guard self?.session?.identity == identity, self?.contextGeneration == generation else { return nil }
                return self?.activeReference
            }
            originalSession.onProviderToolApproval = { [weak self] approval in
                guard let self, self.contextGeneration == generation,
                      self.session?.identity == approval.session else { return false }
                let allowed = await self.consent.request(approval)
                return allowed && self.contextGeneration == generation
                    && self.session?.identity == approval.session && !Task.isCancelled
            }
            let priorCompletion = originalSession.onRunCompletion
            originalSession.onRunCompletion = { [weak self] value in
                priorCompletion?(value)
                if self?.session?.identity == value.session { self?.completion = value }
                self?.presentation?.completed(value)
                services.onRunCompletion?(value)
            }
            let priorInvalidation = originalSession.onSessionInvalidated
            originalSession.onSessionInvalidated = { [weak self] value in
                priorInvalidation?(value)
                self?.presentation?.invalidated(value)
                services.onSessionInvalidated?(value)
            }
            let priorResult = originalSession.onHostResult
            originalSession.onHostResult = { [weak self] value in
                priorResult?(value)
                self?.splitCoordinator.receiptCommitted(value)
                self?.presentation?.hostResult(value)
                services.onHostResult?(value)
            }
            let priorProgress = originalSession.onHostProgress
            originalSession.onHostProgress = { [weak self] value in
                priorProgress?(value); self?.presentation?.hostProgress(value)
                services.onHostProgress?(value)
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
        if let dataAccess { try requireDataAccess(dataAccess, request: request, modelContext: modelContext) }
        host.toolAdapter = toolAdapter
        bindAttachments(to: toolAdapter, identity: session.identity)
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
        var effectiveSystemPrompt = systemPrompt
        if let instructions = presentation?.modelInstructions, !instructions.isEmpty {
            effectiveSystemPrompt = [systemPrompt, instructions].compactMap { $0 }.joined(separator: "\n\n")
        }
        // Engine preparation and history loading can suspend. Recheck the
        // original coordinator immediately before admitting this new turn.
        guard !splitCoordinator.hasRunningSession(for: request.conversationID) else {
            throw HanlinHostError.unresolvedWrite
        }
        if let dataAccess { try requireDataAccess(dataAccess, request: request, modelContext: modelContext) }
        activeUIRunID = request.uiRunID; activeReference = reference; completion = nil
        activeUserOperation = userOperation
        do {
            if let interaction = request.interaction {
                guard bindings.contains(where: { $0.session == interaction.origin.session && $0.canonicalRunID == interaction.origin.runID
                    && $0.reference.messageID == interaction.origin.messageID }) else { throw HanlinHostError.staleContext }
                return try await session.continueInteraction(interaction, messages: messages,
                    modelReference: .init(provider: descriptor.kind.rawValue, modelID: descriptor.modelID),
                    systemPrompt: effectiveSystemPrompt, structuredResponse: native, presentationReference: referenceData, transport: transport)
            }
            return try await session.stream(messages: messages, systemPrompt: effectiveSystemPrompt,
                modelReference: .init(provider: descriptor.kind.rawValue, modelID: descriptor.modelID),
                structuredResponse: native, presentationReference: referenceData, transport: transport)
        } catch {
            activeUIRunID = nil; activeReference = nil
            activeUserOperation = nil
            throw error
        }
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
        onAgentEvent?(event)
    }

    /// This is a receipt query for the event just consumed, never a current-selection
    /// lookup. Empty, rejected, repeated and historical structured parts cannot end
    /// a different request's waiting/reasoning status.
    func hasVisibleModelOutput(_ event: HanlinAgentEvent, uiRunID: UUID) -> Bool {
        guard activeUIRunID == uiRunID, let reference = activeReference,
              event.session == session?.identity,
              contextGeneration == event.session.context.generation,
              let binding = bindings.first(where: {
                  $0.session == event.session && $0.canonicalRunID == event.runID
              }), binding.reference == reference else { return false }
        return presentation?.hasVisibleModelOutput(event) == true
    }

    func producerStreamDrained(uiRunID: UUID) throws {
        guard activeUIRunID == uiRunID, let completion, completion.session == session?.identity else { throw HanlinHostError.staleContext }
        guard case .completed = completion.outcome else { throw HanlinHostError.cancelled }
        presentation?.producerStreamDrained(runID: completion.runID)
        activeUIRunID = nil; activeReference = nil
        activeUserOperation = nil
    }

    /// User-requested clear history uses the same original store and revision chain.
    /// Revoke synchronously before any visible or canonical mutation; queued old writes
    /// still have to pass the store's CAS after the empty replacement revision is saved.
    func clearHistory(conversation: ChatRecords, conversationID: UUID, modelContext: ModelContext,
                      temporary: Bool, replacementText: String) throws -> ChatMessages {
        let namespace = try Self.namespace(conversationID: conversationID, temporary: temporary, modelContext: modelContext)
        let originalStore: HanlinAppConversationStore
        if let store, store.namespace == namespace,
           store.belongsTo(context: modelContext, conversation: conversation, temporary: temporary) {
            originalStore = store
        } else {
            originalStore = HanlinAppConversationStore(context: modelContext, conversation: conversation,
                namespace: namespace, conversationID: conversationID, temporary: temporary)
        }
        cancel()
        let replacement = try originalStore.clearHistory(replacementText: replacementText)
        store = originalStore
        bindings = []
        inlineToolRowID = nil
        inlineToolIsRunning = false
        return replacement
    }

    /// Synchronous authority revocation precedes any asynchronous cancellation/host cleanup.
    func revoke() {
        dataAccessBinding = nil
        revokeSessionAuthority()
    }

    private func revokeSessionAuthority() {
        consent.revoke()
        inlineOrigins.removeAll()
        for task in inlineToolTasks.values { task.cancel() }
        inlineToolTasks.removeAll(); inlineToolTail = nil
        historyGeneration = nil
        contextGeneration = nil
        if let session { splitCoordinator.invalidate(session: session.identity) }
        if let session { presentation?.invalidated(session.identity) }
        activeUIRunID = nil; activeReference = nil
        activeUserOperation = nil
    }

    func invalidate() async { await invalidate(preservingDataAccess: nil) }

    private func invalidate(preservingDataAccess access: DataAccess?) async {
        // Replacing the model engine does not replace the already admitted request.
        // Any external revoke/cancel still clears the lease synchronously, and stream
        // checks its exact epoch again after this suspension.
        if let access, dataAccessBinding?.access == access { revokeSessionAuthority() }
        else { revoke() }
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
            && one.apiType == two.apiType && one.endpoint == two.endpoint && one.apiKey.utf8.elementsEqual(two.apiKey.utf8)
            && one.temperature == two.temperature && one.topP == two.topP && one.maxTokens == two.maxTokens
            && one.supportsReasoning == two.supportsReasoning && one.supportReasoningChange == two.supportReasoningChange
            && one.thinkingLength == two.thinkingLength && one.reasoningEffort == two.reasoningEffort
            && one.supportsToolUse == two.supportsToolUse && one.supportsTextGen == two.supportsTextGen
            && one.systemPrompt == two.systemPrompt
    }
}
