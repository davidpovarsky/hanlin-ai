import CryptoKit
import Foundation
import HanlinAgentCore
import HanlinHostContracts
import HanlinPlatformContracts
import HanlinProductSplit
import Observation
import SwiftData

/// Composition of the existing Session/row/Host receipt and Split mailbox. This is neither a
/// conversation store nor a grant registry. Only the existing immutable request reaches the UI.
@MainActor @Observable
final class HanlinAppSplitOriginCoordinator: HanlinSplitOriginalOrigin {
    static let shared = HanlinAppSplitOriginCoordinator()
    private(set) var acceptedOrigin: SplitBridgeRequest?
    private(set) var lastFailure: SplitBridgeFailure?
    @ObservationIgnored private var modelContext: ModelContext?
    @ObservationIgnored private var pending: [UUID: Pending] = [:]
    @ObservationIgnored private var sessions: [UUID: WeakSession] = [:]
    @ObservationIgnored private let makeMailbox: @MainActor () throws -> HanlinSplitMailbox
    @ObservationIgnored private let makeTransport: @MainActor () throws -> HanlinSplitForegroundTransport
    @ObservationIgnored private let targetContext: @MainActor (SplitBridgeRequest) async throws -> SplitReceiverContext

    init(modelContext: ModelContext? = nil) {
        self.modelContext = modelContext
        makeMailbox = { try HanlinSplitMailbox() }
        makeTransport = { try HanlinSplitForegroundTransport() }
        targetContext = { request in try await HanlinSplitLiveTarget.current(request).1 }
    }

    /// Uses the same actual leaf/store/coordinator in hosted controls; only OS open and current
    /// target authority are injectable. This does not substitute a Session or row callback.
    init(mailbox: HanlinSplitMailbox, openURL: @escaping @MainActor (URL) async -> Bool,
         targetContext: @escaping @MainActor (SplitBridgeRequest) async throws -> SplitReceiverContext) {
        makeMailbox = { mailbox }
        makeTransport = { HanlinSplitForegroundTransport(mailbox: mailbox, openURL: openURL) }
        self.targetContext = targetContext
    }

    private final class WeakSession {
        weak var value: HanlinAgentSession?
        init(_ value: HanlinAgentSession) { self.value = value }
    }
    private struct StoredOrigin: Codable {
        let requestID: UUID
        let requestDigest: String
        let call: HanlinHostCallIdentity
        let resultID: UUID
        let row: HanlinAppAgentRowReference
    }
    private final class Pending {
        let request: SplitBridgeRequest
        let origin: StoredOrigin
        let reference: String
        weak var host: HanlinAppHostIntegration?
        weak var session: HanlinAgentSession?
        var response: SplitBridgeReturn?
        var receipt: HanlinHostResultEvent?
        var waiter: CheckedContinuation<SplitBridgeReturn, Error>?
        var receiptWaiters: [CheckedContinuation<Void, Error>] = []
        var timer: Task<Void, Never>?
        var deliveryStarted = false
        var invalidated = false
        init(request: SplitBridgeRequest, origin: StoredOrigin, reference: String,
             host: HanlinAppHostIntegration, session: HanlinAgentSession) {
            self.request = request; self.origin = origin; self.reference = reference
            self.host = host; self.session = session
        }
    }

    func register(session: HanlinAgentSession, modelContext: ModelContext) throws {
        sessions = sessions.filter { $0.value.value != nil }
        guard sessions.count < 256 || sessions[session.identity.id] != nil else { throw HanlinHostError.storageLimitExceeded }
        if self.modelContext == nil { self.modelContext = modelContext }
        // Several scenes may own the same conversation. Retain ALL actual live Session writers,
        // not merely the most recently registered (possibly idle/failed) owner of that chat.
        sessions[session.identity.id] = WeakSession(session)
    }

    func hasRunningSession(for conversationID: UUID) -> Bool {
        sessions.values.contains { $0.value?.identity.conversationID == conversationID && $0.value?.isRunning == true }
    }

    /// The only AI dispatch entry. Identity/deadline/target generation are host-issued, not model input.
    func execute(_ invocation: HanlinHostInvocation, host: HanlinAppHostIntegration,
                 session: HanlinAgentSession, row: HanlinAppAgentRowReference) async throws -> HanlinHostExecutionResult {
        guard pending.count < 64, invocation.session.context.namespace.workspace == "swiftdata", invocation.session == session.identity,
              invocation.session.conversationID == session.identity.conversationID, row.rowID == row.messageID,
              let original = invocation.originalArgumentsJSON, let deadline = invocation.request.deadline,
              deadline > Date() else { throw SplitBridgeFailure.denied }
        _ = try await host.context(for: invocation.session)
        let plan = try HanlinHostSchemaValidation(schemaJSON: HanlinAppHostIntegration.splitSchema)
        try plan.validate(argumentsJSON: original)
        try HanlinHostSchemaValidation.requireSameValue(originalJSON: original,
            projectedJSON: invocation.request.arguments.canonicalJSONData())
        guard case .object(let input) = invocation.request.arguments,
              case .string(let target)? = input["target"], target == "hanlin.demo.swift-parity",
              case .string(let action)? = input["action"], action == "share.value", let payload = input["payload"] else {
            throw SplitBridgeFailure.unsupportedRoute
        }
        let mailbox = try makeMailbox()
        let targetID = try HanlinAppID(validating: target)
        let registration = try mailbox.registration(for: targetID)
        let now = Date(), expiry = min(deadline, now.addingTimeInterval(120))
        let request = SplitBridgeRequest(caller: try .init(validating: "hanlin.host"), target: targetID,
            installedPackage: registration.installedPackage,
            session: try .init(validating: invocation.session.id.uuidString.lowercased()),
            chat: invocation.session.conversationID, generation: registration.generation,
            action: try .init(validating: action), capability: try .init(validating: "inter-app.share"),
            issuedAt: now, expiresAt: expiry, payload: try HanlinValue(jsonValue: payload))
        let call = HanlinHostCallIdentity(session: invocation.session, runID: invocation.runID, step: invocation.step,
            providerCallID: invocation.providerCallID, invocationID: invocation.request.id,
            logicalToolID: invocation.request.logicalToolID)
        let origin = StoredOrigin(requestID: request.id, requestDigest: try Self.digest(request), call: call,
            resultID: invocation.resultID, row: row)
        try requireOriginalAssistant(origin)
        let reference = Self.originPrefix(request.id) + (try JSONEncoder().encode(origin)).base64EncodedString()
        guard reference.utf8.count <= 4096 else { throw SplitBridgeFailure.oversized }
        let item = Pending(request: request, origin: origin, reference: reference, host: host, session: session)
        pending[request.id] = item
        item.timer = Task { [weak self] in
            let seconds = max(0, request.expiresAt.timeIntervalSinceNow)
            do { try await Task.sleep(for: .seconds(seconds)) } catch { return }
            self?.invalidate(reference: request.id, reason: .timedOut)
        }
        do {
            // Association is committed by the existing ordered Session writer BEFORE dispatch.
            try await session.associateHostInvocation(invocation, opaqueReference: reference)
            try Task.checkCancellation()
            guard !item.invalidated else { throw SplitBridgeFailure.cancelled }
            _ = try await host.context(for: invocation.session)
            item.deliveryStarted = true
            try await makeTransport().dispatch(request, origin: self)
            try Task.checkCancellation()
            guard !item.invalidated else { throw SplitBridgeFailure.cancelled }
            let response = try await withTaskCancellationHandler(operation: {
                try Task.checkCancellation()
                guard !item.invalidated else { throw SplitBridgeFailure.cancelled }
                if let response = item.response { return response }
                return try await withCheckedThrowingContinuation { item.waiter = $0 }
            }, onCancel: { Task { @MainActor in self.invalidate(reference: request.id, reason: .cancelled) } })
            return try Self.result(response, origin: origin)
        } catch {
            // These failures are issued by original transport admission/OS-open rejection before
            // any receiver attempt. Cancellation/IO after possible dispatch remains uncertain.
            let knownAdmissionFailure: Bool
            switch error as? SplitBridgeFailure {
            case .denied?, .unsupportedRoute?, .staleGeneration?, .correlationMismatch?, .expired?,
                 .companionMissing?, .oversized?, .capacityExceeded?, .outOfOrder?: knownAdmissionFailure = true
            default: knownAdmissionFailure = false
            }
            let effect: HanlinHostEffectState = item.deliveryStarted && !knownAdmissionFailure ? .uncertain : .notDispatched
            invalidate(reference: request.id, reason: error as? SplitBridgeFailure ?? .transportUnavailable)
            return .init(result: .init(invocationID: call.invocationID, logicalToolID: call.logicalToolID,
                outcome: .failed(.init(code: effect == .uncertain ? .nativeFailure : .operationUnavailable,
                    userMessage: effect == .uncertain ? "The Mini App outcome is uncertain. Do not retry automatically." : "The Mini App was not dispatched.")),
                completedAt: .now), effectState: effect, context: call.session.context,
                reconciliationReference: Self.receiptReference(request.id))
        }
    }

    func currentContext(for request: SplitBridgeRequest) async throws -> SplitReceiverContext {
        try Task.checkCancellation()
        guard request.caller.rawValue == "hanlin.host", request.target.rawValue == "hanlin.demo.swift-parity",
              request.action.rawValue == "share.value", request.capability.rawValue == "inter-app.share",
              request.issuedAt <= Date(), request.expiresAt > Date(),
              request.expiresAt.timeIntervalSince(request.issuedAt) <= 120 else { throw SplitBridgeFailure.expired }
        if let item = pending[request.id] {
            guard !item.invalidated, item.request == request, let host = item.host, let session = item.session,
                  session.identity == item.origin.call.session else { throw SplitBridgeFailure.cancelled }
            _ = try await host.context(for: item.origin.call.session)
            try requireOriginalAssistant(item.origin)
            guard !item.invalidated else { throw SplitBridgeFailure.cancelled }
        } else { _ = try await coldOrigin(request) }
        let target = try await targetContext(request)
        try Task.checkCancellation()
        // Repeat original-origin checks after the actual target/authorization awaits.
        if let item = pending[request.id] {
            guard !item.invalidated, let host = item.host else { throw SplitBridgeFailure.cancelled }
            _ = try await host.context(for: item.origin.call.session)
            try requireOriginalAssistant(item.origin)
            guard !item.invalidated else { throw SplitBridgeFailure.cancelled }
        } else { _ = try await coldOrigin(request) }
        try target.validate(request)
        return target
    }

    /// Release Host completion FIRST, then await its real persisted-receipt callback. Holding
    /// Host execution until this callback would deadlock the existing model tool loop.
    func persistVerifiedResult(_ response: SplitBridgeReturn) async throws {
        if let item = pending[response.request.id] {
            guard !item.invalidated, item.request == response.request else { throw SplitBridgeFailure.cancelled }
            if let old = item.response { guard old == response else { throw SplitBridgeFailure.correlationMismatch } }
            else {
                item.response = response
                item.waiter?.resume(returning: response); item.waiter = nil
            }
            if item.receipt == nil {
                guard item.receiptWaiters.count < 4 else { throw SplitBridgeFailure.capacityExceeded }
                try await withCheckedThrowingContinuation { item.receiptWaiters.append($0) }
            }
            try Task.checkCancellation()
            guard !item.invalidated, item.receipt != nil else { throw SplitBridgeFailure.cancelled }
        } else {
            // Cold receipt only: no Session/engine/Host/grants are manufactured from stored metadata.
            let (origin, reference, store) = try await coldOrigin(response.request)
            guard !hasRunningSession(for: response.request.chat) else { throw SplitBridgeFailure.transportUnavailable }
            let event = try HanlinHostResultEvent(resultID: origin.resultID, call: origin.call,
                result: Self.result(response, origin: origin))
            let receiptKey = try Self.historicalReceiptReference(response, resultID: origin.resultID)
            try await store.persistHistoricalReceipt(event, originReference: reference, receiptReference: receiptKey)
            _ = try await coldOrigin(response.request)
        }
    }

    func receiptCommitted(_ event: HanlinHostResultEvent) {
        for item in pending.values where item.origin.call == event.call && item.origin.resultID == event.resultID {
            guard !item.invalidated, let response = item.response,
                  let expected = try? Self.result(response, origin: item.origin),
                  event.result.reconciliationReference == expected.reconciliationReference,
                  event.result.effectState == expected.effectState,
                  event.result.metadataReceipt().result.outcome == expected.metadataReceipt().result.outcome else { continue }
            item.receipt = event
            let waiters = item.receiptWaiters; item.receiptWaiters = []
            for waiter in waiters { waiter.resume() }
        }
    }

    /// Called by the transport only after canonical save, fresh context and one-time mailbox accept.
    func navigateToOriginalConversation(_ request: SplitBridgeRequest) {
        let id = request.chat
        guard let modelContext,
              let rows = try? modelContext.fetch(FetchDescriptor<ChatRecords>(predicate: #Predicate { $0.id == id })),
              rows.count == 1 else { lastFailure = .correlationMismatch; return }
        acceptedOrigin = request
        pending[request.id]?.timer?.cancel()
        pending[request.id] = nil
    }

    /// UI mount acknowledgement clears only that delivered request; an older asynchronous
    /// mount cannot erase a newer accepted delivery. This never consumes mailbox state again.
    func acknowledgeAcceptedOrigin(requestID: UUID) {
        guard acceptedOrigin?.id == requestID else { return }
        acceptedOrigin = nil
    }

    func receiveReturn(_ url: URL, modelContext: ModelContext) async {
        self.modelContext = modelContext
        do {
            // Transport itself strictly parses the complete route and treats the URL as a hint only.
            try await makeTransport().receiveReturn(url, origin: self)
            lastFailure = nil
        } catch { lastFailure = error as? SplitBridgeFailure ?? .transportUnavailable }
    }

    func invalidate(session: HanlinHostSession) {
        let ids = pending.values.filter { $0.origin.call.session == session }.map { $0.request.id }
        for id in ids { invalidate(reference: id, reason: .cancelled) }
    }

    private func invalidate(reference: UUID, reason: SplitBridgeFailure) {
        guard let item = pending[reference], !item.invalidated else { return }
        item.invalidated = true
        item.timer?.cancel()
        // Local revocation precedes mailbox IO and release of any original waiters.
        var failure = reason
        do { try makeTransport().invalidate(reference) }
        catch { failure = .transportUnavailable }
        item.waiter?.resume(throwing: reason); item.waiter = nil
        let waiters = item.receiptWaiters; item.receiptWaiters = []
        for waiter in waiters { waiter.resume(throwing: reason) }
        // Keep a bounded tombstone for this process; never fall through to cold read authority.
        lastFailure = failure
    }

    private func coldOrigin(_ request: SplitBridgeRequest) async throws -> (StoredOrigin, String, HanlinAppConversationStore) {
        guard let modelContext else { throw SplitBridgeFailure.transportUnavailable }
        let id = request.chat
        let rows = try modelContext.fetch(FetchDescriptor<ChatRecords>(predicate: #Predicate { $0.id == id }))
        guard rows.count == 1, let row = rows.first else { throw SplitBridgeFailure.correlationMismatch }
        let namespace = try HanlinConversationNamespace(app: "hanlin", account: "local-personal-library", workspace: "swiftdata", space: id.uuidString)
        let store = HanlinAppConversationStore(context: modelContext, conversation: row, namespace: namespace, conversationID: id, temporary: false)
        guard let record = try await store.load(id, namespace: namespace) else { throw SplitBridgeFailure.correlationMismatch }
        _ = try store.requireOriginalConversation()
        let bindings = try HanlinAppAgentSessionOwner.historicalBindings(in: record)
        let matches = try record.entries.compactMap { entry -> (StoredOrigin, String)? in
            guard case .presentationReference(1, let reference) = entry.payload, reference.hasPrefix(Self.originPrefix(request.id)),
                  let data = Data(base64Encoded: String(reference.dropFirst(Self.originPrefix(request.id).count))), data.count <= 4096 else { return nil }
            let origin = try JSONDecoder().decode(StoredOrigin.self, from: data)
            guard origin.requestID == request.id, origin.requestDigest == (try Self.digest(request)),
                  origin.call.session.conversationID == id, origin.call.session.context.namespace == namespace,
                  origin.call.runID == entry.runID, origin.call.step == entry.step,
                  request.session.rawValue == origin.call.session.id.uuidString.lowercased(),
                  origin.call.logicalToolID.providerInstanceID.rawValue == "hanlin.host",
                  origin.call.logicalToolID.localToolID.rawValue == "open_mini_app",
                  bindings.contains(where: { $0.session == origin.call.session && $0.canonicalRunID == origin.call.runID && $0.reference == origin.row }) else {
                throw SplitBridgeFailure.correlationMismatch
            }
            return (origin, reference)
        }
        guard matches.count == 1, let original = matches.first else { throw SplitBridgeFailure.correlationMismatch }
        try requireOriginalAssistant(original.0)
        return (original.0, original.1, store)
    }

    private func requireOriginalAssistant(_ origin: StoredOrigin) throws {
        guard let modelContext else { throw SplitBridgeFailure.transportUnavailable }
        let id = origin.row.rowID
        let messages = try modelContext.fetch(FetchDescriptor<ChatMessages>(predicate: #Predicate { $0.id == id }))
        guard messages.count == 1, let message = messages.first, message.role == "assistant",
              message.record?.id == origin.call.session.conversationID else { throw SplitBridgeFailure.correlationMismatch }
    }

    private static func originPrefix(_ id: UUID) -> String { "hanlin.split.origin.v1:" + id.uuidString.lowercased() + ":" }
    private static func receiptReference(_ id: UUID) -> String { "hanlin.split.return.v1:" + id.uuidString.lowercased() }
    private static func digest<T: Encodable>(_ value: T) throws -> String {
        let raw = try SplitBridgeCodec.encode(value)
        let canonical = try HanlinHostSchemaValidation.deterministicJSONData(raw)
        return SHA256.hash(data: canonical).map { String(format: "%02x", $0) }.joined()
    }
    static func historicalReceiptReference(_ response: SplitBridgeReturn, resultID: UUID) throws -> String {
        "hanlin.split.receipt.v1:" + resultID.uuidString.lowercased() + ":" + (try digest(response))
    }
    private static func result(_ response: SplitBridgeReturn, origin: StoredOrigin) throws -> HanlinHostExecutionResult {
        let outcome: HanlinToolOutcome
        let effect: HanlinHostEffectState
        switch response.outcome {
        case .result(let value): outcome = .completed([.structured(value)]); effect = .confirmedCommitted
        case .failure: outcome = .failed(.init(code: .nativeFailure, userMessage: "The Mini App did not provide a successful operation receipt. Do not retry automatically.")); effect = .uncertain
        }
        return .init(result: .init(invocationID: origin.call.invocationID, logicalToolID: origin.call.logicalToolID,
            outcome: outcome, completedAt: .now), effectState: effect, context: origin.call.session.context,
            reconciliationReference: receiptReference(response.request.id) + ":" + (try digest(response)))
    }
}
