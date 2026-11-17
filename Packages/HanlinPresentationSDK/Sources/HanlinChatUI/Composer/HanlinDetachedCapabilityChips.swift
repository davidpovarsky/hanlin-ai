// Visual reference: Hanlin_Detached_Active_Chips_Original_Composer.swift
// SHA-256 e3cf93feac90ff1ead2e6bd2acbb3cace1a2b89e07dd97d242e4b89751bbb5c7.
import SwiftUI

public enum HanlinCapabilityContextAction: Equatable, Sendable {
    case disableModes, disableChatToolUse, clearChatMCPSelection, chooseModel
}

public enum HanlinDetachedCapability: String, CaseIterable, Identifiable, Sendable {
    case search, thinking, tools, skills, mcp, runtimes, creative

    public var id: String { rawValue }
    public var title: String {
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
    public var symbol: String {
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
    public var subtitle: String {
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

    public func contextAction(imageGenerationActive: Bool) -> HanlinCapabilityContextAction {
        switch self {
        case .tools, .skills, .runtimes: return .disableChatToolUse
        case .mcp: return .clearChatMCPSelection
        case .creative where imageGenerationActive: return .chooseModel
        case .search, .thinking, .creative: return .disableModes
        }
    }
}

public struct HanlinDetachedCapabilityChips: View {
    let capabilities: [HanlinDetachedCapability]
    let availableWidth: CGFloat
    let canDisable: (HanlinDetachedCapability) -> Bool
    let actionTitle: (HanlinDetachedCapability) -> String
    let open: (HanlinDetachedCapability) -> Void
    let disable: (HanlinDetachedCapability) -> Void

    public init(capabilities: [HanlinDetachedCapability], availableWidth: CGFloat,
                canDisable: @escaping (HanlinDetachedCapability) -> Bool,
                actionTitle: @escaping (HanlinDetachedCapability) -> String,
                open: @escaping (HanlinDetachedCapability) -> Void,
                disable: @escaping (HanlinDetachedCapability) -> Void) {
        self.capabilities = capabilities; self.availableWidth = availableWidth
        self.canDisable = canDisable; self.actionTitle = actionTitle
        self.open = open; self.disable = disable
    }

    private let blue = Color(red: 58 / 255, green: 124 / 255, blue: 180 / 255)

    public static func usesCompactLayout(width: CGFloat) -> Bool { width < 510 }

    public var body: some View {
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
