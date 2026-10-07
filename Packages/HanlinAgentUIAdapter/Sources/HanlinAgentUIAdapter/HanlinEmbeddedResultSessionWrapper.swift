// Packages/HanlinAgentUIAdapter/Sources/HanlinAgentUIAdapter/HanlinEmbeddedResultSessionWrapper.swift
import Foundation
import AgentUI

#if canImport(SwiftUI)
import SwiftUI

@MainActor
public final class HanlinEmbeddedResultSessionWrapper: AgentEmbeddedResultSession {
    public let id: UUID
    private let viewBuilder: @MainActor () -> AnyView
    private let onTearDown: @MainActor () -> Void

    public init(
        id: UUID = UUID(),
        @ViewBuilder view: @escaping @MainActor () -> some View,
        onTearDown: @escaping @MainActor () -> Void = {}
    ) {
        self.id = id
        self.viewBuilder = { AnyView(view()) }
        self.onTearDown = onTearDown
    }

    public var rootView: AnyView {
        viewBuilder()
    }

    public func tearDown() {
        onTearDown()
    }
}
#endif
