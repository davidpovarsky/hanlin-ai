import Foundation
import HanlinChatCore
import SwiftData

/// Owns the original schema, persistence and bootstrap for the embedded UI.
/// Keep one context alive for all views using the same model container.
@MainActor
public final class HanlinApplicationContext {
    public let configuration: HanlinApplicationConfiguration
    public let modelContainer: ModelContainer
    let dataManager: AppDataManager
    let applicationLifecycle = HanlinApplicationLifecycleState()

    /// Supply a container when the host owns persistence. Include
    /// `HanlinApplicationContext.schema` in that container's schema; no separate
    /// conversation database or duplicate writer is created.
    public init(configuration: HanlinApplicationConfiguration,
                modelContainer: ModelContainer? = nil) throws {
        _ = try configuration.namespace(conversationID: UUID(), temporary: false)
        _ = try configuration.namespace(conversationID: UUID(), temporary: true)
        let container = try modelContainer ?? configuration.makeModelContainer()
        let requiredEntities = Set(Self.schema.entities.map(\.name))
        guard requiredEntities.isSubset(of: Set(container.schema.entities.map(\.name))) else {
            throw HanlinApplicationError.incompatibleModelContainer
        }
        try HanlinApplicationProcessRuntime.shared.install(configuration.runtime, modelContainer: container)
        self.configuration = configuration
        self.modelContainer = container
        self.dataManager = AppDataManager(modelContainer: container)
        try HanlinApplicationContextRegistry.register(self)
        HanlinApplicationCredentialRegistry.shared.register(container, credentials: configuration.credentials)
    }

    /// The unchanged original SwiftData model types remain in module AI_Hanlin.
    /// Hosts may merge this schema's entities with their own persistent models.
    public static var schema: Schema { AppDataManager.schema }
    public static var modelTypes: [any PersistentModel.Type] { AppDataManager.modelTypes }

    /// Creates the same conversation and welcome row as the original workspace,
    /// using the original model readiness/selection policy.
    @discardableResult
    public func createConversation(title: String? = nil) throws -> UUID {
        dataManager.preloadDataIfNeeded()
        let record = try HanlinConversationCreation.create(in: modelContainer.mainContext, title: title)
        guard let id = record.id else { throw HanlinApplicationError.invalidConversation }
        return id
    }

    public func conversation(_ id: UUID) throws -> HanlinConversationSummary {
        HanlinConversationSummary(try record(id))
    }

    public func conversations() throws -> [HanlinConversationSummary] {
        let records = try modelContainer.mainContext.fetch(FetchDescriptor<ChatRecords>(
            sortBy: [SortDescriptor(\ChatRecords.lastEdited, order: .reverse)]))
        return records.compactMap { record in
            guard record.id != nil else { return nil }
            return HanlinConversationSummary(record)
        }
    }

    func record(_ id: UUID) throws -> ChatRecords {
        let identifier: UUID? = id
        var descriptor = FetchDescriptor<ChatRecords>(predicate: #Predicate { $0.id == identifier })
        descriptor.fetchLimit = 2
        let records = try modelContainer.mainContext.fetch(descriptor)
        guard let record = records.first else { throw HanlinApplicationError.conversationNotFound(id) }
        guard records.count == 1 else { throw HanlinApplicationError.duplicateConversation(id) }
        return record
    }
}

public struct HanlinConversationSummary: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let title: String
    public let lastEdited: Date
    public let isPinned: Bool

    @MainActor
    init(_ record: ChatRecords) {
        // Callers exclude legacy rows without an identifier before constructing
        // a public route; never invent an identifier for an existing row.
        precondition(record.id != nil)
        id = record.id!
        title = record.name ?? ""
        lastEdited = record.lastEdited
        isPinned = record.isPinned
    }
}

/// One creation implementation serves both the original workspace and the
/// public context. Original model selection and welcome text are preserved.
@MainActor
enum HanlinConversationCreation {
    static func create(in context: ModelContext, title: String? = nil) throws -> ChatRecords {
        let models = try context.fetch(FetchDescriptor<AllModels>(
            sortBy: [SortDescriptor(\AllModels.position, order: .forward)]))
        let providers = try context.fetch(FetchDescriptor<APIKeys>())
        guard let selectedIndex = HanlinDefaultChatPolicy.creationModelIndex(
            in: models, providers: providers) else { throw HanlinApplicationError.noChatModelReady }
        let language = Locale.preferredLanguages.first ?? "zh-Hans"
        let chatName = title ?? (language.hasPrefix("zh") ? "新群聊" : "New Group Chat")
        let welcomeText = language.hasPrefix("zh")
            ? "欢迎加入新群聊👏" : "Welcome to the new group chat! 👏"
        let record = ChatRecords(name: chatName, type: "chat", lastEdited: Date(), useModel: selectedIndex)
        let welcome = ChatMessages(role: "information", text: welcomeText,
            reasoning: "", modelDisplayName: "System", timestamp: Date(), record: record)
        context.insert(record)
        context.insert(welcome)
        do { try context.save() }
        catch {
            // Remove only this new insertion; unrelated host edits are not rolled back.
            context.delete(welcome)
            context.delete(record)
            throw error
        }
        return record
    }
}
