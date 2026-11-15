import Foundation
import HanlinHostContracts
import HanlinPlatformContracts

/// Adapts scoped host authority to the existing engine; contains no model or permission loop.
public actor HanlinHostDispatcher {
    private struct CallKey: Hashable { let session: UUID; let run: UUID; let providerID: String }
    private struct CallState {
        let invocationID: HanlinToolInvocationID
        let alias: String
        let arguments: Data
        var result: HanlinHostExecutionResult?
        var progressSequence: UInt64?
    }
    private let host: any HanlinHostIntegration
    private var calls: [CallKey: CallState] = [:]
    private var revokedSessions = Set<UUID>()

    public init(host: any HanlinHostIntegration) { self.host = host }

    public func dispatch(alias: String, argumentsJSON: String, providerCallID: String, runID: UUID,
                         step: Int, session: HanlinHostSession, catalog: HanlinHostCatalog,
                         expectedRevision: String? = nil,
                         limits: HanlinToolInvocationLimits,
                         progress: @escaping @Sendable (HanlinToolProgressEvent) async -> Void = { _ in }) async throws -> HanlinHostExecutionResult {
        try Task.checkCancellation()
        guard host.apiVersion.major == 1 else { throw HanlinHostError.unsupportedVersion }
        try catalog.validate()
        guard catalog.context == session.context else { throw HanlinHostError.staleContext }
        try await requireCurrent(session)
        guard let tool = catalog.tools.first(where: { $0.route.alias == alias }) else { throw HanlinHostError.unknownTool }
        if expectedRevision != nil && tool.writeGuarantee != .atomicRevisionMutation {
            throw HanlinHostError.unsupportedConditionalWrite
        }
        if tool.writeGuarantee == .atomicRevisionMutation {
            guard expectedRevision != nil, session.context.matchesRevision(expectedRevision) else { throw HanlinHostError.staleContext }
        }
        guard !providerCallID.isEmpty, providerCallID.utf8.count <= 512, step >= 0,
              argumentsJSON.utf8.count <= 1_048_576 else { throw HanlinHostError.invalidArguments }
        let arguments = try HanlinJSONValue.decodeCanonicalJSON(Data(argumentsJSON.utf8))
        let bytes = try arguments.canonicalJSONData()
        let key = CallKey(session: session.id, run: runID, providerID: providerCallID)
        if let old = calls[key] {
            guard old.alias == alias, old.arguments == bytes else { throw HanlinHostError.idempotencyConflict }
            guard let result = old.result else { throw HanlinHostError.duplicateInvocation }
            guard try JSONEncoder().encode(result).count <= limits.maximumOutputBytes else { throw HanlinHostError.outputLimitExceeded }
            try Task.checkCancellation()
            guard !revokedSessions.contains(session.id) else { throw HanlinHostError.staleContext }
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
        let invocation = HanlinHostInvocation(request: request, session: session, runID: runID, step: step,
                                              providerCallID: providerCallID, writeGuarantee: tool.writeGuarantee, expectedRevision: expectedRevision)
        // Revalidate after all suspensions and reserve before host dispatch. Host still owns schema,
        // durable idempotency, permission/confirmation and the final native mutation boundary.
        try Task.checkCancellation()
        guard !revokedSessions.contains(session.id) else { throw HanlinHostError.staleContext }
        calls[key] = CallState(invocationID: invocationID, alias: alias, arguments: bytes)
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
        return result
    }

    /// Reconciliation is scoped to the ORIGINAL context, including after a caller stops waiting.
    public func receipts(for session: HanlinHostSession) -> [HanlinHostExecutionResult] {
        calls.filter { $0.key.session == session.id }.values.compactMap(\.result).filter { $0.context == session.context }
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

    /// The host may suspend with a captured matching context. Actor revocation and task
    /// cancellation must both be checked AFTER that await, before any dispatch or delivery.
    private func requireCurrent(_ session: HanlinHostSession) async throws {
        try Task.checkCancellation()
        guard !revokedSessions.contains(session.id) else { throw HanlinHostError.staleContext }
        let current = try await host.context(for: session)
        try Task.checkCancellation()
        guard !revokedSessions.contains(session.id), current == session.context else { throw HanlinHostError.staleContext }
    }

    private func forward(_ event: HanlinToolProgressEvent, key: CallKey, session: HanlinHostSession,
                         to sink: @escaping @Sendable (HanlinToolProgressEvent) async -> Void) async {
        guard !Task.isCancelled, !revokedSessions.contains(session.id), let state = calls[key], state.result == nil,
              state.invocationID == event.invocationID,
              state.progressSequence.map({ event.sequence > $0 }) ?? true,
              (event.message?.utf8.count ?? 0) <= 4_096,
              let current = try? await host.context(for: session), current == session.context,
              !Task.isCancelled, !revokedSessions.contains(session.id), calls[key]?.result == nil,
              calls[key]?.progressSequence.map({ event.sequence > $0 }) ?? true else { return }
        calls[key]?.progressSequence = event.sequence
        await sink(event)
    }
}
