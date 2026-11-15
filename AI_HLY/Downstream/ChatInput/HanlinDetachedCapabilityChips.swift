// Visual reference: Hanlin_Detached_Active_Chips_Original_Composer.swift
// SHA-256 e3cf93feac90ff1ead2e6bd2acbb3cace1a2b89e07dd97d242e4b89751bbb5c7.
import SwiftUI

enum HanlinCapabilityContextAction: Equatable {
    case disableModes, disableChatToolUse, clearChatMCPSelection, chooseModel
}

enum HanlinDetachedCapability: String, CaseIterable, Identifiable {
    case search, thinking, tools, skills, mcp, runtimes, creative

    var id: String { rawValue }
    var title: String {
        switch self {
        case .search: return String(localized: "Search")
        case .thinking: return String(localized: "composer.capability.thinking")
        case .tools: return String(localized: "Tools")
        case .skills: return "Skills"
        case .mcp: return "MCP"
        case .runtimes: return String(localized: "composer.capability.runtimes")
        case .creative: return String(localized: "Creative")
        }
    }
    var symbol: String {
        switch self {
        case .search: return "globe.magnifyingglass"
        case .thinking: return "brain.head.profile"
        case .tools: return "hammer.fill"
        case .skills: return "puzzlepiece.extension.fill"
        case .mcp: return "server.rack"
        case .runtimes: return "terminal"
        case .creative: return "paintbrush.pointed.fill"
        }
    }
    var subtitle: String {
        switch self {
        case .search: return String(localized: "Internet and knowledge")
        case .thinking: return String(localized: "Reasoning and planning")
        case .tools: return String(localized: "Tools and actions")
        case .skills: return String(localized: "Agent capabilities")
        case .mcp: return String(localized: "Servers and connections")
        case .runtimes: return String(localized: "Local runtimes")
        case .creative: return String(localized: "Image and audio")
        }
    }

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

    func contextAction(imageGenerationActive: Bool) -> HanlinCapabilityContextAction {
        switch self {
        case .tools, .skills, .runtimes: return .disableChatToolUse
        case .mcp: return .clearChatMCPSelection
        case .creative where imageGenerationActive: return .chooseModel
        case .search, .thinking, .creative: return .disableModes
        }
    }
}

struct HanlinDetachedCapabilityChips: View {
    let capabilities: [HanlinDetachedCapability]
    let availableWidth: CGFloat
    let canDisable: (HanlinDetachedCapability) -> Bool
    let actionTitle: (HanlinDetachedCapability) -> String
    let open: (HanlinDetachedCapability) -> Void
    let disable: (HanlinDetachedCapability) -> Void

    private let blue = Color(red: 58 / 255, green: 124 / 255, blue: 180 / 255)

    static func usesCompactLayout(width: CGFloat) -> Bool { width < 510 }

    var body: some View {
        let compact = Self.usesCompactLayout(width: availableWidth)
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(capabilities) { capability in
                    Button { open(capability) } label: {
                        HStack(spacing: 4) {
                            Image(systemName: capability.symbol)
                                .font(.system(size: 13, weight: .medium))
                            if !compact {
                                Text(capability.title).font(.caption2.weight(.medium)).lineLimit(1)
                            }
                        }
                        .foregroundStyle(blue)
                        .padding(.horizontal, compact ? 9 : 10)
                        .frame(height: 32)
                        .background(blue.opacity(0.13), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        if canDisable(capability) {
                            Button(role: .destructive) { disable(capability) } label: {
                                Label(actionTitle(capability), systemImage: "power")
                            }
                        }
                    }
                    .accessibilityLabel(Text(capability.title))
                    .accessibilityValue(Text(String(localized: "Enabled")))
                    .accessibilityHint(Text(String(localized: "Open settings")))
                    .accessibilityIdentifier("composer-chip-\(capability.id)")
                }
            }
            .padding(.vertical, 2)
        }
        .frame(height: 36)
        .accessibilityIdentifier("active-tool-chips-above-composer")
    }
}
