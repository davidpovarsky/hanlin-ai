import Foundation
import HanlinHostContracts

/// Ephemeral conversations and fixtures; no durable-write or entitlement claim.
public actor HanlinInMemoryConversationStore: HanlinConversationStore {
    private struct Key: Hashable { let namespace: HanlinConversationNamespace; let id: UUID }
    private var records: [Key: HanlinConversationRecord] = [:]
    public init() {}
    public func load(_ id: UUID, namespace: HanlinConversationNamespace) -> HanlinConversationRecord? {
        records[Key(namespace: namespace, id: id)]
    }
    public func save(_ record: HanlinConversationRecord, replacing revision: UInt64?) throws {
        try record.validate()
        let key = Key(namespace: record.namespace, id: record.conversationID)
        guard records[key]?.revision == revision,
              revision.map({ $0 < UInt64.max && record.revision == $0 + 1 }) ?? (record.revision == 0) else { throw HanlinHostError.storeConflict }
        records[key] = record
    }
    public func delete(_ id: UUID, namespace: HanlinConversationNamespace, replacing revision: UInt64) throws {
        let key = Key(namespace: namespace, id: id)
        guard records[key]?.revision == revision else { throw HanlinHostError.storeConflict }
        records[key] = nil
    }
}
