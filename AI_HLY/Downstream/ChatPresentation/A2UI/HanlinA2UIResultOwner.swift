#if HANLIN_A2UI_POC
import A2UICore
import Foundation
import Observation
import SwiftUI

/// Transient identity supplied by the existing run/result owner, never by an A2UI payload.
/// Registration mints the generation; a wire surface ID cannot select or replace an owner.
struct HanlinA2UIResultKey: Hashable, Sendable {
    enum Origin: Hashable, Sendable {
        case tool(callID: String)
        case model(messageID: UUID)
    }
    let runID: UUID
    let resultID: UUID
    let origin: Origin
    let generation: UUID

    var callID: String? {
        if case .tool(let callID) = origin { return callID }
        return nil
    }

    init(runID: UUID, resultID: UUID, callID: String?, generation: UUID) {
        self.init(runID: runID, resultID: resultID, origin: .tool(callID: callID ?? ""), generation: generation)
    }

    init(runID: UUID, resultID: UUID, origin: Origin, generation: UUID) {
        self.runID = runID
        self.resultID = resultID
        self.origin = origin
        self.generation = generation
    }
}

@MainActor
protocol HanlinA2UIResultEventSink: AnyObject, Sendable {
    func receive(_ event: RendererToAgentMessage, for key: HanlinA2UIResultKey)
}

enum HanlinA2UIResultAdmissionError: Error, Equatable, Sendable {
    case unregisteredResult, inputSealed, inputFinished, outOfOrder, retiredSurfaceID
    case rejected(HanlinA2UIIngress.Rejection)
}

/// Read-only lookup result. Copies used by inline/expanded views share the same owner.
/// It exposes no receive, replacement, seal, teardown or transport authority.
@MainActor
struct HanlinA2UIResultProjection {
    fileprivate let owner: HanlinA2UIResultOwner
    var key: HanlinA2UIResultKey { owner.key }
    var isReadOnly: Bool { owner.session.isInputSealed || owner.session.isClosed }
    var isClosed: Bool { owner.session.isClosed }
    var isReceivingFinished: Bool { owner.isReceivingFinished }
    var surfaceIDs: [String] { owner.session.surfaceIDs }
    func surface(_ id: String) -> SurfaceViewModel? { owner.session.surface(id) }
}

/// Rendering never receives/replays frames and has no appearance-based teardown.
/// The future chat adapter supplies this to the existing generic host's content closures.
@MainActor
struct HanlinA2UIProjectedResultView: View {
    let projection: HanlinA2UIResultProjection
    var body: some View { HanlinA2UIResultView(session: projection.owner.session) }
}

@MainActor
fileprivate final class HanlinA2UIResultOwner {
    let key: HanlinA2UIResultKey
    let session: HanlinA2UISession
    private let relay: HanlinA2UIResultRelay
    private var nextSequence: UInt64 = 0
    private var lifetime = HanlinA2UIFrameLifetime()
    private var receiveTask: Task<Void, Never>?
    private(set) var isReceivingFinished = false

    init(key: HanlinA2UIResultKey, sink: any HanlinA2UIResultEventSink, store: HanlinA2UIResultStore) {
        self.key = key
        let relay = HanlinA2UIResultRelay(sink: sink)
        self.relay = relay
        session = HanlinA2UISession { [weak relay] event in
            Task { @MainActor [weak relay] in relay?.deliver(event) }
        }
        relay.owner = self
        relay.store = store
    }

    func receive(_ json: String, sequence: UInt64) -> Result<Void, HanlinA2UIResultAdmissionError> {
        guard !session.isInputSealed, !session.isClosed else { return .failure(.inputSealed) }
        guard !isReceivingFinished else { return .failure(.inputFinished) }
        guard sequence == nextSequence else { return .failure(.outOfOrder) }
        // A correctly ordered delivery consumes its ordinal even if SDK validation rejects it.
        // Replaying that frame cannot consume budget or mutate a surface a second time.
        let result = lifetime.receive(json, in: session)
        if nextSequence == .max { seal() } else { nextSequence += 1 }
        return result
    }

    func attachReceiveTask(_ task: Task<Void, Never>) -> Bool {
        guard receiveTask == nil, !isReceivingFinished, !session.isInputSealed, !session.isClosed else {
            task.cancel()
            return false
        }
        receiveTask = task
        return true
    }

    /// Successful producer EOF closes only input. The original weak sink still owns
    /// interaction authorization; completion cannot select another host or mint a key.
    func finishReceiving() {
        isReceivingFinished = true
        receiveTask?.cancel()
        receiveTask = nil
    }

    func seal() {
        finishReceiving()
        relay.revoke()
        session.seal()
    }

    func discard() {
        seal()
        session.close() // Session.close is guarded and disposes the actual SDK processor once.
    }

    deinit {
        receiveTask?.cancel()
        // Fallback for an abandoned projection. Explicit discard remains synchronous;
        // the weak store/owner relay has already removed authority before this cleanup.
        let abandonedSession = session
        Task { @MainActor in abandonedSession.close() }
    }
}

/// The owner and event target are weak. Each queued dispatch checks current owner state and
/// actual SDK membership; a retained SDK action cannot acquire a different result's authority.
@MainActor
fileprivate final class HanlinA2UIResultRelay {
    weak var owner: HanlinA2UIResultOwner?
    weak var store: HanlinA2UIResultStore?
    private weak var sink: (any HanlinA2UIResultEventSink)?

    init(sink: any HanlinA2UIResultEventSink) { self.sink = sink }
    func revoke() { sink = nil }

    func deliver(_ event: RendererToAgentMessage) {
        guard let owner, let store, store.containsOwner(owner),
              !owner.session.isInputSealed, !owner.session.isClosed, let sink else { return }
        let surfaceID: String?
        switch event {
        case .action(let action): surfaceID = action.surfaceID
        case .error(let error):
            switch error {
            case .validationFailed(let failure): surfaceID = failure.surfaceID
            case .generic(let failure): surfaceID = failure.surfaceID
            }
        default: return // Agent-function requests/responses never obtain an outbound route.
        }
        guard let surfaceID, owner.session.surface(surfaceID) != nil else { return }
        sink.receive(event, for: owner.key)
    }
}

/// Ephemeral projection storage, not transcript/message/transport authority. Callers explicitly
/// register, deliver already-framed ordered messages and end result lifetimes outside View.body.
/// The caller retains its event sink and must discardAll on chat teardown.
@MainActor
@Observable
final class HanlinA2UIResultStore {
    private struct Slot: Hashable {
        let runID: UUID
        let resultID: UUID
        let modelMessageID: UUID?
        init(_ key: HanlinA2UIResultKey) { self.init(runID: key.runID, resultID: key.resultID, origin: key.origin) }
        init(runID: UUID, resultID: UUID, origin: HanlinA2UIResultKey.Origin) {
            self.runID = runID; self.resultID = resultID
            if case .model(let messageID) = origin { modelMessageID = messageID } else { modelMessageID = nil }
        }
    }
    private var owners: [Slot: HanlinA2UIResultOwner] = [:]
    private var endedRuns: Set<UUID> = []
    private var completedProducerRuns: Set<UUID> = []
    private var isDiscarded = false

    func register(runID: UUID, resultID: UUID, callID: String?,
                  sink: any HanlinA2UIResultEventSink) -> HanlinA2UIResultProjection? {
        guard let callID, !callID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return register(runID: runID, resultID: resultID, origin: .tool(callID: callID), sink: sink)
    }

    /// Model content has a message/part identity, never a fabricated provider tool call.
    func registerModelPart(runID: UUID, messageID: UUID, partID: UUID,
                           sink: any HanlinA2UIResultEventSink) -> HanlinA2UIResultProjection? {
        register(runID: runID, resultID: partID, origin: .model(messageID: messageID), sink: sink)
    }

    private func register(runID: UUID, resultID: UUID, origin: HanlinA2UIResultKey.Origin,
                          sink: any HanlinA2UIResultEventSink) -> HanlinA2UIResultProjection? {
        let slot = Slot(runID: runID, resultID: resultID, origin: origin)
        guard !isDiscarded, !endedRuns.contains(runID), !completedProducerRuns.contains(runID),
              owners[slot] == nil,
              !owners.keys.contains(where: { existing in
                  existing.runID == runID && existing.resultID == resultID
                      && (existing.modelMessageID == nil) != (slot.modelMessageID == nil)
              }) else { return nil }
        let key = HanlinA2UIResultKey(runID: runID, resultID: resultID, origin: origin, generation: UUID())
        let owner = HanlinA2UIResultOwner(key: key, sink: sink, store: self)
        owners[slot] = owner
        return HanlinA2UIResultProjection(owner: owner)
    }

    func projection(for key: HanlinA2UIResultKey) -> HanlinA2UIResultProjection? {
        guard let owner = owned(key) else { return nil }
        return HanlinA2UIResultProjection(owner: owner)
    }

    @discardableResult
    func receive(_ completeMessage: String, sequence: UInt64, for key: HanlinA2UIResultKey)
        -> Result<Void, HanlinA2UIResultAdmissionError> {
        guard let owner = owned(key) else { return .failure(.unregisteredResult) }
        return owner.receive(completeMessage, sequence: sequence)
    }

    @discardableResult
    func attachReceiveTask(_ task: Task<Void, Never>, for key: HanlinA2UIResultKey) -> Bool {
        guard let owner = owned(key) else { task.cancel(); return false }
        return owner.attachReceiveTask(task)
    }

    @discardableResult
    func seal(_ key: HanlinA2UIResultKey) -> Bool {
        guard let owner = owned(key) else { return false }
        owner.seal()
        return true
    }

    func sealRun(_ runID: UUID) {
        endedRuns.insert(runID) // Also reject a late producer attempting to register a new result.
        for owner in owners.values where owner.key.runID == runID { owner.seal() }
    }

    /// Successful EOF preserves live controls under their original owner and sink. The
    /// canonical action broker must still validate originating host/session generation.
    /// Cancellation, failure, invalidation and chat teardown use seal/discard instead.
    func finishRun(_ runID: UUID) {
        completedProducerRuns.insert(runID)
        for owner in owners.values where owner.key.runID == runID { owner.finishReceiving() }
    }

    /// Explicit replacement invalidates the old generation before registering its successor.
    func replace(_ key: HanlinA2UIResultKey, callID: String?,
                 sink: any HanlinA2UIResultEventSink) -> HanlinA2UIResultProjection? {
        guard case .tool = key.origin, let callID,
              !isDiscarded, !endedRuns.contains(key.runID), !completedProducerRuns.contains(key.runID),
              let owner = owned(key), !owner.isReceivingFinished,
              !owner.session.isInputSealed, !owner.session.isClosed,
              !callID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        discard(key)
        return register(runID: key.runID, resultID: key.resultID, callID: callID, sink: sink)
    }

    @discardableResult
    func discard(_ key: HanlinA2UIResultKey) -> Bool {
        guard let owner = owned(key) else { return false }
        owners.removeValue(forKey: Slot(key))
        owner.discard()
        return true
    }

    func discardRun(_ runID: UUID) {
        endedRuns.insert(runID)
        for key in owners.values.map(\.key) where key.runID == runID { discard(key) }
    }

    func discardAll() {
        isDiscarded = true // A cancelled/discarded chat needs a new store, never a reset of old keys.
        for key in owners.values.map(\.key) { discard(key) }
    }

    private func owned(_ key: HanlinA2UIResultKey) -> HanlinA2UIResultOwner? {
        guard let owner = owners[Slot(key)], owner.key == key else { return nil }
        return owner
    }

    fileprivate func containsOwner(_ owner: HanlinA2UIResultOwner) -> Bool {
        owned(owner.key) === owner
    }
}
#endif
