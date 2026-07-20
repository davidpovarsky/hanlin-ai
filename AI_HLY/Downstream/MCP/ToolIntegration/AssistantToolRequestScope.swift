import Foundation

struct AssistantToolRequestScope: Hashable, Sendable {
    var chatID: UUID?
    var mcpServerIDs: Set<UUID>
    var mcpGloballyEnabled: Bool

    static let nativeOnly = AssistantToolRequestScope(
        chatID: nil,
        mcpServerIDs: [],
        mcpGloballyEnabled: false
    )
}
