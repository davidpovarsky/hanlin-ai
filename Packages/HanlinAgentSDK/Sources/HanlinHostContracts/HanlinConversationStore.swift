import Foundation
import HanlinPlatformContracts

/// Persisted content carries no grants or closures. Replay is display data, never execution.
public enum HanlinTranscriptPayload: Codable, Hashable, Sendable {
    case text(String)
    case reasoning(String)
    case toolCall(providerCallID: String, alias: String, arguments: HanlinJSONValue)
    case toolResult(providerCallID: String, result: HanlinHostExecutionResult)
    /// Replay correlation only; never restores live admission or host authority.
    case hostResultIdentity(resultID: UUID, call: HanlinHostCallIdentity)
    case structuredPart(HanlinChatStructuredPart, context: HanlinHostContext)
    case presentationReference(version: Int, opaqueReference: String)
    case finished(reason: String)
    case cancelled
    case failed(code: HanlinHostError)
}

public struct HanlinTranscriptEntry: Codable, Hashable, Sendable {
    public let runID: UUID
    public let step: Int
    public let sequence: UInt64
    public let timestamp: Date
    public let payload: HanlinTranscriptPayload
    public init(runID: UUID, step: Int, sequence: UInt64, timestamp: Date = .now, payload: HanlinTranscriptPayload) {
        self.runID = runID; self.step = step; self.sequence = sequence; self.timestamp = timestamp; self.payload = payload
    }
}

public struct HanlinConversationRecord: Codable, Hashable, Sendable {
    public static let currentFormat = 2
    public let formatVersion: Int
    public let namespace: HanlinConversationNamespace
    public let conversationID: UUID
    public let revision: UInt64
    public let model: HanlinModelReference?
    public let draft: String
    public let entries: [HanlinTranscriptEntry]
    public init(formatVersion: Int = Self.currentFormat, namespace: HanlinConversationNamespace,
                conversationID: UUID, revision: UInt64, model: HanlinModelReference? = nil,
                draft: String = "", entries: [HanlinTranscriptEntry] = []) {
        self.formatVersion = formatVersion; self.namespace = namespace; self.conversationID = conversationID
        self.revision = revision; self.model = model; self.draft = draft; self.entries = entries
    }
    public func validate() throws {
        // Read old metadata records without rewriting them. New saves use the explicit v2 format.
        guard (1...Self.currentFormat).contains(formatVersion) else { throw HanlinHostError.unsupportedVersion }
        var last: UInt64?
        var structured = [UUID: HanlinChatStructuredPartSequence]()
        for entry in entries {
            guard entry.step >= 0, last.map({ entry.sequence > $0 }) ?? true else { throw HanlinHostError.invalidRecord }
            if case .toolResult(_, let outcome) = entry.payload {
                guard outcome.context.namespace == namespace else { throw HanlinHostError.invalidRecord }
            }
            if case .hostResultIdentity(_, let call) = entry.payload {
                guard formatVersion >= 2, call.session.context.namespace == namespace,
                      call.session.conversationID == conversationID, call.runID == entry.runID,
                      call.step == entry.step else { throw HanlinHostError.invalidRecord }
            }
            if case .structuredPart(let part, let context) = entry.payload {
                guard formatVersion >= 2, context.namespace == namespace else { throw HanlinHostError.invalidRecord }
                var ordering = structured[entry.runID] ?? HanlinChatStructuredPartSequence()
                _ = try ordering.admit(part)
                structured[entry.runID] = ordering
            }
            last = entry.sequence
        }
    }

    /// Read-only original entries in global transcript order, including exact typed text/Surface
    /// bytes and original context. This never registers live interaction admission.
    public func structuredEntries(runID: UUID, messageID: UUID) throws -> [HanlinTranscriptEntry] {
        try validate()
        var ordering = HanlinChatStructuredPartSequence()
        return try entries.filter { entry in
            guard entry.runID == runID, case .structuredPart(let part, _) = entry.payload,
                  part.messageID == messageID else { return false }
            return try ordering.admit(part)
        }
    }
}

/// Compare-and-replace for SDK metadata only; unrelated to native host document CAS.
public protocol HanlinConversationStore: Sendable {
    func load(_ id: UUID, namespace: HanlinConversationNamespace) async throws -> HanlinConversationRecord?
    /// nil means create; otherwise require the exact previous revision. Caller supplies next revision.
    func save(_ record: HanlinConversationRecord, replacing revision: UInt64?) async throws
    func delete(_ id: UUID, namespace: HanlinConversationNamespace, replacing revision: UInt64) async throws
}
