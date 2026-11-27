import Foundation
import HanlinHostContracts
import HanlinPlatformContracts

/// Adapts scoped host authority to the existing engine; contains no model or permission loop.
public actor HanlinHostDispatcher {
    private struct CallKey: Hashable { let session: UUID; let run: UUID; let providerID: String }
    private struct CallState {
        let invocationID: HanlinToolInvocationID
        let identity: HanlinHostCallIdentity
        let resultID: UUID
        let alias: String
        let arguments: Data
        var result: HanlinHostExecutionResult?
        var progressSequence: UInt64?
    }
    private let host: any HanlinHostIntegration
    private var calls: [CallKey: CallState] = [:]
    private var revokedSessions = Set<UUID>()
    private struct RunKey: Hashable { let session: UUID; let run: UUID }
    private var cancelledRuns = Set<RunKey>()
    private var executingCalls = Set<CallKey>()
    private var drainWaiters: [RunKey: [CheckedContinuation<Void, Never>]] = [:]
    private var hostDrainTasks: [RunKey: Task<[HanlinHostResultEvent], Never>] = [:]
    private struct NavigationKey: Hashable { let session: UUID; let request: UUID }
    private struct NavigationState {
        let session: HanlinHostSession
        let destination: HanlinHostDestination
        var receipt: HanlinHostNavigationReceipt?
    }
    private var navigationRequests: [NavigationKey: NavigationState] = [:]
    private var activeNavigationBySession: [UUID: NavigationKey] = [:]
    private var retiredSessions = Set<UUID>()

    public init(host: any HanlinHostIntegration) { self.host = host }

    public func dispatch(alias: String, argumentsJSON: String, providerCallID: String, runID: UUID,
                         step: Int, session: HanlinHostSession, catalog: HanlinHostCatalog,
                         expectedRevision: String? = nil,
                         limits: HanlinToolInvocationLimits,
                         progress: @escaping @Sendable (HanlinToolProgressEvent) async -> Void = { _ in }) async throws -> HanlinHostExecutionResult {
        try Task.checkCancellation()
        try requireRun(session, runID: runID)
        guard host.apiVersion.major == 1 else { throw HanlinHostError.unsupportedVersion }
        try catalog.validate()
        guard catalog.context == session.context else { throw HanlinHostError.staleContext }
        try await requireCurrent(session)
        try requireRun(session, runID: runID)
        guard let tool = catalog.tools.first(where: { $0.route.alias == alias }) else { throw HanlinHostError.unknownTool }
        guard tool.writeGuarantee != .hostManagedMutation || host.apiVersion.minor >= 1 else {
            throw HanlinHostError.unsupportedVersion
        }
        if expectedRevision != nil && tool.writeGuarantee != .atomicRevisionMutation {
            throw HanlinHostError.unsupportedConditionalWrite
        }
        if tool.writeGuarantee == .atomicRevisionMutation {
            guard expectedRevision != nil, session.context.matchesRevision(expectedRevision) else { throw HanlinHostError.staleContext }
        }
        guard !providerCallID.isEmpty, providerCallID.utf8.count <= 512, step >= 0,
              argumentsJSON.utf8.count <= 1_048_576 else { throw HanlinHostError.invalidArguments }
        let bytes = Data(argumentsJSON.utf8)
        let arguments = try HanlinJSONValue.decodeCanonicalJSON(bytes)
        let key = CallKey(session: session.id, run: runID, providerID: providerCallID)
        if let old = calls[key] {
            guard old.alias == alias, old.arguments == bytes, old.identity.session == session,
                  old.identity.step == step else { throw HanlinHostError.idempotencyConflict }
            guard let result = old.result else { throw HanlinHostError.duplicateInvocation }
            guard try JSONEncoder().encode(result).count <= limits.maximumOutputBytes else { throw HanlinHostError.outputLimitExceeded }
            try Task.checkCancellation()
            try requireRun(session, runID: runID)
            guard sessionIsAvailable(session) else { throw HanlinHostError.staleContext }
            return result
        }
        // The provider ID is opaque. A fresh UUID maps it to a valid canonical invocation ID.
        let invocationID = try HanlinToolInvocationID(validating: UUID().uuidString.lowercased())
        let request = HanlinToolInvocationRequest(
            id: invocationID, logicalToolID: tool.route.logicalToolID, aliasUsed: alias,
            descriptorRevision: tool.route.descriptorRevision, routingTableRevision: catalog.revision,
            arguments: arguments, origin: .assistantModel,
            idempotencyKey: invocationID.rawValue, deadline: Date().addingTimeInterval(Double(limits.timeoutMilliseconds) / 1_000), limits: limits
        )
        let resultID = UUID()
        let invocation = HanlinHostInvocation(request: request, session: session, runID: runID, step: step,
                                              providerCallID: providerCallID, writeGuarantee: tool.writeGuarantee, expectedRevision: expectedRevision,
                                              originalArgumentsJSON: bytes, resultID: resultID)
        // Revalidate after all suspensions and reserve before host dispatch. Host still owns schema,
        // durable idempotency, permission/confirmation and the final native mutation boundary.
        try Task.checkCancellation()
        try requireRun(session, runID: runID)
        guard sessionIsAvailable(session) else { throw HanlinHostError.staleContext }
        calls[key] = CallState(invocationID: invocationID,
            identity: .init(session: session, runID: runID, step: step, providerCallID: providerCallID,
                            invocationID: invocationID, logicalToolID: tool.route.logicalToolID),
            resultID: resultID, alias: alias, arguments: bytes)
        executingCalls.insert(key)
        defer { finishExecution(key) }
        let result: HanlinHostExecutionResult
        do {
            result = try await host.execute(invocation) { event in
                await self.forward(event, key: key, session: session, to: progress)
            }
        } catch {
            // Throwing/cancellation after entering host dispatch cannot prove no write occurred.
            let uncertain = tool.writeGuarantee != .readOnly
            result = HanlinHostExecutionResult(
                result: .init(invocationID: invocationID, logicalToolID: tool.route.logicalToolID,
                              outcome: .failed(.init(code: .nativeFailure, userMessage: uncertain ? "The write outcome is uncertain. Do not retry automatically." : "The host operation failed.")), completedAt: .now),
                effectState: uncertain ? .uncertain : .confirmedNoEffect, context: session.context,
                reconciliationReference: uncertain ? invocationID.rawValue : nil
            )
        }
        // Retain the receipt BEFORE freshness/cancellation checks suppress delivery. Host must retain
        // a durable journal if an operation can survive this SDK session/process.
        guard result.result.invocationID == invocationID, result.result.logicalToolID == tool.route.logicalToolID,
              result.context == session.context else {
            // Keep reservation unresolved: never execute again after a malformed post-dispatch reply.
            throw HanlinHostError.resultMismatch
        }
        calls[key]?.result = result
        guard try JSONEncoder().encode(result).count <= limits.maximumOutputBytes else {
            throw HanlinHostError.outputLimitExceeded
        }
        try await requireCurrent(session)
        try requireRun(session, runID: runID)
        return result
    }

    /// Same dispatch path with complete call/result correlation for presentation consumers.
    public func dispatchEvent(alias: String, argumentsJSON: String, providerCallID: String, runID: UUID,
                              step: Int, session: HanlinHostSession, catalog: HanlinHostCatalog,
                              expectedRevision: String? = nil, limits: HanlinToolInvocationLimits,
                              progress: @escaping @Sendable (HanlinToolProgressEvent) async -> Void = { _ in }) async throws -> HanlinHostResultEvent {
        let result = try await dispatch(alias: alias, argumentsJSON: argumentsJSON, providerCallID: providerCallID,
            runID: runID, step: step, session: session, catalog: catalog, expectedRevision: expectedRevision,
            limits: limits, progress: progress)
        try Task.checkCancellation()
        try requireRun(session, runID: runID)
        guard sessionIsAvailable(session),
              let state = calls[CallKey(session: session.id, run: runID, providerID: providerCallID)] else {
            throw HanlinHostError.staleContext
        }
        return try .init(resultID: state.resultID, call: state.identity, result: result)
    }

    /// Checks an actual unresolved reservation before a Host associates durable metadata with it.
    /// The result identity and original bytes must be the ones captured before Host entry.
    public func isReserved(_ invocation: HanlinHostInvocation) -> Bool {
        guard !cancelledRuns.contains(.init(session: invocation.session.id, run: invocation.runID)),
              sessionIsAvailable(invocation.session),
              let state = calls[CallKey(session: invocation.session.id, run: invocation.runID, providerID: invocation.providerCallID)] else { return false }
        return state.result == nil && state.invocationID == invocation.request.id && state.resultID == invocation.resultID
            && state.identity.session == invocation.session && state.identity.runID == invocation.runID
            && state.identity.step == invocation.step && state.identity.logicalToolID == invocation.request.logicalToolID
            && state.alias == invocation.request.aliasUsed && state.arguments == invocation.originalArgumentsJSON
    }

    /// Reconciliation is scoped to the ORIGINAL context, including after a caller stops waiting.
    public func receipts(for session: HanlinHostSession) -> [HanlinHostExecutionResult] {
        calls.filter { $0.key.session == session.id }.values.compactMap(\.result).filter { $0.context == session.context }
    }

    /// Fence the exact run before any await, join original host calls, then join
    /// native workers that can outlive uncertain receipts. Historical metadata
    /// is retained even when current-account authority has already disappeared.
    public func cancelAndDrain(runID: UUID, session: HanlinHostSession) async -> [HanlinHostResultEvent] {
        let run = RunKey(session: session.id, run: runID)
        if cancelledRuns.insert(run).inserted {
            let reserved = calls.filter { $0.key.session == session.id && $0.key.run == runID }
            for state in reserved.values where state.result == nil {
                await host.cancel(state.invocationID)
            }
        }
        return await drainOriginalWorkers(runID: runID, session: session)
    }

    /// A confirmed receipt can precede release of the native worker's lease.
    /// EOF and explicit Stop share one original-worker join per run; normal EOF
    /// does not cancel the host or turn successful completion into cancellation.
    public func drainOriginalWorkers(runID: UUID, session: HanlinHostSession) async -> [HanlinHostResultEvent] {
        let run = RunKey(session: session.id, run: runID)
        if let task = hostDrainTasks[run] { return await task.value }
        let task = Task { await self.joinOriginalWorkers(runID: runID, session: session) }
        hostDrainTasks[run] = task
        return await task.value
    }

    private func joinOriginalWorkers(runID: UUID, session: HanlinHostSession) async -> [HanlinHostResultEvent] {
        let run = RunKey(session: session.id, run: runID)
        if executingCalls.contains(where: { $0.session == session.id && $0.run == runID }) {
            await withCheckedContinuation { drainWaiters[run, default: []].append($0) }
        }
        let reserved = calls.filter { $0.key.session == session.id && $0.key.run == runID }
        if let drain = host as? any HanlinHostCancellationDrainSource {
            for (key, state) in reserved {
                if let receipt = await drain.drainCancelledInvocation(state.invocationID),
                   receipt.result.invocationID == state.invocationID,
                   receipt.result.logicalToolID == state.identity.logicalToolID,
                   receipt.context == state.identity.session.context {
                    calls[key]?.result = receipt.metadataReceipt()
                }
            }
        }
        return calls.filter { $0.key.session == session.id && $0.key.run == runID }
            .values.compactMap { state in
                guard state.identity.session == session, let result = state.result,
                      result.context == session.context else { return nil }
                return try? .init(resultID: state.resultID, call: state.identity, result: result.metadataReceipt())
            }
    }

    private func requireRun(_ session: HanlinHostSession, runID: UUID) throws {
        guard !cancelledRuns.contains(.init(session: session.id, run: runID)) else {
            throw HanlinHostError.cancelled
        }
    }

    private func finishExecution(_ key: CallKey) {
        executingCalls.remove(key)
        let run = RunKey(session: key.session, run: key.run)
        guard !executingCalls.contains(where: { $0.session == key.session && $0.run == key.run }) else { return }
        for waiter in drainWaiters.removeValue(forKey: run) ?? [] { waiter.resume() }
    }

    public func invalidate(_ session: HanlinHostSession) async {
        revokedSessions.insert(session.id)
        let ids = calls.filter { $0.key.session == session.id && $0.value.result == nil }.values.map(\.invocationID)
        for id in ids { await host.cancel(id) }
    }

    public func open(_ destination: HanlinHostDestination, session: HanlinHostSession) async throws -> HanlinHostNavigationResult {
        try Task.checkCancellation()
        guard host.apiVersion.major == 1 else { throw HanlinHostError.unsupportedVersion }
        guard destination.context == session.context else { throw HanlinHostError.staleContext }
        try await requireCurrent(session)
        let result = try await host.open(destination)
        try result.validate(for: destination)
        try await requireCurrent(session)
        return result
    }

    /// Open through the original host's explicit context-transition capability. Old
    /// contexts never become fresh by rewriting a reply or skipping a post-await check.
    public func openWithContextTransition(_ destination: HanlinHostDestination,
                                          session: HanlinHostSession) async throws -> HanlinHostNavigationReceipt {
        try Task.checkCancellation()
        guard host.apiVersion.major == 1, host.apiVersion.minor >= 2,
              let transitionHost = host as? any HanlinHostNavigationTransitionSource else {
            throw HanlinHostError.unsupportedVersion
        }
        guard destination.context == session.context else { throw HanlinHostError.staleContext }
        try await requireCurrent(session)
        guard sessionIsAvailable(session) else { throw HanlinHostError.staleContext }
        let key = NavigationKey(session: session.id, request: destination.requestID)
        if let old = navigationRequests[key] {
            guard old.session == session, old.destination == destination,
                  old.destination.objectReference.utf8.elementsEqual(destination.objectReference.utf8),
                  old.destination.blockReference.map({ Data($0.utf8) }) == destination.blockReference.map({ Data($0.utf8) }) else {
                throw HanlinHostError.idempotencyConflict
            }
            // Even a queued/uncertain request must be reconciled by its original host,
            // not entered a second time because the caller did not receive an ACK.
            throw HanlinHostError.duplicateInvocation
        }
        navigationRequests[key] = .init(session: session, destination: destination)
        activeNavigationBySession[session.id] = key
        defer { activeNavigationBySession[session.id] = nil }
        do {
            let receipt = try await transitionHost.openWithContextTransition(destination, session: session)
            try receipt.validate(for: destination, session: session)
            // Preserve a correctly correlated effect receipt before cancellation or
            // authority changes suppress its delivery, just as tool dispatch does.
            navigationRequests[key]?.receipt = receipt
            try Task.checkCancellation()
            guard sessionIsAvailable(session, allowingNavigation: key) else { throw HanlinHostError.staleContext }
            let next = receipt.successorSession ?? session
            try await requireCurrent(next, allowingNavigation: key)
            // Checking the successor alone cannot notice revocation of the origin
            // while the host context callback was suspended.
            try Task.checkCancellation()
            guard sessionIsAvailable(session, allowingNavigation: key) else { throw HanlinHostError.staleContext }
            if receipt.successorSession != nil { retiredSessions.insert(session.id) }
            return receipt
        } catch {
            // Host entry may already have changed the native scene. Preserve the
            // reservation and retire this identity; only the host can issue a fresh
            // session or reconcile the original request. Never silently repeat it.
            retiredSessions.insert(session.id)
            if let successor = navigationRequests[key]?.receipt?.successorSession {
                retiredSessions.insert(successor.id)
            }
            throw error
        }
    }

    /// Correlated historical receipts, not proof that their successor is still current.
    public func navigationReceipts(for session: HanlinHostSession) -> [HanlinHostNavigationReceipt] {
        navigationRequests.values.filter { $0.session == session }.compactMap(\.receipt)
    }

    private func sessionIsAvailable(_ session: HanlinHostSession,
                                    allowingNavigation: NavigationKey? = nil) -> Bool {
        !revokedSessions.contains(session.id) && !retiredSessions.contains(session.id)
            && (activeNavigationBySession[session.id] == nil
                || activeNavigationBySession[session.id] == allowingNavigation)
    }

    /// The host may suspend with a captured matching context. Actor revocation and task
    /// cancellation must both be checked AFTER that await, before any dispatch or delivery.
    private func requireCurrent(_ session: HanlinHostSession, allowingNavigation: NavigationKey? = nil) async throws {
        try Task.checkCancellation()
        guard sessionIsAvailable(session, allowingNavigation: allowingNavigation) else { throw HanlinHostError.staleContext }
        let current = try await host.context(for: session)
        try Task.checkCancellation()
        guard sessionIsAvailable(session, allowingNavigation: allowingNavigation), current == session.context else { throw HanlinHostError.staleContext }
    }

    private func forward(_ event: HanlinToolProgressEvent, key: CallKey, session: HanlinHostSession,
                         to sink: @escaping @Sendable (HanlinToolProgressEvent) async -> Void) async {
        guard !Task.isCancelled, !cancelledRuns.contains(.init(session: key.session, run: key.run)),
              sessionIsAvailable(session), let state = calls[key], state.result == nil,
              state.invocationID == event.invocationID,
              state.progressSequence.map({ event.sequence > $0 }) ?? true,
              (event.message?.utf8.count ?? 0) <= 4_096,
              let current = try? await host.context(for: session), current == session.context,
              !Task.isCancelled, !cancelledRuns.contains(.init(session: key.session, run: key.run)),
              sessionIsAvailable(session), calls[key]?.result == nil,
              calls[key]?.progressSequence.map({ event.sequence > $0 }) ?? true else { return }
        calls[key]?.progressSequence = event.sequence
        await sink(event)
    }
}
