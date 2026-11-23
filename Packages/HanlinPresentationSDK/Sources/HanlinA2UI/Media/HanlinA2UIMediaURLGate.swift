#if canImport(SwiftUI)
import A2UICore
import A2UISwiftUI
import SwiftUI

/// Preserve the original official component builder and model; reject invalid sources before
/// it constructs an AsyncImage or player. Removing a player runs upstream disappearance cleanup.
@MainActor
public struct HanlinA2UIMediaURLGate: View {
    public let node: Node
    public let isPlayer: Bool
    public let builder: ComponentViewBuilder

    public init(node: Node, isPlayer: Bool, builder: @escaping ComponentViewBuilder) {
        self.node = node
        self.isPlayer = isPlayer
        self.builder = builder
    }

    private struct Source: Hashable {
        let url: String?
        let poster: String?
    }

    public var body: some View {
        if permitted {
            if isPlayer {
                HanlinRequestedA2UIPlayer(node: node, builder: builder)
                    .id(Source(url: node.string(for: "url"), poster: node.string(for: "posterUrl")))
            } else {
                builder(node)
            }
        } else {
            ContentUnavailableView("Media unavailable", systemImage: "rectangle.slash",
                description: Text("This media source could not be displayed."))
        }
    }

    private var permitted: Bool {
        guard let value = node.string(for: "url"), HanlinRemoteMediaURL(value) != nil else { return false }
        if let poster = node.string(for: "posterUrl"), !poster.isEmpty {
            return HanlinRemoteMediaURL(poster) != nil
        }
        return true
    }
}

/// Construct the original official player only on a user request. URL-bound identity resets
/// admission before a changed source can construct a new player, rather than resetting after
/// its onAppear/network work. Disabling, leaving the screen or backgrounding unloads it.
@MainActor
private struct HanlinRequestedA2UIPlayer: View {
    let node: Node
    let builder: ComponentViewBuilder
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.scenePhase) private var scenePhase
    @State private var requested = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if requested && isEnabled && scenePhase == .active {
                builder(node)
                    .accessibilityElement(children: .contain)
                    .accessibilityLabel("Media player")
                    .accessibilityIdentifier("hanlin-media-player")
            } else {
                Button("Load media player", systemImage: "play.circle") { requested = true }
                    .disabled(!isEnabled || scenePhase != .active)
                    .accessibilityIdentifier("hanlin-media-load-player")
            }
            if let value = node.string(for: "url"), HanlinRemoteMediaURL(value) != nil,
               let source = URL(string: value) {
                Link("Open media source", destination: source)
                    .disabled(!isEnabled || scenePhase != .active)
                    .accessibilityIdentifier("hanlin-media-source")
            }
        }
        .onChange(of: isEnabled) { _, enabled in if !enabled { requested = false } }
        .onChange(of: scenePhase) { _, phase in if phase != .active { requested = false } }
        .onDisappear { requested = false }
    }
}
#endif
