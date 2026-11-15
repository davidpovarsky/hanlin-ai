import Foundation
import HanlinHostContracts
import SwiftData

/// The SDK store is an adapter of the existing application conversation, not a new database.
/// Legacy ChatMessages remain display projections; canonical SDK parts/receipts live here once.
@MainActor
final class HanlinAppConversationStore: HanlinConversationStore {
    let namespace: HanlinConversationNamespace
    let conversationID: UUID
    private let context: ModelContext
    private weak var conversation: ChatRecords?
    private let temporary: Bool
    private var transientRecord: HanlinConversationRecord?

    init(context: ModelContext, conversation: ChatRecords, namespace: HanlinConversationNamespace,
         conversationID: UUID, temporary: Bool) {
        self.context = context; self.conversation = conversation; self.namespace = namespace
        self.conversationID = conversationID; self.temporary = temporary
    }

    func requireOriginalConversation() throws -> ChatRecords {
        guard let conversation, conversation.id == conversationID else { throw HanlinHostError.staleContext }
        if !temporary {
            let id = conversationID
            let rows = try context.fetch(FetchDescriptor<ChatRecords>(predicate: #Predicate { $0.id == id }))
            guard rows.count == 1, rows.first === conversation else { throw HanlinHostError.staleContext }
        }
        return conversation
    }

    func belongsTo(context: ModelContext, conversation: ChatRecords, temporary: Bool) -> Bool {
        self.context === context && self.conversation === conversation && self.temporary == temporary
    }

    func load(_ id: UUID, namespace: HanlinConversationNamespace) async throws -> HanlinConversationRecord? {
        guard id == conversationID, namespace == self.namespace else { throw HanlinHostError.staleContext }
        let row = try requireOriginalConversation()
        let record: HanlinConversationRecord?
        if temporary { record = transientRecord }
        else if let bytes = row.agentSDKRecordData {
            guard bytes.count <= 4 * 1_048_576 else { throw HanlinHostError.storageLimitExceeded }
            record = try JSONDecoder().decode(HanlinConversationRecord.self, from: bytes)
        } else { record = nil }
        if let record {
            try record.validate()
            guard record.conversationID == id, record.namespace == namespace else { throw HanlinHostError.invalidRecord }
        }
        return record
    }

    func save(_ record: HanlinConversationRecord, replacing revision: UInt64?) async throws {
        try record.validate()
        let old = try await load(record.conversationID, namespace: record.namespace)
        guard old?.revision == revision,
              revision.map({ $0 < UInt64.max && record.revision == $0 + 1 }) ?? (record.revision == 0) else {
            throw HanlinHostError.storeConflict
        }
        let row = try requireOriginalConversation()
        let bytes = try JSONEncoder().encode(record)
        guard bytes.count <= 4 * 1_048_576 else { throw HanlinHostError.storageLimitExceeded }
        if temporary { transientRecord = record; return }
        let original = row.agentSDKRecordData
        row.agentSDKRecordData = bytes
        do { try context.save() }
        catch { row.agentSDKRecordData = original; throw error }
    }

    func delete(_ id: UUID, namespace: HanlinConversationNamespace, replacing revision: UInt64) async throws {
        guard try await load(id, namespace: namespace)?.revision == revision else { throw HanlinHostError.storeConflict }
        let row = try requireOriginalConversation()
        if temporary { transientRecord = nil; return }
        let original = row.agentSDKRecordData
        row.agentSDKRecordData = nil
        do { try context.save() }
        catch { row.agentSDKRecordData = original; throw error }
    }
}
