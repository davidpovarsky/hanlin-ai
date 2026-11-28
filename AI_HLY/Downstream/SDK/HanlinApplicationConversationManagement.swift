import Foundation

public extension HanlinApplicationContext {
    /// Uses the original title edit and its optional information-row announcement.
    /// Empty titles throw; no new conversation or identifier is created.
    @discardableResult
    func renameConversation(_ conversationID: UUID, title: String,
                            announceChange: Bool = true) throws -> HanlinConversationSummary {
        let original = try record(conversationID)
        try HanlinConversationMutation.rename(original, title: title, announceChange: announceChange,
            in: modelContainer.mainContext)
        return HanlinConversationSummary(original)
    }

    @discardableResult
    func setConversationPinned(_ conversationID: UUID, isPinned: Bool) throws -> HanlinConversationSummary {
        let original = try record(conversationID)
        try HanlinConversationMutation.setPinned(original, isPinned: isPinned, in: modelContainer.mainContext)
        return HanlinConversationSummary(original)
    }

    /// Revokes original preparation, live turns, inline tools and consent before
    /// deleting the exact row and its original cascading messages. A failed save
    /// is returned to the host and rolls back this mutation.
    func deleteConversation(_ conversationID: UUID) throws {
        try HanlinConversationMutation.delete(record(conversationID), in: modelContainer.mainContext)
    }

    /// Preserves the original conversation title, draft, canvas and saved excerpts.
    /// The existing original-store transaction clears visible/canonical history
    /// together and keeps its empty revision barrier against delayed old writes.
    /// This is logical history deletion, not account or physical-backup erasure.
    @discardableResult
    func clearConversationHistory(_ conversationID: UUID) throws -> HanlinConversationMessageSnapshot {
        let replacement = try HanlinConversationMutation.clearHistory(record(conversationID),
            in: modelContainer.mainContext)
        return HanlinConversationMessageSnapshot(replacement)
    }
}
