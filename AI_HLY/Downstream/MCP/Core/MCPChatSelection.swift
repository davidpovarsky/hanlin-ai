import Foundation

struct MCPChatSelection: Codable, Hashable, Sendable {
    var chatID: UUID
    var serverIDs: Set<UUID>
    var updatedAt: Date

    init(chatID: UUID, serverIDs: Set<UUID>, updatedAt: Date = .now) {
        self.chatID = chatID
        self.serverIDs = serverIDs
        self.updatedAt = updatedAt
    }
}
