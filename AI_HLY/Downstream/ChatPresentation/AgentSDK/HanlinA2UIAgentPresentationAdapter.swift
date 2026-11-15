#if HANLIN_A2UI_POC
import A2UICore
import Foundation
import HanlinAgentCore
import HanlinHostContracts
import HanlinPlatformContracts
import Observation

/// Consumer of the canonical SDK contract. It owns only bounded, transient presentation.
/// The caller forwards SDK events/completion/invalidation and owns the one conversation store,
/// transport task and action continuation. No callback slot is overwritten by this adapter.
@MainActor
@Observable
final class HanlinA2UIAgentPresentationAdapter: HanlinA2UIResultEventSink {
    enum AdmissionError: Error, Equatable { case foreignSession, endedRun, mixedReplay, resourceLimit, changedPartKind }
    private struct Address: Hashable { let runID: UUID; let messageID: UUID }
    private enum Content {
        case text(String)
        case surface(HanlinA2UIResultKey, nextSequence: UInt64, failed: Bool)
    }
    private struct Message {
        var order: [UUID] = []
        var parts: [UUID: Content] = [:]
        var textBytes = 0
    }
    private enum Mode: Equatable { case live, replay }

    let identity: HanlinHostSession
    let store = HanlinA2UIResultStore()
    private(set) var source: HanlinChatContentProjectionSource?
    @ObservationIgnored private weak var session: HanlinAgentSession?
    @ObservationIgnored private let onInteraction: @MainActor @Sendable (HanlinHostInteractionRequest, HanlinA2UIResultKey) -> Void
    @ObservationIgnored private var messages: [Address: Message] = [:]
    @ObservationIgnored private var ordering: [UUID: HanlinChatStructuredPartSequence] = [:]
    @ObservationIgnored private var modes: [UUID: Mode] = [:]
    @ObservationIgnored private var finishedRuns: Set<UUID> = []
    @ObservationIgnored private var successfulEOF: Set<UUID> = []
    @ObservationIgnored private var runIDs: Set<UUID> = []
    @ObservationIgnored private var routes: [HanlinA2UIResultKey: HanlinHostInteractionOrigin] = [:]
    @ObservationIgnored private var frameCount = 0
    @ObservationIgnored private var wireBytes = 0
    @ObservationIgnored private var invalidated = false
    @ObservationIgnored private var resourceExhausted = false

    init(session: HanlinAgentSession,
         onInteraction: @escaping @MainActor @Sendable (HanlinHostInteractionRequest, HanlinA2UIResultKey) -> Void) {
        self.session = session
        identity = session.identity
        self.onInteraction = onInteraction
    }

    @discardableResult
    func receive(_ event: HanlinAgentEvent) throws -> Bool {
        guard !resourceExhausted else { throw AdmissionError.resourceLimit }
        guard !invalidated, event.session == identity, session?.identity == identity else { throw AdmissionError.foreignSession }
        guard !finishedRuns.contains(event.runID) else { throw AdmissionError.endedRun }
        guard modes[event.runID] != .replay else { throw AdmissionError.mixedReplay }
        guard case .structuredPart(let part) = event.event else { return false }
        try reserveRun(event.runID)
        modes[event.runID] = .live
        return try consume(part, runID: event.runID, live: true)
    }

    /// The SDK record remains the only persisted transcript. A replay is permanently read-only
    /// and cannot mix with live delivery or call admitInteraction for its historical identities.
    func replay(_ record: HanlinConversationRecord, runID: UUID, messageID: UUID) throws {
        guard !resourceExhausted else { throw AdmissionError.resourceLimit }
        guard !invalidated, record.conversationID == identity.conversationID,
              record.namespace == identity.context.namespace else { throw AdmissionError.foreignSession }
        guard modes[runID] != .live else { throw AdmissionError.mixedReplay }
        let entries = try record.structuredEntries(runID: runID, messageID: messageID)
        guard !entries.isEmpty else { return }
        try reserveRun(runID)
        modes[runID] = .replay
        for entry in entries {
            if case .structuredPart(let part, _) = entry.payload { _ = try consume(part, runID: runID, live: false) }
        }
        if let message = messages[Address(runID: runID, messageID: messageID)] {
            for content in message.parts.values {
                if case .surface(let key, _, _) = content { store.seal(key) }
            }
        }
        publish()
    }

    func completed(_ completion: HanlinAgentRunCompletion) {
        guard !invalidated, completion.session == identity, modes[completion.runID] != .replay else { return }
        do { try reserveRun(completion.runID) } catch { return }
        switch completion.outcome {
        case .completed:
            // SDK production can finish before AsyncThrowingStream's consumer drains buffered
            // events. Latch EOF; the same consumer calls producerStreamDrained after its loop.
            successfulEOF.insert(completion.runID)
        case .cancelled, .failed:
            finishedRuns.insert(completion.runID)
            revoke(runID: completion.runID)
            store.discardRun(completion.runID)
        }
        publish()
    }

    @discardableResult
    func producerStreamDrained(runID: UUID) -> Bool {
        guard !invalidated, successfulEOF.remove(runID) != nil, !finishedRuns.contains(runID) else { return false }
        finishedRuns.insert(runID)
        store.finishRun(runID)
        publish()
        return true
    }

    func invalidate(_ originalSession: HanlinHostSession) {
        guard originalSession == identity, !invalidated else { return }
        invalidated = true
        for origin in routes.values { session?.revokeInteraction(origin) }
        routes.removeAll()
        store.discardAll()
        publish()
    }

    /// Recheck this exact key before handing an asynchronously queued action to
    /// Session.continueInteraction. The SDK then checks original host context around await.
    func isCurrent(_ key: HanlinA2UIResultKey) -> Bool {
        !invalidated && session?.identity == identity && routes[key] != nil
            && store.projection(for: key).map { !$0.isReadOnly } == true
    }

    /// Delete the exact presentation generation and its native admission together. Inline /
    /// expanded views only project this store; their disappearance does not delete authority.
    @discardableResult
    func discard(_ key: HanlinA2UIResultKey) -> Bool {
        guard store.projection(for: key) != nil else { return false }
        if let origin = routes.removeValue(forKey: key) { session?.revokeInteraction(origin) }
        let removed = store.discard(key)
        publish()
        return removed
    }

    func receive(_ event: RendererToAgentMessage, for key: HanlinA2UIResultKey) {
        guard isCurrent(key), let origin = routes[key], case .action(let action) = event else { return }
        do {
            let bytes = try JSONEncoder().encode(action)
            guard bytes.count <= HanlinA2UIIngress.maximumMessageBytes else { return }
            let arguments = try HanlinJSONValue.decodeCanonicalJSON(bytes)
            onInteraction(.init(origin: origin, actionID: action.name, arguments: arguments), key)
        } catch { return } // Never forward raw renderer errors or invent a tool invocation.
    }

    private func consume(_ part: HanlinChatStructuredPart, runID: UUID, live: Bool) throws -> Bool {
        guard frameCount < 4096 else { throw AdmissionError.resourceLimit }
        var nextOrdering = ordering[runID] ?? HanlinChatStructuredPartSequence()
        guard try nextOrdering.admit(part) else { return false }
        let address = Address(runID: runID, messageID: part.messageID)
        guard messages[address] != nil || messages.count < 64 else { throw AdmissionError.resourceLimit }
        var message = messages[address] ?? Message()
        guard message.parts[part.partID] != nil || message.order.count < 128 else { throw AdmissionError.resourceLimit }
        let bytes: Int
        switch part.payload {
        case .textDelta(let text): bytes = text.utf8.count
        case .a2uiMessage(_, let data): bytes = data.count
        }
        guard bytes <= 8_388_608 - wireBytes else { throw AdmissionError.resourceLimit }
        frameCount += 1
        wireBytes += bytes
        if message.parts[part.partID] == nil { message.order.append(part.partID) }
        switch part.payload {
        case .textDelta(let text):
            guard message.textBytes <= 1_048_576 - bytes else { throw AdmissionError.resourceLimit }
            let previous: String
            if let existing = message.parts[part.partID] {
                guard case .text(let value) = existing else { throw AdmissionError.changedPartKind }
                previous = value
            } else { previous = "" }
            message.parts[part.partID] = .text(previous + text)
            message.textBytes += bytes
        case .a2uiMessage(let version, let data):
            let origin = HanlinHostInteractionOrigin(session: identity, runID: runID, messageID: part.messageID, partID: part.partID)
            let key: HanlinA2UIResultKey
            let sequence: UInt64
            if let existing = message.parts[part.partID] {
                guard case .surface(let stored, let next, let failed) = existing else { throw AdmissionError.changedPartKind }
                if failed {
                    ordering[runID] = nextOrdering
                    if live { session?.revokeInteraction(origin) }
                    return false
                }
                key = stored; sequence = next
            } else {
                guard let projection = store.registerModelPart(runID: runID, messageID: part.messageID,
                    partID: part.partID, sink: self) else { throw AdmissionError.endedRun }
                key = projection.key; sequence = 0
            }
            let result: Result<Void, HanlinA2UIResultAdmissionError>
            if version != "1.0" {
                result = .failure(.rejected(.init(.unsupportedVersion)))
            } else if data.count > HanlinA2UIIngress.maximumMessageBytes {
                result = .failure(.rejected(.init(.messageTooLarge)))
            } else if let json = String(data: data, encoding: .utf8) {
                result = store.receive(json, sequence: sequence, for: key)
            } else {
                result = .failure(.rejected(.init(.malformedEnvelope)))
            }
            let failed: Bool
            switch result {
            case .success:
                failed = false
                if live, store.projection(for: key)?.surfaceIDs.isEmpty == false {
                    do {
                        guard let originalSession = session else { throw AdmissionError.foreignSession }
                        try originalSession.admitInteraction(origin)
                        routes[key] = origin
                    } catch {
                        store.seal(key)
                        routes.removeValue(forKey: key)
                        session?.revokeInteraction(origin)
                    }
                } else if live {
                    routes.removeValue(forKey: key)
                    session?.revokeInteraction(origin)
                }
            case .failure:
                failed = true
                store.seal(key)
                routes.removeValue(forKey: key)
                session?.revokeInteraction(origin)
            }
            message.parts[part.partID] = .surface(key, nextSequence: sequence + 1, failed: failed)
        }
        ordering[runID] = nextOrdering
        messages[address] = message
        publish()
        return true
    }

    private func revoke(runID: UUID) {
        for key in routes.keys.filter({ $0.runID == runID }) {
            if let origin = routes.removeValue(forKey: key) { session?.revokeInteraction(origin) }
        }
    }

    /// Include completion-only and rejected runs in the bound. Otherwise a long-lived caller
    /// could grow EOF/tombstone/mode sets even after the content budget has been exhausted.
    private func reserveRun(_ runID: UUID) throws {
        guard !runIDs.contains(runID) else { return }
        guard runIDs.count < 64 else {
            resourceExhausted = true
            invalidate(identity)
            throw AdmissionError.resourceLimit
        }
        runIDs.insert(runID)
    }

    private func publish() {
        let projected = messages.compactMap { address, message -> HanlinChatContentProjection? in
            let parts = message.order.compactMap { id -> HanlinChatContentProjection.Part? in
                guard let value = message.parts[id] else { return nil }
                let content: HanlinChatContentProjection.Part.Content
                switch value {
                case .text(let text): content = .markdown(text)
                case .surface(let key, _, let failed):
                    content = failed || store.projection(for: key)?.isClosed != false ? .unavailable : .surface(key)
                }
                return .init(id: id, content: content)
            }
            return HanlinChatContentProjection(runID: address.runID, messageID: address.messageID, parts: parts, store: store)
        }
        source = HanlinChatContentProjectionSource(messages: projected)
    }
}
#endif
