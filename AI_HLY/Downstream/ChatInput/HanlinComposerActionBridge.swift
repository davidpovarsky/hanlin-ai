//
//  HanlinComposerActionBridge.swift
//  AI_HLY
//
//  Authoritative zero-shadow-state bridge connecting the two-entry composer popovers
//  directly to the original ChatViewBottom bindings, model capabilities, and runtime services.
//

import Foundation
import SwiftUI

/// Summarizes an active mode or capability chip displayed above the composer editor.
struct HanlinComposerActiveChip: Identifiable, Equatable, Sendable {
    enum Kind: String, Equatable, Sendable {
        case search
        case knowledge
        case thinking
        case planning
        case audio
        case tools
        case mcp
        case imageGen
        case localModel
    }

    let id: String
    let kind: Kind
    let title: String
    let systemImage: String
    let isRemovable: Bool
}

/// Evaluates capability truth tables and mutates original composer bindings directly.
@MainActor
struct HanlinComposerActionBridge {

    // MARK: - Capability Truth Table

    struct ModelCapabilitySnapshot: Equatable, Sendable {
        let modelName: String
        let displayName: String
        let company: String
        let identity: String
        let icon: String
        let price: Int16
        let isLocal: Bool
        let supportsSearch: Bool
        let supportsTextGen: Bool
        let supportsMultimodal: Bool
        let supportsReasoning: Bool
        let supportReasoningChange: Bool
        let supportsImageGen: Bool
        let supportsVoiceGen: Bool
        let supportsToolUse: Bool

        init(model: AllModels?) {
            self.modelName = model?.name ?? ""
            self.displayName = model?.displayName ?? model?.name ?? String(localized: "Select Model")
            self.company = model?.company ?? "UNKNOWN"
            self.identity = model?.identity ?? "model"
            self.icon = model?.icon ?? "sparkles"
            self.price = model?.price ?? 0
            self.isLocal = (model?.company?.uppercased() == "LOCAL")
            self.supportsSearch = model?.supportsSearch ?? false
            self.supportsTextGen = model?.supportsTextGen ?? true
            self.supportsMultimodal = model?.supportsMultimodal ?? false
            self.supportsReasoning = model?.supportsReasoning ?? false
            self.supportReasoningChange = model?.supportReasoningChange ?? false
            self.supportsImageGen = model?.supportsImageGen ?? false
            self.supportsVoiceGen = model?.supportsVoiceGen ?? false
            self.supportsToolUse = model?.supportsToolUse ?? false
        }
    }

    static func capabilitySnapshot(for model: AllModels?) -> ModelCapabilitySnapshot {
        ModelCapabilitySnapshot(model: model)
    }

    /// Computes active mode chips from live composer state so the user can see and dismiss active modes at a glance.
    static func activeModeChips(
        capability: ModelCapabilitySnapshot,
        ifSearch: Bool,
        ifKnowledge: Bool,
        ifThink: Bool,
        thinkingLength: Int,
        ifPlanning: Bool,
        ifAudio: Bool,
        ifToolUse: Bool,
        activeMCPServerCount: Int,
        selectedImageSize: String
    ) -> [HanlinComposerActiveChip] {
        var chips: [HanlinComposerActiveChip] = []

        if capability.supportsSearch && ifSearch {
            chips.append(
                HanlinComposerActiveChip(
                    id: "search",
                    kind: .search,
                    title: String(localized: "Online Search"),
                    systemImage: "globe",
                    isRemovable: true
                )
            )
        }
        if capability.supportsTextGen && ifKnowledge {
            chips.append(
                HanlinComposerActiveChip(
                    id: "knowledge",
                    kind: .knowledge,
                    title: String(localized: "Knowledge Bag"),
                    systemImage: "book.closed.fill",
                    isRemovable: true
                )
            )
        }
        if capability.supportsReasoning && ifThink {
            let suffix = thinkingLengthShortLabel(thinkingLength)
            let label = suffix.isEmpty
                ? String(localized: "Deep Thinking")
                : "\(String(localized: "Deep Thinking")) · \(suffix)"
            chips.append(
                HanlinComposerActiveChip(
                    id: "thinking",
                    kind: .thinking,
                    title: label,
                    systemImage: "sparkles",
                    isRemovable: capability.supportReasoningChange
                )
            )
        }
        if capability.supportsTextGen && ifPlanning {
            chips.append(
                HanlinComposerActiveChip(
                    id: "planning",
                    kind: .planning,
                    title: String(localized: "Planning"),
                    systemImage: "list.bullet.clipboard.fill",
                    isRemovable: true
                )
            )
        }
        if capability.supportsVoiceGen && ifAudio {
            chips.append(
                HanlinComposerActiveChip(
                    id: "audio",
                    kind: .audio,
                    title: String(localized: "Voice Output"),
                    systemImage: "waveform",
                    isRemovable: true
                )
            )
        }
        if capability.supportsToolUse && ifToolUse {
            chips.append(
                HanlinComposerActiveChip(
                    id: "tools",
                    kind: .tools,
                    title: String(localized: "Tools"),
                    systemImage: "hammer.fill",
                    isRemovable: true
                )
            )
        }
        if activeMCPServerCount > 0 {
            chips.append(
                HanlinComposerActiveChip(
                    id: "mcp",
                    kind: .mcp,
                    title: "MCP (\(activeMCPServerCount))",
                    systemImage: "server.rack",
                    isRemovable: false
                )
            )
        }
        if capability.supportsImageGen {
            chips.append(
                HanlinComposerActiveChip(
                    id: "imageGen",
                    kind: .imageGen,
                    title: selectedImageSize,
                    systemImage: "paintbrush.pointed.fill",
                    isRemovable: false
                )
            )
        }
        if capability.isLocal {
            chips.append(
                HanlinComposerActiveChip(
                    id: "localModel",
                    kind: .localModel,
                    title: String(localized: "On-Device"),
                    systemImage: "bolt.horizontal.icloud.fill",
                    isRemovable: false
                )
            )
        }

        return chips
    }

    static func thinkingLengthShortLabel(_ length: Int) -> String {
        switch length {
        case 1: return String(localized: "Short")
        case 2: return String(localized: "Medium")
        case 3: return String(localized: "Long")
        default: return String(localized: "Auto")
        }
    }

    /// Computes the badge count shown on the direct Tools/Skills/MCP shortcut button.
    static func activeToolsShortcutCount(
        capability: ModelCapabilitySnapshot,
        ifToolUse: Bool,
        selectedMCPCount: Int
    ) -> Int {
        var count = 0
        if capability.supportsToolUse && ifToolUse {
            count += 1
        }
        count += max(0, selectedMCPCount)
        return count
    }
}
