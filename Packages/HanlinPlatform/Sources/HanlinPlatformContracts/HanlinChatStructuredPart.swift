import Foundation

/// Explicit provider channel; never decoded from ordinary model text or fenced JSON.
/// IDs and sequence are scoped to the originating run by HanlinAgentEvent.
public struct HanlinChatStructuredPart: Codable, Hashable, Sendable {
    public static let channel = "hanlin.chat.part.v1"
    public enum Payload: Codable, Hashable, Sendable {
        case textDelta(String)
        /// Complete official-protocol message bytes; the existing renderer owns admission.
        case a2uiMessage(protocolVersion: String, json: Data)
    }
    public let version: Int
    public let messageID: UUID
    public let partID: UUID
    /// Monotonic across all parts in this message, including interleaved text/surfaces.
    public let sequence: UInt64
    public let payload: Payload

    public init(version: Int = 1, messageID: UUID, partID: UUID, sequence: UInt64, payload: Payload) throws {
        self.version = version; self.messageID = messageID; self.partID = partID
        self.sequence = sequence; self.payload = payload
        try validate()
    }

    public func validate() throws {
        guard version == 1 else {
            throw HanlinChatStructuredPartError.invalidEnvelope
        }
        switch payload {
        case .textDelta(let text):
            guard text.utf8.count <= 1_048_576 else { throw HanlinChatStructuredPartError.invalidEnvelope }
        case .a2uiMessage(let protocolVersion, let json):
            guard !protocolVersion.isEmpty, protocolVersion.utf8.count <= 64,
                  !json.isEmpty, json.count <= 1_048_576 else { throw HanlinChatStructuredPartError.invalidEnvelope }
        }
    }

    private enum CodingKeys: String, CodingKey { case version, messageID, partID, sequence, payload }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(version: c.decode(Int.self, forKey: .version), messageID: c.decode(UUID.self, forKey: .messageID),
                      partID: c.decode(UUID.self, forKey: .partID), sequence: c.decode(UInt64.self, forKey: .sequence),
                      payload: c.decode(Payload.self, forKey: .payload))
    }
}

public enum HanlinChatStructuredPartError: Error, Sendable {
    case invalidEnvelope, outOfOrder, conflictingReplay, unadvertisedChannel
}

/// Per-run ordering/replay validation. Replay is display data and conveys no host authority.
public struct HanlinChatStructuredPartSequence: Sendable {
    private enum Kind: Equatable { case text, a2ui(String) }
    private var last: [UUID: UInt64] = [:]
    private var seen: [UUID: [UInt64: HanlinChatStructuredPart]] = [:]
    private var kinds: [UUID: [UUID: Kind]] = [:]
    public init() {}

    /// Returns false for an exact duplicate, throws for changed replay or stale order.
    public mutating func admit(_ part: HanlinChatStructuredPart) throws -> Bool {
        try part.validate()
        if let previous = seen[part.messageID]?[part.sequence] {
            guard previous == part else { throw HanlinChatStructuredPartError.conflictingReplay }
            return false
        }
        guard last[part.messageID].map({ part.sequence > $0 }) ?? true else { throw HanlinChatStructuredPartError.outOfOrder }
        let kind: Kind
        switch part.payload {
        case .textDelta: kind = .text
        case .a2uiMessage(let version, _): kind = .a2ui(version)
        }
        if let previous = kinds[part.messageID]?[part.partID], previous != kind {
            throw HanlinChatStructuredPartError.conflictingReplay
        }
        seen[part.messageID, default: [:]][part.sequence] = part
        kinds[part.messageID, default: [:]][part.partID] = kind
        last[part.messageID] = part.sequence
        return true
    }
}
