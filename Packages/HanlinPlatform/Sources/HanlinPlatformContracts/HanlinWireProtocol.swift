import Foundation

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
        case .request, .response, .error, .cancel, .progress:
            guard requestID != nil else {
                throw HanlinContractError.invalidWireEnvelope(
                    reason: "\(kind.rawValue) messages require a request ID"
                )
            }
        case .hello, .ready, .event, .uiSnapshot, .uiPatch, .log,
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
