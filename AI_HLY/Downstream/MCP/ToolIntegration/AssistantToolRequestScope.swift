import Foundation

struct AssistantToolRequestScope: Hashable, Sendable {
    var chatID: UUID?
    var mcpServerIDs: Set<UUID>
    var mcpGloballyEnabled: Bool
    var isTemporaryChat: Bool = false

    static let nativeOnly = AssistantToolRequestScope(
        chatID: nil,
        mcpServerIDs: [],
        mcpGloballyEnabled: false,
        isTemporaryChat: false
    )
}
