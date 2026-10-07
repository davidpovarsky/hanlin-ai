// Packages/HanlinAgentUIAdapter/Sources/HanlinAgentUIAdapter/HanlinAgentChatScreen.swift
#if canImport(SwiftUI)
import SwiftUI
import AgentUI
import HanlinPlatformContracts

/// Experimental / Development-only chat screen rendering the Hanlin Agent using AgentUI SDK.
/// Preserves the existing ChatView without replacing or deleting it.
public struct HanlinAgentChatScreen: View {
    @State private var session: AgentUISession

    public init(
        runtime: HanlinAgentUIRuntimeAdapter = HanlinAgentUIRuntimeAdapter(),
        models: [AgentModelDescriptor] = [
            AgentModelDescriptor(id: "hanlin-default", displayName: "Hanlin Core Agent", iconSystemName: "sparkles")
        ]
    ) {
        let initial = AgentUISession(
            runtime: runtime,
            models: models,
            selectedModel: models.first ?? .default
        )
        _session = State(initialValue: initial)
    }

    public var body: some View {
        AgentChatView(
            session: session,
            configuration: .init(title: "Hanlin Agent (AgentUI SDK)", showHeader: true),
            surfaces: AgentToolSurfaceRegistry.shared,
            embeddedSurfaces: AgentEmbeddedSurfaceRegistry.shared
        )
    }
}
#endif
