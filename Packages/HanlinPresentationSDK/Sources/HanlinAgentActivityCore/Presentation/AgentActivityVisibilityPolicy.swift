import Foundation

/// The activity tree represents real reasoning phases and tool invocations.
/// Transport, capability discovery and skill-loading prose stay in the audit.
public enum AgentActivityVisibilityPolicy {
    public static let internalToolNames: Set<String> = [
        "load_skill", "read_skill_resource", "tool_search", "read_tool_result", "report_progress"
    ]

    public static func isInternalTool(_ name: String) -> Bool {
        internalToolNames.contains(name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
    }

    public static func showsActivity(kind: String, toolName: String?, hasIdentity: Bool) -> Bool {
        if kind == "reasoning" { return hasIdentity }
        return showsInvocation(kind: kind, toolName: toolName, hasIdentity: hasIdentity)
    }

    /// Input is the projected activity kind, not a transport status string.
    /// A real reasoning event stops owning motion at the first answer text;
    /// an independently running tool can continue alongside that answer.
    public static func animatesActivity(kind: String, status: String, isRunActive: Bool,
                                 hasAnswerText: Bool, isAwaitingApproval: Bool) -> Bool {
        guard isRunActive, status == "running", !isAwaitingApproval else { return false }
        if kind == "reasoning" { return !hasAnswerText }
        return ["tool", "search", "source", "document", "code", "map", "calendar", "health"].contains(kind)
    }

    public static func showsInvocation(kind: String, toolName: String?, hasIdentity: Bool) -> Bool {
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
