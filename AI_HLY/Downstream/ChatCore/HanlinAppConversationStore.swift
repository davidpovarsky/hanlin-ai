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
        guard let conversation else { throw HanlinHostError.staleContext }
        if !temporary {
            let id = conversationID
            let rows = try context.fetch(FetchDescriptor<ChatRecords>(predicate: #Predicate { $0.id == id }))
            guard rows.count == 1, rows.first === conversation else { throw HanlinHostError.staleContext }
        }
        guard conversation.id == conversationID else { throw HanlinHostError.staleContext }
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
    /// Cold historical reconciliation only, when composition proves no live Session writer is
    /// running. Uses this SAME adapter/CAS and metadata receipt; never creates a missing record.
    func persistHistoricalReceipt(_ event: HanlinHostResultEvent, originReference: String,
                                  receiptReference: String) async throws {
        guard event.call.session.conversationID == conversationID,
              event.call.session.context.namespace == namespace,
              originReference.utf8.count <= 4096, receiptReference.utf8.count <= 4096,
              let old = try await load(conversationID, namespace: namespace), old.revision < UInt64.max,
              old.entries.contains(where: {
                  if case .presentationReference(1, let value) = $0.payload { return value.utf8.elementsEqual(originReference.utf8) }
                  return false
              }) else { throw HanlinHostError.staleContext }
        let hasOriginalIdentity = old.entries.contains {
            if case .hostResultIdentity(let id, let call) = $0.payload { return id == event.resultID && call == event.call }
            return false
        }
        if hasOriginalIdentity, old.entries.contains(where: {
            guard case .toolResult(let providerID, let receipt) = $0.payload else { return false }
            return providerID == event.call.providerCallID && receipt.result.invocationID == event.call.invocationID
                && receipt.result.logicalToolID == event.call.logicalToolID
                && receipt.context == event.call.session.context && receipt.effectState == event.result.effectState
                && receipt.reconciliationReference == event.result.reconciliationReference
                && receipt.result.outcome == event.result.metadataReceipt().result.outcome
        }) { return }
        let prefix = "hanlin.split.receipt.v1:" + event.resultID.uuidString.lowercased() + ":"
        for entry in old.entries {
            if case .presentationReference(1, let value) = entry.payload, value.hasPrefix(prefix) {
                guard value.utf8.elementsEqual(receiptReference.utf8) else { throw HanlinHostError.resultMismatch }
                return
            }
        }
        guard old.entries.last?.sequence != UInt64.max else { throw HanlinHostError.storageLimitExceeded }
        let next = old.entries.last.map { $0.sequence + 1 } ?? 0
        guard next < UInt64.max - 3 else { throw HanlinHostError.storageLimitExceeded }
        let additions: [HanlinTranscriptPayload] = [.hostResultIdentity(resultID: event.resultID, call: event.call),
            .toolResult(providerCallID: event.call.providerCallID, result: event.result.metadataReceipt()),
            .presentationReference(version: 1, opaqueReference: receiptReference)]
        let entries = old.entries + additions.enumerated().map { offset, payload in
            HanlinTranscriptEntry(runID: event.call.runID, step: event.call.step,
                sequence: next + UInt64(offset), payload: payload)
        }
        try await save(.init(namespace: namespace, conversationID: conversationID, revision: old.revision + 1,
            model: old.model, draft: old.draft, entries: entries), replacing: old.revision)
    }

}
