import HanlinChatUI

// Host capability decisions stay in Hanlin. The SDK only presents their result.
typealias HanlinCapabilityContextAction = HanlinChatUI.HanlinCapabilityContextAction
typealias HanlinDetachedCapability = HanlinChatUI.HanlinDetachedCapability
typealias HanlinDetachedCapabilityChips = HanlinChatUI.HanlinDetachedCapabilityChips

extension HanlinChatUI.HanlinDetachedCapability {
    /// Projects enabled, model-supported controls already computed by the
    /// action bridge. Model identity and image dimensions are not toggles.
    static func enabled(from chips: [HanlinComposerActiveChip], mcpEnabled: Bool, hasModel: Bool,
                        toolUseEnabled: Bool, toolsEligible: Bool, skillsEligible: Bool, runtimesEligible: Bool) -> [Self] {
        func has(_ kind: HanlinComposerActiveChip.Kind) -> Bool { chips.contains { $0.kind == kind } }
        let toolGate = hasModel && toolUseEnabled
        return allCases.filter { group in
            if !hasModel { return false }
            switch group {
            case .search: return has(.search) || has(.knowledge)
            case .thinking: return has(.thinking) || has(.planning)
            case .tools: return toolGate && toolsEligible
            case .skills: return toolGate && skillsEligible
            case .mcp: return toolGate && mcpEnabled && has(.mcp)
            case .runtimes: return toolGate && runtimesEligible
            case .creative: return has(.audio) || has(.imageGen)
            }
        }
    }

    func canDisable(from chips: [HanlinComposerActiveChip]) -> Bool {
        guard self == .thinking else { return true }
        return !chips.contains { $0.kind == .thinking && !$0.isRemovable }
    }

}
