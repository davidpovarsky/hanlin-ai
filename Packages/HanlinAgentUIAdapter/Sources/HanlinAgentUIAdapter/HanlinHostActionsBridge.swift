// Packages/HanlinAgentUIAdapter/Sources/HanlinAgentUIAdapter/HanlinHostActionsBridge.swift
import Foundation
import AgentUI
import HanlinPlatformContracts

@MainActor
public final class HanlinHostActionsBridge: AgentHostActions {
    public var onOpenURL: (@MainActor (URL) -> Void)?
    public var onPerformAction: (@MainActor (AgentHostAction) -> Void)?

    public init(
        onOpenURL: (@MainActor (URL) -> Void)? = nil,
        onPerformAction: (@MainActor (AgentHostAction) -> Void)? = nil
    ) {
        self.onOpenURL = onOpenURL
        self.onPerformAction = onPerformAction
    }

    public func openURL(_ url: URL) {
        onOpenURL?(url)
    }

    public func requestSheet(_ request: AgentPresentationRequest) {
        // Forwarded to host router
    }

    public func requestFullScreen(_ request: AgentPresentationRequest) {
        // Forwarded to host router
    }

    public func requestWindow(_ request: AgentPresentationRequest) {
        // Forwarded to host router
    }

    public func performAction(_ action: AgentHostAction) {
        onPerformAction?(action)
    }
}
