import Foundation

public enum HanlinWireMessageKind: String, Codable, CaseIterable, Hashable, Sendable {
    case hello
    case negotiation
    case request
    case response
    case event
    case progress
    case cancellation
    case error
    case heartbeat
    case shutdown
}

public struct HanlinWireFeatureSet: Codable, Hashable, Sendable {
    public let required: Set<String>
    public let optional: Set<String>

    public init(required: Set<String> = [], optional: Set<String> = []) {
        self.required = required
        self.optional = optional
    }
}

public struct HanlinWireEnvelope: Codable, Hashable, Sendable {
    public let protocolVersion: HanlinWireProtocolVersion
    public let runtimeSessionID: HanlinRuntimeSessionID
    public let sequence: UInt64
    public let requestID: HanlinRequestID?
    public let invocationID: HanlinToolInvocationID?
    public let cancellationID: HanlinCancellationID?
    public let kind: HanlinWireMessageKind
    public let features: HanlinWireFeatureSet
    public let payload: HanlinValue

    public init(
        protocolVersion: HanlinWireProtocolVersion,
        runtimeSessionID: HanlinRuntimeSessionID,
        sequence: UInt64,
        requestID: HanlinRequestID? = nil,
        invocationID: HanlinToolInvocationID? = nil,
        cancellationID: HanlinCancellationID? = nil,
        kind: HanlinWireMessageKind,
        features: HanlinWireFeatureSet = .init(),
        payload: HanlinValue
    ) {
        self.protocolVersion = protocolVersion
        self.runtimeSessionID = runtimeSessionID
        self.sequence = sequence
        self.requestID = requestID
        self.invocationID = invocationID
        self.cancellationID = cancellationID
        self.kind = kind
        self.features = features
        self.payload = payload
    }

    public func validate(
        support: HanlinVersionSupport = .version1,
        maximumPayloadBytes: Int = 1_048_576
    ) throws {
        try support.validate(protocolVersion)
        guard sequence > 0 else {
            throw HanlinContractError.invalidWireEnvelope(
                reason: "wire sequences begin at one"
            )
        }
        let payloadBytes = try payload.canonicalJSONData().count
        guard payloadBytes <= maximumPayloadBytes else {
            throw HanlinContractError.invalidWireEnvelope(
                reason: "payload is \(payloadBytes) bytes; maximum is \(maximumPayloadBytes)"
            )
        }
        switch kind {
        case .request, .response:
            guard requestID != nil || invocationID != nil else {
                throw HanlinContractError.invalidWireEnvelope(
                    reason: "request and response messages require correlation identity"
                )
            }
        case .cancellation:
            guard cancellationID != nil else {
                throw HanlinContractError.invalidWireEnvelope(
                    reason: "cancellation messages require cancellation identity"
                )
            }
        case .hello, .negotiation, .event, .progress, .error, .heartbeat, .shutdown:
            break
        }
    }
}

public enum HanlinScriptMessageKind: String, Codable, CaseIterable, Hashable, Sendable {
    case hello
    case ready
    case request
    case response
    case error
    case cancel
    case event
    case uiSnapshot
    case uiPatch
    case log
    case progress
    case promiseResolved
    case promiseRejected
    case callbackRegistered
    case callbackInvoked
    case callbackReleased
    case subscribed
    case unsubscribed
    case streamChunk
    case streamCompleted
    case retainHandle
    case releaseHandle
    case heartbeat
    case suspend
    case resume
    case shutdown
}

public struct HanlinScriptEnvelope: Codable, Hashable, Sendable {
    public let protocolVersion: HanlinWireProtocolVersion
    public let sessionID: HanlinSessionID
    public let sequence: UInt64
    public let requestID: HanlinRequestID?
    public let kind: HanlinScriptMessageKind
    public let payload: HanlinValue

    public init(
        protocolVersion: HanlinWireProtocolVersion,
        sessionID: HanlinSessionID,
        sequence: UInt64,
        requestID: HanlinRequestID? = nil,
        kind: HanlinScriptMessageKind,
        payload: HanlinValue
    ) {
        self.protocolVersion = protocolVersion
        self.sessionID = sessionID
        self.sequence = sequence
        self.requestID = requestID
        self.kind = kind
        self.payload = payload
    }

    public func validate(
        support: HanlinVersionSupport = .version1,
        maximumPayloadBytes: Int = 1_048_576
    ) throws {
        try support.validate(protocolVersion)
        guard sequence > 0 else {
            throw HanlinContractError.invalidWireEnvelope(
                reason: "wire sequences begin at one"
            )
        }
        guard maximumPayloadBytes > 0 else {
            throw HanlinContractError.invalidWireEnvelope(
                reason: "maximum payload byte count must be positive"
            )
        }
        let payloadBytes = try payload.canonicalJSONData().count
        guard payloadBytes <= maximumPayloadBytes else {
            throw HanlinContractError.invalidWireEnvelope(
                reason: "payload is \(payloadBytes) bytes; maximum is \(maximumPayloadBytes)"
            )
        }
        switch kind {
        case .request, .response, .error, .cancel, .progress,
             .promiseResolved, .promiseRejected, .callbackInvoked,
             .streamChunk, .streamCompleted:
            guard requestID != nil else {
                throw HanlinContractError.invalidWireEnvelope(
                    reason: "\(kind.rawValue) messages require a request ID"
                )
            }
        case .hello, .ready, .event, .uiSnapshot, .uiPatch, .log,
             .callbackRegistered, .callbackReleased, .subscribed, .unsubscribed,
             .retainHandle, .releaseHandle, .heartbeat, .suspend, .resume,
             .shutdown:
            break
        }
    }

    public func canonicalJSONData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(self)
    }

    public static func decodeAndValidate(
        _ data: Data,
        support: HanlinVersionSupport = .version1,
        maximumPayloadBytes: Int = 1_048_576
    ) throws -> HanlinScriptEnvelope {
        let envelope = try JSONDecoder().decode(Self.self, from: data)
        try envelope.validate(
            support: support,
            maximumPayloadBytes: maximumPayloadBytes
        )
        return envelope
    }
}
