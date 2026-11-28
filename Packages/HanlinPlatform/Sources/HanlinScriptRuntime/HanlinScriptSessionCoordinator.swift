import Foundation
import HanlinPlatformContracts
import HanlinScriptContracts

public enum HanlinScriptSessionError: Error, Equatable, Sendable {
    case invalidTransition(from: HanlinScriptSessionState, to: HanlinScriptSessionState)
    case inactive(HanlinScriptSessionState)
    case wrongSession
    case sequenceRegression
    case pendingPromiseLimit
    case callbackLimit
    case subscriptionLimit
    case objectHandleLimit
    case eventBackpressure
    case duplicateIdentifier(String)
}

public struct HanlinScriptSessionResourceSnapshot: Codable, Hashable, Sendable {
    public let state: HanlinScriptSessionState
    public let pendingPromises: Int
    public let callbacks: Int
    public let subscriptions: Int
    public let objectHandles: Int
    public let queuedEvents: Int
    public let nextOutboundSequence: UInt64

    public init(
        state: HanlinScriptSessionState,
        pendingPromises: Int,
        callbacks: Int,
        subscriptions: Int,
        objectHandles: Int,
        queuedEvents: Int,
        nextOutboundSequence: UInt64
    ) {
        self.state = state
        self.pendingPromises = pendingPromises
        self.callbacks = callbacks
        self.subscriptions = subscriptions
        self.objectHandles = objectHandles
        self.queuedEvents = queuedEvents
        self.nextOutboundSequence = nextOutboundSequence
    }
}

public actor HanlinScriptSessionCoordinator {
    public let descriptor: HanlinScriptSessionDescriptor

    private var state: HanlinScriptSessionState = .created
    private var promises = Set<HanlinPromiseID>()
    private var callbacks = Set<HanlinCallbackID>()
    private var subscriptions = Set<HanlinSubscriptionID>()
    private var objectHandles = Set<HanlinObjectHandleID>()
    private var queuedEvents: [HanlinScriptEnvelope] = []
    private var nextOutboundSequence: UInt64 = 1
    private var lastInboundSequence: UInt64 = 0

    public init(descriptor: HanlinScriptSessionDescriptor) {
        self.descriptor = descriptor
    }

    public func beginLoading() throws { try transition(to: .loading, allowedFrom: [.created]) }
    public func activate() throws { try transition(to: .active, allowedFrom: [.loading]) }
    public func suspend() throws { try transition(to: .suspended, allowedFrom: [.active]) }
    public func resume() throws { try transition(to: .active, allowedFrom: [.suspended]) }

    public func fail() {
        guard state != .closed else { return }
        state = .failed
        releaseAllResources()
    }

    public func close() {
        guard state != .closed else { return }
        state = .closing
        releaseAllResources()
        state = .closed
    }

    public func registerPromise(_ id: HanlinPromiseID) throws {
        try requireActive()
        guard promises.count < descriptor.policy.maximumPendingPromises else {
            throw HanlinScriptSessionError.pendingPromiseLimit
        }
        guard promises.insert(id).inserted else { throw HanlinScriptSessionError.duplicateIdentifier(id.rawValue) }
    }

    @discardableResult
    public func settlePromise(_ id: HanlinPromiseID) -> Bool { promises.remove(id) != nil }

    public func registerCallback(_ id: HanlinCallbackID) throws {
        try requireActive()
        guard callbacks.count < descriptor.policy.maximumCallbacks else {
            throw HanlinScriptSessionError.callbackLimit
        }
        guard callbacks.insert(id).inserted else { throw HanlinScriptSessionError.duplicateIdentifier(id.rawValue) }
    }

    @discardableResult
    public func releaseCallback(_ id: HanlinCallbackID) -> Bool { callbacks.remove(id) != nil }

    public func subscribe(_ id: HanlinSubscriptionID) throws {
        try requireActive()
        guard subscriptions.count < descriptor.policy.maximumCallbacks else {
            throw HanlinScriptSessionError.subscriptionLimit
        }
        guard subscriptions.insert(id).inserted else { throw HanlinScriptSessionError.duplicateIdentifier(id.rawValue) }
    }

    @discardableResult
    public func unsubscribe(_ id: HanlinSubscriptionID) -> Bool { subscriptions.remove(id) != nil }

    public func retainHandle(_ id: HanlinObjectHandleID) throws {
        try requireActive()
        guard objectHandles.count < descriptor.policy.maximumObjectHandles else {
            throw HanlinScriptSessionError.objectHandleLimit
        }
        guard objectHandles.insert(id).inserted else { throw HanlinScriptSessionError.duplicateIdentifier(id.rawValue) }
    }

    @discardableResult
    public func releaseHandle(_ id: HanlinObjectHandleID) -> Bool { objectHandles.remove(id) != nil }

    public func acceptInbound(_ envelope: HanlinScriptEnvelope) throws {
        guard envelope.sessionID == descriptor.sessionID else { throw HanlinScriptSessionError.wrongSession }
        try envelope.validate(
            support: .scriptingV2,
            maximumPayloadBytes: descriptor.policy.maximumOutputBytes
        )
        guard envelope.sequence > lastInboundSequence else { throw HanlinScriptSessionError.sequenceRegression }
        lastInboundSequence = envelope.sequence
    }

    public func enqueue(
        kind: HanlinScriptMessageKind,
        requestID: HanlinRequestID? = nil,
        payload: HanlinValue
    ) throws {
        try requireActive(allowSuspended: true)
        guard queuedEvents.count < descriptor.policy.maximumQueuedEvents else {
            throw HanlinScriptSessionError.eventBackpressure
        }
        let envelope = HanlinScriptEnvelope(
            protocolVersion: .init(major: 2, minor: 0),
            sessionID: descriptor.sessionID,
            sequence: nextOutboundSequence,
            requestID: requestID,
            kind: kind,
            payload: payload
        )
        try envelope.validate(
            support: .scriptingV2,
            maximumPayloadBytes: descriptor.policy.maximumOutputBytes
        )
        queuedEvents.append(envelope)
        nextOutboundSequence &+= 1
    }

    public func dequeue() -> HanlinScriptEnvelope? {
        guard !queuedEvents.isEmpty else { return nil }
        return queuedEvents.removeFirst()
    }

    public func resourceSnapshot() -> HanlinScriptSessionResourceSnapshot {
        .init(
            state: state,
            pendingPromises: promises.count,
            callbacks: callbacks.count,
            subscriptions: subscriptions.count,
            objectHandles: objectHandles.count,
            queuedEvents: queuedEvents.count,
            nextOutboundSequence: nextOutboundSequence
        )
    }

    private func transition(
        to target: HanlinScriptSessionState,
        allowedFrom: Set<HanlinScriptSessionState>
    ) throws {
        guard allowedFrom.contains(state) else {
            throw HanlinScriptSessionError.invalidTransition(from: state, to: target)
        }
        state = target
    }

    private func requireActive(allowSuspended: Bool = false) throws {
        guard state == .active || (allowSuspended && state == .suspended) else {
            throw HanlinScriptSessionError.inactive(state)
        }
    }

    private func releaseAllResources() {
        promises.removeAll(keepingCapacity: false)
        callbacks.removeAll(keepingCapacity: false)
        subscriptions.removeAll(keepingCapacity: false)
        objectHandles.removeAll(keepingCapacity: false)
        queuedEvents.removeAll(keepingCapacity: false)
    }
}
