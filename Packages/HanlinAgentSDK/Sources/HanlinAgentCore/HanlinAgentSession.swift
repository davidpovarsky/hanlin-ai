import Foundation
import HanlinChatCore
import HanlinHostContracts
import HanlinPlatformContracts

public struct HanlinAgentEvent: Sendable {
    public let runID: UUID
    public let step: Int
    public let sequence: UInt64
    public let event: HanlinAISDKStreamEvent
}

/// A DI/persistence facade over ONE HanlinAISDKAgentEngine. No app singleton, SwiftData or renderer.
@MainActor
public final class HanlinAgentSession {
    public let identity: HanlinHostSession
    public var onHostProgress: (@MainActor @Sendable (HanlinToolProgressEvent) -> Void)?
    public var onHostResult: (@MainActor @Sendable (_ providerCallID: String, _ result: HanlinHostExecutionResult) -> Void)?
    private let host: any HanlinHostIntegration
    private let engine: HanlinAISDKAgentEngine
    private let store: any HanlinConversationStore
    private let capabilities: (any HanlinHostCapabilitySource)?
    private let diagnostics: (any HanlinDiagnosticsSink)?
    public let dispatcher: HanlinHostDispatcher
    private var activeRun: UUID?
    private var record: HanlinConversationRecord?
    private var entries: [HanlinTranscriptEntry] = []
    private var sequence: UInt64 = 0
    private var step = 0
    private var preparationError: HanlinHostError?
    private var invalidated = false
    private var producerTask: Task<Void, Never>?
    private var persistenceTail: Task<Void, Error>?
    private var currentCatalog: HanlinHostCatalog?

    public init(identity: HanlinHostSession, host: any HanlinHostIntegration, engine: HanlinAISDKAgentEngine,
                store: any HanlinConversationStore, capabilities: (any HanlinHostCapabilitySource)? = nil,
                diagnostics: (any HanlinDiagnosticsSink)? = nil) {
        self.identity = identity; self.host = host; self.engine = engine; self.store = store
        self.capabilities = capabilities; self.diagnostics = diagnostics
        self.dispatcher = HanlinHostDispatcher(host: host)
    }

    public func stream(messages: [HanlinAISDKMessage], systemPrompt: String? = nil,
                       modelReference: HanlinModelReference, maxSteps: Int? = nil) async throws -> AsyncThrowingStream<HanlinAgentEvent, Error> {
        guard !invalidated else { throw HanlinHostError.staleContext }
        guard activeRun == nil else { throw HanlinHostError.duplicateInvocation }
        guard host.apiVersion.major == 1 else { throw HanlinHostError.unsupportedVersion }
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
                            case .cancelled: try self.append(.cancelled, run: run, stepOverride: streamStep)
                            default: break
                            }
                            try self.requireActive(run: run)
                            continuation.yield(.init(runID: run, step: streamStep, sequence: eventSequence, event: event))
                            eventSequence += 1
                        }
                        try await self.persist(model: modelReference)
                        try self.requireActive(run: run)
                        self.activeRun = nil
                        self.producerTask = nil
                        await self.diagnostics?.record(.init(kind: .runFinished, runID: run))
                        continuation.finish()
                    } catch {
                        let safe = (error as? HanlinHostError) ?? (Task.isCancelled ? .cancelled : .unsupportedProviderCapability)
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
        invalidated = true
        producerTask?.cancel()
        await dispatcher.invalidate(identity)
    }

    private func makeDefinitions(catalog: HanlinHostCatalog, run: UUID, model: HanlinModelReference) throws -> [HanlinAISDKToolDefinition] {
        try catalog.tools.map { tool in
            let execution: HanlinAISDKToolDefinition.ProvenanceExecutor = { [weak self] arguments, providerID, provenance in
                guard let self else { throw HanlinHostError.cancelled }
                try self.requireActive(run: run)
                if let error = self.preparationError { throw error }
                return try await HanlinModelToolInputGuard.withValidatedArguments(arguments, originalInputVerified: provenance == .acceptedOriginal) { _ -> HanlinAISDKToolExecutionOutput in
                    // Invalid/unsupported input is rejected before pending entry or host effect.
                    // Never persist raw arguments; original input remains transient.
                    try self.append(.toolCall(providerCallID: providerID, alias: tool.route.alias, arguments: .null), run: run)
                    // Durable pending entry BEFORE dispatch; interruption must not silently replay.
                    try await self.persist(model: model)
                    try self.requireActive(run: run)
                    let result = try await self.dispatcher.dispatch(alias: tool.route.alias, argumentsJSON: arguments,
                        providerCallID: providerID, runID: run, step: self.step, session: self.identity, catalog: catalog,
                        expectedRevision: tool.writeGuarantee == .atomicRevisionMutation ? self.identity.context.sourceRevision : nil,
                        limits: HanlinToolInvocationLimits(), progress: { event in
                            await self.deliverProgress(event, run: run)
                        })
                    guard self.activeRun == run else { throw HanlinHostError.staleContext }
                    try self.append(.toolResult(providerCallID: providerID, result: result.metadataReceipt()), run: run)
                    try await self.persist(model: model)
                    try await self.requireCurrent(run: run)
                    self.onHostResult?(providerID, result)
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
                    default:
                        return .init(modelText: "The host did not authorize or complete this operation.", resultReference: result.reconciliationReference, isError: true)
                    }
                }
            }
            return HanlinAISDKToolDefinition(name: tool.route.alias,
                description: tool.descriptor.summary.preferredValue(forLocale: identity.context.localeIdentifier),
                inputSchemaData: try tool.descriptor.inputSchema.canonicalJSONData(),
                execute: { arguments, id in try await execution(arguments, id, .normalized) },
                executeWithInputProvenance: execution)
        }
    }

    private func deliverProgress(_ event: HanlinToolProgressEvent, run: UUID) async {
        do { try await requireCurrent(run: run) } catch { return }
        onHostProgress?(event)
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
