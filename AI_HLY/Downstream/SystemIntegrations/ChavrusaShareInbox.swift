import Foundation

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

    func pendingItems() throws -> [ChavrusaSharedItem] {
        guard let container = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: groupID
        ) else { return [] }
        let url = container.appending(path: fileName)
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        return try JSONDecoder().decode([ChavrusaSharedItem].self, from: Data(contentsOf: url))
    }

    func clear() throws {
        guard let container = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: groupID
        ) else { return }
        let url = container.appending(path: fileName)
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }
}
