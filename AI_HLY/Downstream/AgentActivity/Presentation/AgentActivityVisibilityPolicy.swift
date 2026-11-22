import Foundation

/// The activity tree represents invocations, not transport, capability discovery,
/// skill instructions, or model prose. Stored events remain available for audit.
enum AgentActivityVisibilityPolicy {
    static let internalToolNames: Set<String> = [
        "load_skill", "read_skill_resource", "tool_search", "read_tool_result", "report_progress"
    ]

    static func isInternalTool(_ name: String) -> Bool {
        internalToolNames.contains(name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
    }

    static func showsInvocation(kind: String, toolName: String?, hasIdentity: Bool) -> Bool {
        guard hasIdentity, !isInternalTool(toolName ?? "") else { return false }
        switch kind {
        case "toolCall", "toolExecution", "webSearch", "sourceRead", "documentRead",
             "codeExecution", "map", "calendar", "health", "nativeApp":
            return true
        default:
            return false
        }
    }
}
