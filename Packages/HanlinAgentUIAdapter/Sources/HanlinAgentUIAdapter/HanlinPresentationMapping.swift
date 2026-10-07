// Packages/HanlinAgentUIAdapter/Sources/HanlinAgentUIAdapter/HanlinPresentationMapping.swift
import Foundation
import HanlinPlatformContracts
import AgentUI

public enum HanlinPresentationMapping {
    public static func map(preset: HanlinEmbeddedSizePreset) -> AgentEmbeddedSizePreset {
        switch preset {
        case .automatic: return .automatic
        case .compact: return .compact
        case .regular: return .regular
        case .large: return .large
        }
    }

    public static func map(sizing: HanlinEmbeddedSizingPreference) -> AgentEmbeddedSizingPreference {
        AgentEmbeddedSizingPreference(
            preset: map(preset: sizing.preset),
            idealHeight: sizing.preferredHeight,
            maxHeight: nil
        )
    }

    public static func map(mode: HanlinExpansionMode) -> AgentExpansionMode {
        switch mode {
        case .sheet: return .sheet
        case .fullScreen: return .fullScreen
        case .window: return .window
        }
    }

    public static func map(expansion: HanlinExpansionDescriptor?) -> AgentExpansionDescriptor {
        guard let expansion else {
            return AgentExpansionDescriptor(allowedModes: [.sheet], preferredMode: .sheet, supportsInlineCollapse: true)
        }
        let modes = expansion.supportedModes.map { map(mode: $0) }
        return AgentExpansionDescriptor(
            allowedModes: modes.isEmpty ? [.sheet] : modes,
            preferredMode: modes.first ?? .sheet,
            supportsInlineCollapse: true
        )
    }

    public static func map(action: HanlinEmbeddedContentAction) -> AgentEmbeddedContentAction {
        AgentEmbeddedContentAction(
            id: action.id,
            title: action.title,
            iconSystemName: action.systemImage,
            actionID: action.launchRequest?.intent.rawValue ?? action.id
        )
    }

    public static func map(payload: HanlinEmbeddedResultPayload) -> AgentEmbeddedPayload {
        var dict: [String: String] = payload.metadata ?? [:]
        if let title = payload.title {
            dict["title"] = title
        }
        if let owner = payload.ownerID {
            dict["ownerID"] = owner
        }
        let actions = payload.actions.map { map(action: $0) }

        return AgentEmbeddedPayload(
            jsonString: payload.resultReference ?? "{}",
            dictionary: dict,
            actions: actions
        )
    }

    public static func map(descriptor: HanlinEmbeddedPresentationDescriptor, id: AgentEmbeddedID = AgentEmbeddedID()) -> AgentEmbeddedPresentationDescriptor {
        AgentEmbeddedPresentationDescriptor(
            id: id,
            handlerID: descriptor.handler ?? "generic",
            title: nil,
            sizing: map(sizing: descriptor.sizing),
            expansion: map(expansion: descriptor.expansion),
            payload: .empty
        )
    }

    public static func map(toolDescriptor: HanlinToolExecutionPresentationDescriptor?, toolName: String, arguments: String) -> AgentToolExecution {
        let handlerID: String
        if let custom = toolDescriptor?.customHandler {
            handlerID = custom
        } else if let family = toolDescriptor?.familyID {
            handlerID = family.rawValue
        } else {
            handlerID = "generic"
        }

        let inspection = ToolCallInspection(
            service: "Hanlin Agent Engine",
            toolName: toolName,
            arguments: arguments
        )

        return AgentToolExecution(
            handlerID: handlerID,
            inspection: inspection,
            status: .running
        )
    }
}
