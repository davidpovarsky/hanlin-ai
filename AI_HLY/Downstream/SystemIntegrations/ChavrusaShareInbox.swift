import Foundation
import HanlinScriptStore
import HanlinScriptExtensions
import HanlinPlatformContracts

struct ChavrusaSharedItem: Codable, Identifiable, Sendable {
    let id: UUID
    let createdAt: Date
    let text: String?
    let url: URL?
    let fileName: String?
}

actor ChavrusaShareInbox {
    static let shared = ChavrusaShareInbox()

    private let groupID = "group.com.itorah.chavrusachat"
    private let fileName = "share-inbox.json"

    func batch(_ id: UUID) throws -> HanlinShareBatch {
        try ownedStore().batch(id)
    }

    func actionPayload(_ command: HanlinScriptResumeCommand) throws -> HanlinValue {
        try HanlinShareInvocation.payload(for: command, inbox: ownedStore())
    }

    private func ownedStore() throws -> HanlinShareInboxStore {
        guard let container = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: groupID
        ) else { throw HanlinShareInboxError.invalidPath }
        return try HanlinShareInboxStore(container: container)
    }

    func pendingItems() throws -> [ChavrusaSharedItem] {
        guard let container = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: groupID
        ) else { return [] }
        let url = container.appending(path: fileName)
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        return try JSONDecoder().decode([ChavrusaSharedItem].self, from: Data(contentsOf: url))
    }

    func pendingBatches() throws -> (batches: [HanlinShareBatch], rejected: [UUID?]) {
        guard let container = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: groupID
        ) else { throw HanlinShareInboxError.invalidPath }
        return try HanlinShareInboxStore(container: container).scan()
    }

    func ownedFile(batchID: UUID, itemID: UUID) throws -> URL {
        guard let container = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: groupID
        ) else { throw HanlinShareInboxError.invalidPath }
        return try HanlinShareInboxStore(container: container).ownedFile(batchID: batchID, itemID: itemID)
    }
}
