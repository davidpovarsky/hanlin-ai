import Foundation
import HanlinHostContracts
import SwiftData

public enum HanlinConversationMutationError: Error, Equatable, Sendable {
    case emptyTitle
}

/// The original UI and public application facade mutate the same SwiftData rows.
/// Destructive operations revoke live authority before the save boundary. There
/// is no second conversation database, account lifecycle or history format here.
@MainActor
enum HanlinConversationMutation {
    struct Change: Sendable {
        enum Kind: Sendable { case metadata, historyCleared, deleted }
        let conversationID: UUID
        let originalRow: ObjectIdentifier
        let kind: Kind
        let messageID: UUID?
    }

    static let didChange = Notification.Name("HanlinOriginalConversationDidChange")

    static func change(from notification: Notification, in container: ModelContainer,
                       conversationID: UUID? = nil) -> Change? {
        guard let originalContainer = notification.object as? ModelContainer,
              originalContainer === container,
              let change = notification.userInfo?["change"] as? Change,
              conversationID == nil || conversationID == change.conversationID else { return nil }
        return change
    }

    @discardableResult
    static func requireOriginal(_ record: ChatRecords, in context: ModelContext,
                                temporary: Bool = false) throws -> ChatRecords {
        guard !record.isDeleted, let id = record.id,
              record.modelContext === context || (temporary && record.modelContext == nil) else {
            throw HanlinHostError.staleContext
        }
        return try HanlinAppConversationStore.requireOriginalConversation(context: context,
            conversation: record, conversationID: id, temporary: temporary)
    }

    private static func saveMetadata(_ record: ChatRecords, in context: ModelContext,
                                     temporary: Bool, update: () -> Void) throws {
        try requireOriginal(record, in: context, temporary: temporary)
        if temporary && record.modelContext == nil { update(); return }
        if context.hasChanges { try context.save() }
        update()
        do { try context.save() }
        catch { context.rollback(); throw error }
    }

    @discardableResult
    static func rename(_ record: ChatRecords, title: String, announceChange: Bool,
                       in context: ModelContext, temporary: Bool = false) throws -> ChatMessages? {
        guard !title.isEmpty else { throw HanlinConversationMutationError.emptyTitle }
        try requireOriginal(record, in: context, temporary: temporary)
        guard record.name != title else { return nil }
        let ephemeral = temporary && record.modelContext == nil
        var announcement: ChatMessages?
        try saveMetadata(record, in: context, temporary: temporary) {
            if announceChange {
                let currentLanguage = Locale.preferredLanguages.first ?? "zh-Hans"
                let text: String
                if currentLanguage.hasPrefix("zh") {
                    text = "群聊名称被修改为“\(title)”"
                } else {
                    text = "Group chat name has been changed to \"\(title)\""
                }
                let message = ChatMessages(role: "information", text: text,
                    modelDisplayName: "system", timestamp: Date(), record: record)
                if ephemeral { record.messages = (record.messages ?? []) + [message] }
                else { context.insert(message) }
                announcement = message
            }
            record.name = title
        }
        publish(record.id!, originalRow: ObjectIdentifier(record), kind: .metadata, messageID: announcement?.id, in: context.container)
        return announcement
    }

    /// The original list editor also changes icon/color and permits its existing
    /// empty-title behavior; those exact fields remain one atomic metadata save.
    static func updateAppearance(_ record: ChatRecords, title: String, icon: String,
                                 color: String, in context: ModelContext) throws {
        try saveMetadata(record, in: context, temporary: false) {
            record.name = title
            record.icon = icon
            record.color = color
        }
        publish(record.id!, originalRow: ObjectIdentifier(record), kind: .metadata, in: context.container)
    }

    static func setPinned(_ record: ChatRecords, isPinned: Bool, in context: ModelContext) throws {
        try saveMetadata(record, in: context, temporary: false) { record.isPinned = isPinned }
        publish(record.id!, originalRow: ObjectIdentifier(record), kind: .metadata, in: context.container)
    }

    static func delete(_ record: ChatRecords, in context: ModelContext, temporary: Bool = false) throws {
        try requireOriginal(record, in: context, temporary: temporary)
        let id = record.id!
        HanlinConversationRunLease.revoke(container: context.container, conversationID: id)
        if temporary && record.modelContext == nil {
            record.messages = []
            record.agentSDKRecordData = nil
        } else {
            if context.hasChanges { try context.save() }
            context.delete(record)
            do { try context.save() }
            catch { context.rollback(); throw error }
        }
        publish(id, originalRow: ObjectIdentifier(record), kind: .deleted, in: context.container)
    }

    static var originalClearedText: String {
        let currentLanguage = Locale.preferredLanguages.first ?? "zh-Hans"
        return currentLanguage.hasPrefix("zh") ? "一切都是崭新的✨" : "Everything is brand new ✨"
    }

    /// Delegates to the existing visible/canonical clear-history transaction and
    /// its empty revision CAS barrier. A supplied original owner keeps its exact
    /// temporary store; public persistent callers use the same adapter/schema.
    @discardableResult
    static func clearHistory(_ record: ChatRecords, in context: ModelContext, temporary: Bool = false,
                             replacementText: String? = nil,
                             originalStore: HanlinAppConversationStore? = nil) throws -> ChatMessages {
        try requireOriginal(record, in: context, temporary: temporary)
        let id = record.id!
        let namespace = try HanlinApplicationContextRegistry.configuration(for: context.container)
            .namespace(conversationID: id, temporary: temporary)
        let store: HanlinAppConversationStore
        if let originalStore {
            guard originalStore.namespace == namespace,
                  originalStore.belongsTo(context: context, conversation: record, temporary: temporary) else {
                throw HanlinHostError.staleContext
            }
            store = originalStore
        } else {
            store = HanlinAppConversationStore(context: context, conversation: record,
                namespace: namespace, conversationID: id, temporary: temporary)
        }
        HanlinConversationRunLease.revoke(container: context.container, conversationID: id)
        let replacement = try store.clearHistory(replacementText: replacementText ?? originalClearedText)
        publish(id, originalRow: ObjectIdentifier(record), kind: .historyCleared, messageID: replacement.id, in: context.container)
        return replacement
    }

    private static func publish(_ id: UUID, originalRow: ObjectIdentifier,
                                kind: Change.Kind, messageID: UUID? = nil, in container: ModelContainer) {
        let change = Change(conversationID: id, originalRow: originalRow, kind: kind, messageID: messageID)
        HanlinConversationControllerRegistry.conversationDidChange(change, in: container)
        NotificationCenter.default.post(name: didChange, object: container, userInfo: ["change": change])
    }
}
