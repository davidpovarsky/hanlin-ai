import Foundation
import HanlinPlatformContracts

struct AssistantToolRequestScope: Hashable, Sendable {
    var chatID: UUID?
    var mcpServerIDs: Set<UUID>
    var mcpGloballyEnabled: Bool
    var isTemporaryChat: Bool = false
    var capabilityAttachments: [HanlinCapabilityAttachment] = []

    static let nativeOnly = AssistantToolRequestScope(
        chatID: nil,
        mcpServerIDs: [],
        mcpGloballyEnabled: false,
        isTemporaryChat: false
    )
}
