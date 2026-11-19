import Foundation
import HanlinChatCore
import HanlinHostContracts
import HanlinPlatformContracts

public struct HanlinAgentEvent: Sendable {
    public let session: HanlinHostSession
    public let interactionOrigin: HanlinHostInteractionOrigin?
    public let runID: UUID
    public let step: Int
    public let sequence: UInt64
    public let event: HanlinAISDKStreamEvent
}

public struct HanlinAgentRunCompletion: Sendable {
    public enum Outcome: Sendable { case completed, cancelled, failed(HanlinHostError) }
    public let session: HanlinHostSession
    public let runID: UUID
    public let outcome: Outcome
}

public struct HanlinAgentToolApproval: Sendable {
    public let session: HanlinHostSession
    public let runID: UUID
    public let step: Int
    public let request: HanlinAISDKToolApprovalRequest
    public let deadline: Date
}

/// A DI/persistence facade over ONE HanlinAISDKAgentEngine. No app singleton, SwiftData or renderer.
@MainActor
public final class HanlinAgentSession {
    public let identity: HanlinHostSession
    public var onHostProgress: (@MainActor @Sendable (HanlinHostProgressEvent) -> Void)?
    public var onHostResult: (@MainActor @Sendable (HanlinHostResultEvent) -> Void)?
    public var onRunCompletion: (@MainActor @Sendable (HanlinAgentRunCompletion) -> Void)?
    public var onProviderToolApproval: (@MainActor @Sendable (HanlinAgentToolApproval) async -> Bool)?
    public var onSessionInvalidated: (@MainActor @Sendable (HanlinHostSession) -> Void)?
    private let host: any HanlinHostIntegration
    private let engine: HanlinAISDKAgentEngine
    private let store: any HanlinConversationStore
    private let capabilities: (any HanlinHostCapabilitySource)?
    private let interactions: (any HanlinHostInteractionSource)?
    private let diagnostics: (any HanlinDiagnosticsSink)?
    public let dispatcher: HanlinHostDispatcher
    public var isRunning: Bool { activeRun != nil }
    private var activeRun: UUID?
    private var record: HanlinConversationRecord?
    private var entries: [HanlinTranscriptEntry] = []
    private var sequence: UInt64 = 0
    private var step = 0
    private var preparationError: HanlinHostError?
    private var invalidated = false
    private var producerTask: Task<Void, Never>?
    private var persistenceTail: Task<Void, Error>?
    private var associatedInvocations: [HanlinToolInvocationID: String] = [:]
    private var currentCatalog: HanlinHostCatalog?
    private var interactionOrigins = Set<HanlinHostInteractionOrigin>()
    private var observedInteractionOrigins = Set<HanlinHostInteractionOrigin>()
    private var interactionRequests = Set<UUID>()
    private var completedLiveRuns = Set<UUID>()

    public init(identity: HanlinHostSession, host: any HanlinHostIntegration, engine: HanlinAISDKAgentEngine,
                store: any HanlinConversationStore, capabilities: (any HanlinHostCapabilitySource)? = nil,
                interactions: (any HanlinHostInteractionSource)? = nil,
                diagnostics: (any HanlinDiagnosticsSink)? = nil) {
        self.identity = identity; self.host = host; self.engine = engine; self.store = store
        self.capabilities = capabilities; self.diagnostics = diagnostics
        // Hosts can pass their original interaction interface explicitly, just
        // like step capabilities. Keep inference for existing SDK clients.
        self.interactions = interactions ?? (host as? any HanlinHostInteractionSource)
        self.dispatcher = HanlinHostDispatcher(host: host)
    }

    public func stream(messages: [HanlinAISDKMessage], systemPrompt: String? = nil,
                       modelReference: HanlinModelReference, maxSteps: Int? = nil,
                       structuredResponse: HanlinNativeStructuredResponse? = nil,
                       presentationReference: String? = nil,
                       transport: HanlinAISDKTurnTransport? = nil) async throws -> AsyncThrowingStream<HanlinAgentEvent, Error> {
        try await startStream(messages: messages, systemPrompt: systemPrompt, modelReference: modelReference,
                              maxSteps: maxSteps, interactionOrigin: nil, structuredResponse: structuredResponse,
                              presentationReference: presentationReference, transport: transport)
    }

    private func startStream(messages: [HanlinAISDKMessage], systemPrompt: String?, modelReference: HanlinModelReference,
                             maxSteps: Int?, interactionOrigin: HanlinHostInteractionOrigin?,
                             structuredResponse: HanlinNativeStructuredResponse?,
                             presentationReference: String?, transport: HanlinAISDKTurnTransport?) async throws -> AsyncThrowingStream<HanlinAgentEvent, Error> {
        guard !invalidated else { throw HanlinHostError.staleContext }
        guard activeRun == nil else { throw HanlinHostError.duplicateInvocation }
        guard host.apiVersion.major == 1 else { throw HanlinHostError.unsupportedVersion }
        guard presentationReference.map({ !$0.isEmpty && $0.utf8.count <= 4096 }) ?? true else { throw HanlinHostError.invalidArguments }
        // Reserve before ANY store/host await. Concurrent starts cannot share a producer.
        let run = UUID()
        activeRun = run
        do {
            try await requireCurrent(run: run)
            record = try await store.load(identity.conversationID, namespace: identity.context.namespace)
            try requireActive(run: run)
            if let record { try record.validate() }
            entries = record?.entries ?? []
            guard entries.last?.sequence != UInt64.max else { throw HanlinHostError.storageLimitExceeded }
            sequence = (entries.last?.sequence).map { $0 + 1 } ?? 0
            step = 0; preparationError = nil
            persistenceTail = nil
            associatedInvocations = [:]
            // An interrupted dispatch must be reconciled by the original host before another run.
            var pending = Set<String>()
            for entry in entries {
                switch entry.payload {
                case .toolCall(let id, _, _): pending.insert(entry.runID.uuidString + id)
                case .toolResult(let id, let result):
                    if result.effectState != .uncertain { pending.remove(entry.runID.uuidString + id) }
                default: break
                }
            }
            guard pending.isEmpty else { throw HanlinHostError.unresolvedWrite }
            let catalog = try await host.catalog(for: identity.context)
            try await requireCurrent(run: run)
            try catalog.validate()
            guard !invalidated, catalog.context == identity.context, activeRun == run else { throw HanlinHostError.staleContext }
            currentCatalog = catalog
            if let presentationReference {
                try append(.presentationReference(version: 1, opaqueReference: presentationReference), run: run)
            }
            try await persist(model: modelReference)
            try requireActive(run: run)
            let definitions = try makeDefinitions(catalog: catalog, run: run, model: modelReference)
            let source = try await engine.stream(messages: messages, baseSystemPrompt: systemPrompt, tools: definitions,
                maxSteps: maxSteps,
                dynamicTools: { [weak self] in
                    guard let self, !self.invalidated, self.activeRun == run else { return [] }
                    do {
                        let refreshed = try await self.host.catalog(for: self.identity.context)
                        try await self.requireCurrent(run: run)
                        try refreshed.validate()
                        guard refreshed.context == self.identity.context else { throw HanlinHostError.staleContext }
                        // Existing core reloads when names change. Same-name descriptor changes must
                        // terminate this run explicitly rather than silently use an obsolete schema.
                        if let prior = self.currentCatalog,
                           Set(prior.tools.map(\.route.alias)) == Set(refreshed.tools.map(\.route.alias)),
                           prior.revision != refreshed.revision { throw HanlinHostError.staleContext }
                        self.currentCatalog = refreshed
                        return try self.makeDefinitions(catalog: refreshed, run: run, model: modelReference)
                    } catch {
                        if self.activeRun == run { self.preparationError = (error as? HanlinHostError) ?? .denied }
                        return []
                    }
                },
                structuredResponse: structuredResponse,
                requestApproval: { [weak self] request in
                    guard let self else { throw HanlinHostError.cancelled }
                    try await self.requireCurrent(run: run)
                    guard self.currentCatalog?.tools.contains(where: { $0.route.alias == request.toolName }) == true else {
                        return false // Unadvertised provider tools never acquire host authority.
                    }
                    let limits = try HanlinToolInvocationLimits()
                    let review = HanlinAgentToolApproval(session: self.identity, runID: run, step: self.step,
                        request: request, deadline: Date().addingTimeInterval(Double(limits.timeoutMilliseconds) / 1_000))
                    let allowed = await self.onProviderToolApproval?(review) ?? false
                    try Task.checkCancellation()
                    try await self.requireCurrent(run: run)
                    return allowed
                },
                transport: transport,
                prepareStep: { [weak self] index in
                    guard let self, !self.invalidated, self.activeRun == run else { return .init(activeToolAliases: []) }
                    self.step = index
                    do {
                        try await self.requireCurrent(run: run)
                        let prepared = try await self.capabilities?.prepareStep(index, session: self.identity)
                        try await self.requireCurrent(run: run)
                        let scopedCatalog = self.currentCatalog ?? catalog
                        let known = Set(scopedCatalog.tools.map(\.route.alias))
                        let aliases = prepared?.activeAliases ?? scopedCatalog.tools.map(\.route.alias)
                        guard Set(aliases).isSubset(of: known) else { throw HanlinHostError.unknownTool }
                        return .init(activeToolAliases: aliases, loadedSkillIDs: prepared?.skillIDs ?? [],
                                     loadedSkillInstructions: prepared?.instructions ?? [],
                                     visibleSchemaBytes: try scopedCatalog.tools.filter { aliases.contains($0.route.alias) }
                                        .reduce(0) { try $0 + $1.descriptor.inputSchema.canonicalJSONData().count })
                    } catch {
                        if self.activeRun == run { self.preparationError = (error as? HanlinHostError) ?? .denied }
                        return .init(activeToolAliases: [])
                    }
                })
            try requireActive(run: run)

            return AsyncThrowingStream { continuation in
                let task = Task { @MainActor in
                    var eventSequence: UInt64 = 0
                    var streamStep = 0
                    var wasCancelled = false
                    await self.diagnostics?.record(.init(kind: .runStarted, runID: run))
                    do {
                        for try await event in source {
                            try await self.requireCurrent(run: run)
                            if let error = self.preparationError { throw error }
                            switch event {
                            case .stepStarted(let index, _): streamStep = index
                            case .textDelta(let text): try self.append(.text(text), run: run, stepOverride: streamStep)
                            case .reasoningDelta(let text): try self.append(.reasoning(text), run: run, stepOverride: streamStep)
                            case .finished(let reason, _): try self.append(.finished(reason: reason), run: run, stepOverride: streamStep)
                            case .structuredPart(let part):
                                try self.append(.structuredPart(part, context: self.identity.context), run: run, stepOverride: streamStep)
                                // Preserve partial interrupted output in the authoritative conversation path.
                                try await self.persist(model: modelReference)
                                try await self.requireCurrent(run: run)
                                if case .a2uiMessage = part.payload {
                                    self.observedInteractionOrigins.insert(.init(session: self.identity, runID: run,
                                        messageID: part.messageID, partID: part.partID))
                                }
                            case .cancelled:
                                wasCancelled = true
                                try self.append(.cancelled, run: run, stepOverride: streamStep)
                            default: break
                            }
                            try self.requireActive(run: run)
                            continuation.yield(.init(session: self.identity, interactionOrigin: interactionOrigin,
                                runID: run, step: streamStep, sequence: eventSequence, event: event))
                            eventSequence += 1
                        }
                        try await self.persist(model: modelReference)
                        try self.requireActive(run: run)
                        self.activeRun = nil
                        self.producerTask = nil
                        if wasCancelled {
                            self.revokeInteractions(run: run)
                            if let interactionOrigin { self.revokeInteraction(interactionOrigin) }
                        } else {
                            self.completedLiveRuns.insert(run)
                        }
                        self.onRunCompletion?(.init(session: self.identity, runID: run,
                            outcome: wasCancelled ? .cancelled : .completed))
                        await self.diagnostics?.record(.init(kind: .runFinished, runID: run))
                        continuation.finish()
                    } catch {
                        self.revokeInteractions(run: run)
                        if let interactionOrigin { self.revokeInteraction(interactionOrigin) }
                        let safe = (error as? HanlinHostError) ?? (Task.isCancelled ? .cancelled : .unsupportedProviderCapability)
                        self.onRunCompletion?(.init(session: self.identity, runID: run, outcome: .failed(safe)))
                        do { try self.append(.failed(code: safe), run: run); try await self.persist(model: modelReference) }
                        catch { self.activeRun = nil; self.producerTask = nil; continuation.finish(throwing: error); return }
                        self.activeRun = nil
                        self.producerTask = nil
                        await self.diagnostics?.record(.init(kind: .hostFailure, runID: run))
                        continuation.finish(throwing: error)
                    }
                }
                self.producerTask = task
                continuation.onTermination = { termination in
                    if case .cancelled = termination {
                        task.cancel()
                        Task { @MainActor in await self.invalidate() }
                    }
                }
            }
        } catch {
            activeRun = nil
            throw error
        }
    }

    /// Auth/Space/scene invalidation is terminal for this presentation identity.
    public func invalidate() async {
        let firstInvalidation = !invalidated
        invalidated = true
        interactionOrigins.removeAll()
        observedInteractionOrigins.removeAll()
        completedLiveRuns.removeAll()
        producerTask?.cancel()
        if firstInvalidation { onSessionInvalidated?(identity) }
        await dispatcher.invalidate(identity)
    }

    /// Surface deletion/replacement is explicit host lifecycle, independent of sheet visibility.
    public func revokeInteraction(_ origin: HanlinHostInteractionOrigin) {
        interactionOrigins.remove(origin)
        observedInteractionOrigins.remove(origin)
    }

    /// Called by the trusted presentation adapter AFTER official A2UI admission. Merely receiving
    /// model bytes does not enable actions. The host still owns live action/policy validation.
    public func admitInteraction(_ origin: HanlinHostInteractionOrigin) throws {
        guard !invalidated, origin.session == identity, observedInteractionOrigins.contains(origin) else { throw HanlinHostError.staleContext }
        interactionOrigins.insert(origin)
    }

    /// The trusted host binds a marked inline block to its original live response
    /// row. Unlike restored JSON, only an actually completed run of THIS session
    /// can supply this origin. Admission is provenance, never tool permission.
    public func admitInlinePresentation(_ origin: HanlinHostInteractionOrigin) throws {
        guard !invalidated, origin.session == identity, completedLiveRuns.contains(origin.runID),
              entries.contains(where: { entry in
                  guard entry.runID == origin.runID else { return false }
                  if case .text = entry.payload { return true }
                  if case .structuredPart = entry.payload { return true }
                  return false
              }) else { throw HanlinHostError.staleContext }
        observedInteractionOrigins.insert(origin)
        interactionOrigins.insert(origin)
    }

    /// Query/Mutation uses the same catalog, original dispatcher, Host consent,
    /// pending-before-effect journal and ordered persistence as model tools.
    /// No second agent loop or permission broker is introduced.
    public func executePresentationTool(_ request: HanlinHostInteractionRequest,
                                        alias: String, argumentsJSON: String,
                                        presentationReference: String? = nil,
                                        onStarted: (@MainActor @Sendable (HanlinAgentEvent) throws -> Void)? = nil) async throws -> HanlinAISDKToolExecutionOutput {
        guard interactionRequests.insert(request.requestID).inserted else { throw HanlinHostError.duplicateInvocation }
        try await requireInteraction(request.origin)
        guard let model = record?.model else { throw HanlinHostError.staleContext }
        var pending = Set<String>()
        for entry in entries {
            switch entry.payload {
            case .toolCall(let id, _, _): pending.insert(entry.runID.uuidString + id)
            case .toolResult(let id, let result):
                if result.effectState != .uncertain { pending.remove(entry.runID.uuidString + id) }
            default: break
            }
        }
        guard pending.isEmpty else { throw HanlinHostError.unresolvedWrite }
        guard presentationReference.map({ !$0.isEmpty && $0.utf8.count <= 4096 }) ?? true else { throw HanlinHostError.invalidArguments }
        let run = UUID()
        activeRun = run; step = 0; preparationError = nil; persistenceTail = nil
        defer { if activeRun == run { activeRun = nil } }
        do {
            try await requireCurrent(run: run)
            let catalog = try await host.catalog(for: identity.context)
            try await requireCurrent(run: run)
            try catalog.validate()
            guard catalog.context == identity.context else { throw HanlinHostError.staleContext }
            currentCatalog = catalog
            guard let definition = try makeDefinitions(catalog: catalog, run: run, model: model).first(where: { $0.name == alias }) else {
                throw HanlinHostError.unknownTool
            }
            if let presentationReference { try append(.presentationReference(version: 1, opaqueReference: presentationReference), run: run) }
            try onStarted?(.init(session: identity, interactionOrigin: request.origin, runID: run,
                step: 0, sequence: 0, event: .runStarted))
            // The bridge has normalized JSON. Preserve the original input guard;
            // do not manufacture a provider-original provenance assertion.
            let result = try await definition.execute(argumentsJSON, request.requestID.uuidString)
            try await requireCurrent(run: run)
            activeRun = nil
            onRunCompletion?(.init(session: identity, runID: run, outcome: .completed))
            return result
        } catch {
            let safe = (error as? HanlinHostError) ?? (Task.isCancelled ? .cancelled : .denied)
            onRunCompletion?(.init(session: identity, runID: run, outcome: .failed(safe)))
            if !invalidated { try append(.failed(code: safe), run: run); try await persist(model: model) }
            throw error
        }
    }

    /// The original Host receipt must already have passed the ordered durable writer.
    /// Called only by the trusted presentation adapter after official tool-Surface admission.
    /// Historical metadata, forged outcomes and another invocation cannot authorize a control.
    public func admitHostResultInteraction(_ event: HanlinHostResultEvent, messageID: UUID) throws -> HanlinHostInteractionOrigin {
        guard !invalidated, event.call.session == identity,
              event.result.context == identity.context,
              event.result.effectState == .confirmedCommitted || event.result.effectState == .confirmedNoEffect,
              case .completed = event.result.result.outcome,
              record?.entries.contains(where: {
                  if case .hostResultIdentity(let id, let call) = $0.payload { return id == event.resultID && call == event.call }
                  return false
              }) == true,
              record?.entries.contains(where: {
                  if case .toolResult(let callID, let result) = $0.payload {
                      return $0.runID == event.call.runID && callID == event.call.providerCallID && result == event.result.metadataReceipt()
                  }
                  return false
              }) == true else { throw HanlinHostError.staleContext }
        let origin = HanlinHostInteractionOrigin(session: identity, runID: event.call.runID,
            messageID: messageID, partID: event.resultID)
        observedInteractionOrigins.insert(origin)
        interactionOrigins.insert(origin)
        return origin
    }

    /// Successful producer EOF keeps admitted controls live. A user action obtains current host
    /// admission and starts a NEW turn through the same stream/engine, retaining original provenance.
    public func continueInteraction(_ request: HanlinHostInteractionRequest, messages: [HanlinAISDKMessage],
                                    modelReference: HanlinModelReference, maxSteps: Int? = nil,
                                    systemPrompt: String? = nil,
                                    structuredResponse: HanlinNativeStructuredResponse? = nil,
                                    presentationReference: String? = nil,
                                    transport: HanlinAISDKTurnTransport? = nil) async throws -> AsyncThrowingStream<HanlinAgentEvent, Error> {
        guard let source = interactions else { throw HanlinHostError.unsupportedProviderCapability }
        guard interactionRequests.insert(request.requestID).inserted else { throw HanlinHostError.duplicateInvocation }
        try await requireInteraction(request.origin)
        guard !request.actionID.isEmpty, request.actionID.utf8.count <= 512,
              try request.arguments.canonicalJSONData().count <= 1_048_576 else { throw HanlinHostError.invalidArguments }
        let prepared = try await source.prepareInteraction(request)
        try await requireInteraction(request.origin)
        guard !prepared.userMessage.isEmpty, prepared.userMessage.utf8.count <= 1_048_576 else { throw HanlinHostError.invalidArguments }
        return try await startStream(messages: messages + [.init(role: .user, text: prepared.userMessage)], systemPrompt: systemPrompt,
            modelReference: modelReference, maxSteps: maxSteps, interactionOrigin: request.origin,
            structuredResponse: structuredResponse, presentationReference: presentationReference, transport: transport)
    }

    /// Associates one bounded opaque host reference with an ACTUAL pending call before an
    /// external dispatch. Uses this Session's existing ordered CAS writer; no competing store save.
    /// The reference is display/correlation metadata, never permission or executable input.
    public func associateHostInvocation(_ invocation: HanlinHostInvocation, opaqueReference: String) async throws {
        guard invocation.session == identity, !opaqueReference.isEmpty, opaqueReference.utf8.count <= 4096,
              let model = record?.model else { throw HanlinHostError.invalidArguments }
        try await requireCurrent(run: invocation.runID)
        guard await dispatcher.isReserved(invocation) else { throw HanlinHostError.resultMismatch }
        try await requireCurrent(run: invocation.runID)
        guard entries.contains(where: {
            guard $0.runID == invocation.runID, $0.step == invocation.step,
                  case .toolCall(let providerID, let alias, _) = $0.payload else { return false }
            return providerID == invocation.providerCallID && alias == invocation.request.aliasUsed
        }) else { throw HanlinHostError.resultMismatch }
        if let original = associatedInvocations[invocation.request.id] {
            guard original.utf8.elementsEqual(opaqueReference.utf8) else { throw HanlinHostError.resultMismatch }
            try await persistenceTail?.value
        } else {
            associatedInvocations[invocation.request.id] = opaqueReference
            try append(.presentationReference(version: 1, opaqueReference: opaqueReference), run: invocation.runID,
                       stepOverride: invocation.step)
            try await persist(model: model)
        }
        try await requireCurrent(run: invocation.runID)
    }

    private func requireInteraction(_ origin: HanlinHostInteractionOrigin) async throws {
        try Task.checkCancellation()
        guard !invalidated, origin.session == identity, interactionOrigins.contains(origin) else { throw HanlinHostError.staleContext }
        guard activeRun == nil else { throw HanlinHostError.duplicateInvocation }
        let current = try await host.context(for: identity)
        try Task.checkCancellation()
        guard !invalidated, origin.session == identity, interactionOrigins.contains(origin), current == identity.context else { throw HanlinHostError.staleContext }
        guard activeRun == nil else { throw HanlinHostError.duplicateInvocation }
    }

    private func revokeInteractions(run: UUID) {
        interactionOrigins = interactionOrigins.filter { $0.runID != run }
        observedInteractionOrigins = observedInteractionOrigins.filter { $0.runID != run }
    }

    private func makeDefinitions(catalog: HanlinHostCatalog, run: UUID, model: HanlinModelReference) throws -> [HanlinAISDKToolDefinition] {
        try catalog.tools.map { tool in
            let execution: HanlinAISDKToolDefinition.ProvenanceExecutor = { [weak self] arguments, providerID, provenance in
                guard let self else { throw HanlinHostError.cancelled }
                try self.requireActive(run: run)
                let invocationStep = self.step
                if let error = self.preparationError { throw error }
                return try await HanlinModelToolInputGuard.withValidatedArguments(arguments, originalInputVerified: provenance == .acceptedOriginal) { _ -> HanlinAISDKToolExecutionOutput in
                    // Invalid/unsupported input is rejected before pending entry or host effect.
                    // Never persist raw arguments; original input remains transient.
                    try self.append(.toolCall(providerCallID: providerID, alias: tool.route.alias, arguments: .null), run: run)
                    // Durable pending entry BEFORE dispatch; interruption must not silently replay.
                    try await self.persist(model: model)
                    try self.requireActive(run: run)
                    let hostEvent = try await self.dispatcher.dispatchEvent(alias: tool.route.alias, argumentsJSON: arguments,
                        providerCallID: providerID, runID: run, step: invocationStep, session: self.identity, catalog: catalog,
                        expectedRevision: tool.writeGuarantee == .atomicRevisionMutation ? self.identity.context.sourceRevision : nil,
                        limits: HanlinToolInvocationLimits(), progress: { event in
                            await self.deliverProgress(event, run: run, providerCallID: providerID,
                                                       step: invocationStep, logicalToolID: tool.route.logicalToolID)
                        })
                    let result = hostEvent.result
                    guard self.activeRun == run else { throw HanlinHostError.staleContext }
                    try self.append(.hostResultIdentity(resultID: hostEvent.resultID, call: hostEvent.call),
                                    run: run, stepOverride: hostEvent.call.step)
                    try self.append(.toolResult(providerCallID: providerID, result: result.metadataReceipt()),
                                    run: run, stepOverride: hostEvent.call.step)
                    try await self.persist(model: model)
                    try await self.requireCurrent(run: run)
                    self.onHostResult?(hostEvent)
                    if result.effectState == .uncertain { throw HanlinHostError.unresolvedWrite }
                    let encoded = try JSONEncoder().encode(result)
                    guard encoded.count <= 1_048_576 else { throw HanlinHostError.outputLimitExceeded }
                    switch result.result.outcome {
                    case .completed(let content):
                        let text = try content.map { item -> String in
                            switch item {
                            case .text(let text): return text
                            case .structured(let value): return String(decoding: try value.canonicalJSONData(), as: UTF8.self)
                            case .attachment(let handle, let mediaType, let byteCount):
                                return "Scoped attachment reference: \(handle) (\(mediaType), \(byteCount) bytes)"
                            case .resourceLink(let uri, let title): return "\(title ?? "Host resource"): \(uri)"
                            }
                        }.joined(separator: "\n")
                        return .init(modelText: text, resultReference: result.reconciliationReference)
                    case .failed(let failure):
                        // The host explicitly sanctions this transient model feedback. The
                        // persisted metadataReceipt still redacts it and the business payload.
                        return .init(modelText: failure.userMessage, resultReference: result.reconciliationReference, isError: true)
                    default:
                        return .init(modelText: "The host did not authorize or complete this operation.", resultReference: result.reconciliationReference, isError: true)
                    }
                }
            }
            return HanlinAISDKToolDefinition(name: tool.route.alias,
                description: tool.descriptor.summary.preferredValue(forLocale: identity.context.localeIdentifier),
                inputSchemaData: try HanlinHostSchemaValidation.providerSchema(
                    tool.originalInputSchemaJSON ?? tool.descriptor.inputSchema.canonicalJSONData()),
                execute: { arguments, id in try await execution(arguments, id, .normalized) },
                executeWithInputProvenance: execution)
        }
    }

    private func deliverProgress(_ event: HanlinToolProgressEvent, run: UUID, providerCallID: String,
                                 step: Int, logicalToolID: HanlinLogicalToolID) async {
        do { try await requireCurrent(run: run) } catch { return }
        let call = HanlinHostCallIdentity(session: identity, runID: run, step: step,
            providerCallID: providerCallID, invocationID: event.invocationID, logicalToolID: logicalToolID)
        guard let wrapped = try? HanlinHostProgressEvent(call: call, progress: event) else { return }
        onHostProgress?(wrapped)
    }

    private func requireActive(run: UUID) throws {
        try Task.checkCancellation()
        guard !invalidated, activeRun == run else { throw HanlinHostError.cancelled }
    }

    /// MainActor invalidation/run replacement may occur while the host returns an old context.
    private func requireCurrent(run: UUID) async throws {
        try requireActive(run: run)
        let context = try await host.context(for: identity)
        try requireActive(run: run)
        guard context == identity.context else { throw HanlinHostError.staleContext }
    }

    private func append(_ payload: HanlinTranscriptPayload, run: UUID, stepOverride: Int? = nil) throws {
        guard sequence < UInt64.max else { throw HanlinHostError.storageLimitExceeded }
        entries.append(.init(runID: run, step: stepOverride ?? step, sequence: sequence, payload: payload))
        sequence += 1
    }

    private func persist(model: HanlinModelReference) async throws {
        // Tool callbacks can interleave across actor awaits. Serialize CAS writes without losing
        // a later callback's transcript; a failed save poisons this run rather than permitting dispatch.
        let previous = persistenceTail
        let snapshot = entries
        let task = Task { @MainActor in
            try await previous?.value
            guard self.record?.revision != UInt64.max else { throw HanlinHostError.storageLimitExceeded }
            let next = HanlinConversationRecord(namespace: self.identity.context.namespace, conversationID: self.identity.conversationID,
                revision: self.record.map { $0.revision + 1 } ?? 0, model: model, draft: self.record?.draft ?? "", entries: snapshot)
            try await self.store.save(next, replacing: self.record?.revision)
            self.record = next
        }
        persistenceTail = task
        try await task.value
    }
}
