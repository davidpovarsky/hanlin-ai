import Foundation
import HanlinPlatformContracts

/// Represents compact skill discovery metadata formatted for agent system prompt injection.
public enum HanlinSkillIndex {
    /// Builds a concise, context-efficient index of available skills.
    /// Does not include full instructions or full schemas.
    public static func formattedIndex(skills: [HanlinSkillDescriptor]) -> String {
        guard !skills.isEmpty else { return "" }
        var lines: [String] = [
            "Available Skills (call load_skill(skill_id) to activate instructions and tools):"
        ]
        for skill in skills {
            let id = skill.id.rawValue
            let title = skill.title.preferredValue()
            let summary = skill.summary.preferredValue()
            var line = "- \(title) (`\(id)`): \(summary)"
            if !skill.triggerHints.isEmpty {
                line += " [Triggers: \(skill.triggerHints.joined(separator: ", "))]"
            }
            lines.append(line)
        }
        lines.append("To find tools not listed above, call tool_search(query: \"...\").")
        return lines.joined(separator: "\n")
    }

    /// Convenience alias matching APIManager integration.
    public static func prompt(for skills: [HanlinSkillDescriptor]) -> String {
        formattedIndex(skills: skills)
    }
}
